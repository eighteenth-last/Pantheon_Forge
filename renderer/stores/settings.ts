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
}

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
