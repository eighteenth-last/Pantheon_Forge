<script setup lang="ts">
import { ref } from 'vue'
import { useProjectStore, type FileEntry } from '../stores/project'
import FileTreeNode from './FileTreeNode.vue'

const project = useProjectStore()

const sidebarTabs = [
  { id: 'files', icon: 'fa-regular fa-copy', label: '文件资源管理器' },
  { id: 'search', icon: 'fa-solid fa-magnifying-glass', label: '搜索' },
  { id: 'git', icon: 'fa-solid fa-code-branch', label: '源代码管理' },
  { id: 'extensions', icon: 'fa-solid fa-puzzle-piece', label: '扩展' },
]
const activeTab = ref('files')

const rootExpanded = ref(true)
const selectedPath = ref('')
const showNewInput = ref<'file' | 'folder' | null>(null)
const newInputTarget = ref('')  // 新建输入框所在的目录路径

async function handleClick(entry: FileEntry) {
  selectedPath.value = entry.path
  if (entry.isDirectory) {
    await project.toggleDirectory(entry)
  } else {
    await project.openFile(entry.path, entry.name)
  }
}

function toggleRoot() {
  rootExpanded.value = !rootExpanded.value
  if (!rootExpanded.value) {
    collapseAll(project.fileTree)
  }
}

function collapseAll(entries: FileEntry[]) {
  for (const e of entries) {
    if (e.isDirectory) {
      e.expanded = false
      if (e.children) collapseAll(e.children)
    }
  }
}

/** 获取新建的目标目录：选中目录 → 该目录；选中文件 → 其父目录；无选中 → 项目根 */
function getTargetDir(): string {
  if (selectedPath.value) {
    const entry = findEntry(project.fileTree, selectedPath.value)
    if (entry?.isDirectory) return entry.path
    // 文件 → 父目录
    const parts = selectedPath.value.replace(/\\/g, '/').split('/')
    parts.pop()
    return parts.join('/')
  }
  return project.projectPath
}

function findEntry(entries: FileEntry[], path: string): FileEntry | null {
  for (const e of entries) {
    if (e.path === path) return e
    if (e.isDirectory && e.children) {
      const found = findEntry(e.children, path)
      if (found) return found
    }
  }
  return null
}

async function startNew(type: 'file' | 'folder') {
  const targetDir = getTargetDir()
  newInputTarget.value = targetDir
  showNewInput.value = type

  // 如果目标是根目录，确保根展开
  if (targetDir === project.projectPath) {
    rootExpanded.value = true
    return
  }

  // 确保目标目录已展开（这样输入框才能显示）
  const entry = findEntry(project.fileTree, targetDir)
  if (entry && entry.isDirectory && !entry.expanded) {
    await project.toggleDirectory(entry)
  }
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
</script>

<template>
  <div class="h-full flex flex-col bg-[#18181c] text-[#a1a1aa]">
    <!-- 功能入口工具栏 -->
    <div class="h-[50px] px-2 border-b border-[#2e2e32] flex items-center justify-center gap-1 shrink-0 bg-[#18181c]">
      <div
        v-for="tab in sidebarTabs" :key="tab.id"
        class="w-8 h-8 flex items-center justify-center rounded cursor-pointer transition-all"
        :class="activeTab === tab.id ? 'bg-[#3b82f6]/15 text-white' : 'text-[#52525b] hover:text-[#a1a1aa] hover:bg-[#27272a]'"
        :title="tab.label"
        @click="activeTab = tab.id"
      >
        <i :class="tab.icon" class="text-sm"></i>
      </div>
    </div>

    <!-- Header: 项目名 + 操作按钮 -->
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
        <!-- 根目录级别的新建输入框 -->
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
          @click="handleClick"
          @confirm-new="confirmNew"
          @cancel-new="cancelNew"
        />

        <div v-if="project.fileTree.length === 0" class="px-3 py-4 text-center text-[10px] text-[#52525b]">
          目录为空
        </div>
      </template>

      <div v-if="!project.projectPath" class="px-3 py-6 text-center text-xs text-[#52525b]">
        <i class="fa-solid fa-folder-open text-2xl mb-2 block"></i>
        <p>打开文件夹开始工作</p>
      </div>
    </div>
  </div>
</template>
