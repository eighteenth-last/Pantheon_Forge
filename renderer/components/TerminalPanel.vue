<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, nextTick, reactive } from 'vue'
import { useProjectStore } from '../stores/project'
import { Terminal } from 'xterm'
import { FitAddon } from 'xterm-addon-fit'
import { WebLinksAddon } from 'xterm-addon-web-links'
import 'xterm/css/xterm.css'

const project = useProjectStore()
const emit = defineEmits<{ (e: 'close'): void }>()
const activeTab = ref<'terminal' | 'output' | 'problems'>('terminal')

interface TermInstance {
  id: number          // backend pty id
  label: string
  term: Terminal
  fitAddon: FitAddon
  el?: HTMLElement
}

const terminals = reactive<TermInstance[]>([])
const activeTermIdx = ref(0)
const termContainerEl = ref<HTMLElement>()

let unsubData: (() => void) | null = null
let unsubExit: (() => void) | null = null
let unsubServiceCreated: (() => void) | null = null
let resizeObserver: ResizeObserver | null = null
let termCounter = 0

// ---- xterm theme ----
const xtermTheme = {
  background: '#18181c', foreground: '#e4e4e7', cursor: '#3b82f6', cursorAccent: '#18181c',
  selectionBackground: '#3b82f644',
  black: '#18181c', red: '#ef4444', green: '#22c55e', yellow: '#eab308',
  blue: '#3b82f6', magenta: '#a855f7', cyan: '#06b6d4', white: '#e4e4e7',
  brightBlack: '#52525b', brightRed: '#f87171', brightGreen: '#4ade80',
  brightYellow: '#facc15', brightBlue: '#60a5fa', brightMagenta: '#c084fc',
  brightCyan: '#22d3ee', brightWhite: '#ffffff'
}

function createXterm(): { term: Terminal; fitAddon: FitAddon } {
  const term = new Terminal({
    theme: xtermTheme, fontFamily: "'JetBrains Mono', monospace",
    fontSize: 13, lineHeight: 1.4, cursorBlink: true, cursorStyle: 'bar',
    scrollback: 5000, allowProposedApi: true
  })
  const fitAddon = new FitAddon()
  term.loadAddon(fitAddon)
  term.loadAddon(new WebLinksAddon())
  return { term, fitAddon }
}

async function addTerminal() {
  if (!termContainerEl.value) return
  const cwd = project.projectPath || '.'
  const backendId = await window.api.terminal.create(cwd)
  const { term, fitAddon } = createXterm()
  termCounter++
  const inst: TermInstance = { id: backendId, label: `终端 ${termCounter}`, term, fitAddon }
  terminals.push(inst)
  activeTermIdx.value = terminals.length - 1

  await nextTick()
  mountTerminal(inst)
}

function mountTerminal(inst: TermInstance) {
  if (!termContainerEl.value) return
  // hide all other term elements
  for (const t of terminals) {
    if (t.el) t.el.style.display = 'none'
  }
  // create wrapper div
  const el = document.createElement('div')
  el.style.cssText = 'width:100%;height:100%;'
  termContainerEl.value.appendChild(el)
  inst.el = el
  inst.term.open(el)
  inst.fitAddon.fit()

  inst.term.onData((data) => {
    window.api.terminal.write(inst.id, data)
  })
}

function switchTerminal(idx: number) {
  activeTermIdx.value = idx
  for (let i = 0; i < terminals.length; i++) {
    if (terminals[i].el) terminals[i].el!.style.display = i === idx ? '' : 'none'
  }
  nextTick(() => {
    terminals[idx]?.fitAddon.fit()
    terminals[idx]?.term.focus()
  })
}

async function closeTerminal(idx: number) {
  const inst = terminals[idx]
  if (!inst) return
  await window.api.terminal.kill(inst.id)
  inst.term.dispose()
  inst.el?.remove()
  terminals.splice(idx, 1)
  if (terminals.length === 0) {
    activeTermIdx.value = 0
  } else {
    activeTermIdx.value = Math.min(idx, terminals.length - 1)
    switchTerminal(activeTermIdx.value)
  }
}

async function restartTerminal() {
  const inst = terminals[activeTermIdx.value]
  if (!inst) return
  await window.api.terminal.kill(inst.id)
  inst.term.clear()
  inst.term.writeln('\x1b[33m终端已重启\x1b[0m\r\n')
  const cwd = project.projectPath || '.'
  const newId = await window.api.terminal.create(cwd)
  inst.id = newId
  // re-wire input
  inst.term.onData((data) => {
    window.api.terminal.write(inst.id, data)
  })
}

function clearTerminal() {
  terminals[activeTermIdx.value]?.term.clear()
}

async function killAllTerminals() {
  await window.api.terminal.killAll()
  for (const t of terminals) { t.term.dispose(); t.el?.remove() }
  terminals.splice(0)
  activeTermIdx.value = 0
}

function closePanel() {
  emit('close')
}

// ---- Global listeners ----
function setupGlobalListeners() {
  unsubData = window.api.terminal.onData(({ id, data }) => {
    const inst = terminals.find(t => t.id === id)
    inst?.term.write(data)
  })
  unsubExit = window.api.terminal.onExit(({ id, exitCode }) => {
    const inst = terminals.find(t => t.id === id)
    if (inst) {
      inst.term.writeln(`\r\n\x1b[33m进程已退出 (code: ${exitCode})\x1b[0m`)
    }
  })
  // 监听 Agent 启动的服务终端
  unsubServiceCreated = window.api.service.onTerminalCreated(({ id, serviceId, command }) => {
    // 检查是否已存在该终端
    if (terminals.find(t => t.id === id)) return
    const { term, fitAddon } = createXterm()
    termCounter++
    const inst: TermInstance = { id, label: `🔧 ${serviceId}`, term, fitAddon }
    terminals.push(inst)
    activeTermIdx.value = terminals.length - 1
    nextTick(() => mountTerminal(inst))
  })
}

// ---- Resize observer ----
function setupResizeObserver() {
  if (!termContainerEl.value) return
  resizeObserver = new ResizeObserver(() => {
    const inst = terminals[activeTermIdx.value]
    if (!inst) return
    try {
      inst.fitAddon.fit()
      window.api.terminal.resize(inst.id, inst.term.cols, inst.term.rows)
    } catch {}
  })
  resizeObserver.observe(termContainerEl.value)
}

// ---- Lifecycle ----
watch(() => project.projectPath, async (path) => {
  if (path && terminals.length === 0) {
    await nextTick()
    await addTerminal()
  }
})

// expose for parent (TitleBar menu)
defineExpose({ addTerminal, killAllTerminals, clearTerminal, restartTerminal })

// Listen for run-command events from TitleBar
function onRunCommand(e: Event) {
  const cmd = (e as CustomEvent).detail
  if (!cmd) return
  const inst = terminals[activeTermIdx.value]
  if (inst) {
    window.api.terminal.write(inst.id, cmd + '\r')
  }
}

onMounted(async () => {
  setupGlobalListeners()
  window.addEventListener('terminal:run-command', onRunCommand)
  await nextTick()
  setupResizeObserver()
  if (project.projectPath && terminals.length === 0) {
    await addTerminal()
  }
})

onUnmounted(() => {
  unsubData?.()
  unsubExit?.()
  unsubServiceCreated?.()
  resizeObserver?.disconnect()
  window.removeEventListener('terminal:run-command', onRunCommand)
  for (const t of terminals) { t.term.dispose() }
  window.api.terminal.killAll()
})
</script>

<template>
  <div class="h-full border-t border-[#2e2e32] bg-[#18181c] flex flex-col">
    <!-- Header: tabs + actions -->
    <div class="flex items-center px-2 py-1 border-b border-[#2e2e32] shrink-0 bg-[#27272a]/30 gap-1">
      <!-- Panel tabs: 终端 / 输出 / 问题 -->
      <div class="flex gap-3 mr-3">
        <span
          v-for="tab in (['terminal', 'output', 'problems'] as const)" :key="tab"
          class="text-xs font-semibold pb-0.5 cursor-pointer transition-colors"
          :class="activeTab === tab ? 'text-white border-b-2 border-blue-500' : 'text-[#a1a1aa] hover:text-white'"
          @click="activeTab = tab"
        >{{ tab === 'terminal' ? '终端' : tab === 'output' ? '输出' : '问题' }}</span>
      </div>

      <!-- Terminal instance tabs (only when terminal tab active) -->
      <div v-if="activeTab === 'terminal'" class="flex gap-1 flex-1 min-w-0 overflow-x-auto items-center">
        <div
          v-for="(t, idx) in terminals" :key="t.id"
          class="flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] cursor-pointer whitespace-nowrap transition-colors"
          :class="idx === activeTermIdx ? 'bg-[#3b82f6]/20 text-white' : 'text-[#a1a1aa] hover:bg-[#27272a] hover:text-white'"
          @click="switchTerminal(idx)"
        >
          <i class="fa-solid fa-terminal text-[9px]"></i>
          <span>{{ t.label }}</span>
          <i class="fa-solid fa-xmark text-[9px] ml-1 hover:text-red-400 opacity-60 hover:opacity-100"
             @click.stop="closeTerminal(idx)"></i>
        </div>
      </div>
      <div v-else class="flex-1"></div>

      <!-- Action buttons -->
      <div class="flex gap-2 text-xs text-[#a1a1aa] items-center ml-2 shrink-0">
        <i class="fa-solid fa-plus hover:text-white cursor-pointer" title="新建终端" @click="addTerminal"></i>
        <i class="fa-solid fa-rotate-right hover:text-white cursor-pointer" title="重启终端" @click="restartTerminal"></i>
        <i class="fa-solid fa-trash hover:text-white cursor-pointer" title="清空" @click="clearTerminal"></i>
        <i class="fa-solid fa-xmark hover:text-white cursor-pointer" title="关闭面板" @click="closePanel"></i>
      </div>
    </div>

    <!-- Terminal container -->
    <div v-show="activeTab === 'terminal'" ref="termContainerEl" class="flex-1 min-h-0 px-1 py-1 relative"></div>

    <!-- Output placeholder -->
    <div v-show="activeTab === 'output'" class="flex-1 p-3 text-xs text-[#52525b] flex items-center justify-center">暂无输出</div>

    <!-- Problems placeholder -->
    <div v-show="activeTab === 'problems'" class="flex-1 p-3 text-xs text-[#52525b] flex items-center justify-center">暂无问题</div>
  </div>
</template>
