/**
 * Gemini 适配器
 * Google Gemini API 格式转换
 * 支持 functionCall / functionResponse 工具调用
 */
import type { ModelAdapter, Message, ModelConfig, ModelChunk, ToolDefinition } from './base-adapter'

export class GeminiAdapter implements ModelAdapter {
  async *stream(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]): AsyncGenerator<ModelChunk> {
    const base = config.baseUrl.replace(/\/$/, '')
    const url = base.includes('/v1beta')
      ? `${base}/models/${config.modelName}:streamGenerateContent?alt=sse&key=${config.apiKey}`
      : `${base}/v1beta/models/${config.modelName}:streamGenerateContent?alt=sse&key=${config.apiKey}`

    const systemInstruction = messages.find(m => m.role === 'system')?.content

    // 转换消息格式 — 处理 tool result
    const contents: any[] = []
    for (const m of messages.filter(m => m.role !== 'system')) {
      if (m.role === 'tool') {
        // Gemini: tool result 作为 functionResponse
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
        // assistant 带工具调用
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

    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    })

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
