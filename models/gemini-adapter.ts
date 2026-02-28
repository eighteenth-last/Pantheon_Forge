/**
 * Gemini 适配器
 * 支持两种模式:
 * 1. Gemini 原生 API (streamGenerateContent)
 * 2. OpenAI 兼容模式 (当 base_url 包含 /openai 时)
 * 支持 functionCall / functionResponse 工具调用
 */
import type { ModelAdapter, Message, ModelConfig, ModelChunk, ToolDefinition } from './base-adapter'
import { retryFetch } from './retry-fetch'

export class GeminiAdapter implements ModelAdapter {
  async *stream(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]): AsyncGenerator<ModelChunk> {
    const base = config.baseUrl.replace(/\/$/, '')

    // 只有 Google 原生 API 地址（且不含 /openai）才走原生模式，其余全部走 OpenAI 兼容
    const isNativeGemini = base.includes('generativelanguage.googleapis.com') && !base.includes('/openai')

    if (isNativeGemini) {
      yield* this.streamNative(messages, config, tools, base)
    } else {
      yield* this.streamOpenAICompat(messages, config, tools, base)
    }
  }

  /** OpenAI 兼容模式 — 用于 /v1beta/openai 端点 */
  private async *streamOpenAICompat(messages: Message[], config: ModelConfig, tools?: ToolDefinition[], base?: string): AsyncGenerator<ModelChunk> {
    const b = (base || config.baseUrl).replace(/\/$/, '')
    const url = b.endsWith('/chat/completions') ? b : `${b}/chat/completions`

    const apiMessages = messages.map(m => {
      const msg: any = { role: m.role }
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
      console.log('[Gemini-OpenAI] Requesting:', url)
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
          console.log(`[Gemini] 限流重试 ${attempt}，等待 ${Math.round(delayMs / 1000)}s`)
        }
      })
    } catch (fetchErr: any) {
      yield { type: 'error', error: `Gemini 网络请求失败: ${fetchErr.message}` }
      return
    }

    if (!response.ok) {
      const errText = await response.text()
      yield { type: 'error', error: `Gemini API Error ${response.status}: ${errText}` }
      return
    }

    const reader = response.body?.getReader()
    if (!reader) { yield { type: 'error', error: 'No response body' }; return }

    const decoder = new TextDecoder()
    let buffer = ''
    const toolCalls = new Map<number, { id: string; name: string; args: string }>()

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split('\n')
      buffer = lines.pop() || ''

      for (const line of lines) {
        const trimmed = line.trim()
        if (!trimmed.startsWith('data: ')) continue
        const data = trimmed.slice(6)
        if (data === '[DONE]') {
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
        } catch { /* skip */ }
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

  /** Gemini 原生 API 模式 */
  private async *streamNative(messages: Message[], config: ModelConfig, tools?: ToolDefinition[], base?: string): AsyncGenerator<ModelChunk> {
    const url = (base || config.baseUrl).replace(/\/$/, '')

    const systemInstruction = messages.find(m => m.role === 'system')?.content

    const contents: any[] = []
    for (const m of messages.filter(m => m.role !== 'system')) {
      if (m.role === 'tool') {
        contents.push({
          role: 'user',
          parts: [{
            functionResponse: {
              name: m.tool_call_id || 'unknown',
              response: { result: m.content }
            }
          }]
        })
      } else if (m.role === 'assistant' && m.tool_calls && m.tool_calls.length > 0) {
        const parts: any[] = []
        if (m.content) parts.push({ text: m.content })
        for (const tc of m.tool_calls) {
          parts.push({
            functionCall: {
              name: tc.function.name,
              args: JSON.parse(tc.function.arguments)
            }
          })
        }
        contents.push({ role: 'model', parts })
      } else {
        contents.push({
          role: m.role === 'assistant' ? 'model' : 'user',
          parts: [{ text: m.content }]
        })
      }
    }

    const body: any = {
      contents,
      generationConfig: {
        maxOutputTokens: config.maxTokens ?? 4096,
        temperature: config.temperature ?? 0.7
      }
    }
    if (systemInstruction) {
      body.systemInstruction = { parts: [{ text: systemInstruction }] }
    }
    if (tools && tools.length > 0) {
      body.tools = [{
        functionDeclarations: tools.map(t => ({
          name: t.name, description: t.description, parameters: t.parameters
        }))
      }]
    }

    let response: Response
    try {
      console.log('[Gemini-Native] Requesting:', url)
      response = await retryFetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      }, {
        maxRetries: 5,
        baseDelayMs: 5000,
        onRetry: (attempt, delayMs) => {
          console.log(`[Gemini-Native] 限流重试 ${attempt}，等待 ${Math.round(delayMs / 1000)}s`)
        }
      })
    } catch (fetchErr: any) {
      yield { type: 'error', error: `Gemini 网络请求失败: ${fetchErr.message}（可能需要代理访问 Google API）` }
      return
    }

    if (!response.ok) {
      const errText = await response.text()
      yield { type: 'error', error: `Gemini API Error ${response.status}: ${errText}` }
      return
    }

    const reader = response.body?.getReader()
    if (!reader) { yield { type: 'error', error: 'No response body' }; return }

    const decoder = new TextDecoder()
    let buffer = ''

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split('\n')
      buffer = lines.pop() || ''

      for (const line of lines) {
        const trimmed = line.trim()
        if (!trimmed.startsWith('data: ')) continue

        try {
          const json = JSON.parse(trimmed.slice(6))
          const parts = json.candidates?.[0]?.content?.parts

          if (parts) {
            for (const part of parts) {
              if (part.text) {
                yield { type: 'text', content: part.text }
              }
              if (part.functionCall) {
                yield {
                  type: 'tool_call',
                  toolCall: { name: part.functionCall.name, arguments: part.functionCall.args || {} }
                }
              }
            }
          }
        } catch { /* skip */ }
      }
    }

    yield { type: 'done' }
  }
}
