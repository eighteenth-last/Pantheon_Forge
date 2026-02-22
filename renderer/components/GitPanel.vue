<script setup lang="ts">
import { onMounted, watch } from 'vue'
import { useGitStore, type GitFileStatus } from '../stores/git'
import { useProjectStore } from '../stores/project'

const git = useGitStore()
const project = useProjectStore()

onMounted(() => {
  if (project.projectPath) git.checkIsRepo().then(() => { if (git.isRepo) git.refresh() })
})

watch(() => project.projectPath, () => {
  git.checkIsRepo().then(() => { if (git.isRepo) git.refresh() })
})

function statusLabel(s: string) {
  const map: Record<string, string> = { M: '修改', A: '新增', D: '删除', R: '重命名', C: '复制', U: '未跟踪', '?': '未跟踪' }
  return map[s] || s
}

function statusColor(s: string) {
  const map: Record<string, string> = { M: 'text-yellow-400', A: 'text-green-400', D: 'text-red-400', U: 'text-green-400', '?': 'text-green-400', R: 'text-blue-400' }
  return map[s] || 'text-[#a1a1aa]'
}

function fileName(f: string) {
  return f.split(/[/\\]/).pop() || f
}
</script>

<template>
  <div class="h-full flex flex-col text-[#a1a1aa] text-xs">
    <!-- 未初始化 Git -->
    <div v-if="!git.isRepo" class="flex-1 flex flex-col items-center justify-start px-4 pt-6">
      <div class="text-sm text-[#cccccc] font-medium mb-4 self-start">源代码管理</div>
      <div class="text-[13px] text-[#a1a1aa] leading-relaxed mb-5">
        当前打开的文件夹中没有 Git 存储库。可初始化一个仓库，它将实现 Git 提供支持的源代码管理功能。
      </div>
      <button
        class="w-full py-2 bg-[#0078d4] hover:bg-[#1a8ae8] text-white text-[13px] rounded transition-colors flex items-center justify-center gap-2"
        :disabled="git.loading"
        @click="git.initRepo()"
      >
        <i v-if="git.loading" class="fa-solid fa-spinner fa-spin"></i>
        <span>初始化仓库</span>
      </button>
    </div>

    <!-- 已初始化 Git -->
    <template v-else>
      <!-- Header: 分支 + 操作 -->
      <div class="h-9 px-3 border-b border-[#2e2e32] flex items-center justify-between shrink-0 bg-[#27272a]/30">
        <div class="flex items-center gap-1.5">
          <i class="fa-solid fa-code-branch text-xs text-blue-400"></i>
          <span class="text-xs text-[#cccccc] font-medium">{{ git.branch || 'main' }}</span>
        </div>
        <div class="flex gap-2">
          <i class="fa-solid fa-arrows-rotate text-[11px] hover:text-white cursor-pointer transition-colors" title="刷新" @click="git.refresh()"></i>
        </div>
      </div>

      <!-- 提交消息输入 -->
      <div class="px-3 py-2 border-b border-[#2e2e32]">
        <div class="flex gap-1.5">
          <input
            v-model="git.commitMessage"
            class="flex-1 bg-[#27272a] border border-[#3e3e42] rounded px-2 py-1.5 text-xs text-white outline-none placeholder-[#52525b] focus:border-[#0078d4] transition-colors"
            placeholder="提交消息"
            @keydown.enter.ctrl="git.commit()"
          />
          <button
            class="px-3 py-1.5 bg-[#0078d4] hover:bg-[#1a8ae8] text-white text-[11px] rounded transition-colors shrink-0 disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="!git.commitMessage.trim() || git.stagedFiles.length === 0"
            title="提交暂存的更改 (Ctrl+Enter)"
            @click="git.commit()"
          >
            <i class="fa-solid fa-check"></i>
          </button>
        </div>
      </div>

      <!-- 文件列表 -->
      <div class="flex-1 overflow-y-auto">
        <!-- 暂存的更改 -->
        <div v-if="git.stagedFiles.length > 0">
          <div class="flex items-center justify-between px-3 py-1.5 text-[11px] text-[#cccccc] font-medium bg-[#27272a]/30 select-none">
            <span>暂存的更改 ({{ git.stagedFiles.length }})</span>
            <i class="fa-solid fa-minus text-[10px] hover:text-white cursor-pointer" title="全部取消暂存" @click="git.stagedFiles.forEach(f => git.unstageFile(f.file))"></i>
          </div>
          <div
            v-for="f in git.stagedFiles" :key="'s-' + f.file"
            class="flex items-center gap-2 px-3 py-1 hover:bg-[#27272a] cursor-pointer group"
          >
            <span :class="statusColor(f.status)" class="w-3 text-center text-[10px] font-bold shrink-0">{{ f.status }}</span>
            <span class="flex-1 truncate text-[#cccccc]" :title="f.file">{{ fileName(f.file) }}</span>
            <span class="text-[10px] text-[#52525b] truncate max-w-[80px]" :title="f.file">{{ f.file }}</span>
            <i class="fa-solid fa-minus text-[10px] text-[#52525b] hover:text-white cursor-pointer opacity-0 group-hover:opacity-100 transition-opacity shrink-0" title="取消暂存" @click.stop="git.unstageFile(f.file)"></i>
          </div>
        </div>

        <!-- 更改 -->
        <div v-if="git.changedFiles.length > 0 || git.untrackedFiles.length > 0">
          <div class="flex items-center justify-between px-3 py-1.5 text-[11px] text-[#cccccc] font-medium bg-[#27272a]/30 select-none">
            <span>更改 ({{ git.changedFiles.length + git.untrackedFiles.length }})</span>
            <div class="flex gap-2">
              <i class="fa-solid fa-plus text-[10px] hover:text-white cursor-pointer" title="全部暂存" @click="git.stageAll()"></i>
            </div>
          </div>
          <!-- 已跟踪的修改文件 -->
          <div
            v-for="f in git.changedFiles" :key="'c-' + f.file"
            class="flex items-center gap-2 px-3 py-1 hover:bg-[#27272a] cursor-pointer group"
          >
            <span :class="statusColor(f.status)" class="w-3 text-center text-[10px] font-bold shrink-0">{{ f.status }}</span>
            <span class="flex-1 truncate text-[#cccccc]" :title="f.file">{{ fileName(f.file) }}</span>
            <span class="text-[10px] text-[#52525b] truncate max-w-[80px]" :title="f.file">{{ f.file }}</span>
            <i class="fa-solid fa-rotate-left text-[10px] text-[#52525b] hover:text-white cursor-pointer opacity-0 group-hover:opacity-100 transition-opacity shrink-0" title="放弃更改" @click.stop="git.discardFile(f.file)"></i>
            <i class="fa-solid fa-plus text-[10px] text-[#52525b] hover:text-white cursor-pointer opacity-0 group-hover:opacity-100 transition-opacity shrink-0" title="暂存" @click.stop="git.stageFile(f.file)"></i>
          </div>
          <!-- 未跟踪文件 -->
          <div
            v-for="f in git.untrackedFiles" :key="'u-' + f.file"
            class="flex items-center gap-2 px-3 py-1 hover:bg-[#27272a] cursor-pointer group"
          >
            <span class="text-green-400 w-3 text-center text-[10px] font-bold shrink-0">U</span>
            <span class="flex-1 truncate text-[#cccccc]" :title="f.file">{{ fileName(f.file) }}</span>
            <span class="text-[10px] text-[#52525b] truncate max-w-[80px]" :title="f.file">{{ f.file }}</span>
            <i class="fa-solid fa-plus text-[10px] text-[#52525b] hover:text-white cursor-pointer opacity-0 group-hover:opacity-100 transition-opacity shrink-0" title="暂存" @click.stop="git.stageFile(f.file)"></i>
          </div>
        </div>

        <!-- 无更改 -->
        <div v-if="git.stagedFiles.length === 0 && git.changedFiles.length === 0 && git.untrackedFiles.length === 0 && !git.loading" class="px-4 py-6 text-center text-[#52525b]">
          <i class="fa-solid fa-check-circle text-2xl mb-2 block text-green-500/50"></i>
          <p>没有待提交的更改</p>
        </div>

        <!-- 加载中 -->
        <div v-if="git.loading" class="px-4 py-6 text-center text-[#52525b]">
          <i class="fa-solid fa-spinner fa-spin text-lg mb-2 block"></i>
          <p>加载中...</p>
        </div>
      </div>
    </template>
  </div>
</template>
