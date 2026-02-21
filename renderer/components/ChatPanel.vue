<script setup lang="ts">
import { ref, nextTick, watch } from 'vue'
import { useChatStore } from '../stores/chat'
import { useProjectStore } from '../stores/project'
import { useSettingsStore } from '../stores/settings'
import { marked } from 'marked'
import hljs from 'highlight.js'

const chat = useChatStore()
const project = useProjectStore()
const settings = useSettingsStore()
const inputText = ref('')
const chatContainer = ref<HTMLElement>()
const showModelPicker = ref(false)
const thinkingExpanded = ref<Record<number, boolean>>({})
const showHistory = ref(false)
const historyList = ref<{ id: number; preview: string; created_at: string }[]>([])

async function toggleHistory() {
  if (showHistory.value) {
    showHistory.value = false
    return
  }
  historyList.value = await chat.loadSessionList()
  showHistory.value = true
}

async function switchSession(sid: number) {
  showHistory.value = false
  await chat.loadSession(sid)
}

async function deleteSession(e: Event, sid: number) {
  e.stopPropagation()
  await chat.deleteSession(sid)
  historyList.value = historyList.value.filter(s => s.id !== sid)
}

function formatTime(dateStr: string): string {
  if (!dateStr) return ''
  try {
    const d = new Date(dateStr + 'Z') // SQLite datetime is UTC
    const now = new Date()
    const diff = now.getTime() - d.getTime()
    if (diff < 60000) return '刚刚'
    if (diff < 3600000) return `${Math.floor(diff / 60000)} 分钟前`
    if (diff < 86400000) return `${Math.floor(diff / 3600000)} 小时前`
    if (diff < 604800000) return `${Math.floor(diff / 86400000)} 天前`
    return d.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' })
  } catch { return '' }
}

// 配置 marked
const renderer = new marked.Renderer()
renderer.code = function ({ text, lang }: { text: string; lang?: string }) {
  const language = lang && hljs.getLanguage(lang) ? lang : 'plaintext'
  const highlighted = hljs.highlight(text, { language }).value
  const lineCount = text.split('\n').length
  return `<div class="code-block-wrapper" data-lines="${lineCount}">
    <div class="code-block-header">
      <span class="code-lang">${language}</span>
      <button class="code-copy-btn" onclick="navigator.clipboard.writeText(this.closest('.code-block-wrapper').querySelector('code').textContent)">
        <i class="fa-regular fa-copy"></i> 复制
      </button>
    </div>
    <pre class="code-block-pre"><code class="hljs language-${language}">${highlighted}</code></pre>
  </div>`
}
marked.setOptions({ renderer, breaks: true, gfm: true })

function renderMarkdown(content: string): string {
  if (!content) return ''
  try { return marked.parse(content) as string } catch { return content }
}

function toggleThinking(msgId: number) {
  thinkingExpanded.value[msgId] = !thinkingExpanded.value[msgId]
}
function isThinkingOpen(msgId: number, msg: any): boolean {
  if (msgId in thinkingExpanded.value) return thinkingExpanded.value[msgId]
  return !msg.thinkingDone
}

async function send() {
  if (!inputText.value.trim() || chat.isStreaming) return
  if (!chat.sessionId && project.projectPath) {
    await chat.createSession(project.projectPath)
  }
  const msg = inputText.value
  inputText.value = ''
  await chat.sendMessage(msg, project.projectPath)
}
function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() }
}
async function selectModel(id: number) {
  const model = settings.models.find(m => m.id === id)
  if (model) chat.selectModel(id, model.name)
  showModelPicker.value = false
}

function handleContentClick(e: MouseEvent) {
  const target = e.target as HTMLElement
  const toggleBtn = target.closest('.code-toggle-btn') as HTMLElement
  if (toggleBtn) {
    const wrapper = toggleBtn.closest('.code-block-wrapper') as HTMLElement
    if (wrapper) wrapper.classList.toggle('expanded')
  }
}

function processCodeBlocks(container: HTMLElement) {
  if (!container) return
  const wrappers = container.querySelectorAll('.code-block-wrapper:not([data-processed])')
  wrappers.forEach(wrapper => {
    wrapper.setAttribute('data-processed', '1')
    const lines = parseInt(wrapper.getAttribute('data-lines') || '0')
    if (lines > 2) {
      const btn = document.createElement('div')
      btn.className = 'code-toggle-btn'
      btn.innerHTML = `<span class="collapsed-label"><i class="fa-solid fa-chevron-right"></i> 展开 ${lines} 行</span><span class="expanded-label"><i class="fa-solid fa-chevron-down"></i> 收起</span>`
      wrapper.appendChild(btn)
    } else {
      wrapper.classList.add('expanded')
    }
  })
}

// 工具图标映射
function toolIcon(name: string): string {
  switch (name) {
    case 'read_file': return 'fa-solid fa-file-code'
    case 'write_file': return 'fa-solid fa-pen-to-square'
    case 'list_dir': return 'fa-solid fa-folder-open'
    case 'run_terminal': return 'fa-solid fa-terminal'
    case 'search_files': return 'fa-solid fa-magnifying-glass'
    default: return 'fa-solid fa-gear'
  }
}
function toolLabel(name: string): string {
  switch (name) {
    case 'read_file': return '读取文件'
    case 'write_file': return '写入文件'
    case 'list_dir': return '列出目录'
    case 'run_terminal': return '执行命令'
    case 'search_files': return '搜索文件'
    default: return name
  }
}

// 自动滚动 + 处理代码块
watch(
  () => {
    const m = chat.messages
    return m.map(msg => {
      const blockSig = msg.blocks.map(b => b.type === 'text' ? b.text.length : b.tool.status).join(',')
      return blockSig + (msg.thinking || '')
    }).join('|')
  },
  () => {
    nextTick(() => {
      if (chatContainer.value) {
        chatContainer.value.scrollTop = chatContainer.value.scrollHeight
        processCodeBlocks(chatContainer.value)
      }
    })
  }
)
</script>

<template>
  <div class="bg-[#18181c] border-r border-[#2e2e32] flex flex-col h-full">
    <!-- Header -->
    <div class="h-9 px-3 border-b border-[#2e2e32] flex items-center justify-between shrink-0 bg-[#27272a]/30">
      <span class="font-semibold text-xs uppercase tracking-wider text-[#a1a1aa]">AI 助手</span>
      <div class="flex gap-2 text-xs">
        <div class="relative">
          <i class="fa-solid fa-clock-rotate-left text-[#a1a1aa] hover:text-white cursor-pointer" title="历史会话" @click="toggleHistory"></i>
          <!-- History dropdown -->
          <div v-if="showHistory" class="absolute right-0 top-full mt-2 bg-[#27272a] border border-[#3e3e42] rounded-lg shadow-2xl py-1 w-[200px] z-50 max-h-[240px] overflow-y-auto">
            <div class="px-2 py-1.5 text-[9px] text-[#52525b] uppercase tracking-wider border-b border-[#2e2e32]">历史会话</div>
            <div v-if="historyList.length === 0" class="px-2 py-3 text-[10px] text-[#52525b] text-center">
              暂无历史会话
            </div>
            <div
              v-for="session in historyList" :key="session.id"
              class="flex items-center gap-1.5 px-2 py-1.5 cursor-pointer transition-colors group"
              :class="session.id === chat.sessionId ? 'bg-blue-500/10 text-white' : 'text-[#a1a1aa] hover:bg-[#3e3e42]'"
              @click="switchSession(session.id)"
            >
              <i class="fa-regular fa-message text-[8px] shrink-0" :class="session.id === chat.sessionId ? 'text-blue-400' : 'text-[#52525b]'"></i>
              <div class="min-w-0 flex-1">
                <div class="text-[10px] truncate leading-tight">{{ session.preview }}</div>
                <div class="text-[8px] text-[#52525b] leading-tight">{{ formatTime(session.created_at) }}</div>
              </div>
              <i
                class="fa-solid fa-xmark text-[8px] text-[#52525b] hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                title="删除会话"
                @click="deleteSession($event, session.id)"
              ></i>
            </div>
          </div>
          <div v-if="showHistory" class="fixed inset-0 z-40" @click="showHistory = false"></div>
        </div>
        <i class="fa-solid fa-plus text-[#a1a1aa] hover:text-white cursor-pointer" title="新建对话" @click="chat.newChat()"></i>
      </div>
    </div>

    <!-- Messages -->
    <div ref="chatContainer" class="flex-1 overflow-y-auto p-4 space-y-4" @click="handleContentClick">
      <div v-if="chat.messages.length === 0" class="text-center text-[#52525b] text-sm mt-8">
        <i class="fa-solid fa-robot text-3xl mb-3 block"></i>
        <p>输入指令开始编程</p>
        <p class="text-xs mt-1">支持代码编辑、文件操作、终端命令</p>
      </div>

      <div v-for="msg in chat.messages" :key="msg.id" class="space-y-2">
        <!-- User -->
        <div v-if="msg.role === 'user'" class="flex justify-end">
          <div class="bg-blue-600/20 border border-blue-500/30 text-white p-3 rounded-2xl rounded-tr-none text-sm max-w-[90%] whitespace-pre-wrap">
            {{ msg.blocks[0]?.type === 'text' ? msg.blocks[0].text : '' }}
          </div>
        </div>

        <!-- Assistant -->
        <div v-else class="flex gap-3">
          <div class="flex-1 min-w-0 space-y-2">
            <!-- Thinking block -->
            <div v-if="msg.thinking" class="thinking-block">
              <div
                class="flex items-center gap-1.5 px-3 py-1.5 bg-purple-500/10 border border-purple-500/20 rounded-t-lg cursor-pointer select-none hover:bg-purple-500/15 transition-colors"
                @click="toggleThinking(msg.id)"
              >
                <i class="fa-solid text-purple-400 text-[10px]" :class="isThinkingOpen(msg.id, msg) ? 'fa-chevron-down' : 'fa-chevron-right'"></i>
                <i class="fa-solid fa-brain text-purple-400 text-[10px]"></i>
                <span class="text-[11px] text-purple-300 font-medium">
                  {{ msg.thinkingDone ? '思考过程' : '思考中...' }}
                </span>
                <i v-if="!msg.thinkingDone" class="fa-solid fa-spinner fa-spin text-purple-400 text-[10px] ml-1"></i>
              </div>
              <div
                v-show="isThinkingOpen(msg.id, msg)"
                class="bg-purple-500/5 border border-t-0 border-purple-500/20 rounded-b-lg p-3 text-[11px] text-purple-200/70 whitespace-pre-wrap max-h-[300px] overflow-y-auto code-font leading-relaxed"
              >{{ msg.thinking }}</div>
            </div>

            <!-- 按顺序渲染 blocks：文字和工具调用交替 -->
            <template v-for="(block, bi) in msg.blocks" :key="bi">
              <!-- 文字块 -->
              <div
                v-if="block.type === 'text' && block.text"
                class="chat-markdown bg-[#27272a] text-gray-300 p-3 rounded-2xl rounded-tl-none text-sm border border-[#2e2e32]"
                v-html="renderMarkdown(block.text)"
              ></div>

              <!-- 工具调用块 -->
              <div v-else-if="block.type === 'tool'" class="tool-call-block flex items-start gap-2 px-3 py-2 rounded-lg border text-[11px]"
                :class="block.tool.status === 'done' ? 'bg-[#27272a]/50 border-[#2e2e32]' : 'bg-yellow-500/5 border-yellow-500/20'"
              >
                <i :class="[toolIcon(block.tool.name), block.tool.status === 'done' ? 'text-green-400' : 'text-yellow-400']" class="text-[10px] mt-0.5 shrink-0"></i>
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-1.5">
                    <span class="text-[#a1a1aa] font-medium">{{ toolLabel(block.tool.name) }}</span>
                    <span class="text-[#52525b] code-font truncate">{{ block.tool.args }}</span>
                    <span class="ml-auto shrink-0 flex items-center gap-1"
                      :class="block.tool.status === 'done' ? 'text-green-400/70' : 'text-yellow-400/70'"
                    >
                      <i :class="block.tool.status === 'done' ? 'fa-solid fa-check' : 'fa-solid fa-spinner fa-spin'" class="text-[8px]"></i>
                      {{ block.tool.status === 'done' ? '完成' : '执行中' }}
                    </span>
                  </div>
                </div>
              </div>
            </template>

            <!-- Streaming indicator -->
            <div v-if="msg.streaming && msg.blocks.length === 0 && !msg.thinking" class="flex gap-1 p-2">
              <span class="w-1.5 h-1.5 bg-[#52525b] rounded-full animate-bounce"></span>
              <span class="w-1.5 h-1.5 bg-[#52525b] rounded-full animate-bounce" style="animation-delay: 75ms"></span>
              <span class="w-1.5 h-1.5 bg-[#52525b] rounded-full animate-bounce" style="animation-delay: 150ms"></span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Input -->
    <div class="p-3 border-t border-[#2e2e32] bg-[#18181c] shrink-0">
      <div class="relative group">
        <textarea
          v-model="inputText"
          class="w-full bg-[#27272a] border border-[#2e2e32] rounded-lg p-3 pr-10 text-sm text-white focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/20 resize-none h-24 placeholder-[#52525b] code-font transition-all"
          placeholder="输入指令编辑代码、运行命令或解释... (Enter 发送)"
          @keydown="handleKeydown"
        ></textarea>
        <div class="absolute bottom-2 right-2 flex gap-1">
          <div class="relative">
            <div
              class="h-7 px-2 rounded hover:bg-[#2e2e32] flex items-center gap-1.5 text-[#a1a1aa] transition-colors cursor-pointer mr-1 border border-transparent hover:border-[#2e2e32]/50"
              title="选择模型"
              @click="showModelPicker = !showModelPicker"
            >
              <span class="w-1.5 h-1.5 rounded-full shadow" :class="chat.activeModelName === '未配置' ? 'bg-[#52525b]' : 'bg-green-500 shadow-green-500/50'"></span>
              <span class="text-[10px] font-medium group-hover:text-white">{{ chat.activeModelName }}</span>
              <i class="fa-solid fa-chevron-up text-[8px] ml-0.5"></i>
            </div>
            <div v-if="showModelPicker" class="absolute bottom-full right-0 mb-1 bg-[#27272a] border border-[#3e3e42] rounded-lg shadow-xl py-1 min-w-[180px] z-50 max-h-[240px] overflow-y-auto">
              <div v-if="settings.models.filter(m => m.is_active).length === 0" class="px-3 py-3 text-[11px] text-[#52525b] text-center">
                暂无激活模型，请在设置中配置
              </div>
              <div
                v-for="model in settings.models.filter(m => m.is_active)" :key="model.id"
                class="flex items-center gap-2 px-3 py-2 text-xs cursor-pointer transition-colors"
                :class="model.id === chat.selectedModelId ? 'text-white bg-[#3b82f6]/15' : 'text-[#a1a1aa] hover:bg-[#3b82f6] hover:text-white'"
                @click="selectModel(model.id!)"
              >
                <i v-if="model.id === chat.selectedModelId" class="fa-solid fa-check text-[10px] text-[#3b82f6] w-3"></i>
                <span v-else class="w-3"></span>
                <span>{{ model.name }}</span>
                <span class="text-[9px] text-[#52525b] ml-auto">{{ model.model_name }}</span>
              </div>
              <div class="border-t border-[#3e3e42] mt-1 pt-1">
                <div class="flex items-center gap-2 px-3 py-2 text-xs text-[#a1a1aa] hover:bg-[#3b82f6] hover:text-white cursor-pointer transition-colors"
                  @click="settings.showSettings = true; showModelPicker = false"
                >
                  <i class="fa-solid fa-gear text-[10px] w-3"></i>
                  <span>模型设置...</span>
                </div>
              </div>
            </div>
            <div v-if="showModelPicker" class="fixed inset-0 z-40" @click="showModelPicker = false"></div>
          </div>
          <button v-if="chat.isStreaming"
            class="w-7 h-7 rounded bg-red-600 hover:bg-red-500 text-white flex items-center justify-center transition-colors"
            title="停止生成" @click="chat.stopGeneration()"
          ><i class="fa-solid fa-stop text-xs"></i></button>
          <button v-else
            class="w-7 h-7 rounded bg-blue-600 hover:bg-blue-500 text-white flex items-center justify-center transition-colors shadow-lg shadow-blue-900/20"
            title="发送消息" @click="send"
          ><i class="fa-solid fa-paper-plane text-xs"></i></button>
        </div>
      </div>
      <div class="flex justify-between items-center mt-2 px-1">
        <div class="text-[10px] text-[#52525b]"><i class="fa-brands fa-markdown mr-1"></i>支持 Markdown</div>
        <div class="text-[10px] text-[#52525b]">上下文: <span class="text-blue-400 cursor-pointer hover:underline">当前文件</span></div>
      </div>
    </div>
  </div>
</template>

<style>
.chat-markdown { line-height: 1.6; word-wrap: break-word; overflow-wrap: break-word; }
.chat-markdown p { margin: 0.4em 0; }
.chat-markdown p:first-child { margin-top: 0; }
.chat-markdown p:last-child { margin-bottom: 0; }
.chat-markdown ul, .chat-markdown ol { margin: 0.4em 0; padding-left: 1.5em; }
.chat-markdown li { margin: 0.2em 0; }
.chat-markdown strong { color: #e4e4e7; font-weight: 600; }
.chat-markdown em { color: #a1a1aa; }
.chat-markdown a { color: #60a5fa; text-decoration: underline; }
.chat-markdown blockquote { border-left: 3px solid #3b82f6; padding-left: 0.8em; margin: 0.5em 0; color: #a1a1aa; }
.chat-markdown h1, .chat-markdown h2, .chat-markdown h3, .chat-markdown h4, .chat-markdown h5, .chat-markdown h6 { color: #e4e4e7; margin: 0.6em 0 0.3em; font-weight: 600; }
.chat-markdown h1 { font-size: 1.3em; }
.chat-markdown h2 { font-size: 1.15em; }
.chat-markdown h3 { font-size: 1.05em; }
.chat-markdown code:not(.hljs) { background: #1a1a2e; color: #f472b6; padding: 0.15em 0.4em; border-radius: 4px; font-size: 0.85em; font-family: 'Cascadia Code', 'Fira Code', 'JetBrains Mono', monospace; }

.code-block-wrapper { margin: 0.6em 0; border-radius: 8px; overflow: hidden; border: 1px solid #2e2e32; background: #0d0d11; }
.code-block-header { display: flex; justify-content: space-between; align-items: center; padding: 4px 12px; background: #1a1a2e; border-bottom: 1px solid #2e2e32; }
.code-lang { font-size: 10px; color: #52525b; text-transform: uppercase; font-weight: 500; }
.code-copy-btn { font-size: 10px; color: #52525b; background: none; border: none; cursor: pointer; padding: 2px 6px; border-radius: 4px; transition: all 0.15s; }
.code-copy-btn:hover { color: #a1a1aa; background: #27272a; }
.code-block-pre { margin: 0; overflow-x: auto; transition: max-height 0.3s ease; }
.code-block-wrapper:not(.expanded) .code-block-pre { max-height: 3.6em; overflow: hidden; }
.code-block-wrapper.expanded .code-block-pre { max-height: none; }
.code-block-pre code { display: block; padding: 10px 12px; font-size: 12px; line-height: 1.5; font-family: 'Cascadia Code', 'Fira Code', 'JetBrains Mono', monospace; }
.code-toggle-btn { display: flex; justify-content: center; padding: 4px 0; font-size: 10px; color: #3b82f6; cursor: pointer; border-top: 1px solid #2e2e32; background: #111118; transition: background 0.15s; user-select: none; }
.code-toggle-btn:hover { background: #1a1a2e; }
.code-block-wrapper:not(.expanded) .code-toggle-btn .expanded-label { display: none; }
.code-block-wrapper.expanded .code-toggle-btn .collapsed-label { display: none; }

.hljs { background: transparent !important; color: #c9d1d9; }
.hljs-keyword { color: #ff7b72; }
.hljs-string { color: #a5d6ff; }
.hljs-comment { color: #8b949e; font-style: italic; }
.hljs-function { color: #d2a8ff; }
.hljs-number { color: #79c0ff; }
.hljs-title { color: #d2a8ff; }
.hljs-built_in { color: #ffa657; }
.hljs-type { color: #ffa657; }
.hljs-params { color: #c9d1d9; }
.hljs-attr { color: #79c0ff; }
.hljs-variable { color: #ffa657; }
.hljs-literal { color: #79c0ff; }
.hljs-meta { color: #8b949e; }
.hljs-selector-tag { color: #7ee787; }
.hljs-selector-class { color: #d2a8ff; }
.hljs-tag { color: #7ee787; }
.hljs-name { color: #7ee787; }
.hljs-attribute { color: #79c0ff; }

.chat-markdown table { border-collapse: collapse; margin: 0.5em 0; width: 100%; font-size: 0.85em; }
.chat-markdown th, .chat-markdown td { border: 1px solid #2e2e32; padding: 4px 8px; }
.chat-markdown th { background: #1a1a2e; color: #e4e4e7; font-weight: 600; }
.chat-markdown hr { border: none; border-top: 1px solid #2e2e32; margin: 0.8em 0; }
</style>
