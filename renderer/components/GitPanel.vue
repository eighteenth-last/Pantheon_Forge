<script setup lang="ts">
import { ref, computed, onMounted, watch, onBeforeUnmount } from 'vue'
import { useGitStore, type GitFileStatus } from '../stores/git'
import { useProjectStore } from '../stores/project'

const git = useGitStore()
const project = useProjectStore()

// 操作提示
const toast = ref<{ msg: string; type: 'ok' | 'err' } | null>(null)
let toastTimer: ReturnType<typeof setTimeout> | null = null

// 折叠状态
const collapsedStaged = ref(false)
const collapsedChanges = ref(false)
const collapsedGraph = ref(false)

// ---- 虚拟滚动 ----
const ITEM_HEIGHT = 26 // px per file row
const scrollContainer = ref<HTMLElement>()
const scrollTop = ref(0)
const containerHeight = ref(400)

function onScroll() {
  if (scrollContainer.value) {
    scrollTop.value = scrollContainer.value.scrollTop
  }
}

// 监听容器大小变化
let resizeObserver: ResizeObserver | null = null
onMounted(() => {
  if (project.projectPath) git.checkIsRepo().then(() => { if (git.isRepo) git.refresh() })
  if (scrollContainer.value) {
    containerHeight.value = scrollContainer.value.clientHeight
    resizeObserver = new ResizeObserver(entries => {
      for (const entry of entries) {
        containerHeight.value = entry.contentRect.height
      }
    })
    resizeObserver.observe(scrollContainer.value)
  }
})
onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  if (toastTimer) clearTimeout(toastTimer)
})
watch(() => project.projectPath, () => {
  git.checkIsRepo().then(() => { if (git.isRepo) git.refresh() })
})

/**
 * 构建统一的虚拟列表数据源
 * 将 section headers + file items 合并为一个扁平数组
 * 这样虚拟滚动只需要处理一个列表
 */
type VirtualItem =
  | { type: 'section-staged'; count: number }
  | { type: 'section-changes'; count: number }
  | { type: 'section-graph' }
  | { type: 'staged-file'; file: GitFileStatus }
  | { type: 'changed-file'; file: GitFileStatus }
  | { type: 'untracked-file'; file: GitFileStatus }
  | { type: 'commit'; commit: any }
  | { type: 'commit-detail'; commit: any }
  | { type: 'truncated-warning' }
  | { type: 'no-changes' }

const flatList = computed<VirtualItem[]>(() => {
  const items: VirtualItem[] = []

  // 暂存的更改
  if (git.stagedFiles.length > 0) {
    items.push({ type: 'section-staged', count: git.stagedFiles.length })
    if (!collapsedStaged.value) {
      for (const f of git.stagedFiles) items.push({ type: 'staged-file', file: f })
    }
  }

  // 更改
  const changesCount = git.changedFiles.length + git.untrackedFiles.length
  if (changesCount > 0) {
    items.push({ type: 'section-changes', count: changesCount })
    if (!collapsedChanges.value) {
      for (const f of git.changedFiles) items.push({ type: 'changed-file', file: f })
      for (const f of git.untrackedFiles) items.push({ type: 'untracked-file', file: f })
    }
  }

  // 截断警告
  if (git.statusTruncated) {
    items.push({ type: 'truncated-warning' })
  }

  // 无更改
  if (git.stagedFiles.length === 0 && git.changedFiles.length === 0 && git.untrackedFiles.length === 0 && !git.loading) {
    items.push({ type: 'no-changes' })
  }

  // 图形（提交历史）
  if (git.commits.length > 0) {
    items.push({ type: 'section-graph' })
    if (!collapsedGraph.value) {
      for (const c of git.commits) {
        items.push({ type: 'commit', commit: c })
        if (git.selectedCommit?.hash === c.hash) {
          items.push({ type: 'commit-detail', commit: c })
        }
      }
    }
  }

  return items
})

// 虚拟滚动计算：只渲染可见区域 + 上下各 5 个缓冲
const BUFFER = 5
const totalHeight = computed(() => flatList.value.length * ITEM_HEIGHT)
const visibleStart = computed(() => Math.max(0, Math.floor(scrollTop.value / ITEM_HEIGHT) - BUFFER))
const visibleEnd = computed(() => Math.min(flatList.value.length, Math.ceil((scrollTop.value + containerHeight.value) / ITEM_HEIGHT) + BUFFER))
const visibleItems = computed(() => flatList.value.slice(visibleStart.value, visibleEnd.value))
const offsetY = computed(() => visibleStart.value * ITEM_HEIGHT)

function showToast(msg: string, type: 'ok' | 'err' = 'ok') {
  toast.value = { msg, type }
  if (toastTimer) clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { toast.value = null }, 4000)
}

async function doPull() {
  showToast('正在拉取...', 'ok')
  const r = await git.pull()
  showToast(r.success ? `拉取成功${r.output ? ': ' + r.output.slice(0, 80) : ''}` : `拉取失败: ${r.output.slice(0, 80)}`, r.success ? 'ok' : 'err')
}
async function doPush() {
  showToast('正在推送...', 'ok')
  const r = await git.push()
  showToast(r.success ? `推送成功${r.output ? ': ' + r.output.slice(0, 80) : ''}` : `推送失败: ${r.output.slice(0, 80)}`, r.success ? 'ok' : 'err')
}
async function doFetch() {
  showToast('正在获取...', 'ok')
  const r = await git.fetch()
  showToast(r.success ? '获取成功' : `获取失败: ${r.output.slice(0, 80)}`, r.success ? 'ok' : 'err')
}

function sColor(s: string) {
  const m: Record<string, string> = { M: 'text-yellow-400', A: 'text-green-400', D: 'text-red-400', U: 'text-green-400', '?': 'text-green-400', R: 'text-blue-400' }
  return m[s] || 'text-[#a1a1aa]'
}
function fName(f: string) { return f.split(/[/\\]/).pop() || f }
function fDir(f: string) { const p = f.split(/[/\\]/); p.pop(); return p.join('/') }
</script>

<template>
  <div class="h-full flex flex-col text-[#a1a1aa] text-xs relative">
    <!-- 未初始化 -->
    <div v-if="!git.isRepo" class="flex-1 flex flex-col items-center justify-start px-4 pt-6">
      <div class="text-sm text-[#cccccc] font-medium mb-4 self-start">源代码管理</div>
      <div class="text-[13px] text-[#a1a1aa] leading-relaxed mb-5">当前打开的文件夹中没有 Git 存储库。可初始化一个仓库。</div>
      <button class="w-full py-2 bg-[#0078d4] hover:bg-[#1a8ae8] text-white text-[13px] rounded flex items-center justify-center gap-2" :disabled="git.loading" @click="git.initRepo()">
        <i v-if="git.loading" class="fa-solid fa-spinner fa-spin"></i><span>初始化仓库</span>
      </button>
    </div>
    <template v-else>
      <!-- Header -->
      <div class="h-9 px-3 border-b border-[#2e2e32] flex items-center justify-between shrink-0 bg-[#27272a]/30">
        <div class="flex items-center gap-1.5">
          <i class="fa-solid fa-code-branch text-xs text-blue-400"></i>
          <span class="text-xs text-[#cccccc] font-medium">{{ git.branch || 'main' }}</span>
        </div>
        <div class="flex items-center gap-2.5">
          <i class="fa-solid fa-cloud-arrow-down text-[11px] hover:text-white cursor-pointer transition-colors" title="拉取 (Pull)" @click="doPull()"></i>
          <i class="fa-solid fa-cloud-arrow-up text-[11px] hover:text-white cursor-pointer transition-colors" title="推送 (Push)" @click="doPush()"></i>
          <i class="fa-solid fa-download text-[11px] hover:text-white cursor-pointer transition-colors" title="获取 (Fetch)" @click="doFetch()"></i>
          <i class="fa-solid fa-arrows-rotate text-[11px] hover:text-white cursor-pointer transition-colors" title="刷新" @click="git.refresh()"></i>
        </div>
      </div>
      <!-- 提交输入 -->
      <div class="px-3 py-2 border-b border-[#2e2e32]">
        <div class="flex gap-1.5">
          <input v-model="git.commitMessage" class="flex-1 bg-[#27272a] border border-[#3e3e42] rounded px-2 py-1.5 text-xs text-white outline-none placeholder-[#52525b] focus:border-[#0078d4]" placeholder="提交消息" @keydown.enter.ctrl="git.commit()" />
          <button class="px-3 py-1.5 bg-[#0078d4] hover:bg-[#1a8ae8] text-white text-[11px] rounded shrink-0 disabled:opacity-40" :disabled="!git.commitMessage.trim() || git.stagedFiles.length === 0" @click="git.commit()"><i class="fa-solid fa-check"></i></button>
        </div>
      </div>

      <!-- 虚拟滚动区域 -->
      <div ref="scrollContainer" class="flex-1 overflow-y-auto" @scroll="onScroll">
        <div :style="{ height: totalHeight + 'px', position: 'relative' }">
          <div :style="{ transform: `translateY(${offsetY}px)` }">
            <template v-for="(item, i) in visibleItems" :key="visibleStart + i">

              <!-- 暂存的更改 section header -->
              <div v-if="item.type === 'section-staged'"
                class="flex items-center justify-between px-3 text-[11px] text-[#cccccc] font-medium bg-[#27272a]/30 select-none cursor-pointer hover:bg-[#27272a]/50"
                :style="{ height: ITEM_HEIGHT + 'px', lineHeight: ITEM_HEIGHT + 'px' }"
                @click="collapsedStaged = !collapsedStaged"
              >
                <div class="flex items-center gap-1">
                  <i class="fa-solid text-[9px] w-3 transition-transform" :class="collapsedStaged ? 'fa-chevron-right' : 'fa-chevron-down'"></i>
                  <span>暂存的更改 ({{ item.count }})</span>
                </div>
                <i class="fa-solid fa-minus text-[10px] hover:text-white cursor-pointer" title="全部取消暂存" @click.stop="git.stagedFiles.forEach(f => git.unstageFile(f.file))"></i>
              </div>

              <!-- 暂存文件 -->
              <div v-else-if="item.type === 'staged-file'"
                class="flex items-center gap-2 px-3 hover:bg-[#27272a] cursor-pointer group"
                :style="{ height: ITEM_HEIGHT + 'px' }"
                @click="git.openStagedDiff(item.file.file)"
              >
                <span :class="sColor(item.file.status)" class="w-3 text-center text-[10px] font-bold shrink-0">{{ item.file.status }}</span>
                <span class="flex-1 truncate text-[#cccccc]" :title="item.file.file">{{ fName(item.file.file) }}</span>
                <span class="text-[10px] text-[#52525b] truncate max-w-[80px]" :title="item.file.file">{{ fDir(item.file.file) }}</span>
                <i class="fa-solid fa-minus text-[10px] text-[#52525b] hover:text-white opacity-0 group-hover:opacity-100 shrink-0" title="取消暂存" @click.stop="git.unstageFile(item.file.file)"></i>
              </div>

              <!-- 更改 section header -->
              <div v-else-if="item.type === 'section-changes'"
                class="flex items-center justify-between px-3 text-[11px] text-[#cccccc] font-medium bg-[#27272a]/30 select-none cursor-pointer hover:bg-[#27272a]/50"
                :style="{ height: ITEM_HEIGHT + 'px', lineHeight: ITEM_HEIGHT + 'px' }"
                @click="collapsedChanges = !collapsedChanges"
              >
                <div class="flex items-center gap-1">
                  <i class="fa-solid text-[9px] w-3 transition-transform" :class="collapsedChanges ? 'fa-chevron-right' : 'fa-chevron-down'"></i>
                  <span>更改 ({{ item.count }})</span>
                </div>
                <i class="fa-solid fa-plus text-[10px] hover:text-white cursor-pointer" title="全部暂存" @click.stop="git.stageAll()"></i>
              </div>

              <!-- 已修改文件 -->
              <div v-else-if="item.type === 'changed-file'"
                class="flex items-center gap-2 px-3 hover:bg-[#27272a] cursor-pointer group"
                :style="{ height: ITEM_HEIGHT + 'px' }"
                @click="git.openWorkingDiff(item.file.file)"
              >
                <span :class="sColor(item.file.status)" class="w-3 text-center text-[10px] font-bold shrink-0">{{ item.file.status }}</span>
                <span class="flex-1 truncate text-[#cccccc]" :title="item.file.file">{{ fName(item.file.file) }}</span>
                <span class="text-[10px] text-[#52525b] truncate max-w-[80px]" :title="item.file.file">{{ fDir(item.file.file) }}</span>
                <i class="fa-solid fa-rotate-left text-[10px] text-[#52525b] hover:text-white opacity-0 group-hover:opacity-100 shrink-0" title="放弃更改" @click.stop="git.discardFile(item.file.file)"></i>
                <i class="fa-solid fa-plus text-[10px] text-[#52525b] hover:text-white opacity-0 group-hover:opacity-100 shrink-0" title="暂存" @click.stop="git.stageFile(item.file.file)"></i>
              </div>

              <!-- 未跟踪文件 -->
              <div v-else-if="item.type === 'untracked-file'"
                class="flex items-center gap-2 px-3 hover:bg-[#27272a] cursor-pointer group"
                :style="{ height: ITEM_HEIGHT + 'px' }"
              >
                <span class="text-green-400 w-3 text-center text-[10px] font-bold shrink-0">U</span>
                <span class="flex-1 truncate text-[#cccccc]" :title="item.file.file">{{ fName(item.file.file) }}</span>
                <span class="text-[10px] text-[#52525b] truncate max-w-[80px]" :title="item.file.file">{{ fDir(item.file.file) }}</span>
                <i class="fa-solid fa-plus text-[10px] text-[#52525b] hover:text-white opacity-0 group-hover:opacity-100 shrink-0" title="暂存" @click.stop="git.stageFile(item.file.file)"></i>
              </div>

              <!-- 截断警告 -->
              <div v-else-if="item.type === 'truncated-warning'"
                class="flex items-center gap-2 px-3 text-yellow-400/80"
                :style="{ height: ITEM_HEIGHT + 'px' }"
              >
                <i class="fa-solid fa-triangle-exclamation text-[10px]"></i>
                <span class="text-[10px]">文件过多，仅显示前 {{ git.statusTotal > 5000 ? '5000' : git.statusTotal }} 项（共 {{ git.statusTotal }} 项）</span>
              </div>

              <!-- 无更改 -->
              <div v-else-if="item.type === 'no-changes'" class="px-4 py-6 text-center text-[#52525b]">
                <i class="fa-solid fa-check-circle text-2xl mb-2 block text-green-500/50"></i><p>没有待提交的更改</p>
              </div>

              <!-- 图形 section header -->
              <div v-else-if="item.type === 'section-graph'"
                class="flex items-center justify-between px-3 text-[11px] text-[#cccccc] font-medium bg-[#27272a]/30 select-none cursor-pointer hover:bg-[#27272a]/50"
                :style="{ height: ITEM_HEIGHT + 'px', lineHeight: ITEM_HEIGHT + 'px' }"
                @click="collapsedGraph = !collapsedGraph"
              >
                <div class="flex items-center gap-1">
                  <i class="fa-solid text-[9px] w-3 transition-transform" :class="collapsedGraph ? 'fa-chevron-right' : 'fa-chevron-down'"></i>
                  <span>图形</span>
                </div>
                <div class="flex items-center gap-2.5">
                  <i class="fa-solid fa-cloud-arrow-down text-[10px] hover:text-white cursor-pointer transition-colors" title="拉取 (Pull)" @click.stop="doPull()"></i>
                  <i class="fa-solid fa-cloud-arrow-up text-[10px] hover:text-white cursor-pointer transition-colors" title="推送 (Push)" @click.stop="doPush()"></i>
                  <i class="fa-solid fa-download text-[10px] hover:text-white cursor-pointer transition-colors" title="获取 (Fetch)" @click.stop="doFetch()"></i>
                  <span class="text-[10px] text-[#52525b] ml-1">{{ git.commits.length }} 条提交</span>
                </div>
              </div>

              <!-- 提交记录 -->
              <div v-else-if="item.type === 'commit'"
                class="px-3 cursor-pointer transition-colors"
                :style="{ height: ITEM_HEIGHT + 'px' }"
                :class="git.selectedCommit?.hash === item.commit.hash ? 'bg-[#0078d4]/15' : 'hover:bg-[#27272a]'"
                @click="git.selectCommit(item.commit)"
              >
                <div class="flex items-center gap-2 h-full">
                  <div class="w-2 h-2 rounded-full border-[1.5px] shrink-0" :class="git.selectedCommit?.hash === item.commit.hash ? 'border-blue-400 bg-blue-400' : 'border-[#52525b] bg-[#18181c]'"></div>
                  <span class="text-[11px] text-[#cccccc] truncate flex-1">{{ item.commit.message }}</span>
                  <span class="text-[10px] text-[#52525b] font-mono shrink-0">{{ item.commit.shortHash }}</span>
                  <span class="text-[10px] text-[#52525b] shrink-0">{{ item.commit.date }}</span>
                </div>
              </div>

              <!-- 提交详情（展开的文件列表） -->
              <div v-else-if="item.type === 'commit-detail'"
                class="bg-[#1a1a1e] border-t border-b border-[#2e2e32]/50 py-1"
              >
                <div v-if="git.commitFilesLoading" class="px-6 py-2 text-center text-[#52525b]"><i class="fa-solid fa-spinner fa-spin"></i> 加载中...</div>
                <div v-else-if="git.commitFiles.length === 0" class="px-6 py-2 text-[#52525b]">无文件变更</div>
                <div v-else>
                  <div class="px-6 py-0.5 text-[10px] text-[#52525b]">{{ git.commitFiles.length }} 个文件变更</div>
                  <div v-for="cf in git.commitFiles" :key="cf.file" class="flex items-center gap-2 px-6 py-1 hover:bg-[#27272a] cursor-pointer group" @click="git.openCommitFileDiff(item.commit.hash, cf.file)">
                    <span :class="sColor(cf.status)" class="w-3 text-center text-[10px] font-bold shrink-0">{{ cf.status }}</span>
                    <span class="flex-1 truncate text-[#cccccc]" :title="cf.file">{{ fName(cf.file) }}</span>
                    <span class="text-[10px] text-[#52525b] truncate max-w-[80px]">{{ fDir(cf.file) }}</span>
                  </div>
                </div>
              </div>

            </template>
          </div>
        </div>

        <div v-if="git.loading" class="px-4 py-6 text-center text-[#52525b]">
          <i class="fa-solid fa-spinner fa-spin text-lg mb-2 block"></i><p>加载中...</p>
        </div>
      </div>
    </template>
    <!-- Toast 提示 -->
    <div v-if="toast" class="absolute bottom-2 left-2 right-2 px-3 py-2 rounded text-[11px] z-10 shadow-lg transition-all"
      :class="toast.type === 'ok' ? 'bg-[#1a3a1a] text-green-300 border border-green-800/50' : 'bg-[#3a1a1a] text-red-300 border border-red-800/50'"
    >
      <i :class="toast.type === 'ok' ? 'fa-solid fa-check-circle text-green-400' : 'fa-solid fa-exclamation-circle text-red-400'" class="mr-1.5"></i>
      {{ toast.msg }}
    </div>
  </div>
</template>
