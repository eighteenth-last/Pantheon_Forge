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
      chat: (sessionId: number, message: string, projectPath: string, modelId?: number | null, images?: string[]) => Promise<any>
      stop: () => Promise<void>
      setConfig: (config: any) => Promise<{ success: boolean }>
      onChunk: (cb: (data: any) => void) => () => void
    }
    fs: {
      readDir: (path: string) => Promise<any[]>
      readFile: (path: string) => Promise<string>
      writeFile: (path: string, content: string) => Promise<boolean>
      rename: (oldPath: string, newPath: string) => Promise<boolean>
      delete: (targetPath: string) => Promise<boolean>
      copyFile: (src: string, dest: string) => Promise<boolean>
      showInExplorer: (path: string) => Promise<void>
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
      getOutput: (id: number, lines?: number) => Promise<string>
      onData: (cb: (payload: { id: number; data: string }) => void) => () => void
      onExit: (cb: (payload: { id: number; exitCode: number }) => void) => () => void
    }
    service: {
      start: (serviceId: string, command: string, cwd: string, options?: { successPattern?: string; errorPattern?: string; timeoutMs?: number }) =>
        Promise<{ success: boolean; status: string; termId: number; output: string }>
      check: (serviceId: string) => Promise<{ exists: boolean; status: string; termId?: number; command?: string; uptime?: number; output: string }>
      stop: (serviceId: string) => Promise<{ success: boolean; error?: string }>
      list: () => Promise<{ serviceId: string; termId: number; command: string; status: string; alive: boolean; startTime: number }[]>
      onTerminalCreated: (cb: (payload: { id: number; serviceId: string; command: string }) => void) => () => void
    }
    dialog: {
      openFolder: () => Promise<string | null>
    }
    fileServer: {
      getUrl: (filePath: string) => Promise<string>
    }
    git: {
      isRepo: (cwd: string) => Promise<boolean>
      init: (cwd: string) => Promise<{ success: boolean; output: string }>
      status: (cwd: string) => Promise<{ items: { status: string; file: string }[]; truncated: boolean; total: number }>
      branch: (cwd: string) => Promise<string>
      add: (cwd: string, files: string[]) => Promise<boolean>
      unstage: (cwd: string, files: string[]) => Promise<boolean>
      commit: (cwd: string, message: string) => Promise<{ success: boolean; output: string }>
      diff: (cwd: string, file: string) => Promise<string>
      discard: (cwd: string, file: string) => Promise<boolean>
      log: (cwd: string, count?: number) => Promise<{ hash: string; shortHash: string; author: string; date: string; message: string }[]>
      showCommitFiles: (cwd: string, hash: string) => Promise<{ status: string; file: string }[]>
      diffCommitFile: (cwd: string, hash: string, file: string) => Promise<string>
      diffStaged: (cwd: string, file: string) => Promise<string>
      showFile: (cwd: string, ref: string, file: string) => Promise<string>
      pull: (cwd: string) => Promise<{ success: boolean; output: string }>
      push: (cwd: string) => Promise<{ success: boolean; output: string }>
      fetch: (cwd: string) => Promise<{ success: boolean; output: string }>
    }
    search: {
      files: (cwd: string, query: string, options: {
        caseSensitive?: boolean; wholeWord?: boolean; useRegex?: boolean;
        includePattern?: string; excludePattern?: string
      }) => Promise<{ file: string; relPath: string; matches: { line: number; col: number; text: string; matchText: string }[] }[]>
      replace: (cwd: string, filePath: string, query: string, replacement: string, options: {
        caseSensitive?: boolean; wholeWord?: boolean; useRegex?: boolean
      }) => Promise<{ success: boolean; replacements: number; error?: string }>
      replaceAll: (cwd: string, query: string, replacement: string, options: {
        caseSensitive?: boolean; wholeWord?: boolean; useRegex?: boolean;
        includePattern?: string; excludePattern?: string
      }, files: string[]) => Promise<{ success: boolean; totalReplacements: number; filesChanged: number; error?: string }>
    }
    ext: {
      getDir: () => Promise<string>
      list: () => Promise<any[]>
      install: (sourcePath: string) => Promise<{ success: boolean; manifest?: any; error?: string }>
      uninstall: (dirName: string) => Promise<{ success: boolean; error?: string }>
      readFile: (dirName: string, filePath: string) => Promise<string>
      selectFolder: () => Promise<string | null>
      loadTheme: (dirName: string, themeFile: string) => Promise<{ success: boolean; theme?: any; error?: string }>
    }
    window: {
      minimize: () => void
      maximize: () => void
      close: () => void
    }
  }
}
