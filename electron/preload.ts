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
    chat: (sessionId: number, message: string, projectPath: string, modelId?: number | null) =>
      ipcRenderer.invoke('agent:chat', sessionId, message, projectPath, modelId),
    stop: () => ipcRenderer.invoke('agent:stop'),
    onChunk: (cb: (data: any) => void) => {
      const handler = (_e: any, data: any) => cb(data)
      ipcRenderer.on('agent:chunk', handler)
      return () => ipcRenderer.removeListener('agent:chunk', handler)
    }
  },

  // File system
  fs: {
    readDir: (path: string) => ipcRenderer.invoke('fs:readDir', path),
    readFile: (path: string) => ipcRenderer.invoke('fs:readFile', path),
    writeFile: (path: string, content: string) => ipcRenderer.invoke('fs:writeFile', path, content),
    watch: (path: string) => ipcRenderer.invoke('fs:watch', path),
    unwatch: () => ipcRenderer.invoke('fs:unwatch'),
    onChanged: (cb: (data: any) => void) => {
      const handler = (_e: any, data: any) => cb(data)
      ipcRenderer.on('fs:changed', handler)
      return () => ipcRenderer.removeListener('fs:changed', handler)
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

  // Dialog
  dialog: {
    openFolder: () => ipcRenderer.invoke('dialog:openFolder')
  }
}

contextBridge.exposeInMainWorld('api', api)
