/**
 * Search Worker — 在独立线程中执行文件搜索
 * 避免递归文件遍历阻塞主进程事件循环
 *
 * 参照 git-worker.ts 模式，使用 worker_threads parentPort 通信
 */
import { parentPort } from 'worker_threads'
import { readdir, readFile, stat } from 'fs/promises'
import { join, relative, extname } from 'path'

interface SearchRequest {
  id: string
  type: 'agent-search' | 'ipc-search'
  cwd: string
  query: string
  options: {
    isRegex?: boolean
    caseSensitive?: boolean
    wholeWord?: boolean
    pattern?: string          // 文件名匹配（agent 用）
    includePattern?: string   // glob include（IPC 用）
    excludePattern?: string   // glob exclude（IPC 用）
    maxResults?: number
    contextLines?: number
  }
}

const SKIP_DIRS = new Set([
  'node_modules', '.git', 'dist', 'dist-electron', '.idea', '.vscode',
  '__pycache__', '.next', 'build', 'target', '.gradle'
])

const TEXT_EXTS = new Set([
  '.ts', '.tsx', '.js', '.jsx', '.vue', '.html', '.htm', '.css', '.scss', '.less',
  '.json', '.md', '.txt', '.xml', '.svg', '.yaml', '.yml', '.toml', '.ini', '.cfg',
  '.py', '.java', '.kt', '.go', '.rs', '.rb', '.php', '.c', '.cpp', '.h', '.cs',
  '.swift', '.dart', '.lua', '.sh', '.bat', '.ps1', '.sql', '.graphql', '.env',
  '.gitignore', '.editorconfig', '.prettierrc', '.eslintrc', '.dockerfile',
])

function globToRegex(glob: string): RegExp {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')
  return new RegExp(`(^|/)${escaped}$`, 'i')
}

parentPort?.on('message', async (req: SearchRequest) => {
  const { id, type, cwd, query, options } = req
  const maxResults = options.maxResults || (type === 'agent-search' ? 50 : 500)
  const contextLines = options.contextLines ?? (type === 'agent-search' ? 2 : 0)

  try {
    // 构建正则
    let src = options.isRegex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    if (options.wholeWord) src = `\\b${src}\\b`
    const pattern = new RegExp(src, options.caseSensitive ? 'g' : 'gi')

    interface MatchItem {
      line: number
      col: number
      text: string
      matchText: string
      contextBefore?: string[]
      contextAfter?: string[]
    }

    const results: { file: string; relPath: string; matches: MatchItem[] }[] = []
    let totalMatches = 0
    let fileCount = 0
    const MAX_FILES = 5000

    function shouldInclude(relPath: string): boolean {
      if (options.includePattern) {
        const patterns = options.includePattern.split(',').map(p => p.trim()).filter(Boolean)
        if (patterns.length > 0 && !patterns.some(p => globToRegex(p).test(relPath))) return false
      }
      if (options.excludePattern) {
        const patterns = options.excludePattern.split(',').map(p => p.trim()).filter(Boolean)
        if (patterns.some(p => globToRegex(p).test(relPath))) return false
      }
      return true
    }

    async function walk(dir: string) {
      if (fileCount >= MAX_FILES || totalMatches >= maxResults) return
      let entries
      try { entries = await readdir(dir, { withFileTypes: true }) } catch { return }
      for (const entry of entries) {
        if (fileCount >= MAX_FILES || totalMatches >= maxResults) return
        const fullPath = join(dir, entry.name)
        if (entry.isDirectory()) {
          if (!SKIP_DIRS.has(entry.name) && !entry.name.startsWith('.')) await walk(fullPath)
        } else {
          const e = extname(entry.name).toLowerCase()
          const isText = TEXT_EXTS.has(e) || entry.name.startsWith('.') || e === ''
          if (!isText) continue

          // agent-search: 用 pattern 过滤文件名
          if (type === 'agent-search' && options.pattern) {
            if (!entry.name.match(new RegExp(options.pattern.replace(/\*/g, '.*')))) continue
          }

          const relPath = relative(cwd, fullPath).replace(/\\/g, '/')
          if (type === 'ipc-search' && !shouldInclude(relPath)) continue

          fileCount++
          try {
            const content = await readFile(fullPath, 'utf-8')
            const lines = content.split('\n')
            const matches: MatchItem[] = []
            for (let i = 0; i < lines.length; i++) {
              if (totalMatches >= maxResults) break
              pattern.lastIndex = 0
              let m
              while ((m = pattern.exec(lines[i])) !== null) {
                const item: MatchItem = {
                  line: i + 1,
                  col: m.index + 1,
                  text: lines[i],
                  matchText: m[0]
                }
                if (contextLines > 0) {
                  item.contextBefore = lines.slice(Math.max(0, i - contextLines), i)
                  item.contextAfter = lines.slice(i + 1, i + 1 + contextLines)
                }
                matches.push(item)
                totalMatches++
                if (!pattern.global) break
                if (totalMatches >= maxResults) break
              }
            }
            if (matches.length > 0) {
              results.push({ file: fullPath, relPath, matches })
            }
          } catch { /* skip binary / unreadable */ }
        }
      }
    }

    await walk(cwd)
    parentPort?.postMessage({
      id,
      result: results,
      truncated: totalMatches >= maxResults,
      totalMatches
    })
  } catch (err: any) {
    parentPort?.postMessage({ id, error: err.message })
  }
})
