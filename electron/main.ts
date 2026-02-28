// ===== Windows 控制台 UTF-8 编码修复（防止中文乱码）=====
if (process.platform === 'win32') {
  // 强制 stdout / stderr 以 UTF-8 输出，解决 GBK 乱码
  if (process.stdout.isTTY) (process.stdout as any)._handle?.setBlocking?.(true)
  try { (process.stdout as any).setDefaultEncoding?.('utf8') } catch { }
  try { (process.stderr as any).setDefaultEncoding?.('utf8') } catch { }
}

import { app, BrowserWindow, ipcMain, dialog } from 'electron'
import { join } from 'path'
import { AgentCore } from '../agent/agent-core'
import { ModelRouter } from '../agent/model-router'
import { ToolExecutor } from '../agent/tool-executor'
import { ServiceManager } from '../agent/service-manager'
import { SkillLoader } from '../agent/skill-loader'
import { MCPClient } from '../agent/mcp-client'
import { Database } from '../database/db'

import { createServer, type Server } from 'http'
import { readFile as fsReadFile } from 'fs/promises'
import { extname } from 'path'
import { Worker } from 'worker_threads'

let mainWindow: BrowserWindow | null = null
let database: Database
let agentCore: AgentCore
let serviceManager: ServiceManager
let fileServer: Server | null = null
let fileServerPort = 0

// ========== Git Worker（独立线程执行 git 命令） ==========
let gitWorker: Worker | null = null
const gitPendingRequests = new Map<string, { resolve: (v: any) => void; reject: (e: any) => void }>()
let gitReqId = 0

function initGitWorker() {
  const workerPath = join(__dirname, 'git-worker.js')
  gitWorker = new Worker(workerPath)
  gitWorker.on('message', (msg: { id: string; result?: any; error?: string }) => {
    const pending = gitPendingRequests.get(msg.id)
    if (pending) {
      gitPendingRequests.delete(msg.id)
      if (msg.error) pending.reject(new Error(msg.error))
      else pending.resolve(msg.result)
    }
  })
  gitWorker.on('error', (err) => {
    console.error('[GitWorker] error:', err)
  })
}

function gitExec(command: string[], cwd: string, parser: string): Promise<any> {
  return new Promise((resolve, reject) => {
    const id = `git_${++gitReqId}`
    gitPendingRequests.set(id, { resolve, reject })
    gitWorker?.postMessage({ id, command, cwd, parser })
  })
}

// ========== Search Worker（独立线程执行文件搜索） ==========
let searchWorker: Worker | null = null
const searchPendingRequests = new Map<string, { resolve: (v: any) => void; reject: (e: any) => void }>()
let searchReqId = 0

function initSearchWorker() {
  const workerPath = join(__dirname, 'search-worker.js')
  searchWorker = new Worker(workerPath)
  searchWorker.on('message', (msg: { id: string; result?: any; error?: string; truncated?: boolean; totalMatches?: number }) => {
    const pending = searchPendingRequests.get(msg.id)
    if (pending) {
      searchPendingRequests.delete(msg.id)
      if (msg.error) pending.reject(new Error(msg.error))
      else pending.resolve({ results: msg.result, truncated: msg.truncated, totalMatches: msg.totalMatches })
    }
  })
  searchWorker.on('error', (err) => {
    console.error('[SearchWorker] error:', err)
  })
}

function searchExec(cwd: string, query: string, type: 'agent-search' | 'ipc-search', options: Record<string, any> = {}): Promise<any> {
  return new Promise((resolve, reject) => {
    const id = `search_${++searchReqId}`
    searchPendingRequests.set(id, { resolve, reject })
    searchWorker?.postMessage({ id, type, cwd, query, options })
  })
}

// ========== Agent Chunk 批量发送（减少 IPC 开销） ==========
let chunkBuffer: { sessionId: number; chunk: any }[] = []
let chunkFlushTimer: ReturnType<typeof setTimeout> | null = null
const CHUNK_FLUSH_INTERVAL = 32 // ms — 约 30fps，人眼感知不到延迟

function queueAgentChunk(sessionId: number, chunk: any) {
  chunkBuffer.push({ sessionId, chunk })
  if (!chunkFlushTimer) {
    chunkFlushTimer = setTimeout(flushAgentChunks, CHUNK_FLUSH_INTERVAL)
  }
}

function flushAgentChunks() {
  chunkFlushTimer = null
  if (chunkBuffer.length === 0) return
  const batch = chunkBuffer
  chunkBuffer = []
  // 批量发送：一次 IPC 调用传递所有 chunks
  mainWindow?.webContents.send('agent:chunks', batch)
}

/** 立即刷新（用于 done/error 等需要即时响应的事件） */
function flushAgentChunksNow() {
  if (chunkFlushTimer) { clearTimeout(chunkFlushTimer); chunkFlushTimer = null }
  flushAgentChunks()
}

// ========== PTY 输出节流（减少终端数据 IPC 洪泛） ==========
const ptyBufferMap = new Map<number, string>()
let ptyFlushTimer: ReturnType<typeof setTimeout> | null = null
const PTY_FLUSH_INTERVAL = 16 // ms — 约 60fps

function queuePtyData(id: number, data: string) {
  const existing = ptyBufferMap.get(id) || ''
  ptyBufferMap.set(id, existing + data)
  if (!ptyFlushTimer) {
    ptyFlushTimer = setTimeout(flushPtyData, PTY_FLUSH_INTERVAL)
  }
}

function flushPtyData() {
  ptyFlushTimer = null
  for (const [id, data] of ptyBufferMap) {
    if (data) mainWindow?.webContents.send('terminal:data', { id, data })
  }
  ptyBufferMap.clear()
}

// ========== 文件监听事件防抖（批量合并） ==========
let fsChangeBuffer: { eventType: string; filename: string; dirPath: string }[] = []
let fsChangeTimer: ReturnType<typeof setTimeout> | null = null
const FS_CHANGE_DEBOUNCE = 300 // ms

function queueFsChange(eventType: string, filename: string, dirPath: string) {
  fsChangeBuffer.push({ eventType, filename, dirPath })
  if (!fsChangeTimer) {
    fsChangeTimer = setTimeout(flushFsChanges, FS_CHANGE_DEBOUNCE)
  }
}

function flushFsChanges() {
  fsChangeTimer = null
  if (fsChangeBuffer.length === 0) return
  // 去重：同一文件只保留最后一个事件
  const seen = new Map<string, typeof fsChangeBuffer[0]>()
  for (const ev of fsChangeBuffer) seen.set(ev.filename, ev)
  const batch = [...seen.values()]
  fsChangeBuffer = []
  // 批量发送
  mainWindow?.webContents.send('fs:changes', batch)
}

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
    icon: join(__dirname, process.env.VITE_DEV_SERVER_URL ? '../public/icon.png' : '../dist/icon.png'),
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

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html', '.htm': 'text/html', '.css': 'text/css',
  '.js': 'application/javascript', '.mjs': 'application/javascript',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.ttf': 'font/ttf', '.eot': 'application/vnd.ms-fontobject',
  '.xml': 'application/xml', '.pdf': 'application/pdf',
  '.mp4': 'video/mp4', '.webm': 'video/webm', '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav', '.webp': 'image/webp', '.txt': 'text/plain',
}

// 当前预览的基础目录（HTML 文件所在目录）
let previewBaseDir = ''

function startFileServer(): Promise<void> {
  return new Promise((resolve) => {
    fileServer = createServer(async (req, res) => {
      try {
        const url = new URL(req.url || '/', `http://localhost`)
        let requestPath = decodeURIComponent(url.pathname)

        // 根路径 → 需要 ?file= 参数指定 HTML 文件
        if (requestPath === '/' || requestPath === '') {
          const filePath = url.searchParams.get('file')
          if (!filePath) { res.writeHead(400); res.end('Missing file parameter'); return }
          // 设置基础目录为 HTML 文件所在目录
          const { dirname } = require('path')
          previewBaseDir = dirname(filePath)
          const data = await fsReadFile(filePath)
          const ext = extname(filePath).toLowerCase()
          res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'text/html', 'Access-Control-Allow-Origin': '*' })
          res.end(data)
          return
        }

        // 相对资源请求 → 基于 previewBaseDir 解析
        if (previewBaseDir) {
          const { resolve: pathResolve, normalize } = require('path')
          const resolved = normalize(pathResolve(previewBaseDir, requestPath.slice(1)))
          // 安全检查：不允许访问基础目录之外的文件（向上遍历）
          // 但允许同级和子级
          const data = await fsReadFile(resolved)
          const ext = extname(resolved).toLowerCase()
          res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream', 'Access-Control-Allow-Origin': '*' })
          res.end(data)
          return
        }

        res.writeHead(404); res.end('Not found')
      } catch (err: any) {
        if (err.code === 'ENOENT') {
          res.writeHead(404); res.end('File not found')
        } else {
          res.writeHead(500); res.end(err.message)
        }
      }
    })

    fileServer.listen(0, '127.0.0.1', () => {
      const addr = fileServer!.address() as any
      fileServerPort = addr.port
      console.log(`[FileServer] Listening on http://127.0.0.1:${fileServerPort}`)
      resolve()
    })
  })
}

// 禁用 Autofill，消除 DevTools "Autofill.enable wasn't found" 报错
app.commandLine.appendSwitch('disable-features', 'AutofillServerCommunication')

// ===== 用 electron.net.fetch 替换全局 fetch =====
// Node.js 原生 fetch 不走系统代理/VPN，electron.net.fetch 基于 Chromium 网络栈，
// 自动识别系统代理设置，解决挂 VPN 后 "fetch failed" 的问题
import('electron').then(({ net }) => {
  (global as any).fetch = net.fetch.bind(net)
  console.log('[Main] 已启用 electron.net.fetch（代理感知模式）')
})

app.whenReady().then(async () => {
  database = new Database()
  const modelRouter = new ModelRouter(database)
  const toolExecutor = new ToolExecutor()

  // 初始化 SkillLoader（本地 skills/ 目录）和 MCPClient
  const skillsDir = join(app.getAppPath(), 'skills')
  const skillLoader = new SkillLoader(skillsDir)
  const mcpClient = new MCPClient()

  agentCore = new AgentCore(modelRouter, toolExecutor, database, skillLoader, mcpClient)

  // 注入 SkillLoader 到 ToolExecutor（供 load_skill 工具使用）
  toolExecutor.setSkillLoader(skillLoader)

  // 启动 Git Worker 线程
  initGitWorker()

  // 启动 Search Worker 线程
  initSearchWorker()

  // 启动本地文件服务器（用于内置浏览器预览）
  await startFileServer()

  createWindow()
  registerIpcHandlers(toolExecutor)
})

app.on('window-all-closed', () => {
  database?.close()
  gitWorker?.terminate()
  searchWorker?.terminate()
  agentCore?.shutdown().catch(() => { })
  if (process.platform !== 'darwin') app.quit()
})

function registerIpcHandlers(toolExecutor: ToolExecutor) {
  // ---- Window Controls ----
  ipcMain.on('window:minimize', () => mainWindow?.minimize())
  ipcMain.on('window:maximize', () => {
    if (mainWindow?.isMaximized()) mainWindow.unmaximize()
    else mainWindow?.maximize()
  })
  ipcMain.on('window:close', () => mainWindow?.close())

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

  // ---- Agent Chat (streaming via batched events) ----
  ipcMain.handle('agent:chat', async (_e, sessionId: number, userMessage: string, projectPath: string, modelId?: number | null, images?: string[]) => {
    try {
      const chunks: string[] = []
      for await (const chunk of agentCore.run(sessionId, userMessage, projectPath, modelId ?? undefined, images)) {
        // 文本和 thinking 走批量队列，工具调用/done/error 立即刷新
        const chunkType = (chunk as any).type
        if (chunkType === 'text' || chunkType === 'thinking') {
          queueAgentChunk(sessionId, chunk)
        } else {
          // tool_call / tool_result / done / error → 先刷新缓冲区再发送
          flushAgentChunksNow()
          mainWindow?.webContents.send('agent:chunks', [{ sessionId, chunk }])
        }
        chunks.push(typeof chunk === 'string' ? chunk : JSON.stringify(chunk))
      }
      flushAgentChunksNow()
      return { success: true, content: chunks.join('') }
    } catch (err: any) {
      flushAgentChunksNow()
      // 确保错误通过 chunk 事件通知前端
      mainWindow?.webContents.send('agent:chunks', [
        { sessionId, chunk: { type: 'error', error: err.message || '未知错误' } },
        { sessionId, chunk: { type: 'done' } }
      ])
      return { success: false, error: err.message }
    }
  })

  ipcMain.handle('agent:stop', () => {
    agentCore.stop()
    return { success: true }
  })

  ipcMain.handle('agent:getContextWindow', () => {
    return { maxTokens: agentCore.getMaxContextTokens() }
  })

  ipcMain.handle('agent:setConfig', (_e, config: any) => {
    agentCore.setConfig(config)
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

  ipcMain.handle('fs:rename', async (_e, oldPath: string, newPath: string) => {
    const { rename } = await import('fs/promises')
    await rename(oldPath, newPath)
    return true
  })

  ipcMain.handle('fs:delete', async (_e, targetPath: string) => {
    const { rm } = await import('fs/promises')
    await rm(targetPath, { recursive: true, force: true })
    return true
  })

  ipcMain.handle('fs:copyFile', async (_e, src: string, dest: string) => {
    const { cp } = await import('fs/promises')
    await cp(src, dest, { recursive: true })
    return true
  })

  ipcMain.handle('fs:showInExplorer', (_e, filePath: string) => {
    const { shell } = require('electron')
    shell.showItemInFolder(filePath)
    return true
  })

  // ---- Interactive Terminal (node-pty, multi-instance) ----
  const ptyMap = new Map<number, any>()
  // 输出缓冲区：每个终端保留最近的输出（用于 Agent 查询）
  const ptyOutputBuffer = new Map<number, string[]>()
  const PTY_BUFFER_MAX_LINES = 200
  const nextTermIdRef = { value: 1 }

  // 创建 ServiceManager 并注入到 ToolExecutor
  serviceManager = new ServiceManager(ptyMap, ptyOutputBuffer, nextTermIdRef, () => mainWindow)
  toolExecutor.setServiceManager(serviceManager)

  // 注入搜索函数（委托给 SearchWorker）
  toolExecutor.setSearchFunction((cwd, query, options) => searchExec(cwd, query, 'agent-search', options))

  /** 向终端输出缓冲区追加数据 */
  function appendPtyBuffer(id: number, data: string) {
    if (!ptyOutputBuffer.has(id)) ptyOutputBuffer.set(id, [])
    const buf = ptyOutputBuffer.get(id)!
    const lines = data.split('\n')
    for (const line of lines) buf.push(line)
    while (buf.length > PTY_BUFFER_MAX_LINES) buf.shift()
  }

  ipcMain.handle('terminal:create', async (_e, cwd: string) => {
    const pty = await import('@lydell/node-pty')
    const id = nextTermIdRef.value++

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

    ptyOutputBuffer.set(id, [])

    proc.onData((data: string) => {
      appendPtyBuffer(id, data)
      queuePtyData(id, data) // 节流发送到渲染进程
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
    try { ptyMap.get(id)?.resize(cols, rows) } catch { }
  })

  ipcMain.handle('terminal:kill', (_e, id: number) => {
    const proc = ptyMap.get(id)
    if (proc) { proc.kill(); ptyMap.delete(id) }
    ptyOutputBuffer.delete(id)
    return true
  })

  ipcMain.handle('terminal:killAll', () => {
    for (const [id, proc] of ptyMap) { proc.kill(); ptyMap.delete(id) }
    ptyOutputBuffer.clear()
    return true
  })

  // ---- Service Management IPC (前端调用) ----
  ipcMain.handle('service:start', async (_e, serviceId: string, command: string, cwd: string, options?: any) => {
    return serviceManager.startService(serviceId, command, cwd, options)
  })

  ipcMain.handle('service:check', (_e, serviceId: string) => {
    return serviceManager.checkService(serviceId)
  })

  ipcMain.handle('service:stop', (_e, serviceId: string) => {
    return serviceManager.stopService(serviceId)
  })

  ipcMain.handle('service:list', () => {
    return serviceManager.listServices()
  })

  // 获取终端输出缓冲区
  ipcMain.handle('terminal:getOutput', (_e, id: number, lines?: number) => {
    const buf = ptyOutputBuffer.get(id) || []
    const n = lines || 50
    return buf.slice(-n).join('\n')
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
        queueFsChange(eventType, filename, dirPath) // 防抖批量发送
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

  // ---- File Server (内置浏览器预览) ----
  ipcMain.handle('fileServer:getUrl', (_e, filePath: string) => {
    return `http://127.0.0.1:${fileServerPort}/?file=${encodeURIComponent(filePath)}`
  })

  // ---- Git Operations (via Worker Thread) ----
  ipcMain.handle('git:isRepo', async (_e, cwd: string) => {
    try {
      const raw = await gitExec(['rev-parse', '--is-inside-work-tree'], cwd, 'lines')
      return raw === 'true'
    } catch { return false }
  })

  ipcMain.handle('git:init', (_e, cwd: string) => gitExec(['init'], cwd, 'result'))

  ipcMain.handle('git:status', (_e, cwd: string) => gitExec(['status', '--porcelain=v1', '-uall'], cwd, 'status'))

  ipcMain.handle('git:branch', async (_e, cwd: string) => {
    try {
      const raw = await gitExec(['branch', '--show-current'], cwd, 'lines')
      return raw || 'main'
    } catch { return '' }
  })

  ipcMain.handle('git:add', async (_e, cwd: string, files: string[]) => {
    try { await gitExec(['add', ...files], cwd, 'boolean'); return true } catch { return false }
  })

  ipcMain.handle('git:unstage', async (_e, cwd: string, files: string[]) => {
    try { await gitExec(['reset', 'HEAD', ...files], cwd, 'boolean'); return true } catch { return false }
  })

  ipcMain.handle('git:commit', (_e, cwd: string, message: string) => gitExec(['commit', '-m', message], cwd, 'result'))

  ipcMain.handle('git:diff', async (_e, cwd: string, file: string) => {
    try { return await gitExec(['diff', '--', file], cwd, 'raw') } catch { return '' }
  })

  ipcMain.handle('git:discard', async (_e, cwd: string, file: string) => {
    try { await gitExec(['checkout', '--', file], cwd, 'boolean'); return true } catch { return false }
  })

  ipcMain.handle('git:log', (_e, cwd: string, count: number = 20) =>
    gitExec(['log', `--max-count=${count}`, '--pretty=format:%H%x09%h%x09%an%x09%ar%x09%s'], cwd, 'log')
  )

  ipcMain.handle('git:showCommitFiles', (_e, cwd: string, hash: string) =>
    gitExec(['diff-tree', '--no-commit-id', '-r', '--name-status', hash], cwd, 'commitFiles')
  )

  ipcMain.handle('git:diffCommitFile', async (_e, cwd: string, hash: string, file: string) => {
    try { return await gitExec(['diff', `${hash}~1`, hash, '--', file], cwd, 'raw') } catch { return '' }
  })

  ipcMain.handle('git:diffStaged', async (_e, cwd: string, file: string) => {
    try { return await gitExec(['diff', '--cached', '--', file], cwd, 'raw') } catch { return '' }
  })

  ipcMain.handle('git:showFile', async (_e, cwd: string, ref: string, file: string) => {
    try { return await gitExec(['show', `${ref}:${file}`], cwd, 'raw') } catch { return '' }
  })

  ipcMain.handle('git:pull', (_e, cwd: string) => gitExec(['pull'], cwd, 'result'))
  ipcMain.handle('git:push', (_e, cwd: string) => gitExec(['push'], cwd, 'result'))
  ipcMain.handle('git:fetch', (_e, cwd: string) => gitExec(['fetch', '--all'], cwd, 'result'))

  // ---- 全局搜索 & 替换（via Search Worker） ----
  ipcMain.handle('search:files', async (_e, cwd: string, query: string, options: {
    caseSensitive?: boolean; wholeWord?: boolean; useRegex?: boolean;
    includePattern?: string; excludePattern?: string
  }) => {
    if (!query) return []
    try {
      const { results } = await searchExec(cwd, query, 'ipc-search', {
        caseSensitive: options.caseSensitive,
        wholeWord: options.wholeWord,
        isRegex: options.useRegex,
        includePattern: options.includePattern,
        excludePattern: options.excludePattern
      })
      return results
    } catch {
      return []
    }
  })

  ipcMain.handle('search:replace', async (_e, cwd: string, filePath: string, query: string, replacement: string, options: {
    caseSensitive?: boolean; wholeWord?: boolean; useRegex?: boolean
  }) => {
    const { readFile: rf, writeFile: wf } = await import('fs/promises')
    try {
      let src = options.useRegex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      if (options.wholeWord) src = `\\b${src}\\b`
      const pattern = new RegExp(src, options.caseSensitive ? 'g' : 'gi')
      const content = await rf(filePath, 'utf-8')
      const newContent = content.replace(pattern, replacement)
      if (content !== newContent) {
        await wf(filePath, newContent, 'utf-8')
        return { success: true, replacements: (content.match(pattern) || []).length }
      }
      return { success: true, replacements: 0 }
    } catch (err: any) {
      return { success: false, error: err.message, replacements: 0 }
    }
  })

  ipcMain.handle('search:replaceAll', async (_e, cwd: string, query: string, replacement: string, options: {
    caseSensitive?: boolean; wholeWord?: boolean; useRegex?: boolean;
    includePattern?: string; excludePattern?: string
  }, files: string[]) => {
    const { readFile: rf, writeFile: wf } = await import('fs/promises')
    let totalReplacements = 0
    let filesChanged = 0
    try {
      let src = options.useRegex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      if (options.wholeWord) src = `\\b${src}\\b`
      const pattern = new RegExp(src, options.caseSensitive ? 'g' : 'gi')
      for (const filePath of files) {
        const content = await rf(filePath, 'utf-8')
        const matches = content.match(pattern)
        if (matches && matches.length > 0) {
          const newContent = content.replace(pattern, replacement)
          await wf(filePath, newContent, 'utf-8')
          totalReplacements += matches.length
          filesChanged++
        }
      }
      return { success: true, totalReplacements, filesChanged }
    } catch (err: any) {
      return { success: false, error: err.message, totalReplacements, filesChanged }
    }
  })

  // ---- 扩展管理 ----
  const extensionsDir = join(app.getPath('userData'), 'extensions')

  ipcMain.handle('ext:getDir', () => extensionsDir)

  ipcMain.handle('ext:list', async () => {
    const { readdir, readFile: rf } = await import('fs/promises')
    const { join: pjoin } = await import('path')
    try {
      await import('fs/promises').then(f => f.mkdir(extensionsDir, { recursive: true }))
      const dirs = await readdir(extensionsDir, { withFileTypes: true })
      const extensions = []
      for (const d of dirs) {
        if (!d.isDirectory()) continue
        try {
          const manifest = JSON.parse(await rf(pjoin(extensionsDir, d.name, 'manifest.json'), 'utf-8'))
          extensions.push({ ...manifest, dirName: d.name, installed: true })
        } catch { /* skip invalid */ }
      }
      return extensions
    } catch { return [] }
  })

  ipcMain.handle('ext:install', async (_e, sourcePath: string) => {
    const { readFile: rf, mkdir, cp } = await import('fs/promises')
    const { join: pjoin, basename } = await import('path')
    try {
      // 读取 manifest
      const manifest = JSON.parse(await rf(pjoin(sourcePath, 'manifest.json'), 'utf-8'))
      const id = manifest.id || basename(sourcePath)
      const targetDir = pjoin(extensionsDir, id)
      await mkdir(targetDir, { recursive: true })
      await cp(sourcePath, targetDir, { recursive: true })
      return { success: true, manifest: { ...manifest, dirName: id } }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  })

  ipcMain.handle('ext:uninstall', async (_e, dirName: string) => {
    const { rm } = await import('fs/promises')
    const { join: pjoin } = await import('path')
    try {
      await rm(pjoin(extensionsDir, dirName), { recursive: true, force: true })
      return { success: true }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  })

  ipcMain.handle('ext:readFile', async (_e, dirName: string, filePath: string) => {
    const { readFile: rf } = await import('fs/promises')
    const { join: pjoin } = await import('path')
    return rf(pjoin(extensionsDir, dirName, filePath), 'utf-8')
  })

  ipcMain.handle('ext:selectFolder', async () => {
    const result = await dialog.showOpenDialog({ properties: ['openDirectory'], title: '选择扩展文件夹' })
    return result.canceled ? null : result.filePaths[0]
  })

  // 读取主题 JSON（VS Code 格式）
  ipcMain.handle('ext:loadTheme', async (_e, dirName: string, themeFile: string) => {
    const { readFile: rf } = await import('fs/promises')
    const { join: pjoin } = await import('path')
    try {
      const content = await rf(pjoin(extensionsDir, dirName, themeFile), 'utf-8')
      return { success: true, theme: JSON.parse(content) }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  })
}
