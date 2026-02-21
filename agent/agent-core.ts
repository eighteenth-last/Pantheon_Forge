/**
 * Agent 核心 — ReAct 循环
 *
 * 流程:
 * 1. 拼接系统 Prompt + 历史消息
 * 2. 调用模型
 * 3. 解析是否包含 Tool Call
 * 4. 执行工具 → 正确格式回传结果
 * 5. 循环直到 Final Answer 或达到安全阀
 */
import type { Message, ModelChunk } from '../models/base-adapter'
import type { ModelRouter } from './model-router'
import type { ToolExecutor } from './tool-executor'
import type { Database } from '../database/db'

const MAX_STEPS = 50

const SYSTEM_PROMPT = `你是 Pantheon Forge 的 AI 编程助手。你可以帮助用户编写、修改和理解代码。

你有以下工具可以使用:
- read_file: 读取项目文件
- write_file: 写入/创建文件
- list_dir: 列出目录内容
- run_terminal: 执行终端命令
- search_files: 搜索项目文件

工作流程:
1. 理解用户需求
2. 如果需要，先读取相关文件了解上下文
3. 制定修改方案
4. 使用工具执行修改
5. 向用户报告结果

请用中文回复。当你需要修改文件时，使用 write_file 工具。
每次只调用一个工具，等待结果后再决定下一步。`

export class AgentCore {
  private aborted = false

  constructor(
    private modelRouter: ModelRouter,
    private toolExecutor: ToolExecutor,
    private db: Database
  ) {}

  stop() {
    this.aborted = true
  }

  async *run(sessionId: number, userMessage: string, projectPath: string, modelId?: number): AsyncGenerator<ModelChunk> {
    this.aborted = false
    this.toolExecutor.setProjectRoot(projectPath)

    // 保存用户消息
    this.db.addMessage(sessionId, 'user', userMessage)

    // 构建消息历史
    const history = this.db.getMessages(sessionId)
    const messages: Message[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      ...history.map(m => ({ role: m.role as Message['role'], content: m.content }))
    ]

    const tools = this.toolExecutor.getToolDefinitions()
    let steps = 0

    while (steps < MAX_STEPS && !this.aborted) {
      steps++
      const { adapter, config } = this.modelRouter.getActiveAdapter(modelId)

      let fullText = ''
      let pendingToolCall: { id?: string; name: string; arguments: Record<string, any> } | null = null

      for await (const chunk of adapter.stream(messages, config, tools)) {
        if (this.aborted) return

        switch (chunk.type) {
          case 'text':
            fullText += chunk.content || ''
            yield chunk
            break
          case 'thinking':
            yield chunk
            break
          case 'tool_call':
            pendingToolCall = chunk.toolCall!
            yield chunk
            break
          case 'error':
            yield chunk
            return
          case 'done':
            // 单轮完成，循环决定是否继续
            break
        }
      }

      if (pendingToolCall) {
        // 构建正确的 assistant 消息（带 tool_calls 字段，OpenAI 格式要求）
        const toolCallId = pendingToolCall.id || `call_${Date.now()}_${steps}`
        const assistantMessage: Message = {
          role: 'assistant',
          content: fullText || '',
          tool_calls: [{
            id: toolCallId,
            type: 'function',
            function: {
              name: pendingToolCall.name,
              arguments: JSON.stringify(pendingToolCall.arguments)
            }
          }]
        }
        messages.push(assistantMessage)

        // 执行工具
        const toolResult = await this.toolExecutor.execute(pendingToolCall.name, pendingToolCall.arguments)

        // 记录工具日志
        this.db.addToolLog(sessionId, pendingToolCall.name, JSON.stringify(pendingToolCall.arguments), toolResult)

        // 通知前端工具执行完成
        yield { type: 'tool_result', toolName: pendingToolCall.name, content: toolResult }

        // 构建正确的 tool result 消息（带 tool_call_id）
        messages.push({
          role: 'tool',
          content: toolResult,
          tool_call_id: toolCallId
        })

        continue
      }

      // 没有工具调用 = 最终回答
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
