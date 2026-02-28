import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import electron from 'vite-plugin-electron'
import renderer from 'vite-plugin-electron-renderer'
import monacoEditorPlugin from 'vite-plugin-monaco-editor'
import { resolve } from 'path'

// vite-plugin-monaco-editor 可能导出 default 包装
const monacoPlugin = (monacoEditorPlugin as any).default || monacoEditorPlugin

export default defineConfig({
  plugins: [
    vue(),
    monacoPlugin({
      languageWorkers: ['editorWorkerService', 'typescript', 'json', 'css', 'html']
    }),
    electron([
      {
        entry: 'electron/main.ts',
        vite: {
          build: {
            outDir: 'dist-electron',
            rollupOptions: {
              external: ['better-sqlite3', '@lydell/node-pty']
            }
          }
        }
      },
      {
        entry: 'electron/git-worker.ts',
        vite: {
          build: {
            outDir: 'dist-electron',
            rollupOptions: {
              external: []
            }
          }
        }
      },
      {
        entry: 'electron/search-worker.ts',
        vite: {
          build: {
            outDir: 'dist-electron',
            rollupOptions: {
              external: []
            }
          }
        }
      },
      {
        entry: 'electron/preload.ts',
        onstart(options) {
          options.reload()
        }
      }
    ]),
    renderer()
  ],
  resolve: {
    alias: {
      '@': resolve(__dirname, 'renderer'),
      '@agent': resolve(__dirname, 'agent'),
      '@models': resolve(__dirname, 'models'),
      '@tools': resolve(__dirname, 'tools'),
      '@database': resolve(__dirname, 'database')
    }
  }
})
