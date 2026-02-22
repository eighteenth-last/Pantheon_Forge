import { defineStore } from 'pinia'
import { ref } from 'vue'

export interface ExtensionManifest {
  id: string
  name: string
  version: string
  description?: string
  author?: string
  type: 'theme' | 'snippets' | 'language' | 'mixed'
  // 主题扩展
  themes?: { label: string; uiTheme: 'vs-dark' | 'vs' | 'hc-black'; path: string }[]
  // 代码片段
  snippets?: { language: string; path: string }[]
  // 语法高亮 (TextMate)
  grammars?: { language: string; scopeName: string; path: string }[]
  // 运行时
  dirName: string
  installed: boolean
  enabled: boolean
}

const EXT_ENABLED_KEY = 'pantheon-ext-enabled'

export const useExtensionsStore = defineStore('extensions', () => {
  const extensions = ref<ExtensionManifest[]>([])
  const loading = ref(false)
  const activeTheme = ref<string>('')  // 当前激活的主题 id
  const pendingThemeData = ref<any>(null)  // 待应用的主题数据，EditorPanel 监听此值

  function loadEnabledState(): Record<string, boolean> {
    try {
      return JSON.parse(localStorage.getItem(EXT_ENABLED_KEY) || '{}')
    } catch { return {} }
  }

  function saveEnabledState() {
    const state: Record<string, boolean> = {}
    for (const ext of extensions.value) {
      state[ext.id || ext.dirName] = ext.enabled
    }
    localStorage.setItem(EXT_ENABLED_KEY, JSON.stringify(state))
  }

  async function loadExtensions() {
    loading.value = true
    try {
      const list = await window.api.ext.list()
      const enabledState = loadEnabledState()
      extensions.value = list.map((m: any) => ({
        ...m,
        enabled: enabledState[m.id || m.dirName] !== false, // 默认启用
      }))
    } catch (err) {
      console.error('Failed to load extensions:', err)
    }
    loading.value = false
  }

  async function installFromFolder() {
    const folder = await window.api.ext.selectFolder()
    if (!folder) return
    loading.value = true
    const result = await window.api.ext.install(folder)
    if (result.success) {
      await loadExtensions()
    }
    loading.value = false
    return result
  }

  async function uninstall(dirName: string) {
    const result = await window.api.ext.uninstall(dirName)
    if (result.success) {
      extensions.value = extensions.value.filter(e => e.dirName !== dirName)
      saveEnabledState()
    }
    return result
  }

  function toggleEnabled(ext: ExtensionManifest) {
    ext.enabled = !ext.enabled
    saveEnabledState()
  }

  async function applyTheme(ext: ExtensionManifest, themeEntry: { label: string; path: string }) {
    const result = await window.api.ext.loadTheme(ext.dirName, themeEntry.path)
    if (result.success && result.theme) {
      activeTheme.value = `${ext.dirName}:${themeEntry.path}`
      localStorage.setItem('pantheon-active-theme', activeTheme.value)
      pendingThemeData.value = result.theme
      return result.theme
    }
    return null
  }

  function loadSavedTheme() {
    activeTheme.value = localStorage.getItem('pantheon-active-theme') || ''
  }

  return {
    extensions, loading, activeTheme, pendingThemeData,
    loadExtensions, installFromFolder, uninstall, toggleEnabled, applyTheme, loadSavedTheme
  }
})
