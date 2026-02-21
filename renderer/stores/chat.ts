import { defineStore } from 'pinia'
import { ref, triggerRef } from 'vue'

export interface ToolCallInfo {
  name: string
  args: string
  output: string
  status: 'running' | 'done' | 'error'
}

/** 消息内容块 — 按顺序排列，支持文字和工具调用交替 */
export type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'tool'; tool: ToolCallInfo }

export interface ChatMessage {
  id: number
  role: 'user' | 'assistant'
  blocks: ContentBlock[]
  thinking?: string
  thinkingDone?: boolean
  streaming?: boolean
}

export const useChatStore = defineStore('chat', () => {
  const messages = ref<ChatMessage[]>([])
  const sessionId = ref<number | null>(null)
  const isStreaming = ref(false)
  const activeModelName = ref('未配置')
  const selectedModelId = ref<number | null>(null)
  let msgIdCounter = 0
  let unsubChunk: (() => void) | null = null

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
    triggerRef(messages)
  }

  async function sendMessage(content: string, projectPath: string) {
    if (!sessionId.value || !content.trim() || isStreaming.value) return

    messages.value.push({ id: ++msgIdCounter, role: 'user', blocks: [{ type: 'text', text: content }] })

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
            triggerRef(messages)
          }
          break

        case 'thinking':
          if (chunk.thinking) {
            assistantMsg.thinking = (assistantMsg.thinking || '') + chunk.thinking
            triggerRef(messages)
          }
          break

        case 'tool_call':
          if (chunk.toolCall) {
            // 工具调用作为新 block，显示在当前文字之后
            const toolInfo: ToolCallInfo = {
              name: chunk.toolCall.name,
              args: formatToolArgs(chunk.toolCall.name, chunk.toolCall.arguments),
              output: '',
              status: 'running'
            }
            assistantMsg.blocks.push({ type: 'tool', tool: toolInfo })
            triggerRef(messages)
          }
          break

        case 'tool_result':
          if (chunk.toolName) {
            // 找到最后一个匹配的 running 工具
            for (let i = assistantMsg.blocks.length - 1; i >= 0; i--) {
              const b = assistantMsg.blocks[i]
              if (b.type === 'tool' && b.tool.name === chunk.toolName && b.tool.status === 'running') {
                b.tool.status = 'done'
                b.tool.output = chunk.content || ''
                break
              }
            }
            triggerRef(messages)
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
          unsubChunk?.()
          unsubChunk = null
          break
      }
    })

    try {
      await window.api.agent.chat(sessionId.value, content, projectPath, selectedModelId.value)
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
  function formatToolArgs(name: string, args: Record<string, any>): string {
    switch (name) {
      case 'read_file': return args.path || ''
      case 'write_file': return args.path || ''
      case 'list_dir': return args.path || '.'
      case 'run_terminal': return args.command || ''
      case 'search_files': return `${args.query || ''}${args.pattern ? ` (${args.pattern})` : ''}`
      default: return JSON.stringify(args)
    }
  }

  async function stopGeneration() {
    await window.api.agent.stop()
    isStreaming.value = false
    unsubChunk?.()
  }

  function clearMessages() {
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
    sessionId.value = sid
    const rawMessages = await window.api.sessions.getMessages(sid)
    // 将数据库的 flat messages 转为 ChatMessage blocks 格式
    const converted: ChatMessage[] = []
    let idCounter = 0
    for (const m of rawMessages) {
      if (m.role === 'user') {
        converted.push({
          id: ++idCounter,
          role: 'user',
          blocks: [{ type: 'text', text: m.content }]
        })
      } else if (m.role === 'assistant') {
        converted.push({
          id: ++idCounter,
          role: 'assistant',
          blocks: [{ type: 'text', text: m.content }],
          thinkingDone: true
        })
      }
      // tool messages are internal, skip display
    }
    messages.value = converted
    msgIdCounter = idCounter
  }

  /** 新建对话 */
  function newChat() {
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
    clearMessages, loadSessionList, loadSession, newChat, deleteSession
  }
})
