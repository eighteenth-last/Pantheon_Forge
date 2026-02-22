<script setup lang="ts">
import { onMounted } from 'vue'
import { useExtensionsStore, type ExtensionManifest } from '../stores/extensions'

const store = useExtensionsStore()

onMounted(() => {
  store.loadExtensions()
  store.loadSavedTheme()
})

async function onApplyTheme(ext: ExtensionManifest, themeEntry: { label: string; path: string }) {
  await store.applyTheme(ext, themeEntry)
}

function typeLabel(type: string) {
  const map: Record<string, string> = { theme: '主题', snippets: '代码片段', language: '语言支持', mixed: '混合' }
  return map[type] || type
}

function typeIcon(type: string) {
  const map: Record<string, string> = {
    theme: 'fa-solid fa-palette text-purple-400',
    snippets: 'fa-solid fa-code text-yellow-400',
    language: 'fa-solid fa-language text-blue-400',
    mixed: 'fa-solid fa-puzzle-piece text-green-400',
  }
  return map[type] || 'fa-solid fa-puzzle-piece text-[#a1a1aa]'
}
</script>

<template>
  <div class="h-full flex flex-col text-[#a1a1aa] text-xs">
    <!-- Header -->
    <div class="h-9 px-3 border-b border-[#2e2e32] flex items-center justify-between shrink-0 bg-[#27272a]/30">
      <span class="text-xs text-[#cccccc] font-medium">扩展</span>
      <div class="flex gap-2">
        <i class="fa-solid fa-arrows-rotate text-[11px] hover:text-white cursor-pointer transition-colors" :class="{ 'fa-spin': store.loading }" title="刷新" @click="store.loadExtensions()"></i>
        <i class="fa-solid fa-folder-plus text-[11px] hover:text-white cursor-pointer transition-colors" title="从文件夹安装" @click="store.installFromFolder()"></i>
      </div>
    </div>

    <!-- 扩展列表 -->
    <div class="flex-1 overflow-y-auto">
      <!-- 已安装 -->
      <div v-if="store.extensions.length > 0">
        <div class="px-3 py-1.5 text-[10px] text-[#717171] font-medium bg-[#27272a]/30 select-none">
          已安装 ({{ store.extensions.length }})
        </div>
        <div
          v-for="ext in store.extensions" :key="ext.dirName"
          class="px-3 py-2 border-b border-[#2e2e32]/50 hover:bg-[#27272a] transition-colors"
        >
          <!-- 扩展信息 -->
          <div class="flex items-start gap-2">
            <i :class="typeIcon(ext.type)" class="text-lg mt-0.5 shrink-0"></i>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-1.5">
                <span class="text-[#cccccc] font-medium truncate">{{ ext.name }}</span>
                <span class="text-[10px] text-[#52525b]">v{{ ext.version }}</span>
              </div>
              <div v-if="ext.description" class="text-[11px] text-[#717171] mt-0.5 line-clamp-2">{{ ext.description }}</div>
              <div v-if="ext.author" class="text-[10px] text-[#52525b] mt-0.5">{{ ext.author }}</div>

              <!-- 主题列表 -->
              <div v-if="ext.themes && ext.themes.length > 0" class="mt-1.5 space-y-0.5">
                <div
                  v-for="t in ext.themes" :key="t.path"
                  class="flex items-center gap-1.5 px-2 py-1 rounded cursor-pointer transition-colors text-[11px]"
                  :class="store.activeTheme === ext.dirName + ':' + t.path ? 'bg-[#0078d4]/20 text-[#4fc1ff]' : 'hover:bg-[#3e3e42] text-[#a1a1aa]'"
                  @click="onApplyTheme(ext, t)"
                >
                  <i class="fa-solid fa-circle text-[6px]" :class="store.activeTheme === ext.dirName + ':' + t.path ? 'text-[#0078d4]' : 'text-[#52525b]'"></i>
                  <span>{{ t.label }}</span>
                  <span class="text-[10px] text-[#52525b]">{{ t.uiTheme === 'vs-dark' ? '深色' : t.uiTheme === 'vs' ? '浅色' : '高对比度' }}</span>
                </div>
              </div>
            </div>

            <!-- 操作按钮 -->
            <div class="flex items-center gap-1 shrink-0">
              <button
                class="w-5 h-5 flex items-center justify-center rounded text-[10px] transition-colors"
                :class="ext.enabled ? 'text-green-400 hover:bg-[#3e3e42]' : 'text-[#52525b] hover:bg-[#3e3e42]'"
                :title="ext.enabled ? '禁用' : '启用'"
                @click="store.toggleEnabled(ext)"
              >
                <i :class="ext.enabled ? 'fa-solid fa-toggle-on' : 'fa-solid fa-toggle-off'"></i>
              </button>
              <button
                class="w-5 h-5 flex items-center justify-center rounded text-[10px] text-[#52525b] hover:text-red-400 hover:bg-[#3e3e42] transition-colors"
                title="卸载"
                @click="store.uninstall(ext.dirName)"
              >
                <i class="fa-solid fa-trash-can"></i>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- 空状态 -->
      <div v-if="store.extensions.length === 0 && !store.loading" class="px-4 py-8 text-center text-[#52525b]">
        <i class="fa-solid fa-puzzle-piece text-3xl mb-3 block"></i>
        <p class="text-[13px] mb-2">暂无已安装的扩展</p>
        <p class="text-[11px] text-[#717171] mb-4 leading-relaxed">
          扩展可以添加主题、代码片段和语法高亮。<br/>
          点击上方 <i class="fa-solid fa-folder-plus"></i> 从本地文件夹安装。
        </p>
        <div class="text-left bg-[#27272a] rounded p-3 text-[11px] text-[#a1a1aa] leading-relaxed">
          <div class="text-[#cccccc] font-medium mb-1.5">扩展文件夹结构：</div>
          <pre class="text-[10px] text-[#717171] whitespace-pre leading-relaxed">my-theme/
├── manifest.json
└── themes/
    └── dark.json</pre>
          <div class="text-[#cccccc] font-medium mt-2 mb-1">manifest.json 示例：</div>
          <pre class="text-[10px] text-[#717171] whitespace-pre leading-relaxed">{
  "id": "my-theme",
  "name": "My Theme",
  "version": "1.0.0",
  "type": "theme",
  "themes": [{
    "label": "My Dark",
    "uiTheme": "vs-dark",
    "path": "themes/dark.json"
  }]
}</pre>
        </div>
      </div>

      <!-- 加载中 -->
      <div v-if="store.loading" class="px-4 py-6 text-center text-[#52525b]">
        <i class="fa-solid fa-spinner fa-spin text-lg mb-2 block"></i>
        <p>加载中...</p>
      </div>
    </div>
  </div>
</template>
