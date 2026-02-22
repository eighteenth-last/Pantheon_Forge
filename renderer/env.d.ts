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
      onData: (cb: (payload: { id: number; data: string }) => void) => () => void
      onExit: (cb: (payload: { id: number; exitCode: number }) => void) => () => void
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
      status: (cwd: string) => Promise<{ status: string; file: string }[]>
      branch: (cwd: string) => Promise<string>
      add: (cwd: string, files: string[]) => Promise<boolean>
      unstage: (cwd: string, files: string[]) => Promise<boolean>
      commit: (cwd: string, message: string) => Promise<{ success: boolean; output: string }>
      diff: (cwd: string, file: string) => Promise<string>
      discard: (cwd: string, file: string) => Promise<boolean>
      log: (cwd: string, count?: number) => Promise<{ hash: string; shortHash: string; author: string; date: string; message: string }[]>
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
