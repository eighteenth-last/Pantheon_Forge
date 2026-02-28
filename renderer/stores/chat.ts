import { defineStore } from 'pinia'
import { ref, triggerRef } from 'vue'
import { useSettingsStore, BUILTIN_SKILLS, BUILTIN_MCP_SERVERS, BUILTIN_RULES } from './settings'
import { useTaskStore } from './tasks'
import { useProjectStore } from './project'

export interface ToolCallInfo {
  name: string
  args: string
  output: string
  status: 'running' | 'done' | 'error'
}

/** 消息内容块 — 按顺序排列，支持文字、工具调用交替 */
export type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'tool'; tool: ToolCallInfo }

export interface ChatMessage {
  id: number
  role: 'user' | 'assistant'
  blocks: ContentBlock[]
  /** 用户消息附带的图片（base64 data URL） */
  images?: string[]
  thinking?: string
  thinkingDone?: boolean
  streaming?: boolean
  /**
   * 渐进式渲染状态（仿 VS Code）
   * 流式输出时，renderedWordCount 表示已渲染到 UI 的词数，
   * 实际数据（blocks 中的 text）可能远超这个数。
   * 渲染定时器每 50ms 推进一批词到 UI。
   */
  renderData?: {
    renderedWordCount: number
    lastRenderTime: number
  }
  /** 每个 text block 对应的已渲染 HTML 缓存，key = block index */
  renderedHtmlCache?: Record<number, string>
}

/**
 * 简易词计数 & 截取（仿 VS Code 的 getNWords）
 * 支持中文（每个汉字算一个词）、英文按空格分词
 */
function getNWords(str: string, numWords: number): { value: string; count: number; isFullString: boolean } {
  // 匹配：中文字符 | 连续非空白非中文字符
  const wordRegex = /\p{sc=Han}|[^\s\p{sc=Han}]+/gu
  const matches = Array.from(str.matchAll(wordRegex))
  if (numWords >= matches.length) {
    return { value: str, count: matches.length, isFullString: true }
  }
  const lastMatch = matches[numWords - 1]
  const endIdx = lastMatch.index! + lastMatch[0].length
  return { value: str.substring(0, endIdx), count: numWords, isFullString: false }
}

/** 统计文本中的词数 */
function countWords(str: string): number {
  const wordRegex = /\p{sc=Han}|[^\s\p{sc=Han}]+/gu
  const matches = str.match(wordRegex)
  return matches ? matches.length : 0
}

export const useChatStore = defineStore('chat', () => {
  const messages = ref<ChatMessage[]>([])
  const sessionId = ref<number | null>(null)
  const isStreaming = ref(false)
  const activeModelName = ref('未配置')
  const selectedModelId = ref<number | null>(null)
  let msgIdCounter = 0
  let unsubChunk: (() => void) | null = null

  // ---- 渐进式渲染定时器（仿 VS Code 的 50ms interval） ----
  let progressiveTimer: ReturnType<typeof setInterval> | null = null
  const RENDER_INTERVAL = 50 // ms, 同 VS Code
  const WORDS_PER_SECOND_MIN = 40
  const WORDS_PER_SECOND_MAX = 2000
  const WORDS_PER_SECOND_DEFAULT = 80
  const WORDS_PER_SECOND_AFTER_COMPLETE = 120

  /** 启动渐进式渲染定时器 */
  function startProgressiveRender(msg: ChatMessage) {
    if (progressiveTimer) return
    msg.renderData = { renderedWordCount: 0, lastRenderTime: Date.now() }
    progressiveTimer = setInterval(() => {
      doProgressiveRender(msg)
    }, RENDER_INTERVAL)
  }

  /** 停止渐进式渲染定时器 */
  function stopProgressiveRender() {
    if (progressiveTimer) {
      clearInterval(progressiveTimer)
      progressiveTimer = null
    }
  }

  /** 获取消息中所有文本的总词数 */
  function getTotalWordCount(msg: ChatMessage): number {
    let total = 0
    for (const b of msg.blocks) {
      if (b.type === 'text') total += countWords(b.text)
    }
    return total
  }

  /**
   * 渐进式渲染一帧（仿 VS Code 的 doNextProgressiveRender）
   * 计算本帧应渲染到多少词，触发 Vue 更新
   */
  function doProgressiveRender(msg: ChatMessage) {
    if (!msg.renderData) return

    const totalWords = getTotalWordCount(msg)
    const now = Date.now()
    const elapsed = (now - msg.renderData.lastRenderTime) / 1000

    // 计算渲染速率
    const rate = msg.streaming
      ? WORDS_PER_SECOND_DEFAULT
      : WORDS_PER_SECOND_AFTER_COMPLETE

    const clampedRate = Math.max(WORDS_PER_SECOND_MIN, Math.min(rate, WORDS_PER_SECOND_MAX))
    const targetWords = msg.renderData.renderedWordCount + Math.floor(elapsed * clampedRate)

    if (targetWords <= msg.renderData.renderedWordCount && msg.streaming) {
      return // 还没到下一批词的时间
    }

    const newRenderedCount = Math.min(targetWords, totalWords)

    if (newRenderedCount > msg.renderData.renderedWordCount) {
      msg.renderData.renderedWordCount = newRenderedCount
      msg.renderData.lastRenderTime = now
      triggerRef(messages)
    }

    // 全部渲染完毕且流已结束 → 停止定时器
    if (newRenderedCount >= totalWords && !msg.streaming) {
      msg.renderData = undefined // 清除渲染状态，切换到完整 markdown 渲染
      stopProgressiveRender()
      triggerRef(messages)
    }
  }

  /**
   * 获取消息的可显示文本（按词数截取）
   * 供 ChatPanel 调用，流式阶段只返回已渲染词数的文本
   */
  function getVisibleText(msg: ChatMessage, blockIndex: number): string {
    const block = msg.blocks[blockIndex]
    if (!block || block.type !== 'text') return ''

    // 非流式 / 渲染完毕 → 返回完整文本
    if (!msg.renderData) return block.text

    // 计算此 block 之前的所有 text block 的总词数
    let wordsBefore = 0
    for (let i = 0; i < blockIndex; i++) {
      const b = msg.blocks[i]
      if (b.type === 'text') wordsBefore += countWords(b.text)
    }

    const remainingWords = msg.renderData.renderedWordCount - wordsBefore
    if (remainingWords <= 0) return '' // 还没渲染到这个 block

    const result = getNWords(block.text, remainingWords)
    return result.value
  }

  /** 消息是否处于渐进式渲染中（流式阶段） */
  function isProgressiveRendering(msg: ChatMessage): boolean {
    return !!msg.renderData
  }

  async function createSession(projectPath: string) {
    const session = await window.api.sessions.create(projectPath)
    sessionId.value = session.id
    messages.value = []
  }

  async function loadModels() {
    const models = await window.api.models.list()
    const activeModels = models.filter((m: any) => m.is_active)
    if (selectedModelId.value) {
      const still = activeModels.find((m: any) => m.id === selectedModelId.value)
      if (still) {
        activeModelName.value = still.name
      } else if (activeModels.length > 0) {
        selectedModelId.value = activeModels[0].id
        activeModelName.value = activeModels[0].name
      } else {
        selectedModelId.value = null
        activeModelName.value = '未配置'
      }
    } else if (activeModels.length > 0) {
      selectedModelId.value = activeModels[0].id
      activeModelName.value = activeModels[0].name
    } else {
      activeModelName.value = '未配置'
    }
  }

  function selectModel(id: number, name: string) {
    selectedModelId.value = id
    activeModelName.value = name
  }

  /** 获取最后一个 text block，没有就创建一个 */
  function getOrCreateTextBlock(msg: ChatMessage): ContentBlock & { type: 'text' } {
    const last = msg.blocks[msg.blocks.length - 1]
    if (last && last.type === 'text') return last
    const block: ContentBlock = { type: 'text', text: '' }
    msg.blocks.push(block)
    return block as ContentBlock & { type: 'text' }
  }

  function finishStreaming(msg: ChatMessage) {
    msg.streaming = false
    for (const b of msg.blocks) {
      if (b.type === 'tool' && b.tool.status === 'running') b.tool.status = 'done'
    }
    if (msg.thinking) msg.thinkingDone = true
    isStreaming.value = false
    // 不立即清除 renderData，让定时器加速渲染完剩余内容
    // 如果没有定时器在跑（比如纯工具调用无文本），直接清除
    if (!progressiveTimer) {
      msg.renderData = undefined
    }
    triggerRef(messages)
  }

  /** 同步 Agent 配置到主进程 */
  async function syncAgentConfig() {
    const settings = useSettingsStore()
    const allSkills = [
      ...BUILTIN_SKILLS.filter(s => s.enabled),
      ...settings.app.userSkills.filter(s => s.enabled),
    ].map(s => ({ name: s.name, slug: s.slug, enabled: true }))

    const allMcp = [
      ...BUILTIN_MCP_SERVERS.filter(m => m.enabled),
      ...settings.app.userMcpServers.filter(m => m.enabled),
    ].map(m => ({ name: m.name, command: m.command, args: m.args, env: m.env, enabled: true }))

    const allRules = [
      ...BUILTIN_RULES,
      ...settings.app.userRules,
    ]

    await window.api.agent.setConfig({
      skills: allSkills,
      mcpServers: allMcp,
      rules: allRules,
      maxContextTokens: 128000 // 默认 128k，后续可根据模型动态调整
    })
  }

  async function sendMessage(content: string, projectPath: string, images?: string[]) {
    if (!sessionId.value || !content.trim() || isStreaming.value) return

    // 同步 Agent 配置（skills/mcp/rules）
    await syncAgentConfig()

    // 构建用户消息 blocks
    const userBlocks: ContentBlock[] = [{ type: 'text', text: content }]
    // 图片作为附加信息显示在用户消息中
    const userMsg: ChatMessage = {
      id: ++msgIdCounter,
      role: 'user',
      blocks: userBlocks,
      images: images
    }
    messages.value.push(userMsg)

    const assistantMsg: ChatMessage = {
      id: ++msgIdCounter,
      role: 'assistant',
      blocks: [],
      thinking: '',
      thinkingDone: false,
      streaming: true
    }
    messages.value.push(assistantMsg)
    isStreaming.value = true

    // 启动渐进式渲染定时器
    startProgressiveRender(assistantMsg)

    unsubChunk = window.api.agent.onChunk((data: any) => {
      if (data.sessionId !== sessionId.value) return
      const chunk = data.chunk

      switch (chunk.type) {
        case 'text':
          if (chunk.content) {
            const tb = getOrCreateTextBlock(assistantMsg)
            tb.text += chunk.content
            if (assistantMsg.thinking && !assistantMsg.thinkingDone) {
              assistantMsg.thinkingDone = true
            }
            // 不触发 Vue 更新！数据只写入模型，由定时器驱动渲染
          }
          break

        case 'thinking':
          if (chunk.thinking) {
            assistantMsg.thinking = (assistantMsg.thinking || '') + chunk.thinking
            // thinking 也不立即触发更新，由定时器统一刷新
          }
          break

        case 'tool_call':
          if (chunk.toolCall) {
            const tc = chunk.toolCall
            console.log('[ChatStore] tool_call chunk:', JSON.stringify(tc))
            // 防御：某些模型可能返回嵌套结构或不同字段名
            let tcName = tc.name
            let tcArgs = tc.arguments || tc.args || {}
            // 如果 arguments 中包含 name 字段，说明整个 toolCall 被当作 arguments 传了
            if (tcArgs && typeof tcArgs === 'object' && 'name' in tcArgs && 'arguments' in tcArgs) {
              tcName = tcArgs.name
              tcArgs = tcArgs.arguments || {}
            }
            const toolInfo: ToolCallInfo = {
              name: tcName || 'unknown',
              args: formatToolArgs(tcName || 'unknown', tcArgs),
              output: '',
              status: 'running'
            }
            assistantMsg.blocks.push({ type: 'tool', tool: toolInfo })
            triggerRef(messages) // 工具调用立即显示
          }
          break

        case 'tool_result':
          if (chunk.toolName) {
            for (let i = assistantMsg.blocks.length - 1; i >= 0; i--) {
              const b = assistantMsg.blocks[i]
              if (b.type === 'tool' && b.tool.name === chunk.toolName && b.tool.status === 'running') {
                b.tool.status = 'done'
                b.tool.output = chunk.content || ''
                // 文件修改工具完成后，刷新编辑器中已打开的文件
                if ((chunk.toolName === 'write_file' || chunk.toolName === 'edit_file') && b.tool.args) {
                  const projectStore = useProjectStore()
                  const relPath = b.tool.args.split(/\s/)[0]
                  if (relPath && projectStore.projectPath) {
                    const sep = projectStore.projectPath.includes('\\') ? '\\' : '/'
                    const base = projectStore.projectPath.endsWith(sep) ? projectStore.projectPath.slice(0, -1) : projectStore.projectPath
                    const fullPath = base + sep + relPath.replace(/[\\/]/g, sep)
                    projectStore.reloadOpenFile(fullPath)
                  }
                }
                break
              }
            }
            if (chunk.toolName === 'start_service' || chunk.toolName === 'stop_service') {
              const taskStore = useTaskStore()
              taskStore.refreshServices()
            }
            triggerRef(messages) // 工具结果立即显示
          }
          break

        case 'done':
          finishStreaming(assistantMsg)
          unsubChunk?.()
          unsubChunk = null
          break

        case 'error':
          const tb = getOrCreateTextBlock(assistantMsg)
          tb.text += `\n\n❌ ${chunk.error || '未知错误'}`
          finishStreaming(assistantMsg)
          stopProgressiveRender()
          assistantMsg.renderData = undefined
          unsubChunk?.()
          unsubChunk = null
          break
      }
    })

    try {
      await window.api.agent.chat(sessionId.value, content, projectPath, selectedModelId.value, images)
    } catch (err: any) {
      const tb = getOrCreateTextBlock(assistantMsg)
      tb.text += `\n\n❌ 错误: ${(err as Error).message}`
      triggerRef(messages)
    } finally {
      if (assistantMsg.streaming) finishStreaming(assistantMsg)
      if (unsubChunk) { unsubChunk(); unsubChunk = null }
    }
  }

  /** 格式化工具参数为可读字符串 */
  function formatToolArgs(name: string, args: any): string {
    // 防御：args 可能是字符串（某些模型返回未解析的 JSON）
    if (typeof args === 'string') {
      try { args = JSON.parse(args) } catch { return args.slice(0, 100) }
    }
    if (!args || typeof args !== 'object') return ''
    switch (name) {
      case 'read_file': return args.path || ''
      case 'write_file': return args.path || ''
      case 'edit_file': return args.path || ''
      case 'list_dir': return args.path && args.path !== '.' ? args.path : '(根目录)'
      case 'run_terminal': return args.command || ''
      case 'search_files': return `${args.query || ''}${args.pattern ? ` (${args.pattern})` : ''}`
      case 'start_service': return `[${args.service_id}] ${args.command || ''}`
      case 'check_service': return `[${args.service_id}]`
      case 'stop_service': return `[${args.service_id}]`
      case 'load_skill': return args.slug || ''
      default: {
        // 只显示关键参数，不显示大段内容
        const keys = Object.keys(args).filter(k => k !== 'content' && k !== 'new_str' && k !== 'old_str')
        const summary = keys.map(k => `${k}: ${String(args[k]).slice(0, 60)}`).join(', ')
        return summary || '(...)'
      }
    }
  }

  async function stopGeneration() {
    await window.api.agent.stop()
    isStreaming.value = false
    stopProgressiveRender()
    // 清除最后一条消息的渲染状态
    const lastMsg = messages.value[messages.value.length - 1]
    if (lastMsg?.renderData) lastMsg.renderData = undefined
    triggerRef(messages)
    unsubChunk?.()
  }

  function clearMessages() {
    stopProgressiveRender()
    messages.value = []
  }

  /** 加载历史会话列表 */
  async function loadSessionList(): Promise<{ id: number; preview: string; created_at: string }[]> {
    const sessions = await window.api.sessions.list()
    return sessions.map((s: any) => ({
      id: s.id,
      preview: s.preview || '空会话',
      created_at: s.created_at || ''
    }))
  }

  /** 加载指定会话的消息记录 */
  async function loadSession(sid: number) {
    stopProgressiveRender()
    sessionId.value = sid
    const rawMessages = await window.api.sessions.getMessages(sid)
    const converted: ChatMessage[] = []
    let idCounter = 0
    let currentAssistant: ChatMessage | null = null

    for (const m of rawMessages) {
      if (m.role === 'user') {
        currentAssistant = null
        converted.push({
          id: ++idCounter,
          role: 'user',
          blocks: [{ type: 'text', text: m.content }]
        })
      } else if (m.role === 'assistant') {
        // 创建新的 assistant 消息
        currentAssistant = {
          id: ++idCounter,
          role: 'assistant',
          blocks: [],
          thinkingDone: true
        }
        // 如果有文本内容，添加文本块
        if (m.content) {
          currentAssistant.blocks.push({ type: 'text', text: m.content })
        }
        // 如果有 tool_calls，添加工具调用块
        if (m.tool_calls) {
          try {
            const toolCalls = JSON.parse(m.tool_calls)
            for (const tc of toolCalls) {
              currentAssistant.blocks.push({
                type: 'tool',
                tool: {
                  name: tc.function.name,
                  args: formatToolArgs(tc.function.name, JSON.parse(tc.function.arguments)),
                  output: '',
                  status: 'done'
                }
              })
            }
          } catch {}
        }
        converted.push(currentAssistant)
      } else if (m.role === 'tool') {
        // tool result：找到对应的工具调用块，填充 output
        if (currentAssistant && m.tool_call_id) {
          for (const block of currentAssistant.blocks) {
            if (block.type === 'tool' && block.tool.status === 'done' && !block.tool.output) {
              block.tool.output = m.content
              break
            }
          }
        }
      }
    }
    messages.value = converted
    msgIdCounter = idCounter
  }

  /** 新建对话 */
  function newChat() {
    stopProgressiveRender()
    sessionId.value = null
    messages.value = []
    msgIdCounter = 0
  }

  /** 删除会话 */
  async function deleteSession(sid: number) {
    await window.api.sessions.delete(sid)
    if (sessionId.value === sid) {
      newChat()
    }
  }

  return {
    messages, sessionId, isStreaming, activeModelName, selectedModelId,
    createSession, loadModels, selectModel, sendMessage, stopGeneration,
    clearMessages, loadSessionList, loadSession, newChat, deleteSession,
    // 渐进式渲染 API（供 ChatPanel 使用）
    getVisibleText, isProgressiveRendering
  }
})
