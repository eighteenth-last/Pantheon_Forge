# Pantheon Forge

**本地 Agent 编程操作系统 (Local Agent Programming OS)**

Pantheon Forge 是一个基于 Electron 的下一代本地 AI 编程环境。内置具备 ReAct 循环的 AI Agent，支持多模型统一调度、MCP 协议扩展和可插拔 Skills 系统，以 Monaco Editor 为编辑器内核，让 AI 真正参与到你的编码工作流中。

---

## 核心特性

- **多模型统一调度** — 支持 OpenAI / 千问(Qwen) / 豆包 / Kimi / DeepSeek / GLM / Claude / Gemini，统一适配器接口，一键切换
- **ReAct Agent 循环** — 内置规划 → 工具调用 → Observation → 再规划的完整流程，最大执行步数 25 步
- **智能记忆系统** — **256K Token** 上下文窗口，使用率超 80% 时自动调用模型压缩为结构化摘要（ReAct 循环内实时检测）
- **MCP 协议支持** — 通过 stdio JSON-RPC 连接任意 MCP 服务器，动态扩展 Agent 工具集
- **可插拔 Skills 系统** — 16 个内置技能，按需懒加载，用户规则为最高优先级且覆盖基础约束
- **Monaco Editor** — VS Code 同款编辑器内核，支持语法高亮、多文件标签页
- **集成终端** — 基于 xterm.js + node-pty 的多标签终端，支持 Agent 直接执行命令，服务终端智能复用
- **文件拖拽引用** — 文件资源管理器节点可拖入聊天输入框（Chip 样式引用，上限 5 个）或终端（插入绝对路径）
- **Git 集成** — 内置 Git 面板，支持提交、分支管理等操作
- **VPN/代理感知** — 使用 `electron.net.fetch` 替代 Node.js 原生 fetch，自动识别系统代理

---

## 技术栈

| 层 | 技术 |
|---|---|
| 桌面外壳 | Electron 29 + Vite 5 |
| 前端 | Vue 3 + Pinia + Naive UI + Tailwind CSS |
| 编辑器 | Monaco Editor 0.47 |
| 语言 | TypeScript + Node.js |
| 数据库 | SQLite (better-sqlite3) |
| 终端 | xterm.js + node-pty |

---

## 系统架构

```
用户输入
  ↓
UI 层 (Vue 3 Renderer Process)
  ↓
Agent Orchestrator (ReAct 循环, agent-core.ts)
  ├─→ 记忆系统 (AgentMemory 256K) — 循环内实时压缩
  ├─→ Model Router → Model Adapter 层
  │     ├─ OpenAI Compatible (ChatGPT/Qwen/GLM/Kimi/DeepSeek)
  │     ├─ Claude Adapter
  │     └─ Gemini Adapter (streaming + timeout 60s)
  ├─→ Tool Executor (10 个内置工具，stderr 标注)
  ├─→ MCP Client (stdio JSON-RPC 外部工具扩展)
  └─→ Skill Loader (按需加载 Skills 内容)
  ↓
SQLite 存储层 (sessions / messages / tool_logs / token_usage)
```

---

## 内置工具

| 工具 | 说明 |
|---|---|
| `read_file` | 读取文件内容（带行号，支持行范围） |
| `write_file` | 写入或创建文件 |
| `edit_file` | 局部查找替换（优先于 write_file） |
| `list_dir` | 列出目录内容 |
| `run_terminal` | 执行终端命令（30s 超时，stderr 单独标注） |
| `search_files` | 代码搜索（支持正则，含上下文行） |
| `start_service` | 启动长期运行的服务（智能复用已有终端） |
| `check_service` | 检查服务状态和最近 100 行输出 |
| `stop_service` | 停止服务 |
| `load_skill` | 按 slug 懒加载技能详细内容 |

---

## Agent 行为规则

- **用户规则最高优先级** — 设置页添加的规则覆盖任何基础约束，每步操作后强制回顾
- **任务驱动型探索** — 用户要求"阅读项目/继续开发"时，Agent 会系统性遍历整个目录，不提前停止
- **循环内记忆压缩** — 工具结果积累超过 80% 上下文时自动触发 AI 摘要压缩，而非仅在会话入口检查
- **推理模型兼容** — `max_tokens` 默认 16384，避免 DeepSeek-R1 等推理模型 thinking trace 截断工具调用
- **流式超时保护** — 60s 无数据自动中断流式读取，防止 Agent 永久卡死

---

## 目录结构

```
pantheon-forge/
├── electron/               # Electron 主进程
│   ├── main.ts             # 主进程入口，IPC 桥接，electron.net.fetch 代理感知
│   ├── preload.ts          # contextBridge API 暴露
│   ├── git-worker.ts       # Git 操作 Worker
│   └── search-worker.ts    # 文件搜索 Worker
│
├── agent/                  # Agent 核心逻辑
│   ├── agent-core.ts       # ReAct 循环主控，用户规则最高优先级
│   ├── memory.ts           # 记忆压缩系统（256K 窗口）
│   ├── mcp-client.ts       # MCP 协议客户端
│   ├── skill-loader.ts     # Skills 懒加载
│   ├── tool-executor.ts    # 工具执行器（stderr 标注）
│   ├── model-router.ts     # 模型路由
│   └── service-manager.ts  # 服务生命周期管理（终端复用）
│
├── models/                 # 模型适配器
│   ├── base-adapter.ts     # 统一接口定义
│   ├── openai-adapter.ts   # OpenAI 兼容（16384 max_tokens，60s 流式超时）
│   ├── claude-adapter.ts   # Claude 专用适配器
│   ├── gemini-adapter.ts   # Gemini 专用适配器
│   └── retry-fetch.ts      # 限流重试 + 网络错误重试（VPN 切换容错）
│
├── renderer/               # 前端渲染进程 (Vue 3)
│   ├── App.vue             # 根组件（工作区状态持久化）
│   ├── components/
│   │   ├── ChatPanel.vue       # AI 对话（文件 Chip 引用，上限 5 个）
│   │   ├── EditorPanel.vue     # Monaco 编辑器
│   │   ├── FileExplorer.vue    # 文件资源管理器
│   │   ├── FileTreeNode.vue    # 可拖拽文件树节点
│   │   ├── TerminalPanel.vue   # 多标签终端（支持拖入文件路径）
│   │   ├── GitPanel.vue        # Git 操作面板
│   │   ├── SearchPanel.vue     # 全局搜索
│   │   └── SettingsPage.vue    # 设置页（模型/MCP/Skills/规则）
│   └── stores/
│       ├── chat.ts         # 会话与消息
│       ├── project.ts      # 项目与文件
│       └── settings.ts     # 模型与 Agent 配置
│
├── skills/                 # 内置技能库（16 个）
├── database/               # SQLite（5 张表）
└── tools/                  # 基础工具定义
```

---

## 快速开始

```bash
npm install
npm run electron:dev    # 开发模式
npm run electron:build  # 构建（输出 release/）
```

---

## 数据库结构

| 表 | 说明 |
|---|---|
| `models` | 模型配置（name/base_url/model_name/api_key/type） |
| `sessions` | 会话记录（绑定项目路径和模型） |
| `messages` | 完整对话历史（含 tool_calls / tool_call_id） |
| `tool_logs` | 工具执行日志（input/output） |
| `token_usage` | Token 用量统计 |

---

## 许可证

MIT License
