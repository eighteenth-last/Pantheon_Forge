<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'

const props = defineProps<{ terminalVisible: boolean; sidebarCollapsed: boolean }>()
const emit = defineEmits<{ (e: 'update:terminalVisible', v: boolean): void }>()

const leftWidth = ref(320)
const rightWidth = ref(260)
const terminalHeight = ref(200)
const dragging = ref<'left' | 'right' | 'bottom' | null>(null)

// DOM refs for direct style manipulation during drag
const leftEl = ref<HTMLElement>()
const rightEl = ref<HTMLElement>()
const editorArea = ref<HTMLElement>()
const resizerBottom = ref<HTMLElement>()
const terminalArea = ref<HTMLElement>()

let rafId = 0
// 拖拽中的临时值，不触发 Vue 响应式
let dragLeft = 0
let dragRight = 0
let dragTermH = 0

function onMouseDown(target: 'left' | 'right' | 'bottom') {
  dragging.value = target
  dragLeft = leftWidth.value
  dragRight = rightWidth.value
  dragTermH = terminalHeight.value
  document.body.style.cursor = target === 'bottom' ? 'row-resize' : 'col-resize'
  document.body.style.userSelect = 'none'
}

function onMouseMove(e: MouseEvent) {
  if (!dragging.value) return
  if (rafId) return
  const x = e.clientX
  const y = e.clientY
  rafId = requestAnimationFrame(() => {
    rafId = 0
    if (!dragging.value) return

    if (dragging.value === 'left') {
      dragLeft = Math.max(250, Math.min(500, x))
      if (leftEl.value) leftEl.value.style.width = dragLeft + 'px'
    } else if (dragging.value === 'right') {
      if (!props.sidebarCollapsed) {
        dragRight = Math.max(200, Math.min(400, window.innerWidth - x))
        if (rightEl.value) rightEl.value.style.width = dragRight + 'px'
      }
    } else if (dragging.value === 'bottom') {
      const container = document.getElementById('center-col')
      if (container) {
        const rect = container.getBoundingClientRect()
        dragTermH = Math.max(100, Math.min(rect.height * 0.8, rect.bottom - y))
        // 直接操作 DOM，不走 Vue
        if (editorArea.value) editorArea.value.style.bottom = (dragTermH + 4) + 'px'
        if (resizerBottom.value) resizerBottom.value.style.bottom = dragTermH + 'px'
        if (terminalArea.value) terminalArea.value.style.height = dragTermH + 'px'
      }
    }
  })
}

const LAYOUT_KEY = 'pantheon-layout'

function loadLayout() {
  try {
    const saved = localStorage.getItem(LAYOUT_KEY)
    if (saved) {
      const s = JSON.parse(saved)
      if (s.leftWidth) leftWidth.value = s.leftWidth
      if (s.rightWidth) rightWidth.value = s.rightWidth
      if (s.terminalHeight) terminalHeight.value = s.terminalHeight
    }
  } catch {}
}

function saveLayout() {
  localStorage.setItem(LAYOUT_KEY, JSON.stringify({
    leftWidth: leftWidth.value,
    rightWidth: rightWidth.value,
    terminalHeight: terminalHeight.value,
  }))
}

function onMouseUp() {
  if (dragging.value) {
    // 拖拽结束，把临时值同步回 Vue ref（只触发一次响应式更新）
    leftWidth.value = dragLeft
    rightWidth.value = dragRight
    terminalHeight.value = dragTermH
    saveLayout()
  }
  dragging.value = null
  document.body.style.cursor = ''
  document.body.style.userSelect = ''
}

onMounted(() => {
  loadLayout()
  document.addEventListener('mousemove', onMouseMove)
  document.addEventListener('mouseup', onMouseUp)
})
onUnmounted(() => {
  document.removeEventListener('mousemove', onMouseMove)
  document.removeEventListener('mouseup', onMouseUp)
})
</script>

<template>
  <div class="flex-1 flex overflow-hidden relative">
    <!-- 拖动时的透明遮罩 -->
    <div
      v-if="dragging"
      class="fixed inset-0 z-50"
      :style="{ cursor: dragging === 'bottom' ? 'row-resize' : 'col-resize' }"
    />
    <!-- Left: Chat -->
    <div ref="leftEl" class="shrink-0 h-full" :style="{ width: leftWidth + 'px' }">
      <slot name="left" />
    </div>

    <!-- Resizer Left -->
    <div
      class="resizer-v"
      :class="{ active: dragging === 'left' }"
      @mousedown.prevent="onMouseDown('left')"
    />

    <!-- Center: Editor + Terminal -->
    <div id="center-col" class="flex-1 min-w-0 h-full overflow-hidden relative">
      <!-- Editor area -->
      <div ref="editorArea" class="absolute top-0 left-0 right-0 overflow-hidden"
           :style="{ bottom: props.terminalVisible ? (terminalHeight + 4) + 'px' : '0' }">
        <slot name="center-top" />
      </div>

      <!-- Resizer Bottom -->
      <div
        v-if="props.terminalVisible"
        ref="resizerBottom"
        class="resizer-h absolute left-0 right-0"
        :class="{ active: dragging === 'bottom' }"
        :style="{ bottom: terminalHeight + 'px' }"
        @mousedown.prevent="onMouseDown('bottom')"
      />

      <!-- Terminal area -->
      <div v-if="props.terminalVisible" ref="terminalArea" class="absolute left-0 right-0 bottom-0 overflow-hidden" :style="{ height: terminalHeight + 'px' }">
        <slot name="center-bottom" />
      </div>
    </div>

    <!-- Resizer Right -->
    <div
      v-if="!props.sidebarCollapsed"
      class="resizer-v"
      :class="{ active: dragging === 'right' }"
      @mousedown.prevent="onMouseDown('right')"
    />

    <!-- Right: Explorer -->
    <div ref="rightEl" class="shrink-0 h-full" :style="{ width: props.sidebarCollapsed ? '42px' : rightWidth + 'px' }">
      <slot name="right" />
    </div>
  </div>
</template>

<style scoped>
.resizer-v {
  width: 4px;
  cursor: col-resize;
  background: transparent;
  transition: background 0.15s;
  flex-shrink: 0;
}
.resizer-v:hover,
.resizer-v.active {
  background: #3b82f6;
}
.resizer-h {
  height: 4px;
  cursor: row-resize;
  background: transparent;
  transition: background 0.15s;
  z-index: 10;
}
.resizer-h:hover,
.resizer-h.active {
  background: #3b82f6;
}
</style>
