<script setup lang="ts">
import { ref, nextTick, computed } from 'vue'
import { useProjectStore, type FileEntry } from '../stores/project'
import FileTreeNode from './FileTreeNode.vue'
import GitPanel from './GitPanel.vue'
import SearchPanel from './SearchPanel.vue'
import ExtensionsPanel from './ExtensionsPanel.vue'

const project = useProjectStore()

const sidebarTabs = [
  { id: 'files', icon: 'fa-regular fa-copy', label: '文件资源管理器' },
  { id: 'search', icon: 'fa-solid fa-magnifying-glass', label: '搜索' },
  { id: 'git', icon: 'fa-solid fa-code-branch', label: '源代码管理' },
  { id: 'extensions', icon: 'fa-solid fa-puzzle-piece', label: '扩展' },
]
const activeTab = ref<string | null>('files')

const emit = defineEmits<{
  (e: 'update:collapsed', v: boolean): void
}>()

function onTabClick(tabId: string) {
  if (activeTab.value === tabId) {
    // 再次点击当前 tab → 折叠
    activeTab.value = null
    emit('update:collapsed', true)
  } else {
    activeTab.value = tabId
    emit('update:collapsed', false)
  }
}

const rootExpanded = ref(true)
const selectedPath = ref('')
const showNewInput = ref<'file' | 'folder' | null>(null)
const newInputTarget = ref('')

// ---- 右键菜单 ----
const ctxMenu = ref({ show: false, x: 0, y: 0 })
const ctxEntry = ref<FileEntry | null>(null)
// 剪贴板
const clipboard = ref<{ path: string; name: string; isDirectory: boolean; mode: 'copy' | 'cut' } | null>(null)
// 重命名
const renamingPath = ref('')
const renameValue = ref('')

function onContextMenu(entry: FileEntry, e: MouseEvent) {
  e.preventDefault()
  e.stopPropagation()
  selectedPath.value = entry.path
  ctxEntry.value = entry
  // 计算菜单位置，防止溢出屏幕
  const menuW = 240, menuH = 320
  let x = e.clientX, y = e.clientY
  if (x + menuW > window.innerWidth) x = window.innerWidth - menuW - 4
  if (y + menuH > window.innerHeight) y = window.innerHeight - menuH - 4
  if (x < 0) x = 4
  if (y < 0) y = 4
  ctxMenu.value = { show: true, x, y }
}

const ctxMenuStyle = computed(() => ({
  left: ctxMenu.value.x + 'px',
  top: ctxMenu.value.y + 'px',
}))

function closeCtxMenu() {
  ctxMenu.value.show = false
}

// 在文件资源管理器中显示
function ctxShowInExplorer() {
  if (ctxEntry.value) window.api.fs.showInExplorer(ctxEntry.value.path)
  closeCtxMenu()
}

// 剪切
function ctxCut() {
  if (!ctxEntry.value) return
  clipboard.value = { path: ctxEntry.value.path, name: ctxEntry.value.name, isDirectory: ctxEntry.value.isDirectory, mode: 'cut' }
  closeCtxMenu()
}

// 复制
function ctxCopy() {
  if (!ctxEntry.value) return
  clipboard.value = { path: ctxEntry.value.path, name: ctxEntry.value.name, isDirectory: ctxEntry.value.isDirectory, mode: 'copy' }
  closeCtxMenu()
}

// 粘贴
async function ctxPaste() {
  if (!clipboard.value || !ctxEntry.value) return
  const targetDir = ctxEntry.value.isDirectory ? ctxEntry.value.path : getParentDir(ctxEntry.value.path)
  const sep = targetDir.includes('/') ? '/' : '\\'
  const destPath = targetDir + sep + clipboard.value.name

  try {
    if (clipboard.value.mode === 'copy') {
      await window.api.fs.copyFile(clipboard.value.path, destPath)
    } else {
      // cut = rename (move)
      await window.api.fs.rename(clipboard.value.path, destPath)
      clipboard.value = null
    }
    await project.refreshTree()
  } catch (err: any) {
    console.error('粘贴失败:', err)
  }
  closeCtxMenu()
}

// 复制路径
function ctxCopyPath() {
  if (ctxEntry.value) navigator.clipboard.writeText(ctxEntry.value.path)
  closeCtxMenu()
}

// 复制相对路径
function ctxCopyRelativePath() {
  if (ctxEntry.value && project.projectPath) {
    const rel = ctxEntry.value.path.replace(project.projectPath, '').replace(/^[/\\]/, '')
    navigator.clipboard.writeText(rel)
  }
  closeCtxMenu()
}

// 重命名
function ctxRename() {
  if (!ctxEntry.value) return
  renamingPath.value = ctxEntry.value.path
  renameValue.value = ctxEntry.value.name
  closeCtxMenu()
  nextTick(() => {
    const input = document.querySelector('.rename-input') as HTMLInputElement
    if (input) { input.focus(); input.select() }
  })
}

async function confirmRename() {
  if (!renameValue.value.trim() || !renamingPath.value) { cancelRename(); return }
  const oldPath = renamingPath.value
  const parentDir = getParentDir(oldPath)
  const sep = parentDir.includes('/') ? '/' : '\\'
  const newPath = parentDir + sep + renameValue.value.trim()
  if (newPath !== oldPath) {
    try {
      await window.api.fs.rename(oldPath, newPath)
      // 更新已打开文件的路径
      const openFile = project.openFiles.find(f => f.path === oldPath)
      if (openFile) {
        openFile.path = newPath
        openFile.name = renameValue.value.trim()
        if (project.activeFilePath === oldPath) project.activeFilePath = newPath
      }
      await project.refreshTree()
    } catch (err: any) {
      console.error('重命名失败:', err)
    }
  }
  cancelRename()
}

function cancelRename() {
  renamingPath.value = ''
  renameValue.value = ''
}

// 删除
async function ctxDelete() {
  if (!ctxEntry.value) return
  const entry = ctxEntry.value
  closeCtxMenu()
  try {
    await window.api.fs.delete(entry.path)
    // 关闭已打开的文件
    if (!entry.isDirectory) {
      project.closeFile(entry.path)
    } else {
      // 关闭该目录下所有已打开的文件
      const toClose = project.openFiles.filter(f => f.path.startsWith(entry.path)).map(f => f.path)
      toClose.forEach(p => project.closeFile(p))
    }
    await project.refreshTree()
  } catch (err: any) {
    console.error('删除失败:', err)
  }
}

// 运行可执行代码文件
function ctxRun() {
  if (!ctxEntry.value || ctxEntry.value.isDirectory) return
  const ext = ctxEntry.value.name.split('.').pop()?.toLowerCase() || ''

  // HTML 文件 → 在内置浏览器中打开
  if (['html', 'htm'].includes(ext)) {
    project.openInBrowser(ctxEntry.value.path, ctxEntry.value.name)
    closeCtxMenu()
    return
  }

  const runners: Record<string, string> = {
    py: 'python', js: 'node', ts: 'npx ts-node', java: 'java',
    sh: 'bash', bat: 'cmd /c', ps1: 'powershell -File',
    go: 'go run', rs: 'cargo run', rb: 'ruby', php: 'php',
    lua: 'lua', dart: 'dart run', kt: 'kotlin'
  }
  const runner = runners[ext]
  if (runner) {
    // 通过终端执行
    const cmd = `${runner} "${ctxEntry.value.path}"`
    navigator.clipboard.writeText(cmd)
    // TODO: 后续可以直接发送到终端执行
    alert(`已复制运行命令到剪贴板:\n${cmd}`)
  } else {
    alert('不支持运行此类型文件')
  }
  closeCtxMenu()
}

// 在内置浏览器中打开
function ctxOpenInBrowser() {
  if (!ctxEntry.value) return
  project.openInBrowser(ctxEntry.value.path, ctxEntry.value.name)
  closeCtxMenu()
}

function getParentDir(filePath: string): string {
  const sep = filePath.includes('/') ? '/' : '\\'
  const parts = filePath.split(sep)
  parts.pop()
  return parts.join(sep)
}

// ---- 原有逻辑 ----
async function handleClick(entry: FileEntry) {
  selectedPath.value = entry.path
  if (entry.isDirectory) {
    await project.toggleDirectory(entry)
  } else {
    await project.openFile(entry.path, entry.name, true)
  }
}

async function handleDblClick(entry: FileEntry) {
  if (entry.isDirectory) return
  await project.openFile(entry.path, entry.name, false)
}

function toggleRoot() {
  rootExpanded.value = !rootExpanded.value
  if (!rootExpanded.value) collapseAll(project.fileTree)
}

function collapseAll(entries: FileEntry[]) {
  for (const e of entries) {
    if (e.isDirectory) { e.expanded = false; if (e.children) collapseAll(e.children) }
  }
}

function getTargetDir(): string {
  if (selectedPath.value) {
    const entry = findEntry(project.fileTree, selectedPath.value)
    if (entry?.isDirectory) return entry.path
    const parts = selectedPath.value.replace(/\\/g, '/').split('/')
    parts.pop()
    return parts.join('/')
  }
  return project.projectPath
}

function findEntry(entries: FileEntry[], path: string): FileEntry | null {
  for (const e of entries) {
    if (e.path === path) return e
    if (e.isDirectory && e.children) { const f = findEntry(e.children, path); if (f) return f }
  }
  return null
}

async function startNew(type: 'file' | 'folder') {
  const targetDir = getTargetDir()
  newInputTarget.value = targetDir
  showNewInput.value = type
  if (targetDir === project.projectPath) { rootExpanded.value = true; return }
  const entry = findEntry(project.fileTree, targetDir)
  if (entry && entry.isDirectory && !entry.expanded) await project.toggleDirectory(entry)
}

async function confirmNew(name: string) {
  if (!name.trim() || !showNewInput.value) return
  const dir = newInputTarget.value
  const sep = dir.includes('/') ? '/' : '\\'
  const fullPath = dir + sep + name.trim()
  if (showNewInput.value === 'folder') {
    await window.api.fs.writeFile(fullPath + sep + '.gitkeep', '')
  } else {
    await window.api.fs.writeFile(fullPath, '')
  }
  showNewInput.value = null
  newInputTarget.value = ''
  await project.refreshTree()
}

function cancelNew() {
  showNewInput.value = null
  newInputTarget.value = ''
}

// 点击其他地方关闭右键菜单
function onDocClick() { closeCtxMenu() }
</script>

<template>
  <div class="h-full flex bg-[#18181c] text-[#a1a1aa]" @click="onDocClick">
    <!-- 内容区域（可折叠，左侧） -->
    <div v-show="activeTab !== null" class="flex-1 flex flex-col min-w-0 overflow-hidden">

      <!-- ===== 文件资源管理器 ===== -->
      <template v-if="activeTab === 'files'">
      <!-- Header -->
      <div class="h-9 px-3 border-b border-[#2e2e32] flex items-center justify-between shrink-0 bg-[#27272a]/30">
        <div class="flex items-center gap-1.5 cursor-pointer select-none hover:text-white transition-colors" @click="toggleRoot">
          <i :class="rootExpanded ? 'fa-solid fa-chevron-down' : 'fa-solid fa-chevron-right'" class="text-[10px] w-3 text-center"></i>
          <i class="fa-solid fa-folder-open text-blue-400 text-xs"></i>
          <span class="font-semibold text-xs uppercase tracking-wider truncate">
            {{ project.projectPath ? project.projectPath.replace(/\\/g, '/').split('/').pop() : '未打开项目' }}
          </span>
        </div>
        <div v-if="project.projectPath" class="flex gap-1.5">
          <i class="fa-solid fa-file-circle-plus text-[11px] hover:text-white cursor-pointer transition-colors" title="新建文件" @click="startNew('file')"></i>
          <i class="fa-solid fa-folder-plus text-[11px] hover:text-white cursor-pointer transition-colors" title="新建文件夹" @click="startNew('folder')"></i>
        </div>
      </div>

      <!-- 文件树 -->
      <div class="flex-1 overflow-y-auto py-1">
        <template v-if="rootExpanded && project.projectPath">
          <div v-if="showNewInput && newInputTarget === project.projectPath" class="flex items-center gap-1 px-2 py-1" style="padding-left: 8px">
            <span class="w-4"></span>
            <i :class="showNewInput === 'folder' ? 'fa-solid fa-folder text-blue-400' : 'fa-solid fa-file text-gray-400'" class="text-xs w-4 text-center"></i>
            <input
              class="flex-1 bg-[#27272a] border border-blue-500/50 rounded px-2 py-0.5 text-xs text-white outline-none placeholder-[#52525b] min-w-0"
              :placeholder="showNewInput === 'folder' ? '文件夹名称' : '文件名称'"
              autofocus
              @keydown="(e: KeyboardEvent) => { if (e.key === 'Enter') { const v = (e.target as HTMLInputElement).value.trim(); if (v) confirmNew(v) } else if (e.key === 'Escape') cancelNew() }"
              @blur="cancelNew"
            />
          </div>

          <FileTreeNode
            v-for="entry in project.fileTree"
            :key="entry.path"
            :entry="entry"
            :depth="0"
            :selected-path="selectedPath"
            :new-input="showNewInput"
            :new-input-target="newInputTarget"
            :renaming-path="renamingPath"
            :rename-value="renameValue"
            @click="handleClick"
            @dblclick="handleDblClick"
            @contextmenu="onContextMenu"
            @confirm-new="confirmNew"
            @cancel-new="cancelNew"
            @confirm-rename="confirmRename"
            @cancel-rename="cancelRename"
            @update:rename-value="(v: string) => renameValue = v"
          />

          <div v-if="project.fileTree.length === 0" class="px-3 py-4 text-center text-[10px] text-[#52525b]">目录为空</div>
        </template>

        <div v-if="!project.projectPath" class="px-3 py-6 text-center text-xs text-[#52525b]">
          <i class="fa-solid fa-folder-open text-2xl mb-2 block"></i>
          <p>打开文件夹开始工作</p>
        </div>
      </div>
      </template>

      <!-- ===== 源代码管理 (Git) ===== -->
      <GitPanel v-else-if="activeTab === 'git'" />

      <!-- ===== 搜索 ===== -->
      <SearchPanel v-else-if="activeTab === 'search'" />

      <!-- ===== 扩展 ===== -->
      <ExtensionsPanel v-else-if="activeTab === 'extensions'" />
    </div>

    <!-- 功能入口工具栏（始终可见，右侧最边缘） -->
    <div class="w-[42px] border-l border-[#2e2e32] flex flex-col items-center pt-2 gap-1 shrink-0 bg-[#18181c]">
      <div
        v-for="tab in sidebarTabs" :key="tab.id"
        class="w-8 h-8 flex items-center justify-center rounded cursor-pointer transition-all"
        :class="activeTab === tab.id ? 'bg-[#3b82f6]/15 text-white' : 'text-[#52525b] hover:text-[#a1a1aa] hover:bg-[#27272a]'"
        :title="tab.label"
        @click="onTabClick(tab.id)"
      >
        <i :class="tab.icon" class="text-sm"></i>
      </div>
    </div>

    <!-- 右键菜单 -->
    <Teleport to="body">
      <div
        v-if="ctxMenu.show"
        class="fixed z-[9999] bg-[#1f1f1f] border border-[#454545] rounded-md shadow-2xl py-[5px] min-w-[220px] text-[13px] text-[#cccccc] select-none"
        :style="ctxMenuStyle"
        @click.stop
        @contextmenu.prevent
      >
        <div class="ctx-item" @click="ctxShowInExplorer">
          <span>在文件资源管理器中显示</span>
          <span class="ctx-shortcut">Shift+Alt+R</span>
        </div>
        <div class="ctx-divider"></div>
        <div class="ctx-item" @click="ctxCut">
          <span>剪切</span>
          <span class="ctx-shortcut">Ctrl+X</span>
        </div>
        <div class="ctx-item" @click="ctxCopy">
          <span>复制</span>
          <span class="ctx-shortcut">Ctrl+C</span>
        </div>
        <div v-if="clipboard" class="ctx-item" @click="ctxPaste">
          <span>粘贴</span>
          <span class="ctx-shortcut">Ctrl+V</span>
        </div>
        <div class="ctx-divider"></div>
        <div class="ctx-item" @click="ctxCopyPath">
          <span>复制路径</span>
          <span class="ctx-shortcut">Shift+Alt+C</span>
        </div>
        <div class="ctx-item" @click="ctxCopyRelativePath">
          <span>复制相对路径</span>
          <span class="ctx-shortcut">Ctrl+Shift+C</span>
        </div>
        <div class="ctx-divider"></div>
        <div class="ctx-item" @click="ctxRename">
          <span>重命名</span>
          <span class="ctx-shortcut">F2</span>
        </div>
        <div class="ctx-item" @click="ctxDelete">
          <span>删除</span>
          <span class="ctx-shortcut">Delete</span>
        </div>
        <template v-if="ctxEntry && !ctxEntry.isDirectory">
          <div class="ctx-divider"></div>
          <div
            v-if="['html', 'htm'].includes((ctxEntry.name.split('.').pop() || '').toLowerCase())"
            class="ctx-item"
            @click="ctxOpenInBrowser"
          >
            <span>在内置浏览器中打开</span>
            <span class="ctx-shortcut"></span>
          </div>
          <div class="ctx-item" @click="ctxRun">
            <span>运行文件</span>
          </div>
        </template>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.ctx-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 24px;
  height: 30px;
  cursor: pointer;
  white-space: nowrap;
  transition: background 0.08s;
}
.ctx-item:hover {
  background: #04395e;
  color: #fff;
}
.ctx-shortcut {
  color: #717171;
  font-size: 12px;
  margin-left: 32px;
}
.ctx-item:hover .ctx-shortcut {
  color: #b0b0b0;
}
.ctx-divider {
  height: 1px;
  background: #3c3c3c;
  margin: 4px 12px;
}
</style>
