/**
 * Agent 记忆管理
 * 管理上下文窗口，防止超出 token 限制
 */
import type { Message } from '../models/base-adapter'

const DEFAULT_MAX_TOKENS = 8000 // 粗略估算

export class AgentMemory {
  private maxTokens: number

  constructor(maxTokens = DEFAULT_MAX_TOKENS) {
    this.maxTokens = maxTokens
  }

  /**
   * 裁剪消息历史，保留系统消息和最近的对话
   * 简单策略：估算 token 数，超出时从前面截断
   */
  trimMessages(messages: Message[]): Message[] {
    const system = messages.filter(m => m.role === 'system')
    const rest = messages.filter(m => m.role !== 'system')

    let totalChars = system.reduce((sum, m) => sum + m.content.length, 0)
    const kept: Message[] = []

    // 从后往前保留消息
    for (let i = rest.length - 1; i >= 0; i--) {
      const msgChars = rest[i].content.length
      // 粗略估算: 1 token ≈ 2-4 个字符（中英混合取 3）
      if ((totalChars + msgChars) / 3 > this.maxTokens) break
      totalChars += msgChars
      kept.unshift(rest[i])
    }

    return [...system, ...kept]
  }

  /**
   * 估算消息的 token 数
   */
  estimateTokens(messages: Message[]): number {
    const totalChars = messages.reduce((sum, m) => sum + m.content.length, 0)
    return Math.ceil(totalChars / 3)
  }
}
