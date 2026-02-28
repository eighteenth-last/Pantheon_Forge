/**
 * Agent 核心 — ReAct 循环
 *
 * 流程:
 * 1. 加载 Skills 内容 + 连接 MCP 服务器
 * 2. 拼接系统 Prompt（注入 Skill 内容 + 结构化规则）
 * 3. 合并工具列表（内置 + MCP）
 * 4. ReAct 循环：memory.prepareMessages → 调用模型 → 收集所有 tool_calls → 并行执行 → 批量回传
 * 5. 循环直到 Final Answer 或达到安全阀
 */
import type { Message, ModelChunk, ToolDefinition } from '../models/base-adapter'
import type { ModelRouter } from './model-router'
import type { ToolExecutor } from './tool-executor'
import type { Database } from '../database/db'
import { AgentMemory } from './memory'
import { SkillLoader, type SkillRegistryEntry, type SkillItem } from './skill-loader'
import { MCPClient, type McpServerConfig } from './mcp-client'

const MAX_STEPS = 25

const BASE_SYSTEM_PROMPT = `你是 Pantheon Forge 的 AI 编程助手。你的名字是 Pantheon Forge 助手，不要使用其他名字自称。你可以帮助用户编写、修改和理解代码。

你有以下工具可以使用:
- read_file: 读取项目文件（带行号，支持行范围读取）
- write_file: 写入/创建文件（适合新建文件或大范围重写）
- edit_file: 局部修改文件（查找替换，适合小范围修改，优先使用）
- list_dir: 列出目录内容
- run_terminal: 执行短时间终端命令（30秒超时）
- search_files: 搜索项目文件（返回匹配行号、内容和上下文，支持正则）
- start_service: 启动长时间运行的服务
- check_service: 检查服务状态
- stop_service: 停止服务
- load_skill: 按需加载编程技能的详细指导内容

## 文件修改策略
- 局部修改：优先使用 edit_file 工具，提供要替换的旧文本和新文本
- 创建新文件或大范围重写：使用 write_file 工具
- **重要：写入或修改文件时，必须输出完整的内容。禁止省略、截断或用注释代替实际代码。**
- **edit_file 的 new_str 必须包含完整的替换内容，不能只写一半。**
- 例如：新增一个数据表，必须包含完整的 CREATE TABLE 语句（所有字段、索引、约束），以及必要的测试数据。

## 上下文记忆
- 在同一会话中，你之前已经读取或发现的文件路径、目录结构、文件内容等信息，必须记住并直接使用。
- 不要重复调用 list_dir 或 read_file 去查找已经知道的信息。
- 如果之前已经读取过某个文件，直接基于已有内容进行操作。

## 服务管理规则
1. 对于需要持续运行的进程，必须使用 start_service 而不是 run_terminal
2. start_service 会自动监听终端输出，通过 success_pattern 和 error_pattern 判断启动是否成功
3. 启动成功后立即继续执行下一个任务
4. 如果需要同时启动前后端，先启动后端，确认成功后再启动前端

工作流程:
1. 理解用户需求
2. 制定计划并逐步执行
3. 向用户报告结果

## 重要约束
- 禁止重复调用相同工具和相同参数。如果一个工具已经返回了结果，直接使用该结果，不要再次调用。
- 每次工具调用都必须有明确目的，不要盲目探索。
- 如果用户的问题可以直接回答（如简单问候、知识问答），不要调用任何工具，直接回复。
- 收集到足够信息后立即给出最终回答，不要继续调用工具。
- 当用户要求修改某个已知文件时，直接操作该文件，不要重新搜索或列出目录。
- write_file 和 edit_file 的内容必须完整、可用，禁止输出半成品代码。

请用中文回复。你可以在一次回复中调用多个独立的工具，它们会被并行执行。`

export interface AgentConfig {
  skills: SkillItem[]
  mcpServers: McpServerConfig[]
  rules: string[]
  maxContextTokens?: number
}

function buildSystemPrompt(config?: AgentConfig, skillRegistry?: SkillRegistryEntry[]): string {
  let prompt = BASE_SYSTEM_PROMPT

  // Rules：结构化格式，带编号
  if (config?.rules && config.rules.length > 0) {
    prompt += '\n\n## 工作规则（必须严格遵守）\n'
    prompt += '以下规则是用户设定的强制要求，你必须在每次操作中遵守：\n'
    config.rules.forEach((r, i) => {
      prompt += `规则 ${i + 1}: ${r}\n`
    })
  }

  // Skills：仅注入清单摘要，按需通过 load_skill 工具加载详细内容
  if (skillRegistry && skillRegistry.length > 0) {
    prompt += '\n\n## 可用技能清单\n'
    prompt += '以下是系统内置的编程技能。当你需要某个技能的详细指导时，使用 `load_skill` 工具加载它。\n'
    prompt += '| slug | 名称 | 说明 |\n|------|------|------|\n'
    skillRegistry.forEach(s => {
      prompt += `| ${s.slug} | ${s.name} | ${s.summary} |\n`
    })
    prompt += '\n使用方法：调用 load_skill 工具，传入 slug 参数即可获取该技能的完整指导内容。\n'
  }

  return prompt
}

/** 构建规则回顾提示（工具调用后附加） */
function buildRulesReminder(rules: string[]): string {
  if (rules.length === 0) return ''
  return '\n[规则回顾] 请确保你的操作符合以下规则: ' + rules.map((r, i) => `(${i + 1}) ${r}`).join(' ')
}

export class AgentCore {
  private aborted = false
  private agentConfig?: AgentConfig
  private memory: AgentMemory
  private skillLoader: SkillLoader
  private mcpClient: MCPClient
  private skillRegistry: SkillRegistryEntry[] = []
  private mcpConnected = false

  constructor(
    private modelRouter: ModelRouter,
    private toolExecutor: ToolExecutor,
    private db: Database,
    skillLoader?: SkillLoader,
    mcpClient?: MCPClient
  ) {
    this.memory = new AgentMemory()
    this.skillLoader = skillLoader || new SkillLoader('./skills')
    this.mcpClient = mcpClient || new MCPClient()
  }

  setConfig(config: AgentConfig) {
    this.agentConfig = config
    // 动态设置上下文窗口大小
    if (config.maxContextTokens) {
      this.memory.setMaxTokens(config.maxContextTokens)
    }
    // 配置变更时重置，下次 run 时重新加载
    this.skillRegistry = []
    this.mcpConnected = false
  }

  stop() {
    this.aborted = true
  }

  /** 关闭 MCP 连接 */
  async shutdown() {
    await this.mcpClient.shutdown()
    this.mcpConnected = false
  }

  async *run(sessionId: number, userMessage: string, projectPath: string, modelId?: number, images?: string[]): AsyncGenerator<ModelChunk> {
    this.aborted = false
    this.toolExecutor.setProjectRoot(projectPath)

    // 1. 加载 Skills 注册表（仅元信息，不加载全部内容）
    if (this.skillRegistry.length === 0) {
      try {
        this.skillRegistry = await this.skillLoader.loadRegistry()
        if (this.skillRegistry.length > 0) {
          console.log(`[AgentCore] 已加载 ${this.skillRegistry.length} 个 Skills 注册信息`)
        }
      } catch (err) {
        console.error('[AgentCore] Skills 注册表加载失败:', err)
      }
    }

    // 2. 连接 MCP 服务器（首次或配置变更后）
    if (!this.mcpConnected && this.agentConfig?.mcpServers?.length) {
      try {
        await this.mcpClient.connectAll(this.agentConfig.mcpServers)
        this.mcpConnected = true
        this.toolExecutor.setMcpCallFunction((name, args) => this.mcpClient.callTool(name, args))
      } catch (err) {
        console.error('[AgentCore] MCP 连接失败:', err)
      }
    }

    // 3. 构建系统 prompt 和工具列表
    const systemPrompt = buildSystemPrompt(this.agentConfig, this.skillRegistry)
    const builtinTools = this.toolExecutor.getToolDefinitions()
    const mcpTools = this.mcpClient.getAllToolDefinitions()
    const allTools: ToolDefinition[] = [...builtinTools, ...mcpTools]

    // 保存用户消息
    this.db.addMessage(sessionId, 'user', userMessage)

    // 4. 加载会话记忆
    let memorySummary = this.db.getSessionMemory(sessionId)

    // 5. 构建消息历史
    const history = this.db.getMessages(sessionId)
    const rawMessages: Message[] = [
      { role: 'system', content: systemPrompt },
      ...history.map(m => {
        const msg: Message = { role: m.role as Message['role'], content: m.content }
        if (m.tool_call_id) msg.tool_call_id = m.tool_call_id
        if (m.tool_calls) {
          try { msg.tool_calls = JSON.parse(m.tool_calls) } catch {}
        }
        return msg
      })
    ]

    // 给最后一条用户消息附带图片
    if (images && images.length > 0) {
      const lastUserMsg = rawMessages[rawMessages.length - 1]
      if (lastUserMsg && lastUserMsg.role === 'user') {
        lastUserMsg.images = images
      }
    }

    // 6. 检查是否需要压缩记忆
    const messagesWithMemory = this.memory.prepareMessages(rawMessages, memorySummary)
    if (this.memory.needsCompression(messagesWithMemory)) {
      console.log(`[AgentCore] 上下文使用率 ${(this.memory.getUsageRatio(messagesWithMemory) * 100).toFixed(0)}%，触发记忆压缩...`)
      yield { type: 'text', content: '🧠 正在压缩会话记忆...\n' }

      try {
        const { adapter, config } = this.modelRouter.getActiveAdapter(modelId)
        const { summary } = await this.memory.compressWithModel(
          messagesWithMemory, memorySummary, adapter, config
        )
        memorySummary = summary
        this.db.saveSessionMemory(sessionId, summary)
        console.log(`[AgentCore] 记忆压缩完成，摘要 ${summary.length} 字符`)
      } catch (err) {
        console.error('[AgentCore] 记忆压缩失败:', err)
      }
    }

    // 7. 最终构建发送给模型的消息
    const messages = this.memory.prepareMessages(rawMessages, memorySummary)

    // 防御性检查
    const nonSystemMessages = messages.filter(m => m.role !== 'system')
    if (nonSystemMessages.length === 0) {
      console.error(`[AgentCore] 消息列表中没有非 system 消息！history=${history.length}, sessionId=${sessionId}`)
      messages.push({ role: 'user', content: userMessage })
    }

    const usage = this.memory.getUsageRatio(messages)
    console.log(`[AgentCore] 会话 ${sessionId}: ${messages.length} 条消息, 上下文使用率 ${(usage * 100).toFixed(0)}%${memorySummary ? ', 有记忆摘要' : ''}`)

    let steps = 0
    const rules = this.agentConfig?.rules || []
    const recentToolCalls: string[] = []

    while (steps < MAX_STEPS && !this.aborted) {
      steps++

      // 8. 每步检查上下文，必要时再次压缩工具结果
      const currentTokens = this.memory.estimateTokens(messages)
      if (currentTokens > this.memory.getMaxTokens() * 0.95) {
        // 紧急截断：只保留 system + 记忆 + 最近几条
        const systemMsgs = messages.filter(m => m.role === 'system')
        const rest = messages.filter(m => m.role !== 'system')
        const keepCount = Math.min(rest.length, 6)
        messages.length = 0
        messages.push(...systemMsgs, ...rest.slice(-keepCount))
        console.log(`[AgentCore] 紧急截断，保留 ${messages.length} 条消息`)
      }

      const { adapter, config } = this.modelRouter.getActiveAdapter(modelId)

      let fullText = ''
      const pendingToolCalls: { id: string; name: string; arguments: Record<string, any> }[] = []
      let hitRateLimit = false

      // 9. 调用模型
      for await (const chunk of adapter.stream(messages, config, allTools)) {
        if (this.aborted) return

        switch (chunk.type) {
          case 'text':
            fullText += chunk.content || ''
            if (chunk.content) yield { type: 'text', content: chunk.content }
            break
          case 'thinking':
            yield chunk
            break
          case 'tool_call':
            if (chunk.toolCall) {
              const tc = chunk.toolCall
              pendingToolCalls.push({
                id: tc.id || `call_${Date.now()}_${steps}_${pendingToolCalls.length}`,
                name: tc.name,
                arguments: tc.arguments
              })
              yield chunk
            }
            break
          case 'error':
            if (chunk.error && (chunk.error.includes('429') || chunk.error.toLowerCase().includes('rate_limit'))) {
              hitRateLimit = true
              yield { type: 'text', content: '\n\n⏳ 请求频率超限，等待后自动重试...\n' }
              break
            }
            yield chunk
            return
          case 'done':
            break
        }
      }

      if (hitRateLimit) {
        steps--
        const waitMs = 15000 + Math.random() * 5000
        console.log(`[AgentCore] 429 限流，等待 ${Math.round(waitMs / 1000)}s 后重试...`)
        await new Promise(r => setTimeout(r, waitMs))
        continue
      }

      // 10. 处理工具调用
      if (pendingToolCalls.length > 0) {
        for (const tc of pendingToolCalls) {
          console.log(`[AgentCore] Step ${steps}: ${tc.name}(${JSON.stringify(tc.arguments).slice(0, 100)})`)
        }

        // 检测重复
        const callSig = pendingToolCalls.map(tc => `${tc.name}:${JSON.stringify(tc.arguments)}`).join('|')
        recentToolCalls.push(callSig)
        if (recentToolCalls.length > 3) recentToolCalls.shift()
        if (recentToolCalls.length >= 3 && recentToolCalls.every(c => c === callSig)) {
          console.warn(`[AgentCore] 检测到重复工具调用，强制终止`)
          yield { type: 'text', content: '\n\n⚠️ 检测到重复操作，已自动停止。' }
          break
        }

        const assistantToolCalls = pendingToolCalls.map(tc => ({
          id: tc.id,
          type: 'function' as const,
          function: { name: tc.name, arguments: JSON.stringify(tc.arguments) }
        }))
        const assistantMessage: Message = {
          role: 'assistant',
          content: fullText || '',
          tool_calls: assistantToolCalls
        }
        messages.push(assistantMessage)
        this.db.addMessage(sessionId, 'assistant', fullText || '', undefined, JSON.stringify(assistantToolCalls))

        const results = await Promise.allSettled(
          pendingToolCalls.map(tc => this.toolExecutor.execute(tc.name, tc.arguments))
        )

        for (let i = 0; i < pendingToolCalls.length; i++) {
          const tc = pendingToolCalls[i]
          const result = results[i]
          const toolResult = result.status === 'fulfilled'
            ? result.value
            : `工具执行错误: ${(result as PromiseRejectedResult).reason?.message || '未知错误'}`

          this.db.addToolLog(sessionId, tc.name, JSON.stringify(tc.arguments), toolResult)
          this.db.addMessage(sessionId, 'tool', toolResult, tc.id)
          yield { type: 'tool_result', toolName: tc.name, content: toolResult }

          messages.push({
            role: 'tool',
            content: toolResult + buildRulesReminder(rules),
            tool_call_id: tc.id
          })
        }

        continue
      }

      // 11. 最终回答
      if (fullText) {
        this.db.addMessage(sessionId, 'assistant', fullText)
      }
      break
    }

    if (steps >= MAX_STEPS) {
      yield { type: 'text', content: '\n\n⚠️ 达到最大执行步数限制，已停止。' }
    }

    yield { type: 'done' }
  }
}
