import { defineStore } from 'pinia'
import { ref, watch, toRaw } from 'vue'

export interface ModelSetting {
  id?: number
  name: string
  base_url: string
  model_name: string
  api_key: string
  type: 'openai-compatible' | 'claude' | 'gemini'
  is_active: number
}

export interface AppSettings {
  // 通用
  language: 'zh-CN' | 'en-US'
  autoSave: boolean
  autoSaveDelay: number          // ms
  systemNotifications: boolean
  completionSound: boolean
  // 编辑器
  fontSize: number
  fontFamily: string
  tabSize: number
  wordWrap: boolean
  minimap: boolean
  lineNumbers: boolean
  bracketPairColorization: boolean
  renderWhitespace: 'none' | 'selection' | 'all'
  cursorStyle: 'line' | 'block' | 'underline'
  smoothScrolling: boolean
  // 终端
  terminalFontSize: number
  terminalFontFamily: string
  terminalCursorBlink: boolean
  terminalScrollback: number
  defaultShell: string
  // 外观
  theme: 'dark' | 'light'
  accentColor: string
  sidebarPosition: 'left' | 'right'
  // Agent
  userSkills: SkillItem[]
  userMcpServers: McpServerItem[]
  userRules: string[]
}

export interface SkillItem {
  name: string
  slug: string        // 本地 skill 路径，如 "community/code-review"
  enabled: boolean
}

export interface McpServerItem {
  name: string
  command: string
  args: string[]
  env?: Record<string, string>
  enabled: boolean
}

// 内置 Skills（本地 skills/ 目录）
export const BUILTIN_SKILLS: SkillItem[] = [
  { name: 'Plan', slug: 'system/plan', enabled: true },
  { name: 'API Designer', slug: 'community/api-designer', enabled: true },
  { name: 'Code Review', slug: 'community/code-review', enabled: true },
  { name: 'Git Workflow', slug: 'community/git-workflow', enabled: true },
  { name: 'Docker Compose', slug: 'community/docker-compose', enabled: true },
  { name: 'Database Designer', slug: 'community/database-designer', enabled: true },
  { name: 'Test Generator', slug: 'community/test-generator', enabled: true },
  { name: 'Documentation Writer', slug: 'community/documentation-writer', enabled: true },
  { name: 'Refactor Assistant', slug: 'community/refactor-assistant', enabled: true },
  { name: 'Security Scanner', slug: 'community/security-scanner', enabled: true },
  { name: 'CI/CD Generator', slug: 'community/ci-cd-generator', enabled: true },
  { name: 'Prompt Engineer', slug: 'community/prompt-engineer', enabled: true },
  { name: 'React Component', slug: 'community/react-component', enabled: true },
  { name: 'Next.js App', slug: 'community/nextjs-app', enabled: true },
  { name: 'Express API', slug: 'community/express-api', enabled: true },
  { name: 'Web Scraper', slug: 'community/web-scraper', enabled: true },
]

// 内置 MCP Servers（暂时禁用，按需启用）
export const BUILTIN_MCP_SERVERS: McpServerItem[] = []

// 内置 Rules
export const BUILTIN_RULES: string[] = [
  '每次修改完后端代码，都要重启后端服务器',
  '新的业务代码写完后，都要自行联调测试，并输出测试结果，测试不通过则修改错误',
]

const DEFAULT_SETTINGS: AppSettings = {
  language: 'zh-CN',
  autoSave: true,
  autoSaveDelay: 1000,
  systemNotifications: true,
  completionSound: false,
  fontSize: 13,
  fontFamily: "'JetBrains Mono', monospace",
  tabSize: 2,
  wordWrap: true,
  minimap: true,
  lineNumbers: true,
  bracketPairColorization: true,
  renderWhitespace: 'selection',
  cursorStyle: 'line',
  smoothScrolling: true,
  terminalFontSize: 13,
  terminalFontFamily: "'JetBrains Mono', monospace",
  terminalCursorBlink: true,
  terminalScrollback: 5000,
  defaultShell: 'powershell.exe',
  theme: 'dark',
  accentColor: '#3b82f6',
  sidebarPosition: 'right',
  userSkills: [],
  userMcpServers: [],
  userRules: [],
}

function loadFromStorage(): AppSettings {
  try {
    const saved = localStorage.getItem('pantheon-settings')
    if (saved) return { ...DEFAULT_SETTINGS, ...JSON.parse(saved) }
  } catch {}
  return { ...DEFAULT_SETTINGS }
}

export const useSettingsStore = defineStore('settings', () => {
  const models = ref<ModelSetting[]>([])
  const showSettings = ref(false)
  const app = ref<AppSettings>(loadFromStorage())

  // Auto-persist on any change
  watch(app, (val) => {
    localStorage.setItem('pantheon-settings', JSON.stringify(val))
  }, { deep: true })

  async function loadModels() {
    models.value = await window.api.models.list()
  }

  async function addModel(model: Omit<ModelSetting, 'id'>) {
    await window.api.models.add(JSON.parse(JSON.stringify(model)))
    await loadModels()
  }

  async function updateModel(id: number, model: Partial<ModelSetting>) {
    await window.api.models.update(id, JSON.parse(JSON.stringify(model)))
    await loadModels()
  }

  async function deleteModel(id: number) {
    await window.api.models.delete(id)
    await loadModels()
  }

  async function setActiveModel(id: number) {
    await window.api.models.setActive(id)
    await loadModels()
  }

  async function deactivateModel(id: number) {
    await window.api.models.deactivate(id)
    await loadModels()
  }

  function resetSettings() {
    app.value = { ...DEFAULT_SETTINGS }
  }

  return {
    models, showSettings, app,
    loadModels, addModel, updateModel, deleteModel, setActiveModel, deactivateModel, resetSettings
  }
})
