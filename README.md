# Pantheon Forge

**本地 Agent 编程操作系统 (Local Agent Programming OS)**

Pantheon Forge 是一个基于 Electron 和 AI Agent 技术的下一代代码编辑器。它不仅仅是一个编辑器，更是一个集成了多模型统一调度层和可扩展工具运行时的智能编程环境。

## 核心特性

- **多模型统一调度**: 支持多种主流大语言模型，包括 Qwen (千问), Kimi, Claude, GLM, Gemini, 和 ChatGPT。
- **智能 Agent 编排**: 内置 ReAct 循环的 Agent 规划器，能够理解用户需求、规划任务、调用工具并执行操作。
- **可扩展工具运行时**:
  - **文件工具**: 自动读写、修改文件。
  - **终端工具**: 执行系统命令。
  - **搜索工具**: 代码库语义搜索。
- **现代化编辑器体验**: 基于 Monaco Editor (VS Code 同款内核)，提供流畅的代码编辑体验。
- **本地优先**: 使用 SQLite 进行本地数据存储，保护隐私并确保响应速度。

## 技术栈

- **核心框架**: Electron + Vite
- **前端**: Vue 3 + Pinia + Naive UI + Tailwind CSS
- **编辑器内核**: Monaco Editor
- **语言**: TypeScript + Node.js
- **数据库**: SQLite (better-sqlite3)
- **终端模拟**: xterm.js + node-pty

## 系统架构

系统采用分层架构设计，确保模块解耦与高可扩展性：

1.  **UI 层**: 负责用户交互、编辑器渲染 (Renderer Process)。
2.  **Agent Orchestrator**: 负责任务规划、上下文管理 (ReAct 循环)。
3.  **Model Adapter 层**: 统一不同大模型的接口调用。
4.  **Tool Runtime 层**: 提供文件、终端、浏览器等工具的执行环境。
5.  **SQLite 存储层**: 持久化存储对话历史、项目配置等。

## 目录结构

```bash
pantheon-forge/
├── electron/          # Electron 主进程代码
│   ├── main.ts
│   └── preload.ts
├── renderer/          # 前端渲染进程代码 (Vue 3)
│   ├── components/    # UI 组件
│   ├── stores/        # Pinia 状态管理
│   ├── App.vue
│   └── main.ts
├── agent/             # Agent 核心逻辑
│   ├── agent-core.ts  # Agent 主类
│   ├── planner.ts     # 任务规划器
│   └── tool-executor.ts # 工具执行器
├── models/            # 模型适配器 (Adapters)
│   ├── base-adapter.ts
│   ├── openai-adapter.ts
│   └── ...
├── tools/             # 工具实现
│   ├── file-tool.ts
│   └── terminal-tool.ts
├── database/          # 数据库层
│   └── schema.sql
├── ui_design_prototype.html # UI 设计原型
└── start_page.html          # 启动页设计原型
```

## 快速开始

### 前置要求

- Node.js (推荐 v18+)
- npm 或 yarn

### 安装依赖

```bash
npm install
# 或者
yarn install
```

### 开发模式

启动 Vite 开发服务器和 Electron：

```bash
npm run electron:dev
```

### 构建应用

打包生成可执行文件：

```bash
npm run electron:build
```

## 开发文档

更多详细的设计理念和开发指南，请参考 [kaifa.md](./kaifa.md)。

## 许可证

MIT License
