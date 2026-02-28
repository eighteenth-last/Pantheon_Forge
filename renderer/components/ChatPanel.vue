<script setup lang="ts">
import { ref, nextTick, watch, onBeforeUnmount } from 'vue'
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
/** 待发送的粘贴图片列表（base64 data URL） */
const pendingImages = ref<string[]>([])
/** 图片预览 URL */
const previewImage = ref<string | null>(null)

/** 上下文容量估算（与 AgentMemory 同算法：1 token ≈ 3 字符） */
const MAX_CONTEXT_TOKENS = 100000
function estimateContextUsage(): { used: number; total: number; ratio: number } {
  let totalChars = 0
  for (const msg of chat.messages) {
    for (const b of msg.blocks) {
      if (b.type === 'text') totalChars += b.text.length
      else if (b.type === 'tool') {
        totalChars += b.tool.name.length + b.tool.args.length + b.tool.output.length
      }
    }
    if (msg.thinking) totalChars += msg.thinking.length
    if (msg.images) totalChars += msg.images.length * 255
  }
  const used = Math.ceil(totalChars / 3)
  const ratio = Math.min(used / MAX_CONTEXT_TOKENS, 1)
  return { used, total: MAX_CONTEXT_TOKENS, ratio }
}
function contextColor(): string {
  const { ratio } = estimateContextUsage()
  if (ratio < 0.5) return '#22c55e'   // 绿色
  if (ratio < 0.8) return '#eab308'   // 黄色
  return '#ef4444'                      // 红色
}
function contextLabel(): string {
  const { used, total } = estimateContextUsage()
  if (used < 1000) return `${used} / ${(total / 1000).toFixed(0)}K`
  return `${(used / 1000).toFixed(1)}K / ${(total / 1000).toFixed(0)}K`
}
async function toggleHistory() {
  if (showHistory.value) { showHistory.value = false; return }
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
    const d = new Date(dateStr + 'Z')
    const now = new Date()
    const diff = now.getTime() - d.getTime()
    if (diff < 60000) return '刚刚'
    if (diff < 3600000) return `${Math.floor(diff / 60000)} 分钟前`
    if (diff < 86400000) return `${Math.floor(diff / 3600000)} 小时前`
    if (diff < 604800000) return `${Math.floor(diff / 86400000)} 天前`
    return d.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' })
  } catch { return '' }
}

// ---- Markdown 渲染（仅用于完成后的消息） ----
const mdRenderer = new marked.Renderer()
mdRenderer.code = function ({ text, lang }: { text: string; lang?: string }) {
  const language = lang && hljs.getLanguage(lang) ? lang : 'plaintext'
  const highlighted = hljs.highlight(text, { language }).value
  const lineCount = text.split('\n').length
  return `<div class="code-block-wrapper expanded" data-lines="${lineCount}">
    <div class="code-block-header">
      <span class="code-lang">${language}</span>
      <button class="code-copy-btn" onclick="navigator.clipboard.writeText(this.closest('.code-block-wrapper').querySelector('code').textContent)">
        <i class="fa-regular fa-copy"></i> 复制
      </button>
    </div>
    <pre class="code-block-pre"><code class="hljs language-${language}">${highlighted}</code></pre>
  </div>`
}
marked.setOptions({ renderer: mdRenderer, breaks: true, gfm: true })

// Markdown HTML 缓存：key = 原始文本, value = 渲染后 HTML
const mdHtmlCache = new Map<string, string>()
const MD_CACHE_MAX = 100

function renderMarkdownCached(content: string): string {
  if (!content) return ''
  const cached = mdHtmlCache.get(content)
  if (cached) return cached
  try {
    const html = marked.parse(content) as string
    if (mdHtmlCache.size > MD_CACHE_MAX) {
      const keys = [...mdHtmlCache.keys()]
      for (let i = 0; i < keys.length / 2; i++) mdHtmlCache.delete(keys[i])
    }
    mdHtmlCache.set(content, html)
    return html
  } catch { return content }
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
  const images = pendingImages.value.length > 0 ? [...pendingImages.value] : undefined
  inputText.value = ''
  pendingImages.value = []
  await chat.sendMessage(msg, project.projectPath, images)
}
function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() }
}

/** 处理粘贴事件：检测剪贴板中的图片 */
function handlePaste(e: ClipboardEvent) {
  const items = e.clipboardData?.items
  if (!items) return
  for (const item of items) {
    if (item.type.startsWith('image/')) {
      e.preventDefault()
      const file = item.getAsFile()
      if (!file) continue
      const reader = new FileReader()
      reader.onload = () => {
        if (typeof reader.result === 'string') {
          pendingImages.value.push(reader.result)
        }
      }
      reader.readAsDataURL(file)
    }
  }
}

/** 移除待发送的图片 */
function removePendingImage(index: number) {
  pendingImages.value.splice(index, 1)
}

function showImagePreview(url: string) {
  previewImage.value = url
}
function closeImagePreview() {
  previewImage.value = null
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

// 模型图标映射
function modelIcon(type: string): string {
  switch (type) {
    case 'claude': return 'fa-solid fa-c'
    case 'gemini': return 'fa-solid fa-g'
    case 'glm': return 'fa-solid fa-z'
    case 'deepseek': return 'fa-solid fa-d'
    case 'minimax': return 'fa-solid fa-m'
    case 'openai-compatible': return 'fa-solid fa-robot'
    default: return 'fa-solid fa-robot'
  }
}
function modelColor(type: string): string {
  switch (type) {
    case 'claude': return 'text-orange-400'
    case 'gemini': return 'text-blue-400'
    case 'glm': return 'text-blue-500'
    case 'deepseek': return 'text-cyan-400'
    case 'minimax': return 'text-purple-400'
    case 'openai-compatible': return 'text-green-400'
    default: return 'text-[#a1a1aa]'
  }
}

function toolIcon(name: string): string {
  switch (name) {
    case 'read_file': return 'fa-solid fa-file-code'
    case 'write_file': return 'fa-solid fa-pen-to-square'
    case 'edit_file': return 'fa-solid fa-pen'
    case 'list_dir': return 'fa-solid fa-folder-open'
    case 'run_terminal': return 'fa-solid fa-terminal'
    case 'search_files': return 'fa-solid fa-magnifying-glass'
    case 'start_service': return 'fa-solid fa-play'
    case 'check_service': return 'fa-solid fa-heartbeat'
    case 'stop_service': return 'fa-solid fa-stop'
    case 'load_skill': return 'fa-solid fa-book'
    default: return 'fa-solid fa-gear'
  }
}
function toolLabel(name: string): string {
  switch (name) {
    case 'read_file': return '读取文件'
    case 'write_file': return '写入文件'
    case 'edit_file': return '编辑文件'
    case 'list_dir': return '列出目录'
    case 'run_terminal': return '执行命令'
    case 'search_files': return '搜索文件'
    case 'start_service': return '启动服务'
    case 'check_service': return '检查服务'
    case 'stop_service': return '停止服务'
    case 'load_skill': return '加载技能'
    default: return name
  }
}

/** 工具输出展开状态 */
const expandedTools = ref(new Set<string>())
function toggleToolOutput(blockId: string) {
  if (expandedTools.value.has(blockId)) {
    expandedTools.value.delete(blockId)
  } else {
    expandedTools.value.add(blockId)
  }
}
/** 截断工具输出用于预览 */
function truncateOutput(output: string, maxLen = 200): string {
  if (!output) return ''
  if (output.length <= maxLen) return output
  return output.slice(0, maxLen) + '...'
}

/** 从工具输出中解析行数统计 */
function parseLineStats(output: string): { added: number; removed: number } | null {
  if (!output) return null
  // 匹配 "+N -M 行" 格式
  const m = output.match(/\+(\d+)\s+-(\d+)\s+行/)
  if (m) return { added: parseInt(m[1]), removed: parseInt(m[2]) }
  // 匹配 "+N 行, 新文件" 格式
  const m2 = output.match(/\+(\d+)\s+行.*新文件/)
  if (m2) return { added: parseInt(m2[1]), removed: 0 }
  return null
}

// 自动滚动（节流）
let scrollTimer: ReturnType<typeof setTimeout> | null = null
watch(
  () => {
    const m = chat.messages
    if (m.length === 0) return ''
    const last = m[m.length - 1]
    // 只追踪最后一条消息的 block 数量和渲染状态，极轻量
    return `${m.length}-${last.blocks.length}-${last.renderData?.renderedWordCount ?? 'done'}-${last.streaming}`
  },
  () => {
    if (scrollTimer) return
    scrollTimer = setTimeout(() => {
      scrollTimer = null
      nextTick(() => {
        if (chatContainer.value) {
          chatContainer.value.scrollTop = chatContainer.value.scrollHeight
        }
      })
    }, 120)
  }
)

onBeforeUnmount(() => {
  if (scrollTimer) clearTimeout(scrollTimer)
})
</script>

<template>
  <div class="bg-[#18181c] border-r border-[#2e2e32] flex flex-col h-full">
    <!-- Header -->
    <div class="h-9 px-3 border-b border-[#2e2e32] flex items-center justify-between shrink-0 bg-[#27272a]/30">
      <span class="font-semibold text-xs uppercase tracking-wider text-[#a1a1aa]">AI 助手</span>
      <div class="flex gap-2 text-xs">
        <div class="relative">
          <i class="fa-solid fa-clock-rotate-left text-[#a1a1aa] hover:text-white cursor-pointer" title="历史会话" @click="toggleHistory"></i>
          <div v-if="showHistory" class="absolute right-0 top-full mt-2 bg-[#27272a] border border-[#3e3e42] rounded-lg shadow-2xl py-1 w-[200px] z-50 max-h-[240px] overflow-y-auto">
            <div class="px-2 py-1.5 text-[9px] text-[#52525b] uppercase tracking-wider border-b border-[#2e2e32]">历史会话</div>
            <div v-if="historyList.length === 0" class="px-2 py-3 text-[10px] text-[#52525b] text-center">暂无历史会话</div>
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
              <i class="fa-solid fa-xmark text-[8px] text-[#52525b] hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity shrink-0" title="删除会话" @click="deleteSession($event, session.id)"></i>
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

      <template v-for="(msg, mi) in chat.messages" :key="msg.id">
        <!-- 历史消息用 v-memo 冻结：只有 streaming 状态或 renderData 变化时才重渲染 -->
        <div
          v-memo="[msg.id, msg.blocks.length, msg.streaming, msg.renderData?.renderedWordCount, msg.thinking?.length, msg.thinkingDone, msg.images?.length]"
          class="space-y-2"
        >
          <!-- User -->
          <div v-if="msg.role === 'user'" class="flex justify-end">
            <div class="bg-blue-600/20 border border-blue-500/30 text-white p-3 rounded-2xl rounded-tr-none text-sm max-w-[90%]">
              <!-- 用户附带的图片 -->
              <div v-if="msg.images && msg.images.length > 0" class="flex gap-2 mb-2 flex-wrap">
                <img v-for="(img, ii) in msg.images" :key="ii" :src="img" class="max-h-32 rounded border border-blue-500/20 object-contain cursor-zoom-in" alt="截图" @click="showImagePreview(img)" />
              </div>
              <div class="whitespace-pre-wrap">{{ msg.blocks[0]?.type === 'text' ? msg.blocks[0].text : '' }}</div>
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

              <!-- 按顺序渲染 blocks -->
              <template v-for="(block, bi) in msg.blocks" :key="bi">
                <!-- 文字块：流式阶段用纯文本，完成后用 markdown HTML -->
                <template v-if="block.type === 'text' && block.text">
                  <!-- 渐进式渲染中：纯文本显示，不调 marked -->
                  <div
                    v-if="chat.isProgressiveRendering(msg)"
                    class="chat-streaming-text bg-[#27272a] text-gray-300 p-3 rounded-2xl rounded-tl-none text-sm border border-[#2e2e32] whitespace-pre-wrap"
                  >{{ chat.getVisibleText(msg, bi) }}<span class="streaming-cursor"></span></div>
                  <!-- 完成后：markdown 渲染（带缓存） -->
                  <div
                    v-else
                    class="chat-markdown bg-[#27272a] text-gray-300 p-3 rounded-2xl rounded-tl-none text-sm border border-[#2e2e32]"
                    v-html="renderMarkdownCached(block.text)"
                  ></div>
                </template>

                <!-- 工具调用块 -->
                <div v-else-if="block.type === 'tool'" class="tool-call-block rounded-lg border text-[11px] overflow-hidden"
                  :class="block.tool.status === 'done' ? 'bg-[#27272a]/50 border-[#2e2e32]' : 'bg-yellow-500/5 border-yellow-500/20'"
                >
                  <div class="flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-[#ffffff06]"
                    @click="block.tool.output ? toggleToolOutput(`${msg.id}-${bi}`) : undefined"
                  >
                    <i :class="[toolIcon(block.tool.name), block.tool.status === 'done' ? 'text-green-400' : 'text-yellow-400']" class="text-[10px] shrink-0"></i>
                    <span class="text-[#a1a1aa] font-medium">{{ toolLabel(block.tool.name) }}</span>
                    <span class="text-[#52525b] code-font truncate min-w-0 flex-1">{{ block.tool.args }}</span>
                    <!-- 行数统计标签 -->
                    <template v-if="block.tool.status === 'done' && parseLineStats(block.tool.output)">
                      <span class="text-[10px] text-green-400 code-font shrink-0">+{{ parseLineStats(block.tool.output)!.added }}</span>
                      <span class="text-[10px] text-red-400 code-font shrink-0">-{{ parseLineStats(block.tool.output)!.removed }}</span>
                    </template>
                    <span class="ml-auto shrink-0 flex items-center gap-1"
                      :class="block.tool.status === 'done' ? 'text-green-400/70' : 'text-yellow-400/70'"
                    >
                      <i :class="block.tool.status === 'done' ? 'fa-solid fa-check' : 'fa-solid fa-spinner fa-spin'" class="text-[8px]"></i>
                      {{ block.tool.status === 'done' ? '完成' : '执行中' }}
                    </span>
                    <i v-if="block.tool.output" class="fa-solid fa-chevron-down text-[8px] text-[#52525b] transition-transform"
                      :class="{ 'rotate-180': expandedTools.has(`${msg.id}-${bi}`) }"
                    ></i>
                  </div>
                  <!-- 展开的工具输出 -->
                  <div v-if="block.tool.output && expandedTools.has(`${msg.id}-${bi}`)"
                    class="px-3 py-2 border-t border-[#2e2e32] bg-[#18181b]/80"
                  >
                    <pre class="text-[10px] text-[#a1a1aa] whitespace-pre-wrap break-all max-h-[300px] overflow-y-auto code-font">{{ block.tool.output }}</pre>
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
      </template>
    </div>

    <!-- Input -->
    <div class="p-4 border-t border-[#2e2e32] bg-[#18181c] shrink-0">
      <div class="relative bg-[#27272a] border border-[#2e2e32] rounded-xl focus-within:border-[#3b82f6]/50 focus-within:ring-1 focus-within:ring-[#3b82f6]/20 transition-all flex flex-col shadow-sm">
        
        <!-- 粘贴图片预览 -->
        <div v-if="pendingImages.length > 0" class="flex gap-2 px-3 pt-3 flex-wrap animate-in fade-in slide-in-from-bottom-2 duration-200">
          <div v-for="(img, idx) in pendingImages" :key="idx" class="relative group/img shrink-0">
            <div class="relative rounded-lg overflow-hidden border border-[#3f3f46] shadow-sm cursor-zoom-in" @click="showImagePreview(img)">
              <img :src="img" class="h-12 w-auto min-w-[3rem] object-cover opacity-90 group-hover/img:opacity-100 transition-opacity" alt="截图" />
            </div>
            <div 
              class="absolute -top-1.5 -right-1.5 w-4 h-4 bg-[#27272a] hover:bg-red-500 text-[#a1a1aa] hover:text-white rounded-full flex items-center justify-center cursor-pointer opacity-0 group-hover/img:opacity-100 transition-all shadow-sm border border-[#3f3f46] z-10 scale-90 hover:scale-100"
              @click.stop="removePendingImage(idx)"
            >
              <i class="fa-solid fa-xmark text-[9px]"></i>
            </div>
          </div>
        </div>
        
        <textarea
          v-model="inputText"
          class="w-full bg-transparent border-none text-sm text-white focus:outline-none focus:ring-0 resize-none h-24 placeholder-[#52525b] code-font p-3 leading-relaxed"
          placeholder="输入指令编辑代码、运行命令或解释... (Enter 发送)"
          @keydown="handleKeydown"
          @paste="handlePaste"
        ></textarea>
        
        <!-- 底部工具栏 -->
        <div class="flex justify-between items-center px-2 pb-2 mt-auto">
           <!-- 左侧状态 -->
           <div class="flex items-center gap-3 pl-1">
              <div class="text-[10px] text-[#52525b] flex items-center gap-1.5 select-none transition-colors hover:text-[#a1a1aa]" :title="`上下文容量: ${contextLabel()} tokens`">
                <i class="fa-solid fa-brain text-[9px]" :style="{ color: contextColor() }"></i>
                <span class="text-[9px] font-mono opacity-80" :style="{ color: contextColor() }">{{ contextLabel() }}</span>
              </div>
           </div>

           <!-- 右侧按钮 -->
           <div class="flex items-center gap-2">
              <!-- 模型选择 -->
              <div class="relative">
                <div
                  class="h-6 px-2 rounded-md hover:bg-[#3f3f46] flex items-center gap-1.5 text-[#a1a1aa] hover:text-white transition-all cursor-pointer select-none"
                  @click="showModelPicker = !showModelPicker"
                  title="选择模型"
                >
                  <span class="w-1.5 h-1.5 rounded-full" :class="chat.activeModelName === '未配置' ? 'bg-[#52525b]' : 'bg-green-500'"></span>
                  <span class="text-[10px] font-medium max-w-[80px] truncate">{{ chat.activeModelName }}</span>
                  <i class="fa-solid fa-chevron-down text-[8px] ml-0.5 opacity-50"></i>
                </div>
                
                <!-- Model Picker Dropdown -->
                <div v-if="showModelPicker" class="absolute bottom-full right-0 mb-2 bg-[#1f1f23] border border-[#2e2e32] rounded-lg shadow-xl py-1 min-w-[200px] z-50 overflow-hidden animate-in fade-in zoom-in-95 duration-100">
                  <div v-if="settings.models.filter(m => m.is_active).length === 0" class="px-3 py-3 text-[11px] text-[#52525b] text-center">
                    暂无激活模型，请在设置中配置
                  </div>
                  <div
                    v-for="model in settings.models.filter(m => m.is_active)" :key="model.id"
                    class="flex items-center gap-2 px-3 py-2 text-xs cursor-pointer transition-colors"
                    :class="model.id === chat.selectedModelId ? 'bg-[#3b82f6]/10 text-blue-400' : 'text-[#a1a1aa] hover:bg-[#27272a] hover:text-white'"
                    @click="selectModel(model.id!)"
                  >
                    <i :class="[modelIcon(model.type), modelColor(model.type)]" class="text-[12px] w-4 text-center shrink-0"></i>
                    <span class="truncate font-medium">{{ model.name }}</span>
                    <span class="text-[9px] text-[#52525b] ml-auto shrink-0 opacity-60">{{ model.model_name }}</span>
                  </div>
                  <div class="border-t border-[#2e2e32] mt-1 pt-1">
                    <div class="flex items-center gap-2 px-3 py-2 text-xs text-[#a1a1aa] hover:bg-[#27272a] hover:text-white cursor-pointer transition-colors"
                      @click="settings.showSettings = true; showModelPicker = false"
                    >
                      <i class="fa-solid fa-gear text-[10px] w-3 text-center"></i>
                      <span>模型设置...</span>
                    </div>
                  </div>
                </div>
                <div v-if="showModelPicker" class="fixed inset-0 z-40" @click="showModelPicker = false"></div>
              </div>

              <!-- 发送按钮 -->
              <button v-if="chat.isStreaming"
                class="w-7 h-7 rounded-md bg-[#27272a] border border-[#3f3f46] hover:bg-[#3f3f46] text-white flex items-center justify-center transition-all"
                title="停止生成" @click="chat.stopGeneration()"
              ><div class="w-2.5 h-2.5 bg-red-500 rounded-sm"></div></button>
              <button v-else
                class="w-7 h-7 rounded-md bg-blue-600 hover:bg-blue-500 text-white flex items-center justify-center transition-all shadow-sm shadow-blue-500/20 active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
                :disabled="!inputText.trim() && pendingImages.length === 0"
                title="发送消息 (Enter)" @click="send"
              ><i class="fa-solid fa-arrow-up text-xs"></i></button>
           </div>
        </div>
      </div>
      
      <!-- 底部提示 -->
      <div class="flex justify-center mt-2 opacity-40 hover:opacity-80 transition-opacity select-none">
        <span class="text-[9px] text-[#52525b] flex items-center gap-1"><i class="fa-brands fa-markdown"></i>AI 生成的代码可能不准确，请仔细核对</span>
      </div>
    </div>

    <!-- Image Preview Modal -->
    <div v-if="previewImage" class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm animate-in fade-in duration-200" @click="closeImagePreview">
      <div class="relative max-w-[90vw] max-h-[90vh] flex items-center justify-center p-4">
        <img :src="previewImage" class="max-w-full max-h-[85vh] rounded-lg shadow-2xl object-contain border border-[#3f3f46]" @click.stop />
        <button 
          class="absolute -top-10 right-0 w-8 h-8 rounded-full bg-[#27272a] hover:bg-[#3f3f46] text-white flex items-center justify-center transition-colors border border-[#3f3f46]"
          @click="closeImagePreview"
        >
          <i class="fa-solid fa-xmark"></i>
        </button>
      </div>
    </div>
  </div>
</template>

<style>
/* 流式输出光标动画 */
.streaming-cursor {
  display: inline-block;
  width: 2px;
  height: 1em;
  background: #60a5fa;
  margin-left: 1px;
  vertical-align: text-bottom;
  animation: blink 0.8s step-end infinite;
}
@keyframes blink { 50% { opacity: 0; } }

/* 流式纯文本样式 */
.chat-streaming-text {
  line-height: 1.6;
  word-wrap: break-word;
  overflow-wrap: break-word;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

/* Markdown 渲染样式 */
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
.code-block-pre { margin: 0; overflow-x: auto; }
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
