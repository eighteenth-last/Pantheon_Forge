<script setup lang="ts">
import { ref, watch, onMounted, nextTick } from 'vue'
import { useProjectStore } from '../stores/project'

const project = useProjectStore()
const editorContainer = ref<HTMLElement>()
let monacoEditor: any = null
let monaco: any = null
let isUpdating = false

async function initMonaco() {
  if (monacoEditor) return
  monaco = await import('monaco-editor')
  await nextTick()
  if (!editorContainer.value) return

  monacoEditor = monaco.editor.create(editorContainer.value, {
    value: '',
    language: 'plaintext',
    theme: 'vs-dark',
    fontSize: 13,
    fontFamily: "'JetBrains Mono', monospace",
    minimap: { enabled: true },
    scrollBeyondLastLine: false,
    automaticLayout: true,
    tabSize: 2,
    wordWrap: 'on',
    lineNumbers: 'on',
    renderWhitespace: 'selection',
    bracketPairColorization: { enabled: true },
    padding: { top: 8 }
  })

  monacoEditor.onDidChangeModelContent(() => {
    if (isUpdating) return
    const file = project.activeFile
    if (file) {
      file.content = monacoEditor.getValue()
      file.modified = true
    }
  })

  monacoEditor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
    if (project.activeFilePath) {
      project.saveFile(project.activeFilePath)
    }
  })

  loadActiveFile()
}

function loadActiveFile() {
  if (!monacoEditor || !monaco) return
  const file = project.activeFile
  if (file) {
    isUpdating = true
    const lang = getLanguage(file.name)
    const oldModel = monacoEditor.getModel()
    const newModel = monaco.editor.createModel(file.content, lang)
    monacoEditor.setModel(newModel)
    if (oldModel) oldModel.dispose()
    isUpdating = false
  }
}

onMounted(() => { initMonaco() })

watch(() => project.activeFilePath, () => {
  if (!monacoEditor) {
    initMonaco()
  } else {
    loadActiveFile()
  }
})

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
      >
        <i :class="getFileIcon(file.name)"></i>
        <span :class="{ italic: file.modified }">{{ file.name }}</span>
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

    <!-- Monaco Editor (always in DOM, hidden when no files) -->
    <div v-show="project.openFiles.length > 0" ref="editorContainer" class="flex-1 min-h-0"></div>
  </div>
</template>
