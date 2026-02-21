<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'

const props = defineProps<{ terminalVisible: boolean }>()
const emit = defineEmits<{ (e: 'update:terminalVisible', v: boolean): void }>()

const leftWidth = ref(320)
const rightWidth = ref(260)
const terminalHeight = ref(200)
const dragging = ref<'left' | 'right' | 'bottom' | null>(null)

function onMouseDown(target: 'left' | 'right' | 'bottom') {
  dragging.value = target
  document.body.style.cursor = target === 'bottom' ? 'row-resize' : 'col-resize'
  document.body.style.userSelect = 'none'
}

function onMouseMove(e: MouseEvent) {
  if (!dragging.value) return
  if (dragging.value === 'left') {
    leftWidth.value = Math.max(250, Math.min(500, e.clientX))
  } else if (dragging.value === 'right') {
    rightWidth.value = Math.max(200, Math.min(400, window.innerWidth - e.clientX))
  } else if (dragging.value === 'bottom') {
    const container = document.getElementById('center-col')
    if (container) {
      const rect = container.getBoundingClientRect()
      terminalHeight.value = Math.max(100, Math.min(rect.height * 0.8, rect.bottom - e.clientY))
    }
  }
}

function onMouseUp() {
  dragging.value = null
  document.body.style.cursor = ''
  document.body.style.userSelect = ''
}

onMounted(() => {
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
    <!-- 拖动时的透明遮罩，防止鼠标事件被子元素吞掉 -->
    <div
      v-if="dragging"
      class="fixed inset-0 z-50"
      :style="{ cursor: dragging === 'bottom' ? 'row-resize' : 'col-resize' }"
    />
    <!-- Left: Chat -->
    <div class="shrink-0 h-full" :style="{ width: leftWidth + 'px' }">
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
      <div class="absolute top-0 left-0 right-0 overflow-hidden"
           :style="{ bottom: props.terminalVisible ? (terminalHeight + 4) + 'px' : '0' }">
        <slot name="center-top" />
      </div>

      <!-- Resizer Bottom (only when terminal visible) -->
      <div
        v-if="props.terminalVisible"
        class="resizer-h absolute left-0 right-0"
        :class="{ active: dragging === 'bottom' }"
        :style="{ bottom: terminalHeight + 'px' }"
        @mousedown.prevent="onMouseDown('bottom')"
      />

      <!-- Terminal area (only when visible) -->
      <div v-if="props.terminalVisible" class="absolute left-0 right-0 bottom-0 overflow-hidden" :style="{ height: terminalHeight + 'px' }">
        <slot name="center-bottom" />
      </div>
    </div>

    <!-- Resizer Right -->
    <div
      class="resizer-v"
      :class="{ active: dragging === 'right' }"
      @mousedown.prevent="onMouseDown('right')"
    />

    <!-- Right: Explorer -->
    <div class="shrink-0 h-full" :style="{ width: rightWidth + 'px' }">
      <slot name="right" />
    </div>
  </div>
</template>
