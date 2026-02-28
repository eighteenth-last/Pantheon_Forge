/**
 * Git Worker — 在独立线程中执行 git 命令
 * 避免 git spawn 的 stdout 处理阻塞主进程事件循环
 *
 * 使用 Node.js worker_threads，通过 parentPort 通信
 */
import { parentPort } from 'worker_threads'
import { spawn } from 'child_process'

interface GitRequest {
  id: string
  command: string[]
  cwd: string
  /** 如何解析输出 */
  parser: 'raw' | 'boolean' | 'lines' | 'status' | 'log' | 'commitFiles' | 'result'
}

function execGit(args: string[], cwd: string): Promise<{ stdout: string; stderr: string; code: number }> {
  return new Promise((resolve) => {
    const proc = spawn('git', args, { cwd, shell: true })
    let stdout = '', stderr = ''
    proc.stdout?.on('data', (d: Buffer) => { stdout += d.toString() })
    proc.stderr?.on('data', (d: Buffer) => { stderr += d.toString() })
    proc.on('close', (code) => resolve({ stdout, stderr, code: code ?? -1 }))
    proc.on('error', (e) => resolve({ stdout, stderr: e.message, code: -1 }))
  })
}

parentPort?.on('message', async (req: GitRequest) => {
  const { id, command, cwd, parser } = req
  try {
    const { stdout, stderr, code } = await execGit(command, cwd)

    let result: any
    switch (parser) {
      case 'raw':
        result = code === 0 ? stdout : ''
        break
      case 'boolean':
        result = code === 0
        break
      case 'lines':
        result = stdout.trim()
        break
      case 'status':
        if (code !== 0) { result = { items: [], truncated: false, total: 0 }; break }
        const allLines = stdout.trim().split('\n').filter(Boolean)
        const total = allLines.length
        // 默认 limit 5000，可通过 command 参数传入
        const limit = (req as any).limit || 5000
        const truncated = total > limit
        const lines = truncated ? allLines.slice(0, limit) : allLines
        result = {
          items: lines.map(line => {
            const status = line.substring(0, 2)
            const file = line.substring(3)
            return { status: status.trim() || '?', file }
          }),
          truncated,
          total
        }
        break
      case 'log':
        result = stdout.trim().split('\n').filter(Boolean).map(line => {
          const [hash, shortHash, author, date, ...msgParts] = line.split('\t')
          return { hash, shortHash, author, date, message: msgParts.join('\t') }
        })
        break
      case 'commitFiles':
        result = stdout.trim().split('\n').filter(Boolean).map(line => {
          const parts = line.split('\t')
          return { status: parts[0] || '?', file: parts.slice(1).join('\t') }
        })
        break
      case 'result':
        result = { success: code === 0, output: code === 0 ? (stdout.trim() || stderr.trim()) : stderr.trim() }
        break
      default:
        result = stdout
    }

    parentPort?.postMessage({ id, result })
  } catch (err: any) {
    parentPort?.postMessage({ id, error: err.message })
  }
})
