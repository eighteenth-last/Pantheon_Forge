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

export const useGitStore = defineStore('git', () => {
  const isRepo = ref(false)
  const loading = ref(false)
  const branch = ref('')
  const changedFiles = ref<GitFileStatus[]>([])
  const stagedFiles = ref<GitFileStatus[]>([])
  const untrackedFiles = ref<GitFileStatus[]>([])
  const commits = ref<GitCommit[]>([])
  const commitMessage = ref('')

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

  async function refresh() {
    const cwd = getCwd()
    if (!cwd || !isRepo.value) return
    loading.value = true
    try {
      const [br, statusList] = await Promise.all([
        window.api.git.branch(cwd),
        window.api.git.status(cwd),
      ])
      branch.value = br

      // 分类文件状态
      const staged: GitFileStatus[] = []
      const changed: GitFileStatus[] = []
      const untracked: GitFileStatus[] = []

      for (const item of statusList) {
        const x = item.status[0] || ' '  // index status
        const y = item.status.length > 1 ? item.status[1] : ' '  // worktree status
        const raw = item.status

        if (raw === '??' || raw === '?') {
          untracked.push({ status: 'U', file: item.file })
        } else {
          // 暂存区有变化
          if (x !== ' ' && x !== '?') {
            staged.push({ status: x, file: item.file })
          }
          // 工作区有变化
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
  }

  async function stageFile(file: string) {
    const cwd = getCwd()
    if (!cwd) return
    await window.api.git.add(cwd, [file])
    await refresh()
  }

  async function stageAll() {
    const cwd = getCwd()
    if (!cwd) return
    await window.api.git.add(cwd, ['.'])
    await refresh()
  }

  async function unstageFile(file: string) {
    const cwd = getCwd()
    if (!cwd) return
    await window.api.git.unstage(cwd, [file])
    await refresh()
  }

  async function discardFile(file: string) {
    const cwd = getCwd()
    if (!cwd) return
    await window.api.git.discard(cwd, file)
    await refresh()
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
    commits.value = await window.api.git.log(cwd, 30)
  }

  return {
    isRepo, loading, branch, changedFiles, stagedFiles, untrackedFiles, commits, commitMessage,
    checkIsRepo, initRepo, refresh, stageFile, stageAll, unstageFile, discardFile, commit, loadLog
  }
})
