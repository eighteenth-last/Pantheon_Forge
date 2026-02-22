/**
 * Claude 适配器
 * Claude 使用独立的 API 结构，需要单独适配
 * 支持 thinking (extended thinking) 内容块
 * 支持 tool_use id 回传
 */
import type { ModelAdapter, Message, ModelConfig, ModelChunk, ToolDefinition } from './base-adapter'

export class ClaudeAdapter implements ModelAdapter {
  async *stream(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]): AsyncGenerator<ModelChunk> {
    const base = config.baseUrl.replace(/\/$/, '')
    // 如果已包含端点路径则直接用，否则追加
    const url = (base.endsWith('/chat/completions') || base.endsWith('/messages'))
      ? base
      : `${base}/chat/completions`

    const systemMsg = messages.find(m => m.role === 'system')?.content || ''

    // Claude 消息格式转换
    const chatMessages: any[] = []
    for (const m of messages.filter(m => m.role !== 'system')) {
      if (m.role === 'tool') {
        // Claude 需要 tool_result 包在 user 消息的 content 数组里
        chatMessages.push({
          role: 'user',
          content: [{
            type: 'tool_result',
            tool_use_id: m.tool_call_id || 'unknown',
            content: m.content
          }]
        })
      } else if (m.role === 'assistant' && m.tool_calls && m.tool_calls.length > 0) {
        // assistant 消息带工具调用 — 转成 Claude 的 content 数组格式
        const content: any[] = []
        if (m.content) content.push({ type: 'text', text: m.content })
        for (const tc of m.tool_calls) {
          content.push({
            type: 'tool_use',
            id: tc.id,
            name: tc.function.name,
            input: JSON.parse(tc.function.arguments)
          })
        }
        chatMessages.push({ role: 'assistant', content })
      } else {
        chatMessages.push({ role: m.role, content: m.content })
      }
    }

    const body: any = {
      model: config.modelName,
      max_tokens: config.maxTokens ?? 4096,
      system: systemMsg,
      messages: chatMessages,
      stream: true
    }

    if (tools && tools.length > 0) {
      body.tools = tools.map(t => ({
        name: t.name,
        description: t.description,
        input_schema: t.parameters
      }))
    }

    let response: Response
    try {
      console.log('[Claude] Requesting:', url)
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': config.apiKey,
          'Authorization': `Bearer ${config.apiKey}`,
          'anthropic-version': '2023-06-01'
        },
        body: JSON.stringify(body)
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

    const reader = response.body?.getReader()
    if (!reader) { yield { type: 'error', error: 'No response body' }; return }

    const decoder = new TextDecoder()
    let buffer = ''
    let currentToolId = ''
    let currentToolName = ''
    let currentToolArgs = ''
    let currentBlockType = ''
    let detectedFormat: 'anthropic' | 'openai' | null = null

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

        // OpenAI 格式的结束标记
        if (data === '[DONE]') {
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

          // 自动检测格式：有 choices 字段 → OpenAI 格式，有 type 字段 → Anthropic 格式
          if (!detectedFormat) {
            if (event.choices) detectedFormat = 'openai'
            else if (event.type) detectedFormat = 'anthropic'
          }

          if (detectedFormat === 'openai') {
            // ---- OpenAI 兼容格式解析 ----
            const delta = event.choices?.[0]?.delta

            if (delta?.reasoning_content) {
              yield { type: 'thinking', thinking: delta.reasoning_content }
            }

            if (delta?.content) {
              yield { type: 'text', content: delta.content }
            }

            if (delta?.tool_calls?.[0]) {
              const tc = delta.tool_calls[0]
              if (tc.id) currentToolId = tc.id
              if (tc.function?.name) currentToolName = tc.function.name
              if (tc.function?.arguments) currentToolArgs += tc.function.arguments
            }
          } else {
            // ---- Anthropic 原生格式解析 ----
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
                if (event.delta?.type === 'text_delta') {
                  yield { type: 'text', content: event.delta.text }
                } else if (event.delta?.type === 'thinking_delta') {
                  yield { type: 'thinking', thinking: event.delta.thinking }
                } else if (event.delta?.type === 'input_json_delta') {
                  currentToolArgs += event.delta.partial_json
                }
                break

              case 'content_block_stop':
                if (currentBlockType === 'tool_use' && currentToolName) {
                  try {
                    yield { type: 'tool_call', toolCall: { id: currentToolId, name: currentToolName, arguments: JSON.parse(currentToolArgs) } }
                  } catch {
                    yield { type: 'tool_call', toolCall: { id: currentToolId, name: currentToolName, arguments: { raw: currentToolArgs } } }
                  }
                  currentToolId = ''
                  currentToolName = ''
                  currentToolArgs = ''
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

    yield { type: 'done' }
  }
}
