import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export interface FileEntry {
  name: string
  path: string
  isDirectory: boolean
  children?: FileEntry[]
  expanded?: boolean
}

export const useProjectStore = defineStore('project', () => {
  const projectPath = ref('')
  const fileTree = ref<FileEntry[]>([])
  const openFiles = ref<{ path: string; name: string; content: string; modified: boolean }[]>([])
  const activeFilePath = ref('')

  const activeFile = computed(() => openFiles.value.find(f => f.path === activeFilePath.value))

  let unsubWatcher: (() => void) | null = null
  let refreshTimer: ReturnType<typeof setTimeout> | null = null

  async function openProject(path: string) {
    // 清理旧的 watcher
    if (unsubWatcher) { unsubWatcher(); unsubWatcher = null }
    await window.api.fs.unwatch()

    projectPath.value = path
    await loadDirectory(path, fileTree.value)

    // 启动文件监听
    await window.api.fs.watch(path)
    unsubWatcher = window.api.fs.onChanged((data: any) => {
      // 防抖：短时间内多次变化只刷新一次
      if (refreshTimer) clearTimeout(refreshTimer)
      refreshTimer = setTimeout(() => {
        refreshTree()
      }, 500)
    })
  }

  async function refreshTree() {
    if (!projectPath.value) return
    // 刷新根目录
    await loadDirectory(projectPath.value, fileTree.value)
    // 重新加载已展开的子目录
    await refreshExpanded(fileTree.value)
  }

  async function refreshExpanded(entries: FileEntry[]) {
    for (const entry of entries) {
      if (entry.isDirectory && entry.expanded && entry.children) {
        await loadDirectory(entry.path, entry.children)
        await refreshExpanded(entry.children)
      }
    }
  }

  async function loadDirectory(dirPath: string, target: FileEntry[]) {
    try {
      const entries = await window.api.fs.readDir(dirPath)
      target.length = 0
      const sorted = entries.sort((a: any, b: any) => {
        if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1
        return a.name.localeCompare(b.name)
      })
      for (const entry of sorted) {
        target.push({ ...entry, children: entry.isDirectory ? [] : undefined, expanded: false })
      }
    } catch (err) {
      console.error('Failed to load directory:', err)
    }
  }

  async function toggleDirectory(entry: FileEntry) {
    if (!entry.isDirectory) return
    entry.expanded = !entry.expanded
    if (entry.expanded && entry.children && entry.children.length === 0) {
      await loadDirectory(entry.path, entry.children)
    }
  }

  async function openFile(path: string, name: string) {
    const existing = openFiles.value.find(f => f.path === path)
    if (existing) {
      activeFilePath.value = path
      return
    }
    try {
      const content = await window.api.fs.readFile(path)
      openFiles.value.push({ path, name, content, modified: false })
      activeFilePath.value = path
    } catch (err) {
      console.error('Failed to open file:', err)
    }
  }

  function closeFile(path: string) {
    const idx = openFiles.value.findIndex(f => f.path === path)
    if (idx === -1) return
    openFiles.value.splice(idx, 1)
    if (activeFilePath.value === path) {
      activeFilePath.value = openFiles.value[Math.min(idx, openFiles.value.length - 1)]?.path || ''
    }
  }

  async function saveFile(path: string) {
    const file = openFiles.value.find(f => f.path === path)
    if (!file) return
    await window.api.fs.writeFile(path, file.content)
    file.modified = false
  }

  return {
    projectPath, fileTree, openFiles, activeFilePath, activeFile,
    openProject, toggleDirectory, openFile, closeFile, saveFile, loadDirectory, refreshTree
  }
})
