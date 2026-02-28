/**
 * ServiceManager - 管理长时间运行的服务进程
 * 
 * 在主进程中运行，通过 node-pty 创建终端进程，
 * 监听输出匹配成功/失败模式，供 Agent 工具调用。
 */
import type { BrowserWindow } from 'electron'

const PTY_BUFFER_MAX_LINES = 200

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

  getBuffer(id: number, lines = 50): string {
    const buf = this.outputBuffer.get(id) || []
    return buf.slice(-lines).join('\n')
  }

  async startService(
    serviceId: string,
    command: string,
    cwd: string,
    options?: { successPattern?: string; errorPattern?: string; timeoutMs?: number }
  ): Promise<{ success: boolean; status: string; termId: number; output: string }> {
    // 如果已有同名服务在运行，先停掉
    const existing = this.serviceMap.get(serviceId)
    if (existing && this.ptyMap.has(existing.termId)) {
      this.ptyMap.get(existing.termId)?.kill()
      this.ptyMap.delete(existing.termId)
      this.outputBuffer.delete(existing.termId)
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

    // 发送命令
    proc.write(command + '\r')

    // 通知前端
    win?.webContents.send('service:terminal-created', { id, serviceId, command })

    const successPattern = options?.successPattern || 'Started|Listening|ready|compiled|running on|启动成功'
    const errorPattern = options?.errorPattern || 'BUILD FAILURE|EADDRINUSE|Cannot find module'
    const timeoutMs = options?.timeoutMs || 60000

    return new Promise((resolve) => {
      let resolved = false
      const checkInterval = setInterval(() => {
        if (resolved) return
        const buf = this.outputBuffer.get(id) || []
        const recentOutput = buf.join('\n')

        if (successPattern && new RegExp(successPattern, 'i').test(recentOutput)) {
          resolved = true
          clearInterval(checkInterval)
          const svc = this.serviceMap.get(serviceId)
          if (svc) svc.status = 'running'
          resolve({ success: true, status: 'running', termId: id, output: buf.slice(-20).join('\n') })
          return
        }

        if (errorPattern && new RegExp(errorPattern, 'i').test(recentOutput)) {
          resolved = true
          clearInterval(checkInterval)
          const svc = this.serviceMap.get(serviceId)
          if (svc) svc.status = 'error'
          resolve({ success: false, status: 'error', termId: id, output: buf.slice(-20).join('\n') })
          return
        }

        if (!this.ptyMap.has(id)) {
          resolved = true
          clearInterval(checkInterval)
          resolve({ success: false, status: 'exited', termId: id, output: buf.slice(-20).join('\n') })
          return
        }
      }, 500)

      setTimeout(() => {
        if (resolved) return
        resolved = true
        clearInterval(checkInterval)
        const svc = this.serviceMap.get(serviceId)
        const buf = this.outputBuffer.get(id) || []
        if (svc && svc.status === 'starting') svc.status = 'running'
        resolve({ success: true, status: 'timeout_assumed_running', termId: id, output: buf.slice(-20).join('\n') })
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
      output: buf.slice(-30).join('\n')
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
