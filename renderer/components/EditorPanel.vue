<script setup lang="ts">
import { ref, watch, onMounted, nextTick, computed } from 'vue'
import { useProjectStore } from '../stores/project'
import { useSettingsStore } from '../stores/settings'
import { useExtensionsStore } from '../stores/extensions'

const project = useProjectStore()
const settings = useSettingsStore()
const extStore = useExtensionsStore()
const s = settings.app
const editorContainer = ref<HTMLElement>()
let monacoEditor: any = null
let monaco: any = null
let isUpdating = false
let autoSaveTimer: ReturnType<typeof setTimeout> | null = null
let initPromise: Promise<void> | null = null

// 内置浏览器
const browserUrl = ref('')
const browserLoading = ref(false)
const browserIframe = ref<HTMLIFrameElement>()

// 当前是否为浏览器模式
const isBrowserMode = computed(() => project.activeFile?.type === 'browser')

// 编辑器右键菜单
const editorCtx = ref({ show: false, x: 0, y: 0 })

function showEditorCtxMenu(x: number, y: number) {
  const menuW = 260, menuH = 380
  if (x + menuW > window.innerWidth) x = window.innerWidth - menuW - 4
  if (y + menuH > window.innerHeight) y = window.innerHeight - menuH - 4
  editorCtx.value = { show: true, x, y }
}

function closeEditorCtx() { editorCtx.value.show = false }

function editorAction(id: string) {
  if (monacoEditor) monacoEditor.trigger('contextmenu', id, null)
  closeEditorCtx()
}

function editorCut() {
  if (monacoEditor) { monacoEditor.focus(); document.execCommand('cut') }
  closeEditorCtx()
}
function editorCopy() {
  if (monacoEditor) { monacoEditor.focus(); document.execCommand('copy') }
  closeEditorCtx()
}
function editorPaste() {
  if (monacoEditor) { monacoEditor.focus(); document.execCommand('paste') }
  closeEditorCtx()
}
function editorSelectAll() {
  if (monacoEditor) {
    const model = monacoEditor.getModel()
    if (model) {
      monacoEditor.setSelection(model.getFullModelRange())
    }
  }
  closeEditorCtx()
}

async function initMonaco() {
  if (monacoEditor) return
  // 防止并发初始化
  if (initPromise) return initPromise
  initPromise = doInitMonaco()
  return initPromise
}

async function doInitMonaco() {
  if (monacoEditor) return
  monaco = await import('monaco-editor')
  await nextTick()
  if (!editorContainer.value) return

  monacoEditor = monaco.editor.create(editorContainer.value, {
    value: '',
    language: 'plaintext',
    theme: 'vs-dark',
    fontSize: s.fontSize,
    fontFamily: s.fontFamily,
    minimap: { enabled: s.minimap },
    scrollBeyondLastLine: false,
    automaticLayout: true,
    tabSize: s.tabSize,
    wordWrap: s.wordWrap ? 'on' : 'off',
    lineNumbers: s.lineNumbers ? 'on' : 'off',
    renderWhitespace: s.renderWhitespace,
    bracketPairColorization: { enabled: s.bracketPairColorization },
    cursorStyle: s.cursorStyle,
    smoothScrolling: s.smoothScrolling,
    padding: { top: 8 },
    contextmenu: false,
  })

  // 自定义中文右键菜单
  editorContainer.value.addEventListener('contextmenu', (e: MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    showEditorCtxMenu(e.clientX, e.clientY)
  })

  monacoEditor.onDidChangeModelContent(() => {
    if (isUpdating) return
    const file = project.activeFile
    if (file) {
      file.content = monacoEditor.getValue()
      file.modified = true
      // 编辑了内容 → 自动固定预览 tab
      if (file.preview) file.preview = false

      // 自动保存
      if (settings.app.autoSave && project.activeFilePath) {
        if (autoSaveTimer) clearTimeout(autoSaveTimer)
        autoSaveTimer = setTimeout(() => {
          project.saveFile(project.activeFilePath)
        }, settings.app.autoSaveDelay)
      }
    }
  })

  monacoEditor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
    if (project.activeFilePath) {
      project.saveFile(project.activeFilePath)
    }
  })

  loadActiveFile()
  restoreSavedTheme()
}

// 启动时恢复已保存的主题
async function restoreSavedTheme() {
  extStore.loadSavedTheme()
  if (extStore.activeTheme && monaco) {
    const [dirName, ...pathParts] = extStore.activeTheme.split(':')
    const themeFile = pathParts.join(':')
    if (dirName && themeFile) {
      const result = await window.api.ext.loadTheme(dirName, themeFile)
      if (result.success && result.theme) {
        applyVscodeTheme(result.theme)
      }
    }
  }
}

function loadActiveFile() {
  if (!monacoEditor || !monaco) return
  const file = project.activeFile
  if (file && file.type !== 'browser') {
    isUpdating = true
    const lang = getLanguage(file.name)
    const oldModel = monacoEditor.getModel()
    const newModel = monaco.editor.createModel(file.content, lang)
    monacoEditor.setModel(newModel)
    if (oldModel) oldModel.dispose()
    isUpdating = false
  }
}

// ---- 内置浏览器 ----
async function loadBrowserUrl() {
  const file = project.activeFile
  if (file?.type === 'browser') {
    browserLoading.value = true
    try {
      const url = await window.api.fileServer.getUrl(file.path)
      browserUrl.value = url
    } catch (err) {
      console.error('Failed to get browser URL:', err)
    }
  }
}

function onBrowserLoad() {
  browserLoading.value = false
}

function refreshBrowser() {
  if (browserIframe.value) {
    browserLoading.value = true
    browserIframe.value.src = browserUrl.value
  }
}

function openInExternalBrowser() {
  const file = project.activeFile
  if (file) {
    window.api.fs.showInExplorer(file.path)
  }
}

function switchToCode() {
  if (project.activeFilePath) {
    project.openAsCode(project.activeFilePath)
  }
}

function openCurrentInBrowser() {
  const file = project.activeFile
  if (file) {
    project.openInBrowser(file.path, file.name)
  }
  closeEditorCtx()
}

async function reloadFileContent() {
  const file = project.activeFile
  if (!file || file.type === 'browser') return
  // 如果 content 为空（从浏览器模式切回），重新读取文件
  if (!file.content) {
    try {
      file.content = await window.api.fs.readFile(file.path)
    } catch (err) {
      console.error('Failed to reload file content:', err)
    }
  }
  loadActiveFile()
}

onMounted(() => { initMonaco() })

// 设置变化时实时更新编辑器
watch(() => settings.app, (val) => {
  if (!monacoEditor) return
  monacoEditor.updateOptions({
    fontSize: val.fontSize,
    fontFamily: val.fontFamily,
    minimap: { enabled: val.minimap },
    tabSize: val.tabSize,
    wordWrap: val.wordWrap ? 'on' : 'off',
    lineNumbers: val.lineNumbers ? 'on' : 'off',
    renderWhitespace: val.renderWhitespace,
    bracketPairColorization: { enabled: val.bracketPairColorization },
    cursorStyle: val.cursorStyle,
    smoothScrolling: val.smoothScrolling,
  })
}, { deep: true })

watch(() => project.activeFilePath, () => {
  if (!monacoEditor) {
    initMonaco()
  } else {
    loadActiveFile()
  }
  // 浏览器模式：加载 URL
  loadBrowserUrl()
})

// 监听当前文件类型变化（代码 ↔ 浏览器切换）
watch(() => project.activeFile?.type, (newType) => {
  if (newType === 'browser') {
    loadBrowserUrl()
  } else if (newType === 'code' || newType === undefined) {
    // 切回代码模式，需要重新加载文件内容到编辑器
    reloadFileContent()
  }
})

// 监听文件从磁盘重新加载（搜索替换后刷新编辑器）
watch(() => project.fileReloadTick, () => {
  loadActiveFile()
})

// 监听扩展主题变化
watch(() => extStore.pendingThemeData, (themeData) => {
  if (themeData && monaco) {
    applyVscodeTheme(themeData)
  }
})

function applyVscodeTheme(themeData: any) {
  if (!monaco) return
  const themeName = 'custom-ext-theme'
  try {
    // 将 VS Code 主题 JSON 转换为 Monaco 主题格式
    const rules: any[] = []
    if (themeData.tokenColors) {
      for (const tc of themeData.tokenColors) {
        const scopes = Array.isArray(tc.scope) ? tc.scope : (tc.scope ? [tc.scope] : [''])
        for (const scope of scopes) {
          const rule: any = { token: scope }
          if (tc.settings?.foreground) rule.foreground = tc.settings.foreground.replace('#', '')
          if (tc.settings?.fontStyle) rule.fontStyle = tc.settings.fontStyle
          rules.push(rule)
        }
      }
    }
    const colors = themeData.colors || {}
    monaco.editor.defineTheme(themeName, {
      base: themeData.type === 'light' ? 'vs' : 'vs-dark',
      inherit: true,
      rules,
      colors,
    })
    monaco.editor.setTheme(themeName)
  } catch (err) {
    console.error('Failed to apply theme:', err)
  }
}

function getLanguage(filename: string): string {
  const ext = filename.split('.').pop()?.toLowerCase()
  const map: Record<string, string> = {
    ts: 'typescript', tsx: 'typescriptreact', js: 'javascript', jsx: 'javascriptreact',
    vue: 'html', html: 'html', css: 'css', scss: 'scss', less: 'less',
    json: 'json', md: 'markdown', py: 'python', rs: 'rust',
    go: 'go', sql: 'sql', mysql: 'mysql', yaml: 'yaml', yml: 'yaml',
    sh: 'shell', bash: 'shell', xml: 'xml', svg: 'xml',
    java: 'java', kt: 'kotlin', c: 'c', cpp: 'cpp', h: 'cpp',
    cs: 'csharp', rb: 'ruby', php: 'php', swift: 'swift',
    r: 'r', lua: 'lua', dart: 'dart', dockerfile: 'dockerfile',
    graphql: 'graphql', ini: 'ini', toml: 'ini', bat: 'bat', ps1: 'powershell'
  }
  // 特殊文件名
  const nameMap: Record<string, string> = {
    'Dockerfile': 'dockerfile', 'Makefile': 'makefile',
    '.gitignore': 'plaintext', '.env': 'plaintext'
  }
  const name = filename.split(/[/\\]/).pop() || ''
  return nameMap[name] || map[ext || ''] || 'plaintext'
}

function getFileIcon(name: string): string {
  const ext = name.split('.').pop()?.toLowerCase()
  const icons: Record<string, string> = {
    vue: 'fa-brands fa-vuejs text-green-500',
    ts: 'fa-solid fa-file-code text-blue-400',
    tsx: 'fa-brands fa-react text-blue-400',
    js: 'fa-brands fa-js text-yellow-400',
    jsx: 'fa-brands fa-react text-blue-400',
    css: 'fa-brands fa-css3-alt text-blue-400',
    html: 'fa-brands fa-html5 text-orange-500',
    json: 'fa-solid fa-file-code text-yellow-500',
    md: 'fa-brands fa-markdown text-blue-300',
    sql: 'fa-solid fa-database text-blue-300',
    py: 'fa-brands fa-python text-yellow-500',
    java: 'fa-brands fa-java text-red-400',
    go: 'fa-brands fa-golang text-blue-300',
    rs: 'fa-solid fa-gear text-orange-400',
    php: 'fa-brands fa-php text-purple-400',
    rb: 'fa-solid fa-gem text-red-500',
    swift: 'fa-brands fa-swift text-orange-500',
    xml: 'fa-solid fa-code text-orange-300',
    yaml: 'fa-solid fa-file-code text-pink-400',
    yml: 'fa-solid fa-file-code text-pink-400',
    sh: 'fa-solid fa-terminal text-green-400',
    bat: 'fa-solid fa-terminal text-green-400'
  }
  return icons[ext || ''] || 'fa-solid fa-file-code text-gray-400'
}
</script>

<template>
  <div class="flex flex-col h-full bg-[#101014]">
    <!-- Tabs -->
    <div class="h-8 flex bg-[#101014] border-b border-[#2e2e32] shrink-0 overflow-x-auto">
      <div
        v-for="file in project.openFiles"
        :key="file.path"
        class="px-3 py-1.5 text-xs border-r border-[#2e2e32] cursor-pointer flex items-center gap-2 min-w-fit transition-colors"
        :class="file.path === project.activeFilePath
          ? 'text-white bg-[#18181c] border-t-2 border-t-blue-500'
          : 'text-[#a1a1aa] hover:bg-[#18181c]'"
        @click="project.activeFilePath = file.path"
        @dblclick="project.pinFile(file.path)"
      >
        <i :class="file.type === 'browser' ? 'fa-solid fa-globe text-blue-400' : getFileIcon(file.name)"></i>
        <span :class="{ italic: file.preview || file.modified }">{{ file.name }}</span>
        <span v-if="file.modified" class="w-2 h-2 rounded-full bg-white/50 ml-1"></span>
        <i
          class="fa-solid fa-xmark ml-2 text-[10px] hover:bg-[#27272a] rounded p-0.5 w-4 h-4 flex items-center justify-center"
          @click.stop="project.closeFile(file.path)"
        ></i>
      </div>
    </div>

    <!-- Welcome (no files open) -->
    <div v-if="project.openFiles.length === 0" class="flex-1 flex items-center justify-center text-[#52525b]">
      <div class="text-center">
        <i class="fa-solid fa-code text-5xl mb-4 block"></i>
        <p class="text-lg">Pantheon Forge</p>
        <p class="text-sm mt-2">点击左侧文件树打开文件</p>
      </div>
    </div>

    <!-- 内置浏览器预览 -->
    <div v-if="isBrowserMode && project.openFiles.length > 0" class="flex-1 flex flex-col min-h-0">
      <!-- 浏览器工具栏 -->
      <div class="h-9 flex items-center gap-2 px-3 bg-[#1e1e1e] border-b border-[#2e2e32] shrink-0">
        <i class="fa-solid fa-arrow-rotate-right text-xs text-[#a1a1aa] hover:text-white cursor-pointer transition-colors" title="刷新" @click="refreshBrowser"></i>
        <div class="flex-1 bg-[#2d2d2d] rounded px-3 py-1 text-xs text-[#a1a1aa] truncate select-all">
          {{ project.activeFile?.path }}
        </div>
        <i class="fa-solid fa-code text-xs text-[#a1a1aa] hover:text-white cursor-pointer transition-colors" title="切换到代码编辑" @click="switchToCode"></i>
        <i class="fa-solid fa-arrow-up-right-from-square text-xs text-[#a1a1aa] hover:text-white cursor-pointer transition-colors" title="在系统浏览器中打开" @click="openInExternalBrowser"></i>
      </div>
      <!-- 加载指示器 -->
      <div v-if="browserLoading" class="h-0.5 bg-blue-500 animate-pulse shrink-0"></div>
      <!-- iframe -->
      <iframe
        ref="browserIframe"
        :src="browserUrl"
        class="flex-1 w-full border-0 bg-white"
        sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
        @load="onBrowserLoad"
      ></iframe>
    </div>

    <!-- Monaco Editor (hidden when browser mode or no files) -->
    <div v-show="project.openFiles.length > 0 && !isBrowserMode" ref="editorContainer" class="flex-1 min-h-0" @click="closeEditorCtx"></div>

    <!-- 编辑器中文右键菜单 -->
    <Teleport to="body">
      <div v-if="editorCtx.show" class="fixed inset-0 z-[9998]" @click="closeEditorCtx" @contextmenu.prevent="closeEditorCtx"></div>
      <div
        v-if="editorCtx.show"
        class="fixed z-[9999] bg-[#1f1f1f] border border-[#454545] rounded-md shadow-2xl py-[5px] min-w-[220px] text-[13px] text-[#cccccc] select-none"
        :style="{ left: editorCtx.x + 'px', top: editorCtx.y + 'px' }"
        @click.stop
        @contextmenu.prevent
      >
        <div class="ectx-item" @click="editorAction('editor.action.changeAll')">
          <span>更改所有匹配项</span>
          <span class="ectx-shortcut">Ctrl+F2</span>
        </div>
        <div class="ectx-divider"></div>
        <div class="ectx-item" @click="editorCut()">
          <span>剪切</span>
          <span class="ectx-shortcut">Ctrl+X</span>
        </div>
        <div class="ectx-item" @click="editorCopy()">
          <span>复制</span>
          <span class="ectx-shortcut">Ctrl+C</span>
        </div>
        <div class="ectx-item" @click="editorPaste()">
          <span>粘贴</span>
          <span class="ectx-shortcut">Ctrl+V</span>
        </div>
        <div class="ectx-divider"></div>
        <div class="ectx-item" @click="editorSelectAll()">
          <span>全选</span>
          <span class="ectx-shortcut">Ctrl+A</span>
        </div>
        <div class="ectx-divider"></div>
        <div class="ectx-item" @click="editorAction('editor.action.goToSymbol')">
          <span>转到符号...</span>
          <span class="ectx-shortcut">Ctrl+Shift+O</span>
        </div>
        <div class="ectx-item" @click="editorAction('editor.action.rename')">
          <span>重命名符号</span>
          <span class="ectx-shortcut">F2</span>
        </div>
        <div class="ectx-item" @click="editorAction('editor.action.formatDocument')">
          <span>格式化文档</span>
          <span class="ectx-shortcut">Shift+Alt+F</span>
        </div>
        <div class="ectx-divider"></div>
        <div class="ectx-item" @click="editorAction('editor.action.quickCommand')">
          <span>命令面板</span>
          <span class="ectx-shortcut">F1</span>
        </div>
        <!-- HTML 文件：在内置浏览器中打开 -->
        <template v-if="project.activeFile && ['html', 'htm'].includes((project.activeFile.name.split('.').pop() || '').toLowerCase())">
          <div class="ectx-divider"></div>
          <div class="ectx-item" @click="openCurrentInBrowser">
            <span>在内置浏览器中打开</span>
            <span class="ectx-shortcut"></span>
          </div>
        </template>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.ectx-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 24px;
  height: 30px;
  cursor: pointer;
  white-space: nowrap;
  transition: background 0.08s;
}
.ectx-item:hover {
  background: #04395e;
  color: #fff;
}
.ectx-shortcut {
  color: #717171;
  font-size: 12px;
  margin-left: 32px;
}
.ectx-item:hover .ectx-shortcut {
  color: #b0b0b0;
}
.ectx-divider {
  height: 1px;
  background: #3c3c3c;
  margin: 4px 12px;
}
</style>
