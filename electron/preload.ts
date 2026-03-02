import { contextBridge, ipcRenderer } from 'electron'

const api = {
  // Model management
  models: {
    list: () => ipcRenderer.invoke('models:list'),
    add: (model: any) => ipcRenderer.invoke('models:add', model),
    update: (id: number, model: any) => ipcRenderer.invoke('models:update', id, model),
    delete: (id: number) => ipcRenderer.invoke('models:delete', id),
    setActive: (id: number) => ipcRenderer.invoke('models:setActive', id),
    deactivate: (id: number) => ipcRenderer.invoke('models:deactivate', id),
    getById: (id: number) => ipcRenderer.invoke('models:getById', id)
  },

  // Session management
  sessions: {
    list: () => ipcRenderer.invoke('sessions:list'),
    create: (projectPath: string) => ipcRenderer.invoke('sessions:create', projectPath),
    getMessages: (sessionId: number) => ipcRenderer.invoke('sessions:getMessages', sessionId),
    delete: (sessionId: number) => ipcRenderer.invoke('sessions:delete', sessionId)
  },

  // Agent
  agent: {
    chat: (sessionId: number, message: string, projectPath: string, modelId?: number | null, images?: string[]) =>
      ipcRenderer.invoke('agent:chat', sessionId, message, projectPath, modelId, images),
    stop: () => ipcRenderer.invoke('agent:stop'),
    setConfig: (config: any) => ipcRenderer.invoke('agent:setConfig', config),
    getContextWindow: () => ipcRenderer.invoke('agent:getContextWindow'),
    onChunk: (cb: (data: any) => void) => {
      // 支持批量 chunks（新协议）
      const batchHandler = (_e: any, batch: any[]) => {
        for (const data of batch) cb(data)
      }
      ipcRenderer.on('agent:chunks', batchHandler)
      return () => ipcRenderer.removeListener('agent:chunks', batchHandler)
    }
  },

  // File system
  fs: {
    readDir: (path: string) => ipcRenderer.invoke('fs:readDir', path),
    readFile: (path: string) => ipcRenderer.invoke('fs:readFile', path),
    writeFile: (path: string, content: string) => ipcRenderer.invoke('fs:writeFile', path, content),
    rename: (oldPath: string, newPath: string) => ipcRenderer.invoke('fs:rename', oldPath, newPath),
    delete: (targetPath: string) => ipcRenderer.invoke('fs:delete', targetPath),
    copyFile: (src: string, dest: string) => ipcRenderer.invoke('fs:copyFile', src, dest),
    showInExplorer: (path: string) => ipcRenderer.invoke('fs:showInExplorer', path),
    watch: (path: string) => ipcRenderer.invoke('fs:watch', path),
    unwatch: () => ipcRenderer.invoke('fs:unwatch'),
    onChanged: (cb: (data: any) => void) => {
      // 支持批量文件变更事件（新协议）
      const batchHandler = (_e: any, batch: any[]) => {
        for (const data of batch) cb(data)
      }
      ipcRenderer.on('fs:changes', batchHandler)
      return () => ipcRenderer.removeListener('fs:changes', batchHandler)
    }
  },

  // Shell / Terminal
  shell: {
    exec: (command: string, cwd: string) => ipcRenderer.invoke('shell:exec', command, cwd),
    onStdout: (cb: (data: string) => void) => {
      const handler = (_e: any, data: string) => cb(data)
      ipcRenderer.on('shell:stdout', handler)
      return () => ipcRenderer.removeListener('shell:stdout', handler)
    },
    onStderr: (cb: (data: string) => void) => {
      const handler = (_e: any, data: string) => cb(data)
      ipcRenderer.on('shell:stderr', handler)
      return () => ipcRenderer.removeListener('shell:stderr', handler)
    }
  },

  // Interactive Terminal (multi-instance)
  terminal: {
    create: (cwd: string) => ipcRenderer.invoke('terminal:create', cwd),
    write: (id: number, data: string) => ipcRenderer.invoke('terminal:write', id, data),
    resize: (id: number, cols: number, rows: number) => ipcRenderer.invoke('terminal:resize', id, cols, rows),
    kill: (id: number) => ipcRenderer.invoke('terminal:kill', id),
    killAll: () => ipcRenderer.invoke('terminal:killAll'),
    getOutput: (id: number, lines?: number) => ipcRenderer.invoke('terminal:getOutput', id, lines),
    onData: (cb: (payload: { id: number; data: string }) => void) => {
      const handler = (_e: any, payload: { id: number; data: string }) => cb(payload)
      ipcRenderer.on('terminal:data', handler)
      return () => ipcRenderer.removeListener('terminal:data', handler)
    },
    onExit: (cb: (payload: { id: number; exitCode: number }) => void) => {
      const handler = (_e: any, payload: { id: number; exitCode: number }) => cb(payload)
      ipcRenderer.on('terminal:exit', handler)
      return () => ipcRenderer.removeListener('terminal:exit', handler)
    }
  },

  // Service Management (Agent 长时间运行服务)
  service: {
    start: (serviceId: string, command: string, cwd: string, options?: { successPattern?: string; errorPattern?: string; timeoutMs?: number }) =>
      ipcRenderer.invoke('service:start', serviceId, command, cwd, options),
    check: (serviceId: string) => ipcRenderer.invoke('service:check', serviceId),
    stop: (serviceId: string) => ipcRenderer.invoke('service:stop', serviceId),
    list: () => ipcRenderer.invoke('service:list'),
    onTerminalCreated: (cb: (payload: { id: number; serviceId: string; command: string }) => void) => {
      const handler = (_e: any, payload: any) => cb(payload)
      ipcRenderer.on('service:terminal-created', handler)
      return () => ipcRenderer.removeListener('service:terminal-created', handler)
    },
    onTerminalClosed: (cb: (payload: { id: number; serviceId: string }) => void) => {
      const handler = (_e: any, payload: any) => cb(payload)
      ipcRenderer.on('service:terminal-closed', handler)
      return () => ipcRenderer.removeListener('service:terminal-closed', handler)
    }
  },

  // Dialog
  dialog: {
    openFolder: () => ipcRenderer.invoke('dialog:openFolder')
  },

  // File Server (内置浏览器)
  fileServer: {
    getUrl: (filePath: string) => ipcRenderer.invoke('fileServer:getUrl', filePath)
  },

  // Git
  git: {
    isRepo: (cwd: string) => ipcRenderer.invoke('git:isRepo', cwd),
    init: (cwd: string) => ipcRenderer.invoke('git:init', cwd),
    status: (cwd: string) => ipcRenderer.invoke('git:status', cwd),
    branch: (cwd: string) => ipcRenderer.invoke('git:branch', cwd),
    add: (cwd: string, files: string[]) => ipcRenderer.invoke('git:add', cwd, files),
    unstage: (cwd: string, files: string[]) => ipcRenderer.invoke('git:unstage', cwd, files),
    commit: (cwd: string, message: string) => ipcRenderer.invoke('git:commit', cwd, message),
    diff: (cwd: string, file: string) => ipcRenderer.invoke('git:diff', cwd, file),
    discard: (cwd: string, file: string) => ipcRenderer.invoke('git:discard', cwd, file),
    log: (cwd: string, count?: number) => ipcRenderer.invoke('git:log', cwd, count),
    showCommitFiles: (cwd: string, hash: string) => ipcRenderer.invoke('git:showCommitFiles', cwd, hash),
    diffCommitFile: (cwd: string, hash: string, file: string) => ipcRenderer.invoke('git:diffCommitFile', cwd, hash, file),
    diffStaged: (cwd: string, file: string) => ipcRenderer.invoke('git:diffStaged', cwd, file),
    showFile: (cwd: string, ref: string, file: string) => ipcRenderer.invoke('git:showFile', cwd, ref, file),
    pull: (cwd: string) => ipcRenderer.invoke('git:pull', cwd),
    push: (cwd: string) => ipcRenderer.invoke('git:push', cwd),
    fetch: (cwd: string) => ipcRenderer.invoke('git:fetch', cwd),
  },

  // Search
  search: {
    files: (cwd: string, query: string, options: any) => ipcRenderer.invoke('search:files', cwd, query, options),
    replace: (cwd: string, filePath: string, query: string, replacement: string, options: any) =>
      ipcRenderer.invoke('search:replace', cwd, filePath, query, replacement, options),
    replaceAll: (cwd: string, query: string, replacement: string, options: any, files: string[]) =>
      ipcRenderer.invoke('search:replaceAll', cwd, query, replacement, options, files),
  },

  // Extensions
  ext: {
    getDir: () => ipcRenderer.invoke('ext:getDir'),
    list: () => ipcRenderer.invoke('ext:list'),
    install: (sourcePath: string) => ipcRenderer.invoke('ext:install', sourcePath),
    uninstall: (dirName: string) => ipcRenderer.invoke('ext:uninstall', dirName),
    readFile: (dirName: string, filePath: string) => ipcRenderer.invoke('ext:readFile', dirName, filePath),
    selectFolder: () => ipcRenderer.invoke('ext:selectFolder'),
    loadTheme: (dirName: string, themeFile: string) => ipcRenderer.invoke('ext:loadTheme', dirName, themeFile),
  },

  // Window
  window: {
    minimize: () => ipcRenderer.send('window:minimize'),
    maximize: () => ipcRenderer.send('window:maximize'),
    close: () => ipcRenderer.send('window:close')
  }
}

contextBridge.exposeInMainWorld('api', api)
