/**
 * Claude 适配器
 *
 * 自动检测端点格式：
 * - /v1/chat/completions → OpenAI 兼容格式（代理如 claudecn.top）
 * - /v1/messages → Anthropic 原生格式
 *
 * 响应解析同样自动检测：
 * - 有 choices 字段 → OpenAI 格式
 * - 有 type 字段 → Anthropic 格式
 */
import type { ModelAdapter, Message, ModelConfig, ModelChunk, ToolDefinition } from './base-adapter'
import { retryFetch } from './retry-fetch'

export class ClaudeAdapter implements ModelAdapter {
  async *stream(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]): AsyncGenerator<ModelChunk> {
    const base = config.baseUrl.replace(/\/$/, '')
    const url = (base.endsWith('/chat/completions') || base.endsWith('/messages'))
      ? base
      : `${base}/chat/completions`

    // 根据端点决定请求格式
    const useOpenAIFormat = url.includes('/chat/completions')

    let body: any
    let headers: Record<string, string>

    if (useOpenAIFormat) {
      // ========== OpenAI 兼容格式（代理端点） ==========
      const result = this.buildOpenAIBody(messages, config, tools)
      body = result.body
      headers = result.headers
    } else {
      // ========== Anthropic 原生格式 ==========
      const result = this.buildAnthropicBody(messages, config, tools)
      body = result.body
      headers = result.headers
    }

    console.log(`[Claude] Requesting (${useOpenAIFormat ? 'OpenAI' : 'Anthropic'} format):`, url)
    console.log(`[Claude] Messages count: ${body.messages?.length}, tools: ${(body.tools || []).length}`)

    let response: Response
    try {
      response = await retryFetch(url, {
        method: 'POST',
        headers,
        body: JSON.stringify(body)
      }, {
        maxRetries: 5,
        baseDelayMs: 5000,
        onRetry: (attempt, delayMs) => {
          console.log(`[Claude] 限流重试 ${attempt}，等待 ${Math.round(delayMs / 1000)}s`)
        }
      })
    } catch (fetchErr: any) {
      yield { type: 'error', error: `Claude 网络请求失败: ${fetchErr.message}` }
      return
    }

    if (!response.ok) {
      const errText = await response.text()
      yield { type: 'error', error: `Claude API Error ${response.status}: ${errText}` }
      return
    }

    // 流式解析（自动检测响应格式）
    yield* this.parseStream(response)
  }

  /** 构建 OpenAI 兼容格式的请求体（和 openai-adapter 一致） */
  private buildOpenAIBody(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]) {
    const apiMessages = messages.map(m => {
      const msg: any = { role: m.role }
      if (m.role === 'user' && m.images && m.images.length > 0) {
        const parts: any[] = [{ type: 'text', text: m.content }]
        for (const img of m.images) {
          parts.push({ type: 'image_url', image_url: { url: img } })
        }
        msg.content = parts
      } else {
        msg.content = m.content || ''
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

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.apiKey}`
    }

    return { body, headers }
  }

  /** 构建 Anthropic 原生格式的请求体 */
  private buildAnthropicBody(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]) {
    const systemMsg = messages.find(m => m.role === 'system')?.content || ''

    const chatMessages: any[] = []
    for (const m of messages.filter(m => m.role !== 'system')) {
      if (m.role === 'tool') {
        const toolResultBlock = {
          type: 'tool_result',
          tool_use_id: m.tool_call_id || 'unknown',
          content: m.content || '(empty)'
        }
        const lastMsg = chatMessages[chatMessages.length - 1]
        if (lastMsg && lastMsg.role === 'user' && Array.isArray(lastMsg.content) && lastMsg.content[0]?.type === 'tool_result') {
          lastMsg.content.push(toolResultBlock)
        } else {
          chatMessages.push({ role: 'user', content: [toolResultBlock] })
        }
      } else if (m.role === 'assistant' && m.tool_calls && m.tool_calls.length > 0) {
        const content: any[] = []
        if (m.content) content.push({ type: 'text', text: m.content })
        for (const tc of m.tool_calls) {
          let input: any = {}
          try { input = JSON.parse(tc.function.arguments) } catch { input = { raw: tc.function.arguments } }
          content.push({ type: 'tool_use', id: tc.id, name: tc.function.name, input })
        }
        chatMessages.push({ role: 'assistant', content })
      } else if (m.role === 'assistant') {
        chatMessages.push({ role: 'assistant', content: m.content || '...' })
      } else if (m.role === 'user' && m.images && m.images.length > 0) {
        const content: any[] = []
        for (const img of m.images) {
          const match = img.match(/^data:(image\/\w+);base64,(.+)$/)
          if (match) {
            content.push({ type: 'image', source: { type: 'base64', media_type: match[1], data: match[2] } })
          }
        }
        content.push({ type: 'text', text: m.content || '...' })
        chatMessages.push({ role: 'user', content })
      } else {
        chatMessages.push({ role: m.role, content: m.content || '...' })
      }
    }

    // Anthropic 要求严格 user/assistant 交替
    const sanitized: any[] = []
    for (const msg of chatMessages) {
      const last = sanitized[sanitized.length - 1]
      if (last && last.role === msg.role) {
        if (Array.isArray(last.content) && Array.isArray(msg.content)) {
          last.content.push(...msg.content)
        } else if (Array.isArray(last.content)) {
          last.content.push({ type: 'text', text: String(msg.content) })
        } else if (Array.isArray(msg.content)) {
          last.content = [{ type: 'text', text: String(last.content) }, ...msg.content]
        } else {
          last.content = `${last.content}\n${msg.content}`
        }
      } else {
        sanitized.push({ ...msg })
      }
    }
    if (sanitized.length > 0 && sanitized[0].role !== 'user') {
      sanitized.unshift({ role: 'user', content: '(继续)' })
    }

    const body: any = {
      model: config.modelName,
      max_tokens: config.maxTokens ?? 4096,
      system: systemMsg,
      messages: sanitized,
      stream: true
    }

    if (tools && tools.length > 0) {
      body.tools = tools.map(t => ({
        name: t.name,
        description: t.description,
        input_schema: t.parameters
      }))
    }

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'x-api-key': config.apiKey,
      'Authorization': `Bearer ${config.apiKey}`,
      'anthropic-version': '2023-06-01'
    }

    return { body, headers }
  }

  /** 流式解析（自动检测 OpenAI / Anthropic 响应格式） */
  private async *parseStream(response: Response): AsyncGenerator<ModelChunk> {
    const reader = response.body?.getReader()
    if (!reader) { yield { type: 'error', error: 'No response body' }; return }

    const decoder = new TextDecoder()
    let buffer = ''
    let detectedFormat: 'anthropic' | 'openai' | null = null

    // Anthropic 原生格式状态
    let currentToolId = ''
    let currentToolName = ''
    let currentToolArgs = ''
    let currentBlockType = ''

    // OpenAI 兼容格式状态
    const openaiToolCalls = new Map<number, { id: string; name: string; args: string }>()

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
          // OpenAI 格式结束
          for (const [, tc] of openaiToolCalls) {
            if (tc.name) {
              try {
                yield { type: 'tool_call', toolCall: { id: tc.id, name: tc.name, arguments: JSON.parse(tc.args) } }
              } catch {
                yield { type: 'tool_call', toolCall: { id: tc.id, name: tc.name, arguments: { raw: tc.args } } }
              }
            }
          }
          if (currentToolName) {
            try {
              yield { type: 'tool_call', toolCall: { id: currentToolId, name: currentToolName, arguments: JSON.parse(currentToolArgs) } }
            } catch {
              yield { type: 'tool_call', toolCall: { id: currentToolId, name: currentToolName, arguments: { raw: currentToolArgs } } }
            }
          }
          yield { type: 'done' }
          return
        }

        try {
          const event = JSON.parse(data)

          if (!detectedFormat) {
            if (event.choices) detectedFormat = 'openai'
            else if (event.type) detectedFormat = 'anthropic'
          }

          if (detectedFormat === 'openai') {
            const delta = event.choices?.[0]?.delta
            if (delta?.reasoning_content) yield { type: 'thinking', thinking: delta.reasoning_content }
            if (delta?.content) yield { type: 'text', content: delta.content }
            if (delta?.tool_calls) {
              for (const tc of delta.tool_calls) {
                const idx = tc.index ?? 0
                if (!openaiToolCalls.has(idx)) openaiToolCalls.set(idx, { id: '', name: '', args: '' })
                const entry = openaiToolCalls.get(idx)!
                if (tc.id) entry.id = tc.id
                if (tc.function?.name) entry.name = tc.function.name
                if (tc.function?.arguments) entry.args += tc.function.arguments
              }
            }
          } else {
            // Anthropic 原生格式
            switch (event.type) {
              case 'content_block_start':
                if (event.content_block?.type === 'tool_use') {
                  currentBlockType = 'tool_use'
                  currentToolId = event.content_block.id || ''
                  currentToolName = event.content_block.name
                  currentToolArgs = ''
                } else if (event.content_block?.type === 'thinking') {
                  currentBlockType = 'thinking'
                } else if (event.content_block?.type === 'text') {
                  currentBlockType = 'text'
                }
                break
              case 'content_block_delta':
                if (event.delta?.type === 'text_delta') yield { type: 'text', content: event.delta.text }
                else if (event.delta?.type === 'thinking_delta') yield { type: 'thinking', thinking: event.delta.thinking }
                else if (event.delta?.type === 'input_json_delta') currentToolArgs += event.delta.partial_json
                break
              case 'content_block_stop':
                if (currentBlockType === 'tool_use' && currentToolName) {
                  try {
                    yield { type: 'tool_call', toolCall: { id: currentToolId, name: currentToolName, arguments: JSON.parse(currentToolArgs) } }
                  } catch {
                    yield { type: 'tool_call', toolCall: { id: currentToolId, name: currentToolName, arguments: { raw: currentToolArgs } } }
                  }
                  currentToolId = ''; currentToolName = ''; currentToolArgs = ''
                }
                currentBlockType = ''
                break
              case 'message_stop':
                yield { type: 'done' }
                return
            }
          }
        } catch { /* skip malformed lines */ }
      }
    }

    // 流结束兜底
    for (const [, tc] of openaiToolCalls) {
      if (tc.name) {
        try {
          yield { type: 'tool_call', toolCall: { id: tc.id, name: tc.name, arguments: JSON.parse(tc.args) } }
        } catch {
          yield { type: 'tool_call', toolCall: { id: tc.id, name: tc.name, arguments: { raw: tc.args } } }
        }
      }
    }
    if (currentToolName) {
      try {
        yield { type: 'tool_call', toolCall: { id: currentToolId, name: currentToolName, arguments: JSON.parse(currentToolArgs) } }
      } catch {
        yield { type: 'tool_call', toolCall: { id: currentToolId, name: currentToolName, arguments: { raw: currentToolArgs } } }
      }
    }
    yield { type: 'done' }
  }
}
