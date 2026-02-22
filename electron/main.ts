import { app, BrowserWindow, ipcMain, dialog } from 'electron'
import { join } from 'path'
import { AgentCore } from '../agent/agent-core'
import { ModelRouter } from '../agent/model-router'
import { ToolExecutor } from '../agent/tool-executor'
import { Database } from '../database/db'

import { createServer, type Server } from 'http'
import { readFile as fsReadFile } from 'fs/promises'
import { extname } from 'path'

let mainWindow: BrowserWindow | null = null
let database: Database
let agentCore: AgentCore
let fileServer: Server | null = null
let fileServerPort = 0

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

app.whenReady().then(async () => {
  database = new Database()
  const modelRouter = new ModelRouter(database)
  const toolExecutor = new ToolExecutor()
  agentCore = new AgentCore(modelRouter, toolExecutor, database)

  // 启动本地文件服务器（用于内置浏览器预览）
  await startFileServer()

  createWindow()
  registerIpcHandlers()
})

app.on('window-all-closed', () => {
  database?.close()
  if (process.platform !== 'darwin') app.quit()
})

function registerIpcHandlers() {
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
      // 确保错误通过 chunk 事件通知前端
      mainWindow?.webContents.send('agent:chunk', {
        sessionId,
        chunk: { type: 'error', error: err.message || '未知错误' }
      })
      mainWindow?.webContents.send('agent:chunk', {
        sessionId,
        chunk: { type: 'done' }
      })
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

  // ---- File Server (内置浏览器预览) ----
  ipcMain.handle('fileServer:getUrl', (_e, filePath: string) => {
    return `http://127.0.0.1:${fileServerPort}/?file=${encodeURIComponent(filePath)}`
  })

  // ---- Git Operations ----
  ipcMain.handle('git:isRepo', async (_e, cwd: string) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['rev-parse', '--is-inside-work-tree'], { cwd, shell: true })
      let out = ''
      proc.stdout?.on('data', (d: Buffer) => { out += d.toString() })
      proc.on('close', code => resolve(code === 0 && out.trim() === 'true'))
      proc.on('error', () => resolve(false))
    })
  })

  ipcMain.handle('git:init', async (_e, cwd: string) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['init'], { cwd, shell: true })
      let out = '', err = ''
      proc.stdout?.on('data', (d: Buffer) => { out += d.toString() })
      proc.stderr?.on('data', (d: Buffer) => { err += d.toString() })
      proc.on('close', code => resolve({ success: code === 0, output: out + err }))
      proc.on('error', (e) => resolve({ success: false, output: e.message }))
    })
  })

  ipcMain.handle('git:status', async (_e, cwd: string) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['status', '--porcelain=v1', '-uall'], { cwd, shell: true })
      let out = ''
      proc.stdout?.on('data', (d: Buffer) => { out += d.toString() })
      proc.on('close', code => {
        if (code !== 0) { resolve([]); return }
        const files = out.trim().split('\n').filter(Boolean).map(line => {
          const status = line.substring(0, 2)
          const file = line.substring(3)
          return { status: status.trim() || '?', file }
        })
        resolve(files)
      })
      proc.on('error', () => resolve([]))
    })
  })

  ipcMain.handle('git:branch', async (_e, cwd: string) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['branch', '--show-current'], { cwd, shell: true })
      let out = ''
      proc.stdout?.on('data', (d: Buffer) => { out += d.toString() })
      proc.on('close', () => resolve(out.trim() || 'main'))
      proc.on('error', () => resolve(''))
    })
  })

  ipcMain.handle('git:add', async (_e, cwd: string, files: string[]) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['add', ...files], { cwd, shell: true })
      proc.on('close', code => resolve(code === 0))
      proc.on('error', () => resolve(false))
    })
  })

  ipcMain.handle('git:unstage', async (_e, cwd: string, files: string[]) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['reset', 'HEAD', ...files], { cwd, shell: true })
      proc.on('close', code => resolve(code === 0))
      proc.on('error', () => resolve(false))
    })
  })

  ipcMain.handle('git:commit', async (_e, cwd: string, message: string) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['commit', '-m', message], { cwd, shell: true })
      let out = '', err = ''
      proc.stdout?.on('data', (d: Buffer) => { out += d.toString() })
      proc.stderr?.on('data', (d: Buffer) => { err += d.toString() })
      proc.on('close', code => resolve({ success: code === 0, output: out + err }))
      proc.on('error', (e) => resolve({ success: false, output: e.message }))
    })
  })

  ipcMain.handle('git:diff', async (_e, cwd: string, file: string) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['diff', '--', file], { cwd, shell: true })
      let out = ''
      proc.stdout?.on('data', (d: Buffer) => { out += d.toString() })
      proc.on('close', () => resolve(out))
      proc.on('error', () => resolve(''))
    })
  })

  ipcMain.handle('git:discard', async (_e, cwd: string, file: string) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['checkout', '--', file], { cwd, shell: true })
      proc.on('close', code => resolve(code === 0))
      proc.on('error', () => resolve(false))
    })
  })

  ipcMain.handle('git:log', async (_e, cwd: string, count: number = 20) => {
    const { spawn } = await import('child_process')
    return new Promise((resolve) => {
      const proc = spawn('git', ['log', `--max-count=${count}`, '--pretty=format:%H||%h||%an||%ar||%s'], { cwd, shell: true })
      let out = ''
      proc.stdout?.on('data', (d: Buffer) => { out += d.toString() })
      proc.on('close', () => {
        const commits = out.trim().split('\n').filter(Boolean).map(line => {
          const [hash, shortHash, author, date, ...msgParts] = line.split('||')
          return { hash, shortHash, author, date, message: msgParts.join('||') }
        })
        resolve(commits)
      })
      proc.on('error', () => resolve([]))
    })
  })

  // ---- 全局搜索 & 替换 ----
  ipcMain.handle('search:files', async (_e, cwd: string, query: string, options: {
    caseSensitive?: boolean; wholeWord?: boolean; useRegex?: boolean;
    includePattern?: string; excludePattern?: string
  }) => {
    const { readdir, stat, readFile: rf } = await import('fs/promises')
    const { join: pjoin, relative, extname: ext } = await import('path')

    if (!query) return []

    // 构建正则
    let pattern: RegExp
    try {
      let src = options.useRegex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      if (options.wholeWord) src = `\\b${src}\\b`
      pattern = new RegExp(src, options.caseSensitive ? 'g' : 'gi')
    } catch { return [] }

    // 简单 glob → RegExp 转换
    function globToRegex(glob: string): RegExp {
      const escaped = glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')
      return new RegExp(`(^|/)${escaped}$`, 'i')
    }

    const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'dist-electron', '.idea', '.vscode', '__pycache__', '.next', 'build', 'target', '.gradle'])
    const TEXT_EXTS = new Set([
      '.ts', '.tsx', '.js', '.jsx', '.vue', '.html', '.htm', '.css', '.scss', '.less',
      '.json', '.md', '.txt', '.xml', '.svg', '.yaml', '.yml', '.toml', '.ini', '.cfg',
      '.py', '.java', '.kt', '.go', '.rs', '.rb', '.php', '.c', '.cpp', '.h', '.cs',
      '.swift', '.dart', '.lua', '.sh', '.bat', '.ps1', '.sql', '.graphql', '.env',
      '.gitignore', '.editorconfig', '.prettierrc', '.eslintrc', '.dockerfile',
    ])

    const results: { file: string; relPath: string; matches: { line: number; col: number; text: string; matchText: string }[] }[] = []
    let fileCount = 0
    const MAX_FILES = 5000
    const MAX_RESULTS = 500

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
      if (fileCount >= MAX_FILES || results.length >= MAX_RESULTS) return
      let entries
      try { entries = await readdir(dir, { withFileTypes: true }) } catch { return }
      for (const entry of entries) {
        if (fileCount >= MAX_FILES || results.length >= MAX_RESULTS) return
        const fullPath = pjoin(dir, entry.name)
        if (entry.isDirectory()) {
          if (!SKIP_DIRS.has(entry.name)) await walk(fullPath)
        } else {
          const e = ext(entry.name).toLowerCase()
          const isText = TEXT_EXTS.has(e) || entry.name.startsWith('.') || e === ''
          if (!isText) continue
          const relPath = relative(cwd, fullPath).replace(/\\/g, '/')
          if (!shouldInclude(relPath)) continue
          fileCount++
          try {
            const content = await rf(fullPath, 'utf-8')
            const lines = content.split('\n')
            const matches: { line: number; col: number; text: string; matchText: string }[] = []
            for (let i = 0; i < lines.length; i++) {
              pattern.lastIndex = 0
              let m
              while ((m = pattern.exec(lines[i])) !== null) {
                matches.push({ line: i + 1, col: m.index + 1, text: lines[i], matchText: m[0] })
                if (!pattern.global) break
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
    return results
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
