import { defineStore } from 'pinia'
import { ref } from 'vue'
import { useProjectStore } from './project'

export interface GitFileStatus {
  status: string
  file: string
}

export interface GitCommit {
  hash: string
  shortHash: string
  author: string
  date: string
  message: string
}

export interface CommitFileInfo {
  status: string
  file: string
}

/**
 * Git Status 结果上限（仿 VS Code 的 git.statusLimit）
 * 超过此数量时截断，避免 UI 卡顿
 */
const STATUS_LIMIT = 5000

/**
 * 简易 throttle：同一时间只允许一个 refresh 在执行，
 * 执行期间的新请求会排队，但只保留最后一个
 */
function createThrottle() {
  let running = false
  let pending: (() => Promise<void>) | null = null

  return async function throttled(fn: () => Promise<void>) {
    if (running) {
      // 已有任务在跑，记录最新请求（覆盖旧的）
      pending = fn
      return
    }
    running = true
    try {
      await fn()
    } finally {
      running = false
      // 执行完后如果有排队的请求，立即执行
      if (pending) {
        const next = pending
        pending = null
        await throttled(next)
      }
    }
  }
}

export const useGitStore = defineStore('git', () => {
  const isRepo = ref(false)
  const loading = ref(false)
  const branch = ref('')
  const changedFiles = ref<GitFileStatus[]>([])
  const stagedFiles = ref<GitFileStatus[]>([])
  const untrackedFiles = ref<GitFileStatus[]>([])
  const commits = ref<GitCommit[]>([])
  const commitMessage = ref('')
  /** 是否因文件过多而截断 */
  const statusTruncated = ref(false)
  const statusTotal = ref(0)

  // 提交历史
  const selectedCommit = ref<GitCommit | null>(null)
  const commitFiles = ref<CommitFileInfo[]>([])
  const commitFilesLoading = ref(false)

  // Throttle 控制
  const refreshThrottle = createThrottle()
  let refreshDebounceTimer: ReturnType<typeof setTimeout> | null = null

  function getCwd() {
    return useProjectStore().projectPath
  }

  async function checkIsRepo() {
    const cwd = getCwd()
    if (!cwd) { isRepo.value = false; return }
    isRepo.value = await window.api.git.isRepo(cwd)
  }

  async function initRepo() {
    const cwd = getCwd()
    if (!cwd) return
    loading.value = true
    const result = await window.api.git.init(cwd)
    if (result.success) {
      isRepo.value = true
      await refresh()
    }
    loading.value = false
  }

  /**
   * 防抖刷新：短时间内多次调用只执行最后一次
   * 用于文件操作后的自动刷新
   */
  function debouncedRefresh(delay = 300) {
    if (refreshDebounceTimer) clearTimeout(refreshDebounceTimer)
    refreshDebounceTimer = setTimeout(() => {
      refreshDebounceTimer = null
      refresh()
    }, delay)
  }

  /**
   * 核心刷新：throttle 保护，同一时间只跑一个
   */
  async function refresh() {
    const cwd = getCwd()
    if (!cwd || !isRepo.value) return

    await refreshThrottle(async () => {
      loading.value = true
      try {
        const [br, statusResult, log] = await Promise.all([
          window.api.git.branch(cwd),
          window.api.git.status(cwd),
          window.api.git.log(cwd, 50),
        ])
        branch.value = br
        commits.value = log

        // 检查是否截断
        const statusList = statusResult.items || statusResult
        const truncated = statusResult.truncated || false
        const total = statusResult.total || statusList.length
        statusTruncated.value = truncated
        statusTotal.value = total

        const staged: GitFileStatus[] = []
        const changed: GitFileStatus[] = []
        const untracked: GitFileStatus[] = []

        for (const item of statusList) {
          const x = item.status[0] || ' '
          const y = item.status.length > 1 ? item.status[1] : ' '
          const raw = item.status

          if (raw === '??' || raw === '?') {
            untracked.push({ status: 'U', file: item.file })
          } else {
            if (x !== ' ' && x !== '?') {
              staged.push({ status: x, file: item.file })
            }
            if (y !== ' ' && y !== '?') {
              changed.push({ status: y, file: item.file })
            }
          }
        }

        stagedFiles.value = staged
        changedFiles.value = changed
        untrackedFiles.value = untracked
      } catch (err) {
        console.error('Git refresh failed:', err)
      }
      loading.value = false
    })
  }

  async function stageFile(file: string) {
    const cwd = getCwd()
    if (!cwd) return
    await window.api.git.add(cwd, [file])
    debouncedRefresh()
  }

  async function stageAll() {
    const cwd = getCwd()
    if (!cwd) return
    await window.api.git.add(cwd, ['.'])
    debouncedRefresh()
  }

  async function unstageFile(file: string) {
    const cwd = getCwd()
    if (!cwd) return
    await window.api.git.unstage(cwd, [file])
    debouncedRefresh()
  }

  async function discardFile(file: string) {
    const cwd = getCwd()
    if (!cwd) return
    await window.api.git.discard(cwd, file)
    debouncedRefresh()
  }

  async function commit() {
    const cwd = getCwd()
    if (!cwd || !commitMessage.value.trim()) return
    const result = await window.api.git.commit(cwd, commitMessage.value.trim())
    if (result.success) {
      commitMessage.value = ''
      await refresh()
    }
    return result
  }

  async function loadLog() {
    const cwd = getCwd()
    if (!cwd || !isRepo.value) return
    commits.value = await window.api.git.log(cwd, 50)
  }

  async function pull() {
    const cwd = getCwd()
    if (!cwd) return { success: false, output: '' }
    loading.value = true
    const result = await window.api.git.pull(cwd)
    await refresh()
    loading.value = false
    return result
  }

  async function push() {
    const cwd = getCwd()
    if (!cwd) return { success: false, output: '' }
    loading.value = true
    const result = await window.api.git.push(cwd)
    loading.value = false
    return result
  }

  async function fetch_() {
    const cwd = getCwd()
    if (!cwd) return { success: false, output: '' }
    loading.value = true
    const result = await window.api.git.fetch(cwd)
    loading.value = false
    return result
  }

  async function selectCommit(c: GitCommit) {
    if (selectedCommit.value?.hash === c.hash) {
      selectedCommit.value = null
      commitFiles.value = []
      return
    }
    selectedCommit.value = c
    commitFiles.value = []
    commitFilesLoading.value = true
    const cwd = getCwd()
    if (!cwd) return
    try {
      commitFiles.value = await window.api.git.showCommitFiles(cwd, c.hash)
    } catch (err) {
      console.error('Failed to load commit files:', err)
    }
    commitFilesLoading.value = false
  }

  async function openWorkingDiff(file: string) {
    const cwd = getCwd()
    if (!cwd) return
    const project = useProjectStore()
    try {
      const [original, modified] = await Promise.all([
        window.api.git.showFile(cwd, 'HEAD', file),
        window.api.fs.readFile(cwd + '/' + file.replace(/\\/g, '/')),
      ])
      const name = file.split(/[/\\]/).pop() || file
      project.openDiff(file, name, original, modified, `${name} (工作区更改)`)
    } catch (err) {
      console.error('Failed to open working diff:', err)
    }
  }

  async function openStagedDiff(file: string) {
    const cwd = getCwd()
    if (!cwd) return
    const project = useProjectStore()
    try {
      const [original, modified] = await Promise.all([
        window.api.git.showFile(cwd, 'HEAD', file),
        window.api.git.showFile(cwd, ':0', file),
      ])
      const name = file.split(/[/\\]/).pop() || file
      project.openDiff(file, name, original, modified, `${name} (已暂存)`)
    } catch (err) {
      console.error('Failed to open staged diff:', err)
    }
  }

  async function openCommitFileDiff(hash: string, file: string) {
    const cwd = getCwd()
    if (!cwd) return
    const project = useProjectStore()
    try {
      const [original, modified] = await Promise.all([
        window.api.git.showFile(cwd, `${hash}~1`, file),
        window.api.git.showFile(cwd, hash, file),
      ])
      const name = file.split(/[/\\]/).pop() || file
      const commit = commits.value.find(c => c.hash === hash)
      const label = commit ? `${name} (${commit.shortHash} ${commit.message.slice(0, 30)})` : `${name} (${hash.slice(0, 7)})`
      project.openDiff(file, name, original, modified, label)
    } catch (err) {
      console.error('Failed to open commit file diff:', err)
    }
  }

  return {
    isRepo, loading, branch, changedFiles, stagedFiles, untrackedFiles, commits, commitMessage,
    statusTruncated, statusTotal,
    selectedCommit, commitFiles, commitFilesLoading,
    checkIsRepo, initRepo, refresh, stageFile, stageAll, unstageFile, discardFile, commit, loadLog,
    pull, push, fetch: fetch_,
    selectCommit, openWorkingDiff, openStagedDiff, openCommitFileDiff
  }
})
