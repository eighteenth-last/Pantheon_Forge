<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import { useProjectStore } from './stores/project'
import { useChatStore } from './stores/chat'
import { useSettingsStore } from './stores/settings'
import TitleBar from './components/TitleBar.vue'
import WelcomePage from './components/WelcomePage.vue'
import ChatPanel from './components/ChatPanel.vue'
import EditorPanel from './components/EditorPanel.vue'
import TerminalPanel from './components/TerminalPanel.vue'
import FileExplorer from './components/FileExplorer.vue'
import SettingsPage from './components/SettingsPage.vue'
import ResizableLayout from './components/ResizableLayout.vue'

const project = useProjectStore()
const chat = useChatStore()
const settings = useSettingsStore()

// 工作区状态缓存
interface WorkspaceState {
  projectPath: string
  openFiles: { path: string; name: string }[]
  activeFilePath: string
  terminalVisible: boolean
  sidebarCollapsed: boolean
}

const WORKSPACE_KEY = 'pantheon-workspace'

function saveWorkspace() {
  const state: WorkspaceState = {
    projectPath: project.projectPath,
    openFiles: project.openFiles.map(f => ({ path: f.path, name: f.name })),
    activeFilePath: project.activeFilePath,
    terminalVisible: terminalVisible.value,
    sidebarCollapsed: sidebarCollapsed.value,
  }
  localStorage.setItem(WORKSPACE_KEY, JSON.stringify(state))
}

const terminalVisible = ref(true)
const sidebarCollapsed = ref(false)
const terminalPanelRef = ref<InstanceType<typeof TerminalPanel>>()

function toggleTerminal() { terminalVisible.value = !terminalVisible.value }
function showTerminal() { terminalVisible.value = true }
function newTerminal() { terminalVisible.value = true; terminalPanelRef.value?.addTerminal() }
function killAllTerminals() { terminalPanelRef.value?.killAllTerminals() }

onMounted(async () => {
  await settings.loadModels()
  await chat.loadModels()

  // 恢复工作区状态
  try {
    const saved = localStorage.getItem(WORKSPACE_KEY)
    if (saved) {
      const state: WorkspaceState = JSON.parse(saved)
      terminalVisible.value = state.terminalVisible ?? true
      sidebarCollapsed.value = state.sidebarCollapsed ?? false

      if (state.projectPath) {
        await project.openProject(state.projectPath)

        // 恢复上次 session（在文件恢复之前先恢复会话，避免空白对话）
        await chat.restoreLastSession()

        // 恢复打开的文件
        for (const f of state.openFiles) {
          try {
            await project.openFile(f.path, f.name)
          } catch { /* 文件可能已被删除，跳过 */ }
        }

        // 恢复激活的文件
        if (state.activeFilePath) {
          project.activeFilePath = state.activeFilePath
        }
      }
    }
  } catch { /* 恢复失败不影响使用 */ }
})

// 监听状态变化，自动保存工作区
watch(
  () => [project.projectPath, project.openFiles.length, project.activeFilePath, terminalVisible.value, sidebarCollapsed.value],
  () => { saveWorkspace() },
  { deep: true }
)
</script>

<template>
  <div class="h-screen flex flex-col bg-[#101014] text-[#e4e4e7] overflow-hidden">
    <!-- 顶部菜单栏 -->
    <TitleBar
      @toggle-terminal="toggleTerminal"
      @new-terminal="newTerminal"
      @show-terminal="showTerminal"
      @kill-all-terminals="killAllTerminals"
    />

    <!-- 未打开项目：欢迎页 -->
    <WelcomePage v-if="!project.projectPath && !settings.showSettings" />

    <!-- 设置页面 (全屏) -->
    <SettingsPage v-else-if="settings.showSettings" />

    <!-- 已打开项目：工作区 -->
    <ResizableLayout v-else :terminal-visible="terminalVisible" :sidebar-collapsed="sidebarCollapsed" @update:terminal-visible="v => terminalVisible = v">
      <template #left>
        <ChatPanel />
      </template>
      <template #center-top>
        <EditorPanel />
      </template>
      <template #center-bottom>
        <TerminalPanel ref="terminalPanelRef" @close="terminalVisible = false" />
      </template>
      <template #right>
        <FileExplorer @update:collapsed="v => sidebarCollapsed = v" />
      </template>
    </ResizableLayout>

    <!-- 底部状态栏 -->
    <footer class="h-6 bg-[#3b82f6] text-white flex items-center px-3 justify-between text-[10px] select-none shrink-0">
      <div class="flex gap-4">
        <span class="hover:bg-white/20 px-1 rounded cursor-pointer">
          <i class="fa-solid fa-xmark mr-1"></i>0 错误
        </span>
        <span class="hover:bg-white/20 px-1 rounded cursor-pointer">
          <i class="fa-solid fa-triangle-exclamation mr-1"></i>0 警告
        </span>
      </div>
      <div class="flex gap-4">
        <span v-if="!project.projectPath" class="hover:bg-white/20 px-1 rounded cursor-pointer">行 0, 列 0</span>
        <span class="hover:bg-white/20 px-1 rounded cursor-pointer">UTF-8</span>
        <span class="hover:bg-white/20 px-1 rounded cursor-pointer">{{ project.projectPath ? 'TypeScript' : '纯文本' }}</span>
        <span class="hover:bg-white/20 px-1 rounded cursor-pointer">
          <i class="fa-solid fa-bell"></i>
        </span>
      </div>
    </footer>
  </div>
</template>
