<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useProjectStore } from '../stores/project'

const project = useProjectStore()

// 搜索选项
const searchQuery = ref('')
const replaceQuery = ref('')
const caseSensitive = ref(false)
const wholeWord = ref(false)
const useRegex = ref(false)
const includePattern = ref('')
const excludePattern = ref('')
const showReplace = ref(false)
const showFilters = ref(false)

// 搜索结果
interface SearchMatch { line: number; col: number; text: string; matchText: string }
interface SearchResult { file: string; relPath: string; matches: SearchMatch[]; collapsed?: boolean }
const results = ref<SearchResult[]>([])
const searching = ref(false)
const totalMatches = computed(() => results.value.reduce((sum, r) => sum + r.matches.length, 0))

let searchTimer: ReturnType<typeof setTimeout> | null = null

// 输入防抖搜索
watch(searchQuery, () => {
  if (searchTimer) clearTimeout(searchTimer)
  if (!searchQuery.value.trim()) { results.value = []; return }
  searchTimer = setTimeout(() => doSearch(), 400)
})

async function doSearch() {
  const q = searchQuery.value.trim()
  if (!q || !project.projectPath) { results.value = []; return }
  searching.value = true
  try {
    const res = await window.api.search.files(project.projectPath, q, {
      caseSensitive: caseSensitive.value,
      wholeWord: wholeWord.value,
      useRegex: useRegex.value,
      includePattern: includePattern.value || undefined,
      excludePattern: excludePattern.value || undefined,
    })
    results.value = res.map(r => ({ ...r, collapsed: false }))
  } catch (err) {
    console.error('Search failed:', err)
    results.value = []
  }
  searching.value = false
}

function toggleResult(r: SearchResult) {
  r.collapsed = !r.collapsed
}

function openMatch(file: string, name: string) {
  project.openFile(file, name, true)
}

// 替换单个文件
async function replaceInFile(filePath: string) {
  if (!replaceQuery.value && replaceQuery.value !== '') return
  await window.api.search.replace(project.projectPath, filePath, searchQuery.value, replaceQuery.value, {
    caseSensitive: caseSensitive.value,
    wholeWord: wholeWord.value,
    useRegex: useRegex.value,
  })
  // 刷新编辑器中已打开的文件
  await project.reloadOpenFile(filePath)
  await doSearch()
}

// 全部替换
async function replaceAll() {
  if (!project.projectPath) return
  const files = results.value.map(r => r.file)
  await window.api.search.replaceAll(project.projectPath, searchQuery.value, replaceQuery.value, {
    caseSensitive: caseSensitive.value,
    wholeWord: wholeWord.value,
    useRegex: useRegex.value,
    includePattern: includePattern.value || undefined,
    excludePattern: excludePattern.value || undefined,
  }, files)
  // 刷新编辑器中所有被替换的已打开文件
  const openPaths = project.openFiles.map(f => f.path)
  const affectedOpen = files.filter(f => openPaths.includes(f))
  await project.reloadOpenFiles(affectedOpen)
  await doSearch()
}

function fileName(path: string) {
  return path.split(/[/\\]/).pop() || path
}

// 高亮匹配文本
function highlightLine(text: string, matchText: string): string {
  if (!matchText) return escHtml(text)
  const escaped = matchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const re = new RegExp(`(${escaped})`, caseSensitive.value ? 'g' : 'gi')
  return escHtml(text).replace(re, '<span class="bg-[#613214] text-[#e8a64c]">$1</span>')
}

function escHtml(s: string) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}
</script>

<template>
  <div class="h-full flex flex-col text-[#a1a1aa] text-xs">
    <!-- 标题 -->
    <div class="h-9 px-3 border-b border-[#2e2e32] flex items-center justify-between shrink-0 bg-[#27272a]/30">
      <span class="text-xs text-[#cccccc] font-medium">搜索</span>
      <div class="flex gap-1.5">
        <i
          class="fa-solid fa-arrows-rotate text-[11px] cursor-pointer transition-colors"
          :class="searching ? 'text-blue-400 fa-spin' : 'hover:text-white'"
          title="刷新搜索"
          @click="doSearch"
        ></i>
        <i class="fa-solid fa-xmark text-[11px] hover:text-white cursor-pointer transition-colors" title="清除搜索" @click="searchQuery = ''; results = []"></i>
      </div>
    </div>

    <!-- 搜索输入区 -->
    <div class="px-3 py-2 border-b border-[#2e2e32] space-y-1.5">
      <!-- 搜索框 -->
      <div class="flex items-center gap-1">
        <i
          class="fa-solid fa-chevron-right text-[10px] cursor-pointer transition-transform shrink-0"
          :class="{ 'rotate-90': showReplace }"
          @click="showReplace = !showReplace"
        ></i>
        <div class="flex-1 flex items-center bg-[#27272a] border border-[#3e3e42] rounded overflow-hidden focus-within:border-[#0078d4] transition-colors">
          <input
            v-model="searchQuery"
            class="flex-1 bg-transparent px-2 py-1.5 text-xs text-white outline-none placeholder-[#52525b] min-w-0"
            placeholder="搜索"
            @keydown.enter="doSearch"
          />
          <div class="flex items-center gap-0.5 pr-1 shrink-0">
            <button
              class="w-5 h-5 flex items-center justify-center rounded text-[10px] transition-colors"
              :class="caseSensitive ? 'bg-[#0078d4] text-white' : 'text-[#717171] hover:text-white hover:bg-[#3e3e42]'"
              title="区分大小写"
              @click="caseSensitive = !caseSensitive; doSearch()"
            >Aa</button>
            <button
              class="w-5 h-5 flex items-center justify-center rounded text-[10px] transition-colors"
              :class="wholeWord ? 'bg-[#0078d4] text-white' : 'text-[#717171] hover:text-white hover:bg-[#3e3e42]'"
              title="全字匹配"
              @click="wholeWord = !wholeWord; doSearch()"
            ><span class="underline">ab</span></button>
            <button
              class="w-5 h-5 flex items-center justify-center rounded text-[10px] transition-colors"
              :class="useRegex ? 'bg-[#0078d4] text-white' : 'text-[#717171] hover:text-white hover:bg-[#3e3e42]'"
              title="使用正则表达式"
              @click="useRegex = !useRegex; doSearch()"
            >.*</button>
          </div>
        </div>
      </div>

      <!-- 替换框 -->
      <div v-if="showReplace" class="flex items-center gap-1 pl-3">
        <div class="flex-1 flex items-center bg-[#27272a] border border-[#3e3e42] rounded overflow-hidden focus-within:border-[#0078d4] transition-colors">
          <input
            v-model="replaceQuery"
            class="flex-1 bg-transparent px-2 py-1.5 text-xs text-white outline-none placeholder-[#52525b] min-w-0"
            placeholder="替换"
          />
        </div>
        <button
          class="w-6 h-6 flex items-center justify-center rounded text-[10px] text-[#717171] hover:text-white hover:bg-[#3e3e42] transition-colors shrink-0"
          title="全部替换"
          @click="replaceAll"
        >
          <i class="fa-solid fa-file-pen"></i>
        </button>
      </div>

      <!-- 过滤器切换 -->
      <div class="flex items-center pl-3">
        <button
          class="text-[10px] transition-colors"
          :class="showFilters ? 'text-white' : 'text-[#717171] hover:text-[#a1a1aa]'"
          @click="showFilters = !showFilters"
        >
          <i class="fa-solid fa-ellipsis"></i>
        </button>
      </div>

      <!-- 包含/排除文件 -->
      <template v-if="showFilters">
        <div class="pl-3 space-y-1">
          <div>
            <div class="text-[10px] text-[#717171] mb-0.5">包含的文件</div>
            <input
              v-model="includePattern"
              class="w-full bg-[#27272a] border border-[#3e3e42] rounded px-2 py-1 text-xs text-white outline-none placeholder-[#52525b] focus:border-[#0078d4] transition-colors"
              placeholder="例如: *.ts, src/**"
              @change="doSearch"
            />
          </div>
          <div>
            <div class="text-[10px] text-[#717171] mb-0.5">排除的文件</div>
            <input
              v-model="excludePattern"
              class="w-full bg-[#27272a] border border-[#3e3e42] rounded px-2 py-1 text-xs text-white outline-none placeholder-[#52525b] focus:border-[#0078d4] transition-colors"
              placeholder="例如: node_modules, *.min.js"
              @change="doSearch"
            />
          </div>
        </div>
      </template>
    </div>

    <!-- 搜索结果统计 -->
    <div v-if="searchQuery && !searching" class="px-3 py-1.5 text-[10px] text-[#717171] border-b border-[#2e2e32] shrink-0">
      {{ totalMatches }} 个结果，{{ results.length }} 个文件
    </div>

    <!-- 搜索中 -->
    <div v-if="searching" class="px-3 py-3 text-center text-[#52525b]">
      <i class="fa-solid fa-spinner fa-spin text-sm mb-1 block"></i>
      <p>搜索中...</p>
    </div>

    <!-- 结果列表 -->
    <div class="flex-1 overflow-y-auto">
      <div v-for="r in results" :key="r.file">
        <!-- 文件头 -->
        <div
          class="flex items-center gap-1.5 px-3 py-1 hover:bg-[#27272a] cursor-pointer select-none sticky top-0 bg-[#18181c] z-[1]"
          @click="toggleResult(r)"
        >
          <i
            class="fa-solid text-[9px] w-3 text-center transition-transform"
            :class="r.collapsed ? 'fa-chevron-right' : 'fa-chevron-down'"
          ></i>
          <span class="text-[#cccccc] truncate">{{ fileName(r.relPath) }}</span>
          <span class="text-[10px] text-[#52525b] truncate">{{ r.relPath }}</span>
          <span class="ml-auto text-[10px] text-[#52525b] bg-[#27272a] rounded px-1.5 shrink-0">{{ r.matches.length }}</span>
          <i
            v-if="showReplace"
            class="fa-solid fa-file-pen text-[10px] text-[#52525b] hover:text-white cursor-pointer shrink-0"
            title="替换此文件中的所有匹配"
            @click.stop="replaceInFile(r.file)"
          ></i>
        </div>
        <!-- 匹配行 -->
        <template v-if="!r.collapsed">
          <div
            v-for="(m, i) in r.matches" :key="i"
            class="flex items-start gap-2 px-3 py-0.5 pl-7 hover:bg-[#27272a] cursor-pointer text-[11px] leading-relaxed"
            @click="openMatch(r.file, fileName(r.relPath))"
          >
            <span class="text-[#52525b] w-8 text-right shrink-0 select-none">{{ m.line }}</span>
            <span class="flex-1 truncate text-[#cccccc] whitespace-pre" v-html="highlightLine(m.text.trim(), m.matchText)"></span>
          </div>
        </template>
      </div>

      <!-- 无结果 -->
      <div v-if="!searching && searchQuery && results.length === 0" class="px-4 py-6 text-center text-[#52525b]">
        <p>未找到结果</p>
      </div>

      <!-- 空状态 -->
      <div v-if="!searchQuery && !searching" class="px-4 py-8 text-center text-[#52525b]">
        <i class="fa-solid fa-magnifying-glass text-2xl mb-2 block"></i>
        <p>输入关键词开始搜索</p>
      </div>
    </div>
  </div>
</template>
