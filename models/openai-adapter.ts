/**
 * OpenAI 兼容适配器
 * 覆盖: ChatGPT / 千问(Qwen) / GLM / Kimi / DeepSeek / 豆包
 * 支持 tool_call_id 回传、reasoning_content 思考链
 */
import type { ModelAdapter, Message, ModelConfig, ModelChunk, ToolDefinition } from './base-adapter'

export class OpenAICompatibleAdapter implements ModelAdapter {
  async *stream(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]): AsyncGenerator<ModelChunk> {
    const base = config.baseUrl.replace(/\/$/, '')
    // 如果已包含端点路径则直接用，否则追加 /chat/completions
    const url = (base.endsWith('/chat/completions') || base.endsWith('/completions'))
      ? base
      : `${base}/chat/completions`

    // 构建消息体 — 保留 tool_call_id 和 tool_calls
    const apiMessages = messages.map(m => {
      const msg: any = { role: m.role, content: m.content }
      if (m.tool_call_id) msg.tool_call_id = m.tool_call_id
      if (m.tool_calls) msg.tool_calls = m.tool_calls
      return msg
    })

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
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${config.apiKey}`
        },
        body: JSON.stringify(body)
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
    let toolCallId = ''
    let toolCallName = ''
    let toolCallArgs = ''

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
          if (toolCallName) {
            try {
              yield { type: 'tool_call', toolCall: { id: toolCallId, name: toolCallName, arguments: JSON.parse(toolCallArgs) } }
            } catch {
              yield { type: 'tool_call', toolCall: { id: toolCallId, name: toolCallName, arguments: { raw: toolCallArgs } } }
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

          if (delta?.tool_calls?.[0]) {
            const tc = delta.tool_calls[0]
            if (tc.id) toolCallId = tc.id
            if (tc.function?.name) toolCallName = tc.function.name
            if (tc.function?.arguments) toolCallArgs += tc.function.arguments
          }
        } catch { /* skip malformed lines */ }
      }
    }

    yield { type: 'done' }
  }
}
