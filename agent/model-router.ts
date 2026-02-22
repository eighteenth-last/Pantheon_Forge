import type { ModelAdapter, ModelConfig } from '../models/base-adapter'
import { OpenAICompatibleAdapter } from '../models/openai-adapter'
import { ClaudeAdapter } from '../models/claude-adapter'
import { GeminiAdapter } from '../models/gemini-adapter'
import type { Database, ModelRecord } from '../database/db'

const adapters: Record<string, ModelAdapter> = {
  'openai-compatible': new OpenAICompatibleAdapter(),
  'claude': new ClaudeAdapter(),
  'gemini': new GeminiAdapter(),
  'glm': new OpenAICompatibleAdapter(),
  'deepseek': new OpenAICompatibleAdapter(),
  'minimax': new OpenAICompatibleAdapter()
}

export class ModelRouter {
  constructor(private db: Database) {}

  getActiveAdapter(modelId?: number): { adapter: ModelAdapter; config: ModelConfig } {
    const model = modelId ? this.db.getModelById(modelId) : this.db.getActiveModel()
    if (!model) throw new Error('没有配置活跃模型，请先在设置中添加并激活模型')

    const adapter = adapters[model.type]
    if (!adapter) throw new Error(`不支持的模型类型: ${model.type}`)

    return {
      adapter,
      config: {
        baseUrl: model.base_url,
        modelName: model.model_name,
        apiKey: model.api_key
      }
    }
  }

  getActiveModelInfo(): ModelRecord | undefined {
    return this.db.getActiveModel()
  }
}
