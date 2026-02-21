import { app, BrowserWindow, ipcMain, dialog } from 'electron'
import { join } from 'path'
import { AgentCore } from '../agent/agent-core'
import { ModelRouter } from '../agent/model-router'
import { ToolExecutor } from '../agent/tool-executor'
import { Database } from '../database/db'

let mainWindow: BrowserWindow | null = null
let database: Database
let agentCore: AgentCore

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 1000,
    minHeight: 600,
    frame: false,
    titleBarStyle: 'hidden',
    titleBarOverlay: {
      color: '#18181c',
      symbolColor: '#e4e4e7',
      height: 36
    },
    webPreferences: {
      preload: join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    },
    backgroundColor: '#101014'
  })

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL)
  } else {
    mainWindow.loadFile(join(__dirname, '../dist/index.html'))
  }
}

app.whenReady().then(() => {
  database = new Database()
  const modelRouter = new ModelRouter(database)
  const toolExecutor = new ToolExecutor()
  agentCore = new AgentCore(modelRouter, toolExecutor, database)

  createWindow()
  registerIpcHandlers()
})

app.on('window-all-closed', () => {
  database?.close()
  if (process.platform !== 'darwin') app.quit()
})

function registerIpcHandlers() {
  // ---- Model Management ----
  ipcMain.handle('models:list', () => database.getModels())
  ipcMain.handle('models:add', (_e, model) => database.addModel(model))
  ipcMain.handle('models:update', (_e, id, model) => database.updateModel(id, model))
  ipcMain.handle('models:delete', (_e, id) => database.deleteModel(id))
  ipcMain.handle('models:setActive', (_e, id) => database.setActiveModel(id))
  ipcMain.handle('models:deactivate', (_e, id) => database.deactivateModel(id))
  ipcMain.handle('models:getById', (_e, id) => database.getModelById(id))

  // ---- Session Management ----
  ipcMain.handle('sessions:list', () => database.getSessionsWithPreview())
  ipcMain.handle('sessions:create', (_e, projectPath) => database.createSession(projectPath))
  ipcMain.handle('sessions:getMessages', (_e, sessionId) => database.getMessages(sessionId))
  ipcMain.handle('sessions:delete', (_e, sessionId) => database.deleteSession(sessionId))

  // ---- Agent Chat (streaming via event) ----
  ipcMain.handle('agent:chat', async (_e, sessionId: number, userMessage: string, projectPath: string, modelId?: number | null) => {
    try {
      const chunks: string[] = []
      for await (const chunk of agentCore.run(sessionId, userMessage, projectPath, modelId ?? undefined)) {
        mainWindow?.webContents.send('agent:chunk', { sessionId, chunk })
        chunks.push(typeof chunk === 'string' ? chunk : JSON.stringify(chunk))
      }
      return { success: true, content: chunks.join('') }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  })

  ipcMain.handle('agent:stop', () => {
    agentCore.stop()
    return { success: true }
  })

  // ---- File Operations ----
  ipcMain.handle('fs:readDir', async (_e, dirPath: string) => {
    const { readdir, stat } = await import('fs/promises')
    const entries = await readdir(dirPath, { withFileTypes: true })
    return entries.map(e => ({
      name: e.name,
      isDirectory: e.isDirectory(),
      path: join(dirPath, e.name)
    }))
  })

  ipcMain.handle('fs:readFile', async (_e, filePath: string) => {
    const { readFile } = await import('fs/promises')
    return readFile(filePath, 'utf-8')
  })

  ipcMain.handle('fs:writeFile', async (_e, filePath: string, content: string) => {
    const { writeFile, mkdir } = await import('fs/promises')
    const { dirname } = await import('path')
    await mkdir(dirname(filePath), { recursive: true })
    await writeFile(filePath, content, 'utf-8')
    return true
  })

  // ---- Interactive Terminal (node-pty, multi-instance) ----
  const ptyMap = new Map<number, any>()
  let nextTermId = 1

  ipcMain.handle('terminal:create', async (_e, cwd: string) => {
    const pty = await import('@lydell/node-pty')
    const id = nextTermId++

    const isWin = process.platform === 'win32'
    const shell = isWin ? 'powershell.exe' : (process.env.SHELL || '/bin/bash')
    const args = isWin ? ['-NoLogo'] : []

    const proc = pty.spawn(shell, args, {
      name: 'xterm-256color',
      cols: 120,
      rows: 30,
      cwd: cwd || process.env.HOME || '.',
      env: { ...process.env } as Record<string, string>
    })

    proc.onData((data: string) => {
      mainWindow?.webContents.send('terminal:data', { id, data })
    })
    proc.onExit(({ exitCode }: { exitCode: number }) => {
      mainWindow?.webContents.send('terminal:exit', { id, exitCode })
      ptyMap.delete(id)
    })

    ptyMap.set(id, proc)
    return id
  })

  ipcMain.handle('terminal:write', (_e, id: number, data: string) => {
    ptyMap.get(id)?.write(data)
  })

  ipcMain.handle('terminal:resize', (_e, id: number, cols: number, rows: number) => {
    try { ptyMap.get(id)?.resize(cols, rows) } catch {}
  })

  ipcMain.handle('terminal:kill', (_e, id: number) => {
    const proc = ptyMap.get(id)
    if (proc) { proc.kill(); ptyMap.delete(id) }
    return true
  })

  ipcMain.handle('terminal:killAll', () => {
    for (const [id, proc] of ptyMap) { proc.kill(); ptyMap.delete(id) }
    return true
  })

  // Keep old shell:exec for agent tool use
  ipcMain.handle('shell:exec', async (_e, command: string, cwd: string) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn(command, { shell: true, cwd })
      let stdout = '', stderr = ''
      proc.stdout?.on('data', (d: Buffer) => { stdout += d.toString() })
      proc.stderr?.on('data', (d: Buffer) => { stderr += d.toString() })
      proc.on('close', code => resolve({ stdout, stderr, code }))
      setTimeout(() => { proc.kill(); resolve({ stdout, stderr, code: -1, timeout: true }) }, 30000)
    })
  })

  // ---- File Watcher ----
  let watcher: any = null
  ipcMain.handle('fs:watch', async (_e, dirPath: string) => {
    const { watch } = await import('fs')
    if (watcher) { watcher.close(); watcher = null }
    watcher = watch(dirPath, { recursive: true }, (eventType, filename) => {
      if (filename && !filename.includes('node_modules') && !filename.startsWith('.git')) {
        mainWindow?.webContents.send('fs:changed', { eventType, filename, dirPath })
      }
    })
    return true
  })

  ipcMain.handle('fs:unwatch', () => {
    if (watcher) { watcher.close(); watcher = null }
    return true
  })

  // ---- Dialog ----
  ipcMain.handle('dialog:openFolder', async () => {
    const result = await dialog.showOpenDialog({ properties: ['openDirectory'] })
    return result.canceled ? null : result.filePaths[0]
  })
}
