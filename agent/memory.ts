/**
 * Agent 记忆系统（类似 Qoder）
 *
 * 架构:
 * - 每个会话有独立的持久记忆（存储在 DB 的 session_memory 表）
 * - 上下文窗口 100K tokens
 * - 当已用容量超过 80%（剩余不足 20%）时，自动压缩旧对话为摘要
 * - 压缩通过调用模型完成，生成结构化摘要
 * - 消息构建：system prompt + 记忆摘要 + 最近对话
 *
 * 记忆格式:
 * - 项目结构摘要（发现的文件、目录）
 * - 已完成的操作（修改了哪些文件、执行了什么命令）
 * - 关键发现（文件内容要点、错误信息）
 * - 用户偏好和约束
 */
import type { Message } from '../models/base-adapter'
import type { ModelAdapter, ModelConfig } from '../models/base-adapter'

const CONTEXT_WINDOW = 100000 // 100K tokens
const COMPRESS_THRESHOLD = 0.80 // 已用超过 80% 时触发压缩
const COMPRESS_TARGET = 0.50 // 压缩后目标：保留 50% 容量给新对话

const COMPRESS_PROMPT = `你是一个对话记忆压缩器。请将以下对话历史压缩为结构化摘要，保留所有关键信息。

要求：
1. 保留所有文件路径、目录结构信息
2. 保留所有已执行的操作（创建、修改、删除了哪些文件）
3. 保留关键的代码结构和技术决策
4. 保留用户的需求和偏好
5. 保留错误信息和解决方案
6. 使用简洁的条目格式，不要写成叙述文

输出格式：
## 项目信息
（项目路径、技术栈、目录结构等）

## 已完成操作
（按时间顺序列出已执行的操作）

## 关键发现
（文件内容要点、配置信息、依赖关系等）

## 待处理事项
（用户提到但尚未完成的需求）

请压缩以下对话：`

export interface SessionMemory {
  sessionId: number
  summary: string
  updatedAt: string
}

export class AgentMemory {
  private maxTokens: number

  constructor(maxTokens = CONTEXT_WINDOW) {
    this.maxTokens = maxTokens
  }

  /** 动态设置 maxTokens */
  setMaxTokens(n: number) {
    this.maxTokens = n
  }

  /** 获取当前 maxTokens */
  getMaxTokens(): number {
    return this.maxTokens
  }

  /** 估算消息的 token 数（中英混合取 1 token ≈ 3 字符） */
  estimateTokens(messages: Message[]): number {
    let totalChars = 0
    for (const m of messages) {
      totalChars += m.content.length
      if (m.images) totalChars += m.images.length * 255
      if (m.tool_calls) {
        for (const tc of m.tool_calls) {
          totalChars += tc.function.name.length + tc.function.arguments.length
        }
      }
    }
    return Math.ceil(totalChars / 3)
  }

  /** 估算单个字符串的 token 数 */
  estimateStringTokens(str: string): number {
    return Math.ceil(str.length / 3)
  }

  /** 获取当前使用率 */
  getUsageRatio(messages: Message[]): number {
    return this.estimateTokens(messages) / this.maxTokens
  }

  /** 检查是否需要压缩 */
  needsCompression(messages: Message[]): boolean {
    return this.getUsageRatio(messages) >= COMPRESS_THRESHOLD
  }

  /**
   * 准备发送给模型的消息列表
   * 1. 如果有记忆摘要，注入到 system 消息之后
   * 2. 压缩过长的工具结果
   * 3. 如果仍然超限，从前面截断（保留最近对话）
   */
  prepareMessages(messages: Message[], memorySummary?: string): Message[] {
    const result = [...messages]

    // 注入记忆摘要
    if (memorySummary) {
      const systemIdx = result.findIndex(m => m.role === 'system')
      const memoryMsg: Message = {
        role: 'system',
        content: `[会话记忆]\n以下是之前对话的压缩摘要，包含重要的上下文信息：\n\n${memorySummary}`
      }
      if (systemIdx >= 0) {
        result.splice(systemIdx + 1, 0, memoryMsg)
      } else {
        result.unshift(memoryMsg)
      }
    }

    // 压缩过长的工具结果
    const compressed = this.compressToolResults(result)

    // 检查是否超限
    const estimated = this.estimateTokens(compressed)
    if (estimated <= this.maxTokens * COMPRESS_THRESHOLD) {
      return compressed
    }

    // 超限：保留 system 消息 + 记忆摘要 + 最近对话
    const systemMsgs = compressed.filter(m => m.role === 'system')
    const rest = compressed.filter(m => m.role !== 'system')
    const systemTokens = this.estimateTokens(systemMsgs)
    const targetTokens = this.maxTokens * COMPRESS_TARGET
    const kept: Message[] = []

    let keptTokens = systemTokens
    for (let i = rest.length - 1; i >= 0; i--) {
      const msgTokens = this.estimateTokens([rest[i]])
      if (keptTokens + msgTokens > targetTokens && kept.length > 0) break
      keptTokens += msgTokens
      kept.unshift(rest[i])
    }

    return [...systemMsgs, ...kept]
  }

  /**
   * 自动压缩：调用模型将旧对话压缩为摘要
   * 返回新的摘要文本，由调用方存入数据库
   */
  async compressWithModel(
    messages: Message[],
    existingSummary: string | undefined,
    adapter: ModelAdapter,
    config: ModelConfig
  ): Promise<{ summary: string; keptMessages: Message[] }> {
    const systemMsgs = messages.filter(m => m.role === 'system')
    const rest = messages.filter(m => m.role !== 'system')

    // 计算需要压缩多少消息：保留最近的对话，压缩前面的
    const systemTokens = this.estimateTokens(systemMsgs)
    const targetKeepTokens = this.maxTokens * COMPRESS_TARGET - systemTokens
    const kept: Message[] = []
    let keptTokens = 0

    for (let i = rest.length - 1; i >= 0; i--) {
      const msgTokens = this.estimateTokens([rest[i]])
      if (keptTokens + msgTokens > targetKeepTokens && kept.length > 0) break
      keptTokens += msgTokens
      kept.unshift(rest[i])
    }

    const toCompress = rest.slice(0, rest.length - kept.length)
    if (toCompress.length === 0) {
      return { summary: existingSummary || '', keptMessages: messages }
    }

    // 构建压缩请求
    const compressContent = this.formatMessagesForCompression(toCompress)
    const compressMessages: Message[] = [
      { role: 'system', content: COMPRESS_PROMPT },
    ]

    if (existingSummary) {
      compressMessages.push({
        role: 'user',
        content: `已有的记忆摘要：\n${existingSummary}\n\n需要追加压缩的新对话：\n${compressContent}\n\n请将已有摘要和新对话合并，输出更新后的完整摘要。`
      })
    } else {
      compressMessages.push({
        role: 'user',
        content: compressContent
      })
    }

    // 调用模型生成摘要
    let summary = ''
    try {
      console.log(`[Memory] 开始压缩 ${toCompress.length} 条消息...`)
      for await (const chunk of adapter.stream(compressMessages, config)) {
        if (chunk.type === 'text' && chunk.content) {
          summary += chunk.content
        }
      }
      console.log(`[Memory] 压缩完成，摘要长度: ${summary.length} 字符`)
    } catch (err) {
      console.error('[Memory] 模型压缩失败，使用本地压缩:', err)
      summary = this.localCompress(toCompress, existingSummary)
    }

    if (!summary.trim()) {
      summary = this.localCompress(toCompress, existingSummary)
    }

    return {
      summary,
      keptMessages: [...systemMsgs, ...kept]
    }
  }

  /** 本地压缩（模型调用失败时的降级方案） */
  private localCompress(messages: Message[], existingSummary?: string): string {
    const parts: string[] = []
    if (existingSummary) parts.push(existingSummary)

    parts.push('\n--- 新增记录 ---')
    for (const m of messages) {
      if (m.role === 'user') {
        parts.push(`- 用户: ${m.content.slice(0, 200)}`)
      } else if (m.role === 'assistant') {
        if (m.tool_calls) {
          for (const tc of m.tool_calls) {
            try {
              const args = JSON.parse(tc.function.arguments)
              const key = args.path || args.command || args.query || args.service_id || ''
              parts.push(`- 工具 ${tc.function.name}(${String(key).slice(0, 100)})`)
            } catch {
              parts.push(`- 工具 ${tc.function.name}`)
            }
          }
        }
        if (m.content) parts.push(`- 助手: ${m.content.slice(0, 200)}`)
      } else if (m.role === 'tool') {
        parts.push(`- 结果: ${m.content.slice(0, 200)}`)
      }
    }
    return parts.join('\n')
  }

  /** 将消息格式化为可读文本（用于压缩请求） */
  private formatMessagesForCompression(messages: Message[]): string {
    const lines: string[] = []
    for (const m of messages) {
      if (m.role === 'user') {
        lines.push(`[用户] ${m.content}`)
      } else if (m.role === 'assistant') {
        if (m.tool_calls) {
          for (const tc of m.tool_calls) {
            lines.push(`[工具调用] ${tc.function.name}(${tc.function.arguments.slice(0, 500)})`)
          }
        }
        if (m.content) lines.push(`[助手] ${m.content}`)
      } else if (m.role === 'tool') {
        // 工具结果截断，避免压缩请求过长
        const content = m.content.length > 1000
          ? m.content.slice(0, 800) + '\n...(已截断)'
          : m.content
        lines.push(`[工具结果] ${content}`)
      }
    }
    return lines.join('\n\n')
  }

  /** 压缩过长的工具结果消息 */
  private compressToolResults(messages: Message[]): Message[] {
    const MAX_TOOL_RESULT_CHARS = 3000
    return messages.map(m => {
      if (m.role === 'tool' && m.content && m.content.length > MAX_TOOL_RESULT_CHARS) {
        const head = m.content.slice(0, 2000)
        const tail = m.content.slice(-500)
        return {
          ...m,
          content: `${head}\n\n...(内容已压缩，省略 ${m.content.length - 2500} 字符)...\n\n${tail}`
        }
      }
      return m
    })
  }
}
