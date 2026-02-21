<script setup lang="ts">
import { ref, onMounted } from 'vue'
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

const terminalVisible = ref(true)
const terminalPanelRef = ref<InstanceType<typeof TerminalPanel>>()

function toggleTerminal() { terminalVisible.value = !terminalVisible.value }
function showTerminal() { terminalVisible.value = true }
function newTerminal() { terminalVisible.value = true; terminalPanelRef.value?.addTerminal() }
function killAllTerminals() { terminalPanelRef.value?.killAllTerminals() }

onMounted(async () => {
  await settings.loadModels()
  await chat.loadModels()
})
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
    <ResizableLayout v-else :terminal-visible="terminalVisible" @update:terminal-visible="v => terminalVisible = v">
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
        <FileExplorer />
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
