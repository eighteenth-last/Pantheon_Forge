/**
 * ServiceManager - 管理长时间运行的服务进程
 *
 * 在主进程中运行，通过 node-pty 创建终端进程，
 * 监听输出匹配成功/失败模式，供 Agent 工具调用。
 *
 * 改进：
 * - 同名服务已运行时优先复用终端，不重复 kill+重建
 * - 错误 pattern 涵盖 npm error / Error: / FAILED / Exception
 * - buffer 扩大至 200 行，check_service 返回最近 100 行
 */
import type { BrowserWindow } from 'electron'

const PTY_BUFFER_MAX_LINES = 500

export interface ServiceInfo {
  serviceId: string
  termId: number
  command: string
  status: 'starting' | 'running' | 'stopped' | 'error'
  startTime: number
}

export class ServiceManager {
  private ptyMap: Map<number, any>
  private outputBuffer: Map<number, string[]>
  private serviceMap = new Map<string, ServiceInfo>()
  private nextTermId: { value: number }
  private mainWindow: () => BrowserWindow | null

  constructor(
    ptyMap: Map<number, any>,
    outputBuffer: Map<number, string[]>,
    nextTermId: { value: number },
    getMainWindow: () => BrowserWindow | null
  ) {
    this.ptyMap = ptyMap
    this.outputBuffer = outputBuffer
    this.nextTermId = nextTermId
    this.mainWindow = getMainWindow
  }

  appendBuffer(id: number, data: string) {
    if (!this.outputBuffer.has(id)) this.outputBuffer.set(id, [])
    const buf = this.outputBuffer.get(id)!
    const lines = data.split('\n')
    for (const line of lines) buf.push(line)
    while (buf.length > PTY_BUFFER_MAX_LINES) buf.shift()
  }

  getBuffer(id: number, lines = 100): string {
    const buf = this.outputBuffer.get(id) || []
    return buf.slice(-lines).join('\n')
  }

  async startService(
    serviceId: string,
    command: string,
    cwd: string,
    options?: { successPattern?: string; errorPattern?: string; timeoutMs?: number }
  ): Promise<{ success: boolean; status: string; termId: number; output: string }> {
    // ===== 终端复用逻辑 =====
    // 若同名服务已在运行（pty 进程存活），直接在其终端内执行命令，不重建终端
    const existing = this.serviceMap.get(serviceId)
    if (existing && this.ptyMap.has(existing.termId) && existing.status === 'running') {
      console.log(`[ServiceManager] 复用已有终端 ${existing.termId} (${serviceId})`)
      const proc = this.ptyMap.get(existing.termId)
      // 清空旧 buffer，准备接收新输出
      this.outputBuffer.set(existing.termId, [])
      existing.command = command
      existing.status = 'starting'
      existing.startTime = Date.now()
      proc.write(command + '\r')
      return this._waitForPattern(serviceId, existing.termId, options)
    }

    // 停掉旧服务（已停止/错误状态），并通知前端关闭对应 Tab
    if (existing && this.ptyMap.has(existing.termId)) {
      const oldTermId = existing.termId
      // 先通知前端关闭旧 Tab
      this.mainWindow()?.webContents.send('service:terminal-closed', { id: oldTermId, serviceId })
      this.ptyMap.get(oldTermId)?.kill()
      this.ptyMap.delete(oldTermId)
      this.outputBuffer.delete(oldTermId)
    }

    const pty = await import('@lydell/node-pty')
    const id = this.nextTermId.value++
    const isWin = process.platform === 'win32'
    const shell = isWin ? 'powershell.exe' : (process.env.SHELL || '/bin/bash')
    const shellArgs = isWin ? ['-NoLogo'] : []

    const proc = pty.spawn(shell, shellArgs, {
      name: 'xterm-256color',
      cols: 120,
      rows: 30,
      cwd: cwd || process.env.HOME || '.',
      env: { ...process.env } as Record<string, string>
    })

    this.outputBuffer.set(id, [])
    this.serviceMap.set(serviceId, { serviceId, termId: id, command, status: 'starting', startTime: Date.now() })

    const win = this.mainWindow()

    proc.onData((data: string) => {
      this.appendBuffer(id, data)
      win?.webContents.send('terminal:data', { id, data })
    })
    proc.onExit(({ exitCode }: { exitCode: number }) => {
      win?.webContents.send('terminal:exit', { id, exitCode })
      this.ptyMap.delete(id)
      const svc = this.serviceMap.get(serviceId)
      if (svc) svc.status = exitCode === 0 ? 'stopped' : 'error'
    })

    this.ptyMap.set(id, proc)
    proc.write(command + '\r')

    // 通知前端创建了新终端 tab
    win?.webContents.send('service:terminal-created', { id, serviceId, command })

    return this._waitForPattern(serviceId, id, options)
  }

  /** 等待成功/失败 pattern 或超时 */
  private _waitForPattern(
    serviceId: string,
    termId: number,
    options?: { successPattern?: string; errorPattern?: string; timeoutMs?: number }
  ): Promise<{ success: boolean; status: string; termId: number; output: string }> {
    // 增强错误 pattern：覆盖 npm error、Java 异常、通用 Error/FAILED
    const successPattern = options?.successPattern || 'Started|Listening|ready|compiled|running on|启动成功|Server running'
    const errorPattern = options?.errorPattern ||
      'BUILD FAILURE|EADDRINUSE|Cannot find module|npm error|npm ERR!|Error:|Exception:|FAILED|SyntaxError|ModuleNotFoundError|error TS'
    const timeoutMs = options?.timeoutMs || 60000

    return new Promise((resolve) => {
      let resolved = false

      const checkInterval = setInterval(() => {
        if (resolved) return
        const buf = this.outputBuffer.get(termId) || []
        const recentOutput = buf.join('\n')

        if (successPattern && new RegExp(successPattern, 'i').test(recentOutput)) {
          resolved = true
          clearInterval(checkInterval)
          const svc = this.serviceMap.get(serviceId)
          if (svc) svc.status = 'running'
          resolve({ success: true, status: 'running', termId, output: buf.slice(-50).join('\n') })
          return
        }

        if (errorPattern && new RegExp(errorPattern, 'i').test(recentOutput)) {
          resolved = true
          clearInterval(checkInterval)
          const svc = this.serviceMap.get(serviceId)
          if (svc) svc.status = 'error'
          resolve({ success: false, status: 'error', termId, output: buf.slice(-50).join('\n') })
          return
        }

        if (!this.ptyMap.has(termId)) {
          resolved = true
          clearInterval(checkInterval)
          resolve({ success: false, status: 'exited', termId, output: buf.slice(-50).join('\n') })
          return
        }
      }, 500)

      setTimeout(() => {
        if (resolved) return
        resolved = true
        clearInterval(checkInterval)
        const svc = this.serviceMap.get(serviceId)
        const buf = this.outputBuffer.get(termId) || []
        if (svc && svc.status === 'starting') svc.status = 'running'
        resolve({ success: true, status: 'timeout_assumed_running', termId, output: buf.slice(-50).join('\n') })
      }, timeoutMs)
    })
  }

  checkService(serviceId: string): { exists: boolean; status: string; termId?: number; command?: string; uptime?: number; output: string } {
    const svc = this.serviceMap.get(serviceId)
    if (!svc) return { exists: false, status: 'not_found', output: '' }
    const alive = this.ptyMap.has(svc.termId)
    const buf = this.outputBuffer.get(svc.termId) || []
    return {
      exists: true,
      status: alive ? svc.status : 'stopped',
      termId: svc.termId,
      command: svc.command,
      uptime: Date.now() - svc.startTime,
      output: buf.slice(-100).join('\n')  // 返回最近 100 行，覆盖更多错误输出
    }
  }

  stopService(serviceId: string): { success: boolean; error?: string } {
    const svc = this.serviceMap.get(serviceId)
    if (!svc) return { success: false, error: '服务不存在' }
    const proc = this.ptyMap.get(svc.termId)
    if (proc) {
      proc.kill()
      this.ptyMap.delete(svc.termId)
    }
    svc.status = 'stopped'
    return { success: true }
  }

  listServices(): ServiceInfo[] {
    const list: ServiceInfo[] = []
    for (const [, svc] of this.serviceMap) {
      const alive = this.ptyMap.has(svc.termId)
      list.push({ ...svc, status: alive ? svc.status : 'stopped' })
    }
    return list
  }
}
