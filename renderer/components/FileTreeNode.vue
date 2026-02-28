<script setup lang="ts">
import { type PropType } from 'vue'

export interface FileEntry {
  name: string
  path: string
  isDirectory: boolean
  children?: FileEntry[]
  expanded?: boolean
}

const props = defineProps({
  entry: { type: Object as PropType<FileEntry>, required: true },
  depth: { type: Number, default: 0 },
  selectedPath: { type: String, default: '' },
  newInput: { type: String as PropType<'file' | 'folder' | null>, default: null },
  newInputTarget: { type: String, default: '' },
  renamingPath: { type: String, default: '' },
  renameValue: { type: String, default: '' },
})

const emit = defineEmits<{
  (e: 'click', entry: FileEntry): void
  (e: 'dblclick', entry: FileEntry): void
  (e: 'contextmenu', entry: FileEntry, ev: MouseEvent): void
  (e: 'confirmNew', name: string): void
  (e: 'cancelNew'): void
  (e: 'confirmRename'): void
  (e: 'cancelRename'): void
  (e: 'update:renameValue', val: string): void
}>()

function onNewKeydown(ev: KeyboardEvent) {
  if (ev.key === 'Enter') {
    const val = (ev.target as HTMLInputElement).value.trim()
    if (val) emit('confirmNew', val)
  } else if (ev.key === 'Escape') {
    emit('cancelNew')
  }
}

function onRenameKeydown(ev: KeyboardEvent) {
  if (ev.key === 'Enter') emit('confirmRename')
  else if (ev.key === 'Escape') emit('cancelRename')
}

function onRightClick(ev: MouseEvent) {
  ev.preventDefault()
  ev.stopPropagation()
  emit('contextmenu', props.entry, ev)
}

function getIcon(entry: FileEntry): string {
  if (entry.isDirectory) return entry.expanded ? 'fa-solid fa-folder-open text-blue-500' : 'fa-solid fa-folder text-blue-400'
  const name = entry.name.toLowerCase()
  const ext = name.split('.').pop() || ''
  if (name === 'dockerfile' || name.startsWith('dockerfile.')) return 'fa-brands fa-docker text-blue-400'
  if (name === 'makefile' || name === 'cmakelists.txt') return 'fa-solid fa-gears text-orange-400'
  if (name === '.gitignore' || name === '.gitattributes') return 'fa-brands fa-git-alt text-orange-400'
  if (name === '.env' || name.startsWith('.env.')) return 'fa-solid fa-key text-yellow-500'
  if (name === 'license' || name.startsWith('license.')) return 'fa-solid fa-scale-balanced text-yellow-400'
  if (name.startsWith('readme')) return 'fa-solid fa-book text-blue-300'
  if (name === 'package.json') return 'fa-brands fa-npm text-red-500'
  if (name === 'tsconfig.json') return 'fa-solid fa-file-code text-blue-400'
  if (name.endsWith('.lock') || name === 'pnpm-lock.yaml') return 'fa-solid fa-lock text-gray-500'
  if (name.startsWith('docker-compose')) return 'fa-brands fa-docker text-blue-400'
  if (name.startsWith('.eslint')) return 'fa-solid fa-magnifying-glass text-purple-400'
  if (name.startsWith('.prettier')) return 'fa-solid fa-wand-magic-sparkles text-pink-400'
  if (name.startsWith('vite.config')) return 'fa-solid fa-bolt text-yellow-400'
  if (name.startsWith('webpack.config')) return 'fa-solid fa-cube text-blue-400'
  if (name === 'nginx.conf') return 'fa-solid fa-server text-green-500'
  const icons: Record<string, string> = {
    vue: 'fa-brands fa-vuejs text-green-500', ts: 'fa-solid fa-file-code text-blue-400',
    tsx: 'fa-brands fa-react text-blue-400', js: 'fa-brands fa-js text-yellow-400',
    jsx: 'fa-brands fa-react text-blue-400', mjs: 'fa-brands fa-js text-yellow-300',
    cjs: 'fa-brands fa-js text-yellow-300', css: 'fa-brands fa-css3-alt text-blue-400',
    scss: 'fa-brands fa-sass text-pink-400', sass: 'fa-brands fa-sass text-pink-400',
    less: 'fa-solid fa-paintbrush text-blue-300', styl: 'fa-solid fa-paintbrush text-green-400',
    html: 'fa-brands fa-html5 text-orange-500', htm: 'fa-brands fa-html5 text-orange-500',
    svelte: 'fa-solid fa-fire text-orange-500', astro: 'fa-solid fa-rocket text-orange-400',
    json: 'fa-solid fa-file-code text-yellow-500', jsonc: 'fa-solid fa-file-code text-yellow-500',
    yaml: 'fa-solid fa-file-code text-pink-400', yml: 'fa-solid fa-file-code text-pink-400',
    toml: 'fa-solid fa-file-code text-gray-400', ini: 'fa-solid fa-sliders text-gray-400',
    cfg: 'fa-solid fa-sliders text-gray-400', conf: 'fa-solid fa-sliders text-gray-400',
    properties: 'fa-solid fa-sliders text-gray-400', xml: 'fa-solid fa-code text-orange-300',
    csv: 'fa-solid fa-table text-green-400', tsv: 'fa-solid fa-table text-green-400',
    java: 'fa-brands fa-java text-red-400', kt: 'fa-solid fa-file-code text-purple-400',
    kts: 'fa-solid fa-file-code text-purple-400', scala: 'fa-solid fa-file-code text-red-500',
    groovy: 'fa-solid fa-file-code text-blue-300', gradle: 'fa-solid fa-file-code text-green-400',
    py: 'fa-brands fa-python text-yellow-500', pyw: 'fa-brands fa-python text-yellow-500',
    ipynb: 'fa-solid fa-book-open text-orange-400', rb: 'fa-solid fa-gem text-red-500',
    erb: 'fa-solid fa-gem text-red-400', php: 'fa-brands fa-php text-purple-400',
    go: 'fa-brands fa-golang text-blue-300', rs: 'fa-solid fa-gear text-orange-400',
    c: 'fa-solid fa-file-code text-blue-500', cpp: 'fa-solid fa-file-code text-blue-500',
    cc: 'fa-solid fa-file-code text-blue-500', h: 'fa-solid fa-file-code text-purple-300',
    hpp: 'fa-solid fa-file-code text-purple-300', cs: 'fa-solid fa-file-code text-green-400',
    fs: 'fa-solid fa-file-code text-blue-400', swift: 'fa-brands fa-swift text-orange-500',
    m: 'fa-solid fa-file-code text-blue-400', dart: 'fa-solid fa-file-code text-blue-300',
    lua: 'fa-solid fa-moon text-blue-400', r: 'fa-solid fa-chart-line text-blue-400',
    jl: 'fa-solid fa-circle-nodes text-purple-400', ex: 'fa-solid fa-droplet text-purple-500',
    exs: 'fa-solid fa-droplet text-purple-400', erl: 'fa-solid fa-file-code text-red-400',
    hs: 'fa-solid fa-file-code text-purple-400', clj: 'fa-solid fa-file-code text-green-400',
    pl: 'fa-solid fa-file-code text-blue-300', pm: 'fa-solid fa-file-code text-blue-300',
    sh: 'fa-solid fa-terminal text-green-400', bash: 'fa-solid fa-terminal text-green-400',
    zsh: 'fa-solid fa-terminal text-green-400', fish: 'fa-solid fa-terminal text-green-300',
    bat: 'fa-solid fa-terminal text-green-400', cmd: 'fa-solid fa-terminal text-green-400',
    ps1: 'fa-solid fa-terminal text-blue-400', psm1: 'fa-solid fa-terminal text-blue-400',
    sql: 'fa-solid fa-database text-blue-300', sqlite: 'fa-solid fa-database text-blue-300',
    db: 'fa-solid fa-database text-blue-300',
    md: 'fa-brands fa-markdown text-blue-300', mdx: 'fa-brands fa-markdown text-blue-300',
    txt: 'fa-solid fa-file-lines text-gray-400', rtf: 'fa-solid fa-file-lines text-gray-400',
    tex: 'fa-solid fa-file-lines text-green-400',
    doc: 'fa-solid fa-file-word text-blue-500', docx: 'fa-solid fa-file-word text-blue-500',
    xls: 'fa-solid fa-file-excel text-green-500', xlsx: 'fa-solid fa-file-excel text-green-500',
    ppt: 'fa-solid fa-file-powerpoint text-orange-500', pptx: 'fa-solid fa-file-powerpoint text-orange-500',
    pdf: 'fa-solid fa-file-pdf text-red-500',
    png: 'fa-solid fa-image text-green-400', jpg: 'fa-solid fa-image text-green-400',
    jpeg: 'fa-solid fa-image text-green-400', gif: 'fa-solid fa-image text-purple-400',
    bmp: 'fa-solid fa-image text-blue-300', webp: 'fa-solid fa-image text-blue-400',
    avif: 'fa-solid fa-image text-blue-400', svg: 'fa-solid fa-bezier-curve text-yellow-400',
    ico: 'fa-solid fa-image text-yellow-400', tiff: 'fa-solid fa-image text-gray-400',
    tif: 'fa-solid fa-image text-gray-400', psd: 'fa-solid fa-image text-blue-500',
    mp3: 'fa-solid fa-music text-pink-400', wav: 'fa-solid fa-music text-blue-300',
    ogg: 'fa-solid fa-music text-green-400', flac: 'fa-solid fa-music text-orange-400',
    aac: 'fa-solid fa-music text-purple-400', m4a: 'fa-solid fa-music text-pink-300',
    wma: 'fa-solid fa-music text-blue-300',
    mp4: 'fa-solid fa-film text-blue-400', avi: 'fa-solid fa-film text-blue-300',
    mkv: 'fa-solid fa-film text-green-400', mov: 'fa-solid fa-film text-gray-400',
    wmv: 'fa-solid fa-film text-blue-300', flv: 'fa-solid fa-film text-red-400',
    webm: 'fa-solid fa-film text-green-300', m4v: 'fa-solid fa-film text-blue-400',
    ttf: 'fa-solid fa-font text-gray-400', otf: 'fa-solid fa-font text-gray-400',
    woff: 'fa-solid fa-font text-gray-400', woff2: 'fa-solid fa-font text-gray-400',
    zip: 'fa-solid fa-file-zipper text-yellow-500', rar: 'fa-solid fa-file-zipper text-purple-400',
    '7z': 'fa-solid fa-file-zipper text-green-400', tar: 'fa-solid fa-file-zipper text-orange-400',
    gz: 'fa-solid fa-file-zipper text-orange-400', bz2: 'fa-solid fa-file-zipper text-orange-400',
    xz: 'fa-solid fa-file-zipper text-blue-400', tgz: 'fa-solid fa-file-zipper text-orange-400',
    exe: 'fa-solid fa-microchip text-gray-500', dll: 'fa-solid fa-microchip text-gray-500',
    so: 'fa-solid fa-microchip text-gray-500', bin: 'fa-solid fa-microchip text-gray-500',
    dmg: 'fa-solid fa-compact-disc text-gray-400', iso: 'fa-solid fa-compact-disc text-gray-400',
    msi: 'fa-solid fa-box text-blue-400', deb: 'fa-solid fa-box text-red-400',
    rpm: 'fa-solid fa-box text-orange-400', apk: 'fa-brands fa-android text-green-400',
    graphql: 'fa-solid fa-diagram-project text-pink-500', gql: 'fa-solid fa-diagram-project text-pink-500',
    proto: 'fa-solid fa-diagram-project text-blue-300', wasm: 'fa-solid fa-microchip text-purple-500',
    map: 'fa-solid fa-map text-gray-500', lock: 'fa-solid fa-lock text-gray-500',
    log: 'fa-solid fa-file-lines text-gray-500',
    pem: 'fa-solid fa-certificate text-green-400', crt: 'fa-solid fa-certificate text-green-400',
    cert: 'fa-solid fa-certificate text-green-400', key: 'fa-solid fa-key text-yellow-500',
    env: 'fa-solid fa-key text-yellow-500', gitignore: 'fa-brands fa-git-alt text-orange-400'
  }
  return icons[ext] || 'fa-solid fa-file text-gray-400'
}
</script>

<template>
  <div>
    <!-- 节点行 -->
    <div
      v-if="renamingPath !== entry.path"
      class="flex items-center gap-1 px-2 py-1 text-xs cursor-pointer transition-colors"
      :class="selectedPath === entry.path
        ? 'bg-[#094771] text-white'
        : 'text-[#a1a1aa] hover:bg-[#27272a] hover:text-white'"
      :style="{ paddingLeft: (depth * 12 + 8) + 'px' }"
      draggable="true"
      @dragstart.stop="(ev: DragEvent) => {
        if (!ev.dataTransfer) return
        ev.dataTransfer.effectAllowed = 'copy'
        ev.dataTransfer.setData('text/plain', entry.path)
        ev.dataTransfer.setData('application/pantheon-path', entry.path)
        ev.dataTransfer.setData('application/pantheon-type', entry.isDirectory ? 'directory' : 'file')
      }"
      @click.stop="emit('click', entry)"
      @dblclick.stop="emit('dblclick', entry)"
      @contextmenu="onRightClick"
    >
      <i v-if="entry.isDirectory"
        :class="`text-[10px] w-4 text-center ${entry.expanded ? 'fa-solid fa-chevron-down' : 'fa-solid fa-chevron-right'}`"
      ></i>
      <span v-else class="w-4"></span>
      <i :class="`${getIcon(entry)} w-4 text-center`"></i>
      <span class="truncate">{{ entry.name }}</span>
    </div>

    <!-- 重命名输入框 -->
    <div
      v-else
      class="flex items-center gap-1 px-2 py-1"
      :style="{ paddingLeft: (depth * 12 + 8) + 'px' }"
    >
      <i v-if="entry.isDirectory"
        :class="`text-[10px] w-4 text-center ${entry.expanded ? 'fa-solid fa-chevron-down' : 'fa-solid fa-chevron-right'}`"
      ></i>
      <span v-else class="w-4"></span>
      <i :class="`${getIcon(entry)} w-4 text-center`"></i>
      <input
        class="rename-input flex-1 bg-[#27272a] border border-blue-500/50 rounded px-2 py-0.5 text-xs text-white outline-none min-w-0"
        :value="renameValue"
        @input="emit('update:renameValue', ($event.target as HTMLInputElement).value)"
        @keydown="onRenameKeydown"
        @blur="emit('cancelRename')"
      />
    </div>

    <!-- 展开的目录内容 -->
    <template v-if="entry.isDirectory && entry.expanded && entry.children">
      <div v-if="newInput && newInputTarget === entry.path" class="flex items-center gap-1 px-2 py-1" :style="{ paddingLeft: ((depth + 1) * 12 + 8) + 'px' }">
        <span class="w-4"></span>
        <i :class="newInput === 'folder' ? 'fa-solid fa-folder text-blue-400' : 'fa-solid fa-file text-gray-400'" class="text-xs w-4 text-center"></i>
        <input
          class="flex-1 bg-[#27272a] border border-blue-500/50 rounded px-2 py-0.5 text-xs text-white outline-none placeholder-[#52525b] min-w-0"
          :placeholder="newInput === 'folder' ? '文件夹名称' : '文件名称'"
          autofocus
          @keydown="onNewKeydown"
          @blur="emit('cancelNew')"
        />
      </div>

      <FileTreeNode
        v-for="child in entry.children"
        :key="child.path"
        :entry="child"
        :depth="depth + 1"
        :selected-path="selectedPath"
        :new-input="newInput"
        :new-input-target="newInputTarget"
        :renaming-path="renamingPath"
        :rename-value="renameValue"
        @click="(e: FileEntry) => emit('click', e)"
        @dblclick="(e: FileEntry) => emit('dblclick', e)"
        @contextmenu="(e: FileEntry, ev: MouseEvent) => emit('contextmenu', e, ev)"
        @confirm-new="(name: string) => emit('confirmNew', name)"
        @cancel-new="emit('cancelNew')"
        @confirm-rename="emit('confirmRename')"
        @cancel-rename="emit('cancelRename')"
        @update:rename-value="(v: string) => emit('update:renameValue', v)"
      />
    </template>
  </div>
</template>
