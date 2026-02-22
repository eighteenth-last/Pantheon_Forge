<script setup lang="ts">
import { ref } from 'vue'
import { useSettingsStore } from '../stores/settings'
import { useProjectStore } from '../stores/project'
import logo from '../assets/logo.svg'

const settings = useSettingsStore()
const project = useProjectStore()

const emit = defineEmits<{
  (e: 'toggle-terminal'): void
  (e: 'new-terminal'): void
  (e: 'show-terminal'): void
  (e: 'kill-all-terminals'): void
}>()

const openMenu = ref<string | null>(null)

function toggleMenu(name: string) {
  openMenu.value = openMenu.value === name ? null : name
}
function closeMenu() { openMenu.value = null }

async function openFolder() {
  closeMenu()
  const path = await window.api.dialog.openFolder()
  if (path) {
    await project.openProject(path)
    try {
      const name = path.split(/[/\\]/).pop() || path
      const saved = localStorage.getItem('recentProjects')
      const list = saved ? JSON.parse(saved) : []
      const entry = { name, path, icon: 'fa-solid fa-code', iconColor: 'text-blue-500' }
      const updated = [entry, ...list.filter((p: any) => p.path !== path)].slice(0, 10)
      localStorage.setItem('recentProjects', JSON.stringify(updated))
    } catch {}
  }
}

// Menu definitions
interface MenuItem { label: string; shortcut?: string; action?: () => void; divider?: boolean; disabled?: boolean }

const fileMenu: MenuItem[] = [
  { label: '打开文件夹...', shortcut: 'Ctrl+K Ctrl+O', action: openFolder },
  { divider: true, label: '' },
  { label: '保存', shortcut: 'Ctrl+S', action: () => { if (project.activeFilePath) project.saveFile(project.activeFilePath); closeMenu() } },
  { label: '全部保存', shortcut: 'Ctrl+K S' },
  { divider: true, label: '' },
  { label: '设置', shortcut: 'Ctrl+,', action: () => { settings.showSettings = true; closeMenu() } },
]

const terminalMenu: MenuItem[] = [
  { label: '新建终端', shortcut: 'Ctrl+Shift+`', action: () => { emit('new-terminal'); closeMenu() } },
  { divider: true, label: '' },
  { label: '运行活动文件', action: () => { runActiveFile(); closeMenu() } },
  { divider: true, label: '' },
  { label: '显示/隐藏终端', shortcut: 'Ctrl+`', action: () => { emit('toggle-terminal'); closeMenu() } },
  { label: '终止所有终端', action: () => { emit('kill-all-terminals'); closeMenu() } },
]

const menuMap: Record<string, MenuItem[]> = {
  '文件': fileMenu,
  '终端': terminalMenu,
}

async function runActiveFile() {
  if (!project.activeFilePath) return
  emit('show-terminal')
  // Send the run command to the active terminal via a simple approach
  const ext = project.activeFilePath.split('.').pop()?.toLowerCase()
  const filePath = project.activeFilePath.replace(/\\/g, '/')
  let cmd = ''
  if (ext === 'py') cmd = `python "${filePath}"`
  else if (ext === 'js') cmd = `node "${filePath}"`
  else if (ext === 'ts') cmd = `npx ts-node "${filePath}"`
  else if (ext === 'sh') cmd = `bash "${filePath}"`
  else if (ext === 'bat' || ext === 'cmd') cmd = `"${filePath}"`
  else if (ext === 'java') {
    const name = filePath.split('/').pop()?.replace('.java', '')
    cmd = `javac "${filePath}" && java ${name}`
  }
  else if (ext === 'go') cmd = `go run "${filePath}"`
  else if (ext === 'rs') cmd = `rustc "${filePath}" -o temp_out && ./temp_out`
  else cmd = `echo "不支持运行 .${ext} 文件"`
  // We'll write the command + Enter to the terminal via a custom event
  window.dispatchEvent(new CustomEvent('terminal:run-command', { detail: cmd }))
}

function closeWindow() { window.api?.window.close() }
function minimizeWindow() { window.api?.window.minimize() }
function maximizeWindow() { window.api?.window.maximize() }
</script>

<template>
  <header class="h-9 bg-[#18181c] border-b border-[#2e2e32] flex items-center px-4 justify-between select-none shrink-0 text-xs app-drag-region relative z-40">
    <div class="flex items-center gap-4">
      <div class="flex items-center gap-2 mr-4">
        <img :src="logo" class="w-5 h-5" />
      </div>
      <div class="flex gap-1 text-[#a1a1aa]">
        <div v-for="item in ['文件', '编辑', '选择', '查看', '转到', '运行', '终端', '帮助']" :key="item" class="relative">
          <span
            class="px-2 py-1 rounded hover:bg-[#27272a] hover:text-white cursor-pointer no-drag transition-colors"
            :class="{ 'bg-[#27272a] text-white': openMenu === item }"
            @click="toggleMenu(item)"
          >
            {{ item }}
          </span>
          
          <!-- Dropdown Menu -->
          <div v-if="openMenu === item && menuMap[item]" class="absolute top-full left-0 mt-1 w-56 bg-[#1f1f23] border border-[#2e2e32] rounded-md shadow-xl py-1 z-50">
            <template v-for="(menuItem, index) in menuMap[item]" :key="index">
              <div v-if="menuItem.divider" class="h-px bg-[#2e2e32] my-1 mx-2"></div>
              <div
                v-else
                class="px-3 py-1.5 hover:bg-[#007acc] hover:text-white flex justify-between items-center cursor-pointer group"
                :class="{ 'opacity-50 cursor-not-allowed': menuItem.disabled }"
                @click="!menuItem.disabled && menuItem.action && menuItem.action()"
              >
                <span>{{ menuItem.label }}</span>
                <span class="text-[10px] text-[#71717a] group-hover:text-white/80">{{ menuItem.shortcut }}</span>
              </div>
            </template>
          </div>
        </div>
      </div>
    </div>
    
    <!-- Window Controls -->
    <div class="flex gap-2 no-drag">
      <div class="w-3 h-3 rounded-full bg-[#ef4444] hover:bg-[#dc2626] cursor-pointer" @click="closeWindow"></div>
      <div class="w-3 h-3 rounded-full bg-[#eab308] hover:bg-[#ca8a04] cursor-pointer" @click="minimizeWindow"></div>
      <div class="w-3 h-3 rounded-full bg-[#22c55e] hover:bg-[#16a34a] cursor-pointer" @click="maximizeWindow"></div>
    </div>
  </header>
  
  <div v-if="openMenu" class="fixed inset-0 z-30" @click="closeMenu"></div>
</template>