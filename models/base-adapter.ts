/** 统一消息格式 */
export interface Message {
  role: 'system' | 'user' | 'assistant' | 'tool'
  content: string
  tool_call_id?: string
  /** assistant 消息中的工具调用（OpenAI 格式需要回传） */
  tool_calls?: {
    id: string
    type: 'function'
    function: { name: string; arguments: string }
  }[]
}

/** 模型配置 */
export interface ModelConfig {
  baseUrl: string
  modelName: string
  apiKey: string
  maxTokens?: number
  temperature?: number
}

/** 工具调用结构 */
export interface ToolCall {
  id?: string
  name: string
  arguments: Record<string, any>
}

/** 流式返回块 */
export interface ModelChunk {
  type: 'text' | 'tool_call' | 'done' | 'error' | 'thinking' | 'tool_result'
  content?: string
  thinking?: string
  toolCall?: ToolCall
  toolName?: string
  error?: string
}

/** 工具定义（传给模型的 function schema） */
export interface ToolDefinition {
  name: string
  description: string
  parameters: Record<string, any>
}

/** 所有模型适配器必须实现此接口 */
export interface ModelAdapter {
  /** 流式对话 */
  stream(messages: Message[], config: ModelConfig, tools?: ToolDefinition[]): AsyncGenerator<ModelChunk>
}
