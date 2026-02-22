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
  const openFiles = ref<{ path: string; name: string; content: string; modified: boolean; preview: boolean; type?: 'code' | 'browser' }[]>([])
  const activeFilePath = ref('')
  const fileReloadTick = ref(0)

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

  async function openFile(path: string, name: string, isPreview = false) {
    const existing = openFiles.value.find(f => f.path === path)
    if (existing) {
      // 如果已打开且要求固定，取消预览状态
      if (!isPreview && existing.preview) existing.preview = false
      activeFilePath.value = path
      return
    }
    try {
      const content = await window.api.fs.readFile(path)

      if (isPreview) {
        // 替换已有的预览 tab
        const previewIdx = openFiles.value.findIndex(f => f.preview)
        if (previewIdx !== -1) {
          openFiles.value.splice(previewIdx, 1, { path, name, content, modified: false, preview: true })
        } else {
          openFiles.value.push({ path, name, content, modified: false, preview: true })
        }
      } else {
        // 固定打开：如果当前有预览 tab 且就是这个文件，直接固定；否则新增
        const previewIdx = openFiles.value.findIndex(f => f.preview)
        if (previewIdx !== -1 && openFiles.value[previewIdx].path === path) {
          openFiles.value[previewIdx].preview = false
        } else {
          openFiles.value.push({ path, name, content, modified: false, preview: false })
        }
      }
      activeFilePath.value = path
    } catch (err) {
      console.error('Failed to open file:', err)
    }
  }

  /** 固定当前预览文件（双击 tab 或双击文件树） */
  function pinFile(path: string) {
    const file = openFiles.value.find(f => f.path === path)
    if (file) file.preview = false
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

  /** 在内置浏览器中打开文件（HTML 等） */
  function openInBrowser(path: string, name: string) {
    // 如果已经以浏览器模式打开，直接切换
    const existing = openFiles.value.find(f => f.path === path && f.type === 'browser')
    if (existing) {
      activeFilePath.value = path
      return
    }
    // 如果已经以代码模式打开，替换为浏览器模式
    const codeIdx = openFiles.value.findIndex(f => f.path === path)
    if (codeIdx !== -1) {
      openFiles.value[codeIdx].type = 'browser'
      openFiles.value[codeIdx].preview = false
      activeFilePath.value = path
      return
    }
    // 新增浏览器 tab
    openFiles.value.push({ path, name, content: '', modified: false, preview: false, type: 'browser' })
    activeFilePath.value = path
  }

  /** 切换回代码编辑模式 */
  function openAsCode(path: string) {
    const file = openFiles.value.find(f => f.path === path)
    if (file && file.type === 'browser') {
      file.type = 'code'
    }
  }

  /** 从磁盘重新加载已打开文件的内容（替换后刷新用） */
  async function reloadOpenFile(path: string) {
    const file = openFiles.value.find(f => f.path === path)
    if (!file) return
    try {
      file.content = await window.api.fs.readFile(path)
      file.modified = false
      fileReloadTick.value++
    } catch (err) {
      console.error('Failed to reload file:', err)
    }
  }

  /** 批量重新加载多个已打开文件 */
  async function reloadOpenFiles(paths: string[]) {
    for (const p of paths) {
      await reloadOpenFile(p)
    }
  }

  return {
    projectPath, fileTree, openFiles, activeFilePath, activeFile, fileReloadTick,
    openProject, toggleDirectory, openFile, pinFile, closeFile, saveFile, loadDirectory, refreshTree,
    openInBrowser, openAsCode, reloadOpenFile, reloadOpenFiles
  }
})
