<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useProjectStore } from '../stores/project'
import { useSettingsStore } from '../stores/settings'
import logo from '../assets/logo.svg'

const project = useProjectStore()
const settings = useSettingsStore()

interface RecentProject {
  name: string
  path: string
  icon: string
  iconColor: string
}

const recentProjects = ref<RecentProject[]>([])

onMounted(async () => {
  // 从 localStorage 加载最近项目
  try {
    const saved = localStorage.getItem('recentProjects')
    if (saved) recentProjects.value = JSON.parse(saved)
  } catch {}
})

function getProjectIcon(name: string): { icon: string; color: string } {
  const lower = name.toLowerCase()
  if (lower.includes('python') || lower.includes('py')) return { icon: 'fa-brands fa-python', color: 'text-yellow-500' }
  if (lower.includes('vue') || lower.includes('nuxt')) return { icon: 'fa-brands fa-vuejs', color: 'text-green-500' }
  if (lower.includes('react') || lower.includes('next')) return { icon: 'fa-brands fa-react', color: 'text-blue-400' }
  if (lower.includes('node') || lower.includes('express')) return { icon: 'fa-brands fa-node-js', color: 'text-green-400' }
  return { icon: 'fa-solid fa-code', color: 'text-blue-500' }
}

async function openProject() {
  const path = await window.api.dialog.openFolder()
  if (path) {
    await project.openProject(path)
    addToRecent(path)
  }
}

async function openRecent(item: RecentProject) {
  await project.openProject(item.path)
}

function addToRecent(path: string) {
  const name = path.split(/[/\\]/).pop() || path
  const { icon, color } = getProjectIcon(name)
  const entry: RecentProject = { name, path, icon, iconColor: color }
  recentProjects.value = [entry, ...recentProjects.value.filter(p => p.path !== path)].slice(0, 10)
  localStorage.setItem('recentProjects', JSON.stringify(recentProjects.value))
}
</script>

<template>
  <div class="flex-1 flex flex-col items-center justify-center -mt-6">
    <!-- Logo -->
    <div class="flex flex-col items-center mb-10">
      <div class="flex items-center gap-3 text-4xl font-bold text-white mb-2">
        <img :src="logo" class="w-16 h-16" />
        PANTHEON FORGE
      </div>
      <p class="text-[#a1a1aa] text-sm mt-2">编辑代码，构建未来</p>
    </div>

    <!-- Action Buttons -->
    <div class="flex gap-4 mb-12">
      <!-- Open Project -->
      <div
        class="flex flex-col items-start p-4 bg-[#18181c] hover:bg-[#27272a] border border-[#2e2e32] hover:border-blue-500/50 rounded-lg w-40 transition-all cursor-pointer group"
        @click="openProject"
      >
        <i class="fa-regular fa-folder-open text-blue-500 mb-3 text-xl group-hover:scale-110 transition-transform"></i>
        <span class="text-sm font-medium text-[#e4e4e7] group-hover:text-white">打开项目</span>
        <span class="text-[10px] text-[#52525b] mt-1">Ctrl+O</span>
      </div>

      <!-- Clone Repo -->
      <div class="flex flex-col items-start p-4 bg-[#18181c] hover:bg-[#27272a] border border-[#2e2e32] hover:border-blue-500/50 rounded-lg w-40 transition-all cursor-pointer group">
        <i class="fa-solid fa-download text-purple-500 mb-3 text-xl group-hover:scale-110 transition-transform"></i>
        <span class="text-sm font-medium text-[#e4e4e7] group-hover:text-white">远程仓库</span>
        <span class="text-[10px] text-[#52525b] mt-1">从 GitHub 克隆</span>
      </div>

      <!-- SSH -->
      <div class="flex flex-col items-start p-4 bg-[#18181c] hover:bg-[#27272a] border border-[#2e2e32] hover:border-blue-500/50 rounded-lg w-40 transition-all cursor-pointer group">
        <i class="fa-solid fa-terminal text-green-500 mb-3 text-xl group-hover:scale-110 transition-transform"></i>
        <span class="text-sm font-medium text-[#e4e4e7] group-hover:text-white">SSH 连接</span>
        <span class="text-[10px] text-[#52525b] mt-1">连接远程主机</span>
      </div>
    </div>

    <!-- Recent Projects -->
    <div class="w-full max-w-2xl px-4">
      <h3 class="text-xs text-[#52525b] mb-4 font-medium uppercase tracking-wider pl-2 border-l-2 border-blue-500">最近项目</h3>

      <div v-if="recentProjects.length === 0" class="text-center text-[#52525b] text-sm py-6">
        <i class="fa-solid fa-clock-rotate-left text-2xl mb-2 block"></i>
        <p>暂无最近项目</p>
      </div>

      <div v-else class="space-y-1">
        <div
          v-for="item in recentProjects"
          :key="item.path"
          class="flex items-center justify-between py-2.5 px-3 rounded hover:bg-[#27272a] cursor-pointer group transition-colors"
          @click="openRecent(item)"
        >
          <div class="flex items-center gap-3">
            <i :class="`${item.icon} ${item.iconColor} text-xs`"></i>
            <span class="text-sm text-[#e4e4e7] group-hover:text-white font-medium">{{ item.name }}</span>
          </div>
          <span class="text-xs text-[#52525b] group-hover:text-[#a1a1aa]">{{ item.path }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
