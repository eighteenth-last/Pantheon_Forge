<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useSettingsStore, type ModelSetting, type SkillItem, type McpServerItem, BUILTIN_SKILLS, BUILTIN_MCP_SERVERS, BUILTIN_RULES } from '../stores/settings'
import { useChatStore } from '../stores/chat'

const settings = useSettingsStore()
const chat = useChatStore()
const s = computed(() => settings.app)

const activeSection = ref('general')

const sections = [
  { id: 'general', label: '通用', icon: 'fa-solid fa-gear' },
  { id: 'editor', label: '编辑器', icon: 'fa-solid fa-code' },
  { id: 'models', label: '模型', icon: 'fa-solid fa-brain' },
  { id: 'agent', label: 'Agent', icon: 'fa-solid fa-robot' },
  { id: 'terminal', label: '终端', icon: 'fa-solid fa-terminal' },
  { id: 'appearance', label: '外观', icon: 'fa-solid fa-palette' },
  { id: 'shortcuts', label: '快捷键', icon: 'fa-solid fa-keyboard' },
  { id: 'about', label: '关于', icon: 'fa-solid fa-circle-info' },
]

// ---- Model editing ----
const editingModel = ref<Partial<ModelSetting>>({})
const isEditing = ref(false)
const editingId = ref<number | null>(null)
const showApiKey = ref<Record<number, boolean>>({})
const toast = ref<{ msg: string; type: 'success' | 'error' } | null>(null)
let toastTimer: any = null

function showToast(msg: string, type: 'success' | 'error' = 'success') {
  toast.value = { msg, type }
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { toast.value = null }, 2500)
}

const presets = [
  { label: 'ChatGPT', type: 'openai-compatible' as const, url: 'https://api.openai.com', model: 'gpt-4o' },
  { label: '千问 (Qwen)', type: 'openai-compatible' as const, url: 'https://dashscope.aliyuncs.com/compatible-mode', model: 'qwen-plus' },
  { label: 'Kimi', type: 'openai-compatible' as const, url: 'https://api.moonshot.cn', model: 'moonshot-v1-8k' },
  { label: 'GLM', type: 'glm' as const, url: 'https://open.bigmodel.cn/api/paas', model: 'glm-4' },
  { label: 'Claude', type: 'claude' as const, url: 'https://api.anthropic.com', model: 'claude-sonnet-4-20250514' },
  { label: 'Gemini', type: 'gemini' as const, url: 'https://generativelanguage.googleapis.com', model: 'gemini-2.5-pro' },
  { label: 'DeepSeek', type: 'deepseek' as const, url: 'https://api.deepseek.com', model: 'deepseek-chat' },
  { label: 'MiniMax', type: 'minimax' as const, url: 'https://api.minimax.chat/v1', model: 'MiniMax-M1' },
  { label: '豆包 (Doubao)', type: 'openai-compatible' as const, url: 'https://ark.cn-beijing.volces.com/api/v3', model: 'doubao-pro-32k' },
]

function applyPreset(preset: typeof presets[0]) {
  editingModel.value = { name: preset.label, base_url: preset.url, model_name: preset.model, api_key: '', type: preset.type, is_active: 0 }
  isEditing.value = true
  editingId.value = null
}

function editModel(model: ModelSetting) {
  editingModel.value = { ...model }
  isEditing.value = true
  editingId.value = model.id!
}

async function saveModel() {
  if (!editingModel.value.name || !editingModel.value.base_url) {
    showToast('请填写名称和 Base URL', 'error')
    return
  }
  try {
    if (editingId.value) {
      await settings.updateModel(editingId.value, editingModel.value)
      showToast(`模型 "${editingModel.value.name}" 已更新`)
    } else {
      await settings.addModel(editingModel.value as Omit<ModelSetting, 'id'>)
      showToast(`模型 "${editingModel.value.name}" 已添加`)
    }
    isEditing.value = false
    editingId.value = null
    await chat.loadModels()
  } catch (e: any) {
    showToast('保存失败: ' + e.message, 'error')
  }
}

async function removeModel(id: number) {
  const model = settings.models.find(m => m.id === id)
  await settings.deleteModel(id)
  await chat.loadModels()
  showToast(`模型 "${model?.name}" 已删除`)
}

async function toggleModelActive(model: ModelSetting) {
  if (model.is_active) {
    await settings.deactivateModel(model.id!)
    showToast(`已停用 "${model.name}"`)
  } else {
    await settings.setActiveModel(model.id!)
    showToast(`已激活 "${model.name}"`)
  }
  await chat.loadModels()
}

function maskKey(key: string): string {
  if (!key || key.length < 8) return '••••••••'
  return key.slice(0, 4) + '••••' + key.slice(-4)
}

onMounted(() => settings.loadModels())

// ---- Agent settings ----
const newRule = ref('')
const newSkill = ref<Partial<SkillItem>>({ name: '', slug: '', enabled: true })
const newMcp = ref<Partial<McpServerItem>>({ name: '', command: '', args: [], enabled: true })
const newMcpArgs = ref('')
const showAddSkill = ref(false)
const showAddMcp = ref(false)

function addUserRule() {
  if (!newRule.value.trim()) return
  s.value.userRules.push(newRule.value.trim())
  newRule.value = ''
}
function removeUserRule(i: number) { s.value.userRules.splice(i, 1) }

function addUserSkill() {
  if (!newSkill.value.name || !newSkill.value.slug) { showToast('请填写完整', 'error'); return }
  s.value.userSkills.push({ ...newSkill.value, enabled: true } as SkillItem)
  newSkill.value = { name: '', slug: '', enabled: true }
  showAddSkill.value = false
}
function removeUserSkill(i: number) { s.value.userSkills.splice(i, 1) }

function addUserMcp() {
  if (!newMcp.value.name || !newMcp.value.command) { showToast('请填写名称和命令', 'error'); return }
  const args = newMcpArgs.value.split(/\s+/).filter(Boolean)
  s.value.userMcpServers.push({ ...newMcp.value, args, enabled: true } as McpServerItem)
  newMcp.value = { name: '', command: '', args: [], enabled: true }
  newMcpArgs.value = ''
  showAddMcp.value = false
}
function removeUserMcp(i: number) { s.value.userMcpServers.splice(i, 1) }

// Shortcuts data
const shortcuts = [
  { keys: 'Ctrl+S', desc: '保存文件' },
  { keys: 'Ctrl+Shift+`', desc: '新建终端' },
  { keys: 'Ctrl+`', desc: '显示/隐藏终端' },
  { keys: 'Ctrl+K Ctrl+O', desc: '打开文件夹' },
  { keys: 'Ctrl+,', desc: '打开设置' },
  { keys: 'Ctrl+W', desc: '关闭当前标签' },
  { keys: 'Ctrl+Tab', desc: '切换标签' },
  { keys: 'Ctrl+F', desc: '搜索' },
  { keys: 'Ctrl+H', desc: '替换' },
  { keys: 'Ctrl+Z', desc: '撤销' },
  { keys: 'Ctrl+Shift+Z', desc: '重做' },
  { keys: 'Ctrl+//', desc: '切换注释' },
]
</script>

<template>
  <div class="flex-1 flex flex-col overflow-hidden bg-[#101014]">
    <!-- Toast notification -->
    <Transition name="toast">
      <div v-if="toast" class="fixed top-12 left-1/2 -translate-x-1/2 z-[100] px-4 py-2.5 rounded-lg shadow-xl text-xs font-medium flex items-center gap-2"
           :class="toast.type === 'success' ? 'bg-[#22c55e]/15 border border-[#22c55e]/30 text-[#4ade80]' : 'bg-[#ef4444]/15 border border-[#ef4444]/30 text-[#f87171]'">
        <i :class="toast.type === 'success' ? 'fa-solid fa-circle-check' : 'fa-solid fa-circle-xmark'"></i>
        {{ toast.msg }}
      </div>
    </Transition>
    <!-- Settings tab bar -->
    <div class="h-8 flex bg-[#101014] border-b border-[#2e2e32] shrink-0 items-center px-1">
      <div class="flex items-center gap-2 px-3 py-1.5 text-xs text-white bg-[#18181c] border-r border-[#2e2e32] border-t-2 border-t-[#3b82f6] min-w-fit">
        <i class="fa-solid fa-gear text-[10px]"></i>
        <span>设置</span>
        <i class="fa-solid fa-xmark ml-2 text-[10px] text-[#71717a] hover:text-white cursor-pointer"
           @click="settings.showSettings = false"></i>
      </div>
    </div>

    <div class="flex-1 flex overflow-hidden">
    <!-- Left sidebar -->
    <div class="w-[220px] shrink-0 border-r border-[#2e2e32] bg-[#18181c] flex flex-col py-3 overflow-y-auto">
      <div class="px-4 mb-4">
        <div class="relative">
          <i class="fa-solid fa-magnifying-glass absolute left-3 top-1/2 -translate-y-1/2 text-[#52525b] text-[10px]"></i>
          <input
            type="text" placeholder="搜索设置 Ctrl+F"
            class="w-full bg-[#27272a] border border-[#2e2e32] rounded-md pl-8 pr-3 py-1.5 text-xs text-[#a1a1aa] placeholder-[#52525b] focus:outline-none focus:border-[#3b82f6]"
          />
        </div>
      </div>
      <div
        v-for="sec in sections" :key="sec.id"
        class="flex items-center gap-3 px-4 py-2 mx-2 rounded-md cursor-pointer text-[13px] transition-colors"
        :class="activeSection === sec.id ? 'bg-[#3b82f6]/15 text-white' : 'text-[#a1a1aa] hover:bg-[#27272a] hover:text-white'"
        @click="activeSection = sec.id"
      >
        <i :class="sec.icon" class="w-4 text-center text-xs"></i>
        <span>{{ sec.label }}</span>
      </div>
    </div>

    <!-- Right content -->
    <div class="flex-1 overflow-y-auto px-10 py-6">
      <div class="max-w-[680px]">

        <!-- ========== 通用 ========== -->
        <div v-if="activeSection === 'general'">
          <h1 class="text-xl font-semibold text-white mb-6">通用</h1>

          <div class="settings-group">
            <h3 class="settings-group-title">偏好设置</h3>

            <div class="setting-row">
              <div><div class="setting-label">界面语言</div><div class="setting-desc">设置界面显示语言</div></div>
              <select v-model="s.language" class="setting-select">
                <option value="zh-CN">简体中文</option>
                <option value="en-US">English</option>
              </select>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">自动保存</div><div class="setting-desc">文件修改后自动保存</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.autoSave" /><span class="toggle-slider"></span></label>
            </div>

            <div class="setting-row" v-if="s.autoSave">
              <div><div class="setting-label">自动保存延迟</div><div class="setting-desc">修改后等待多久自动保存 (毫秒)</div></div>
              <input type="number" v-model.number="s.autoSaveDelay" min="200" max="10000" step="100" class="setting-input w-24" />
            </div>
          </div>

          <div class="settings-group">
            <h3 class="settings-group-title">通知</h3>

            <div class="setting-row">
              <div><div class="setting-label">系统通知</div><div class="setting-desc">Agent 完成或需要注意时显示系统通知</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.systemNotifications" /><span class="toggle-slider"></span></label>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">完成提示音</div><div class="setting-desc">Agent 完成回复时播放提示音</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.completionSound" /><span class="toggle-slider"></span></label>
            </div>
          </div>

          <div class="settings-group">
            <h3 class="settings-group-title">数据</h3>
            <div class="setting-row">
              <div><div class="setting-label">重置所有设置</div><div class="setting-desc">恢复所有设置为默认值</div></div>
              <button class="setting-btn-danger" @click="settings.resetSettings()">重置</button>
            </div>
          </div>
        </div>

        <!-- ========== 编辑器 ========== -->
        <div v-if="activeSection === 'editor'">
          <h1 class="text-xl font-semibold text-white mb-6">编辑器</h1>

          <div class="settings-group">
            <h3 class="settings-group-title">字体</h3>

            <div class="setting-row">
              <div><div class="setting-label">字体大小</div><div class="setting-desc">编辑器字体大小 (px)</div></div>
              <input type="number" v-model.number="s.fontSize" min="10" max="30" class="setting-input w-20" />
            </div>

            <div class="setting-row">
              <div><div class="setting-label">字体</div><div class="setting-desc">编辑器字体族</div></div>
              <input type="text" v-model="s.fontFamily" class="setting-input w-56" />
            </div>
          </div>

          <div class="settings-group">
            <h3 class="settings-group-title">格式</h3>

            <div class="setting-row">
              <div><div class="setting-label">Tab 大小</div><div class="setting-desc">一个 Tab 等于多少空格</div></div>
              <select v-model.number="s.tabSize" class="setting-select">
                <option :value="2">2</option>
                <option :value="4">4</option>
                <option :value="8">8</option>
              </select>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">自动换行</div><div class="setting-desc">超出编辑器宽度时自动换行</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.wordWrap" /><span class="toggle-slider"></span></label>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">渲染空白字符</div><div class="setting-desc">何时显示空白字符</div></div>
              <select v-model="s.renderWhitespace" class="setting-select">
                <option value="none">不显示</option>
                <option value="selection">选中时</option>
                <option value="all">始终</option>
              </select>
            </div>
          </div>

          <div class="settings-group">
            <h3 class="settings-group-title">显示</h3>

            <div class="setting-row">
              <div><div class="setting-label">小地图</div><div class="setting-desc">在编辑器右侧显示代码缩略图</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.minimap" /><span class="toggle-slider"></span></label>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">行号</div><div class="setting-desc">显示行号</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.lineNumbers" /><span class="toggle-slider"></span></label>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">括号配对着色</div><div class="setting-desc">用不同颜色区分嵌套括号</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.bracketPairColorization" /><span class="toggle-slider"></span></label>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">光标样式</div><div class="setting-desc">编辑器光标的显示样式</div></div>
              <select v-model="s.cursorStyle" class="setting-select">
                <option value="line">竖线</option>
                <option value="block">方块</option>
                <option value="underline">下划线</option>
              </select>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">平滑滚动</div><div class="setting-desc">启用平滑滚动动画</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.smoothScrolling" /><span class="toggle-slider"></span></label>
            </div>
          </div>
        </div>

        <!-- ========== 模型 ========== -->
        <div v-if="activeSection === 'models'">
          <h1 class="text-xl font-semibold text-white mb-6">模型</h1>

          <!-- Quick add presets -->
          <div class="settings-group">
            <h3 class="settings-group-title">快速添加</h3>
            <div class="grid grid-cols-4 gap-2 mt-2">
              <button
                v-for="preset in presets" :key="preset.label"
                class="px-3 py-2.5 bg-[#27272a] border border-[#2e2e32] rounded-lg text-xs text-[#e4e4e7] hover:border-[#3b82f6] hover:bg-[#3b82f6]/10 transition-all"
                @click="applyPreset(preset)"
              >{{ preset.label }}</button>
            </div>
          </div>

          <!-- 新增模型表单（非编辑已有模型时） -->
          <div v-if="isEditing && !editingId" class="settings-group">
            <h3 class="settings-group-title">添加模型</h3>
            <div class="bg-[#1a1a1e] rounded-lg p-4 border border-[#3b82f6]/30 space-y-3 mt-2">
              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="text-[11px] text-[#71717a] block mb-1">名称</label>
                  <input v-model="editingModel.name" class="setting-input w-full" placeholder="例如: GPT-4o" />
                </div>
                <div>
                  <label class="text-[11px] text-[#71717a] block mb-1">类型</label>
                  <select v-model="editingModel.type" class="setting-select w-full">
                    <option value="openai-compatible">OpenAI 兼容</option>
                    <option value="claude">Claude</option>
                    <option value="gemini">Gemini</option>
                    <option value="glm">GLM (智谱)</option>
                    <option value="deepseek">DeepSeek</option>
                    <option value="minimax">MiniMax</option>
                  </select>
                </div>
                <div class="col-span-2">
                  <label class="text-[11px] text-[#71717a] block mb-1">Base URL</label>
                  <input v-model="editingModel.base_url" class="setting-input w-full" placeholder="https://api.openai.com" />
                </div>
                <div>
                  <label class="text-[11px] text-[#71717a] block mb-1">模型名称</label>
                  <input v-model="editingModel.model_name" class="setting-input w-full" placeholder="gpt-4o" />
                </div>
                <div>
                  <label class="text-[11px] text-[#71717a] block mb-1">API Key</label>
                  <input v-model="editingModel.api_key" type="password" class="setting-input w-full" placeholder="sk-..." />
                </div>
              </div>
              <div class="flex gap-2 pt-1">
                <button class="px-4 py-1.5 bg-[#3b82f6] hover:bg-[#2563eb] text-white text-xs rounded-md transition-colors" @click="saveModel">保存</button>
                <button class="px-4 py-1.5 bg-[#27272a] hover:bg-[#3f3f46] text-[#a1a1aa] text-xs rounded-md transition-colors" @click="isEditing = false">取消</button>
              </div>
            </div>
          </div>

          <!-- Model list -->
          <div class="settings-group">
            <h3 class="settings-group-title">已配置模型</h3>
            <div v-if="settings.models.length === 0" class="text-center text-[#52525b] text-xs py-8">
              暂无模型配置，请使用上方快速添加
            </div>
            <div v-else class="space-y-1 mt-2">
              <template v-for="model in settings.models" :key="model.id">
                <div
                  class="flex items-center justify-between px-4 py-3 rounded-lg border transition-colors group"
                  :class="model.is_active ? 'border-[#3b82f6]/30 bg-[#3b82f6]/5' : 'border-[#2e2e32] hover:border-[#3e3e42]'"
                >
                  <div class="flex items-center gap-3 flex-1 min-w-0">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2">
                        <span class="text-[13px] text-white">{{ model.name }}</span>
                        <span class="text-[10px] text-[#52525b] bg-[#27272a] px-1.5 py-0.5 rounded">{{ model.type }}</span>
                      </div>
                      <div class="text-[11px] text-[#52525b] mt-0.5 truncate">
                        {{ model.model_name }} · {{ model.base_url }}
                      </div>
                      <div class="text-[11px] text-[#52525b] mt-0.5 flex items-center gap-1">
                        <span>Key: {{ showApiKey[model.id!] ? model.api_key : maskKey(model.api_key) }}</span>
                        <i
                          :class="showApiKey[model.id!] ? 'fa-solid fa-eye-slash' : 'fa-solid fa-eye'"
                          class="cursor-pointer text-[10px] hover:text-[#a1a1aa]"
                          @click="showApiKey[model.id!] = !showApiKey[model.id!]"
                        ></i>
                      </div>
                    </div>
                  </div>
                  <div class="flex items-center gap-3 shrink-0 ml-4">
                    <i class="fa-solid fa-pen text-[11px] text-[#52525b] hover:text-white cursor-pointer" @click="editModel(model)"></i>
                    <i class="fa-solid fa-trash text-[11px] text-[#52525b] hover:text-red-400 cursor-pointer" @click="removeModel(model.id!)"></i>
                    <label class="toggle"><input type="checkbox" :checked="!!model.is_active" @change="toggleModelActive(model)" /><span class="toggle-slider"></span></label>
                  </div>
                </div>

                <!-- 内联编辑表单：在当前模型卡片下方展开 -->
                <div v-if="isEditing && editingId === model.id" class="bg-[#1a1a1e] rounded-lg p-4 border border-[#3b82f6]/30 space-y-3 ml-2 mr-2 -mt-0.5">
                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <label class="text-[11px] text-[#71717a] block mb-1">名称</label>
                      <input v-model="editingModel.name" class="setting-input w-full" placeholder="例如: GPT-4o" />
                    </div>
                    <div>
                      <label class="text-[11px] text-[#71717a] block mb-1">类型</label>
                      <select v-model="editingModel.type" class="setting-select w-full">
                        <option value="openai-compatible">OpenAI 兼容</option>
                        <option value="claude">Claude</option>
                        <option value="gemini">Gemini</option>
                        <option value="glm">GLM (智谱)</option>
                        <option value="deepseek">DeepSeek</option>
                        <option value="minimax">MiniMax</option>
                      </select>
                    </div>
                    <div class="col-span-2">
                      <label class="text-[11px] text-[#71717a] block mb-1">Base URL</label>
                      <input v-model="editingModel.base_url" class="setting-input w-full" placeholder="https://api.openai.com" />
                    </div>
                    <div>
                      <label class="text-[11px] text-[#71717a] block mb-1">模型名称</label>
                      <input v-model="editingModel.model_name" class="setting-input w-full" placeholder="gpt-4o" />
                    </div>
                    <div>
                      <label class="text-[11px] text-[#71717a] block mb-1">API Key</label>
                      <input v-model="editingModel.api_key" type="password" class="setting-input w-full" placeholder="sk-..." />
                    </div>
                  </div>
                  <div class="flex gap-2 pt-1">
                    <button class="px-4 py-1.5 bg-[#3b82f6] hover:bg-[#2563eb] text-white text-xs rounded-md transition-colors" @click="saveModel">保存</button>
                    <button class="px-4 py-1.5 bg-[#27272a] hover:bg-[#3f3f46] text-[#a1a1aa] text-xs rounded-md transition-colors" @click="isEditing = false; editingId = null">取消</button>
                  </div>
                </div>
              </template>
            </div>
          </div>
        </div>

        <!-- ========== Agent ========== -->
        <div v-if="activeSection === 'agent'">
          <h1 class="text-xl font-semibold text-white mb-6">Agent 配置</h1>

          <!-- Rules -->
          <div class="settings-group">
            <h3 class="settings-group-title">规则 (Rules)</h3>
            <p class="text-[11px] text-[#52525b] mb-3">Agent 在编写代码时必须遵守的规则</p>
            <!-- 内置规则 -->
            <div v-for="(rule, i) in BUILTIN_RULES" :key="'br-'+i" class="flex items-center gap-2 px-3 py-2 border-b border-[#1e1e22]">
              <span class="text-[10px] text-[#3b82f6] bg-[#3b82f6]/10 px-1.5 py-0.5 rounded shrink-0">内置</span>
              <span class="text-[13px] text-[#a1a1aa] flex-1">{{ rule }}</span>
            </div>
            <!-- 用户规则 -->
            <div v-for="(rule, i) in s.userRules" :key="'ur-'+i" class="flex items-center gap-2 px-3 py-2 border-b border-[#1e1e22]">
              <span class="text-[10px] text-[#22c55e] bg-[#22c55e]/10 px-1.5 py-0.5 rounded shrink-0">自定义</span>
              <span class="text-[13px] text-[#e4e4e7] flex-1">{{ rule }}</span>
              <i class="fa-solid fa-trash text-[10px] text-[#52525b] hover:text-red-400 cursor-pointer" @click="removeUserRule(i)"></i>
            </div>
            <!-- 添加规则 -->
            <div class="flex gap-2 mt-3">
              <input v-model="newRule" class="setting-input flex-1" placeholder="输入新规则..." @keydown.enter="addUserRule()" />
              <button class="px-4 py-1.5 bg-[#3b82f6] hover:bg-[#2563eb] text-white text-xs rounded-md" @click="addUserRule()">添加</button>
            </div>
          </div>

          <!-- Skills -->
          <div class="settings-group">
            <h3 class="settings-group-title">Skills</h3>
            <p class="text-[11px] text-[#52525b] mb-3">为 Agent 加载的编程技能包</p>
            <!-- 内置 Skills -->
            <div v-for="skill in BUILTIN_SKILLS" :key="'bs-'+skill.slug" class="flex items-center gap-2 px-3 py-2 border-b border-[#1e1e22]">
              <span class="text-[10px] text-[#3b82f6] bg-[#3b82f6]/10 px-1.5 py-0.5 rounded shrink-0">内置</span>
              <div class="flex-1 min-w-0">
                <div class="text-[13px] text-[#a1a1aa]">{{ skill.name }}</div>
                <div class="text-[10px] text-[#52525b] truncate">{{ skill.slug }}</div>
              </div>
            </div>
            <!-- 用户 Skills -->
            <div v-for="(skill, i) in s.userSkills" :key="'us-'+i" class="flex items-center gap-2 px-3 py-2 border-b border-[#1e1e22]">
              <span class="text-[10px] text-[#22c55e] bg-[#22c55e]/10 px-1.5 py-0.5 rounded shrink-0">自定义</span>
              <div class="flex-1 min-w-0">
                <div class="text-[13px] text-[#e4e4e7]">{{ skill.name }}</div>
                <div class="text-[10px] text-[#52525b] truncate">{{ skill.slug }}</div>
              </div>
              <label class="toggle"><input type="checkbox" v-model="skill.enabled" /><span class="toggle-slider"></span></label>
              <i class="fa-solid fa-trash text-[10px] text-[#52525b] hover:text-red-400 cursor-pointer" @click="removeUserSkill(i)"></i>
            </div>
            <!-- 添加 Skill -->
            <div v-if="!showAddSkill" class="mt-3">
              <button class="px-4 py-1.5 bg-[#27272a] hover:bg-[#3f3f46] text-[#a1a1aa] text-xs rounded-md border border-[#2e2e32]" @click="showAddSkill = true">+ 添加 Skill</button>
            </div>
            <div v-else class="bg-[#1a1a1e] rounded-lg p-4 border border-[#3b82f6]/30 space-y-3 mt-3">
              <div class="grid grid-cols-2 gap-3">
                <div><label class="text-[11px] text-[#71717a] block mb-1">名称</label><input v-model="newSkill.name" class="setting-input w-full" placeholder="My Skill" /></div>
                <div><label class="text-[11px] text-[#71717a] block mb-1">Slug 路径</label><input v-model="newSkill.slug" class="setting-input w-full" placeholder="community/my-skill" /></div>
              </div>
              <div class="flex gap-2">
                <button class="px-4 py-1.5 bg-[#3b82f6] hover:bg-[#2563eb] text-white text-xs rounded-md" @click="addUserSkill()">保存</button>
                <button class="px-4 py-1.5 bg-[#27272a] hover:bg-[#3f3f46] text-[#a1a1aa] text-xs rounded-md" @click="showAddSkill = false">取消</button>
              </div>
            </div>
          </div>

          <!-- MCP Servers -->
          <div class="settings-group">
            <h3 class="settings-group-title">MCP 服务器</h3>
            <p class="text-[11px] text-[#52525b] mb-3">Model Context Protocol 服务器配置</p>
            <!-- 内置 MCP -->
            <div v-for="mcp in BUILTIN_MCP_SERVERS" :key="'bm-'+mcp.name" class="flex items-center gap-2 px-3 py-2 border-b border-[#1e1e22]">
              <span class="text-[10px] text-[#3b82f6] bg-[#3b82f6]/10 px-1.5 py-0.5 rounded shrink-0">内置</span>
              <div class="flex-1 min-w-0">
                <div class="text-[13px] text-[#a1a1aa]">{{ mcp.name }}</div>
                <div class="text-[10px] text-[#52525b] truncate">{{ mcp.command }} {{ mcp.args.join(' ') }}</div>
              </div>
            </div>
            <!-- 用户 MCP -->
            <div v-for="(mcp, i) in s.userMcpServers" :key="'um-'+i" class="flex items-center gap-2 px-3 py-2 border-b border-[#1e1e22]">
              <span class="text-[10px] text-[#22c55e] bg-[#22c55e]/10 px-1.5 py-0.5 rounded shrink-0">自定义</span>
              <div class="flex-1 min-w-0">
                <div class="text-[13px] text-[#e4e4e7]">{{ mcp.name }}</div>
                <div class="text-[10px] text-[#52525b] truncate">{{ mcp.command }} {{ mcp.args.join(' ') }}</div>
              </div>
              <label class="toggle"><input type="checkbox" v-model="mcp.enabled" /><span class="toggle-slider"></span></label>
              <i class="fa-solid fa-trash text-[10px] text-[#52525b] hover:text-red-400 cursor-pointer" @click="removeUserMcp(i)"></i>
            </div>
            <!-- 添加 MCP -->
            <div v-if="!showAddMcp" class="mt-3">
              <button class="px-4 py-1.5 bg-[#27272a] hover:bg-[#3f3f46] text-[#a1a1aa] text-xs rounded-md border border-[#2e2e32]" @click="showAddMcp = true">+ 添加 MCP 服务器</button>
            </div>
            <div v-else class="bg-[#1a1a1e] rounded-lg p-4 border border-[#3b82f6]/30 space-y-3 mt-3">
              <div class="grid grid-cols-3 gap-3">
                <div><label class="text-[11px] text-[#71717a] block mb-1">名称</label><input v-model="newMcp.name" class="setting-input w-full" placeholder="My Server" /></div>
                <div><label class="text-[11px] text-[#71717a] block mb-1">命令</label><input v-model="newMcp.command" class="setting-input w-full" placeholder="npx" /></div>
                <div><label class="text-[11px] text-[#71717a] block mb-1">参数 (空格分隔)</label><input v-model="newMcpArgs" class="setting-input w-full" placeholder="-y package@latest" /></div>
              </div>
              <div class="flex gap-2">
                <button class="px-4 py-1.5 bg-[#3b82f6] hover:bg-[#2563eb] text-white text-xs rounded-md" @click="addUserMcp()">保存</button>
                <button class="px-4 py-1.5 bg-[#27272a] hover:bg-[#3f3f46] text-[#a1a1aa] text-xs rounded-md" @click="showAddMcp = false">取消</button>
              </div>
            </div>
          </div>
        </div>

        <!-- ========== 终端 ========== -->
        <div v-if="activeSection === 'terminal'">
          <h1 class="text-xl font-semibold text-white mb-6">终端</h1>

          <div class="settings-group">
            <h3 class="settings-group-title">字体</h3>

            <div class="setting-row">
              <div><div class="setting-label">字体大小</div><div class="setting-desc">终端字体大小 (px)</div></div>
              <input type="number" v-model.number="s.terminalFontSize" min="10" max="24" class="setting-input w-20" />
            </div>

            <div class="setting-row">
              <div><div class="setting-label">字体</div><div class="setting-desc">终端字体族</div></div>
              <input type="text" v-model="s.terminalFontFamily" class="setting-input w-56" />
            </div>
          </div>

          <div class="settings-group">
            <h3 class="settings-group-title">行为</h3>

            <div class="setting-row">
              <div><div class="setting-label">光标闪烁</div><div class="setting-desc">终端光标是否闪烁</div></div>
              <label class="toggle"><input type="checkbox" v-model="s.terminalCursorBlink" /><span class="toggle-slider"></span></label>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">回滚行数</div><div class="setting-desc">终端保留的最大历史行数</div></div>
              <input type="number" v-model.number="s.terminalScrollback" min="500" max="50000" step="500" class="setting-input w-24" />
            </div>

            <div class="setting-row">
              <div><div class="setting-label">默认 Shell</div><div class="setting-desc">新建终端时使用的 Shell 程序</div></div>
              <select v-model="s.defaultShell" class="setting-select">
                <option value="powershell.exe">PowerShell</option>
                <option value="cmd.exe">CMD</option>
                <option value="bash">Bash (WSL)</option>
              </select>
            </div>
          </div>
        </div>

        <!-- ========== 外观 ========== -->
        <div v-if="activeSection === 'appearance'">
          <h1 class="text-xl font-semibold text-white mb-6">外观</h1>

          <div class="settings-group">
            <h3 class="settings-group-title">主题</h3>

            <div class="setting-row">
              <div><div class="setting-label">颜色主题</div><div class="setting-desc">应用的整体颜色方案</div></div>
              <select v-model="s.theme" class="setting-select">
                <option value="dark">深色</option>
                <option value="light">浅色 (即将推出)</option>
              </select>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">强调色</div><div class="setting-desc">按钮、链接等的主色调</div></div>
              <div class="flex items-center gap-2">
                <input type="color" v-model="s.accentColor" class="w-8 h-8 rounded cursor-pointer border-0 bg-transparent" />
                <span class="text-xs text-[#a1a1aa]">{{ s.accentColor }}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- ========== 快捷键 ========== -->
        <div v-if="activeSection === 'shortcuts'">
          <h1 class="text-xl font-semibold text-white mb-6">快捷键</h1>

          <div class="settings-group">
            <h3 class="settings-group-title">常用快捷键</h3>
            <div class="space-y-0 mt-2">
              <div
                v-for="sc in shortcuts" :key="sc.keys"
                class="flex items-center justify-between px-4 py-2.5 border-b border-[#2e2e32] last:border-b-0"
              >
                <span class="text-[13px] text-[#e4e4e7]">{{ sc.desc }}</span>
                <div class="flex gap-1">
                  <kbd
                    v-for="key in sc.keys.split('+')" :key="key"
                    class="px-2 py-0.5 bg-[#27272a] border border-[#3e3e42] rounded text-[11px] text-[#a1a1aa] font-mono"
                  >{{ key.trim() }}</kbd>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- ========== 关于 ========== -->
        <div v-if="activeSection === 'about'">
          <h1 class="text-xl font-semibold text-white mb-6">关于</h1>

          <div class="settings-group">
            <div class="flex items-center gap-4 mb-6">
              <div class="w-16 h-16 bg-[#3b82f6]/20 rounded-2xl flex items-center justify-center">
                <i class="fa-solid fa-code-branch text-[#3b82f6] text-2xl"></i>
              </div>
              <div>
                <div class="text-lg font-semibold text-white">Pantheon Forge</div>
                <div class="text-xs text-[#71717a]">版本 0.1.0</div>
                <div class="text-xs text-[#52525b] mt-1">本地 Agent 编程操作系统</div>
              </div>
            </div>

            <div class="setting-row">
              <div><div class="setting-label">技术栈</div></div>
              <span class="text-xs text-[#a1a1aa]">Electron + Vue 3 + Monaco Editor</span>
            </div>
            <div class="setting-row">
              <div><div class="setting-label">支持模型</div></div>
              <span class="text-xs text-[#a1a1aa]">ChatGPT / Claude / Gemini / Qwen / Kimi / GLM / DeepSeek</span>
            </div>
          </div>
        </div>

      </div>
    </div>
    </div>
  </div>
</template>

<style scoped>
.settings-group {
  margin-bottom: 2rem;
}
.settings-group-title {
  font-size: 11px;
  font-weight: 600;
  color: #71717a;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 0.5rem;
}
.setting-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 0;
  border-bottom: 1px solid #1e1e22;
}
.setting-row:last-child { border-bottom: none; }
.setting-label {
  font-size: 13px;
  color: #e4e4e7;
}
.setting-desc {
  font-size: 11px;
  color: #52525b;
  margin-top: 2px;
}
.setting-input {
  background: #27272a;
  border: 1px solid #2e2e32;
  border-radius: 6px;
  padding: 6px 10px;
  font-size: 12px;
  color: #e4e4e7;
  outline: none;
  transition: border-color 0.15s;
}
.setting-input:focus { border-color: #3b82f6; }
.setting-select {
  background: #27272a;
  border: 1px solid #2e2e32;
  border-radius: 6px;
  padding: 6px 10px;
  font-size: 12px;
  color: #e4e4e7;
  outline: none;
  cursor: pointer;
  transition: border-color 0.15s;
}
.setting-select:focus { border-color: #3b82f6; }
.setting-btn-danger {
  padding: 6px 16px;
  background: #7f1d1d33;
  color: #f87171;
  border: 1px solid #7f1d1d55;
  border-radius: 6px;
  font-size: 12px;
  cursor: pointer;
  transition: all 0.15s;
}
.setting-btn-danger:hover { background: #7f1d1d55; }

/* Toggle switch */
.toggle {
  position: relative;
  display: inline-block;
  width: 36px;
  height: 20px;
  flex-shrink: 0;
}
.toggle input { opacity: 0; width: 0; height: 0; }
.toggle-slider {
  position: absolute;
  cursor: pointer;
  inset: 0;
  background: #3f3f46;
  border-radius: 20px;
  transition: 0.2s;
}
.toggle-slider::before {
  content: '';
  position: absolute;
  height: 14px;
  width: 14px;
  left: 3px;
  bottom: 3px;
  background: white;
  border-radius: 50%;
  transition: 0.2s;
}
.toggle input:checked + .toggle-slider { background: #22c55e; }
.toggle input:checked + .toggle-slider::before { transform: translateX(16px); }

/* Toast animation */
.toast-enter-active { animation: toast-in 0.25s ease-out; }
.toast-leave-active { animation: toast-out 0.2s ease-in; }
@keyframes toast-in { from { opacity: 0; transform: translate(-50%, -12px); } to { opacity: 1; transform: translate(-50%, 0); } }
@keyframes toast-out { from { opacity: 1; transform: translate(-50%, 0); } to { opacity: 0; transform: translate(-50%, -12px); } }
</style>
