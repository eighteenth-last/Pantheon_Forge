/**
 * OpenAI 兼容适配器
 * 覆盖: ChatGPT / 千问(Qwen) / GLM / Kimi / DeepSeek / 豆包
 * 支持 tool_call_id 回传、reasoning_content 思考链
 */
import type { ModelAdapter, Message, ModelConfig, ModelChunk, ToolDefinition } from './base-adapter'
import { retryFetch } from './retry-fetch'

export class OpenAICompatibleAdapter implements ModelAdapter {
  async *stream(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]): AsyncGenerator<ModelChunk> {
    const base = config.baseUrl.replace(/\/$/, '')
    // 如果已包含端点路径则直接用，否则追加 /chat/completions
    const url = (base.endsWith('/chat/completions') || base.endsWith('/completions'))
      ? base
      : `${base}/chat/completions`

    // 构建消息体 — 保留 tool_call_id 和 tool_calls
    const apiMessages = messages.map(m => {
      const msg: any = { role: m.role }
      // 多模态：用户消息带图片时，content 用数组格式
      if (m.role === 'user' && m.images && m.images.length > 0) {
        const parts: any[] = [{ type: 'text', text: m.content }]
        for (const img of m.images) {
          parts.push({ type: 'image_url', image_url: { url: img } })
        }
        msg.content = parts
      } else {
        msg.content = m.content
      }
      if (m.tool_call_id) msg.tool_call_id = m.tool_call_id
      if (m.tool_calls) msg.tool_calls = m.tool_calls
      return msg
    })

    // 防御性检查
    if (apiMessages.length === 0) {
      console.error('[OpenAI] apiMessages 为空，原始消息:', messages.map(m => m.role))
      yield { type: 'error', error: '消息列表为空，无法发送请求' }
      return
    }

    const body: any = {
      model: config.modelName,
      messages: apiMessages,
      stream: true,
      max_tokens: config.maxTokens ?? 4096,
      temperature: config.temperature ?? 0.7
    }

    if (tools && tools.length > 0) {
      body.tools = tools.map(t => ({
        type: 'function',
        function: { name: t.name, description: t.description, parameters: t.parameters }
      }))
    }
    let response: Response
    try {
      console.log('[OpenAI] Requesting:', url)
      response = await retryFetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${config.apiKey}`
        },
        body: JSON.stringify(body)
      }, {
        maxRetries: 5,
        baseDelayMs: 5000,
        onRetry: (attempt, delayMs) => {
          console.log(`[OpenAI] 限流重试 ${attempt}，等待 ${Math.round(delayMs / 1000)}s`)
        }
      })
    } catch (fetchErr: any) {
      yield { type: 'error', error: `网络请求失败: ${fetchErr.message}` }
      return
    }

    if (!response.ok) {
      const errText = await response.text()
      yield { type: 'error', error: `API Error ${response.status}: ${errText}` }
      return
    }

    const reader = response.body?.getReader()
    if (!reader) { yield { type: 'error', error: 'No response body' }; return }

    const decoder = new TextDecoder()
    let buffer = ''
    // 支持多个并行工具调用
    const toolCalls = new Map<number, { id: string; name: string; args: string }>()

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split('\n')
      buffer = lines.pop() || ''

      for (const line of lines) {
        const trimmed = line.trim()
        if (!trimmed || !trimmed.startsWith('data: ')) continue
        const data = trimmed.slice(6)
        if (data === '[DONE]') {
          // 输出所有收集到的工具调用
          for (const [, tc] of toolCalls) {
            if (tc.name) {
              try {
                yield { type: 'tool_call', toolCall: { id: tc.id, name: tc.name, arguments: JSON.parse(tc.args) } }
              } catch {
                yield { type: 'tool_call', toolCall: { id: tc.id, name: tc.name, arguments: { raw: tc.args } } }
              }
            }
          }
          yield { type: 'done' }
          return
        }

        try {
          const json = JSON.parse(data)
          const delta = json.choices?.[0]?.delta

          if (delta?.reasoning_content) {
            yield { type: 'thinking', thinking: delta.reasoning_content }
          }

          if (delta?.content) {
            yield { type: 'text', content: delta.content }
          }

          if (delta?.tool_calls) {
            for (const tc of delta.tool_calls) {
              const idx = tc.index ?? 0
              if (!toolCalls.has(idx)) {
                toolCalls.set(idx, { id: '', name: '', args: '' })
              }
              const entry = toolCalls.get(idx)!
              if (tc.id) entry.id = tc.id
              if (tc.function?.name) entry.name = tc.function.name
              if (tc.function?.arguments) entry.args += tc.function.arguments
            }
          }
        } catch { /* skip malformed lines */ }
      }
    }

    // 流结束但没有 [DONE] 标记时，输出收集到的工具调用
    for (const [, tc] of toolCalls) {
      if (tc.name) {
        try {
          yield { type: 'tool_call', toolCall: { id: tc.id, name: tc.name, arguments: JSON.parse(tc.args) } }
        } catch {
          yield { type: 'tool_call', toolCall: { id: tc.id, name: tc.name, arguments: { raw: tc.args } } }
        }
      }
    }

    yield { type: 'done' }
  }
}
