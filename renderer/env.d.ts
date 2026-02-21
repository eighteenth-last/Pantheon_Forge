/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<{}, {}, any>
  export default component
}

interface Window {
  api: {
    models: {
      list: () => Promise<any[]>
      add: (model: any) => Promise<any>
      update: (id: number, model: any) => Promise<void>
      delete: (id: number) => Promise<void>
      setActive: (id: number) => Promise<void>
      deactivate: (id: number) => Promise<void>
      getById: (id: number) => Promise<any>
    }
    sessions: {
      list: () => Promise<any[]>
      create: (projectPath: string) => Promise<any>
      getMessages: (sessionId: number) => Promise<any[]>
      delete: (sessionId: number) => Promise<void>
    }
    agent: {
      chat: (sessionId: number, message: string, projectPath: string, modelId?: number | null) => Promise<any>
      stop: () => Promise<void>
      onChunk: (cb: (data: any) => void) => () => void
    }
    fs: {
      readDir: (path: string) => Promise<any[]>
      readFile: (path: string) => Promise<string>
      writeFile: (path: string, content: string) => Promise<boolean>
      watch: (path: string) => Promise<boolean>
      unwatch: () => Promise<boolean>
      onChanged: (cb: (data: any) => void) => () => void
    }
    shell: {
      exec: (command: string, cwd: string) => Promise<any>
      onStdout: (cb: (data: string) => void) => () => void
      onStderr: (cb: (data: string) => void) => () => void
    }
    terminal: {
      create: (cwd: string) => Promise<number>
      write: (id: number, data: string) => Promise<void>
      resize: (id: number, cols: number, rows: number) => Promise<void>
      kill: (id: number) => Promise<boolean>
      killAll: () => Promise<boolean>
      onData: (cb: (payload: { id: number; data: string }) => void) => () => void
      onExit: (cb: (payload: { id: number; exitCode: number }) => void) => () => void
    }
    dialog: {
      openFolder: () => Promise<string | null>
    }
  }
}
