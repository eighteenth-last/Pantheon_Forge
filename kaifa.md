老大，这个就开始有“架构味”了。

你现在不是做一个玩具编辑器，而是在做一个：

> 本地 Agent 编程操作系统
>
> * 多模型统一调度层
> * 可扩展工具运行时

我们直接给你一份**可落地的完整开发方案**。不空谈。

技术栈沿用刚刚确定的：

Electron + Vite
Vue 3 + Pinia + Naive UI
Monaco Editor
Node + TypeScript
SQLite

支持模型：

* 千问（Qwen）
* Kimi
* Claude
* GLM
* Gemini
* ChatGPT

---

# 一、整体架构设计

核心思想：

你不要为“模型”写逻辑。
你要为“协议”写逻辑。

模型只是适配器。

架构分四层：

UI 层
Agent Orchestrator
Model Adapter 层
Tool Runtime 层
SQLite 存储层

逻辑流：

用户输入需求
→ Agent 规划（ReAct）
→ 调用模型
→ 判断是否调用工具
→ 执行工具
→ 反馈 Observation
→ 循环
→ 输出 diff

---

# 二、项目目录结构（可直接开干）

```bash
ai-editor/
├── electron/
│   ├── main.ts
│   ├── preload.ts
│   └── browser/
│
├── renderer/
│   ├── components/
│   ├── views/
│   ├── stores/
│   └── editor/
│
├── agent/
│   ├── agent-core.ts
│   ├── memory.ts
│   ├── planner.ts
│   ├── model-router.ts
│   └── tool-executor.ts
│
├── models/
│   ├── base-adapter.ts
│   ├── openai-adapter.ts
│   ├── qwen-adapter.ts
│   ├── kimi-adapter.ts
│   ├── claude-adapter.ts
│   ├── glm-adapter.ts
│   └── gemini-adapter.ts
│
├── tools/
│   ├── file-tool.ts
│   ├── terminal-tool.ts
│   ├── browser-tool.ts
│   └── search-tool.ts
│
├── database/
│   ├── db.ts
│   └── schema.sql
│
└── package.json
```

---

# 三、多模型适配方案（重点）

## 核心原则

所有模型统一为一个抽象接口：

```ts
export interface ModelAdapter {
  stream(messages: Message[], config: ModelConfig): AsyncGenerator<ModelChunk>
}
```

然后每个模型做“协议适配”。

---

## 1️⃣ ChatGPT / 千问 / GLM / Kimi

大多数支持 OpenAI 兼容协议。

统一用一个：

openai-compatible-adapter.ts

只需可配置：

* base_url
* model_name
* api_key

这可以覆盖：

* ChatGPT
* 千问
* GLM
* Kimi

---

## 2️⃣ Claude

Claude 用不同接口结构。

写单独 claude-adapter.ts

关键：

* 消息结构不同
* tool call 结构不同
* 流式返回格式不同

但只要在 Adapter 层转换成统一格式即可。

---

## 3️⃣ Gemini

Gemini 是 Google 协议。

写 gemini-adapter.ts

做格式转换。

---

## Model Router

根据当前 profile 选择：

```ts
modelRouter.getActiveModel().stream(...)
```

SQLite 存储多个模型配置。

---

# 四、SQLite 设计

你不用复杂数据库。

SQLite 足够。

## 表结构设计

models 表

* id
* name
* base_url
* model_name
* api_key
* type
* is_active

sessions 表

* id
* project_path
* model_id
* created_at

messages 表

* id
* session_id
* role
* content
* created_at

tool_logs 表

* id
* session_id
* tool_name
* input
* output
* created_at

token_usage 表

* session_id
* prompt_tokens
* completion_tokens

SQLite 优点：

* 本地
* 轻量
* 事务安全
* 无需额外部署

---

# 五、Agent 设计（核心）

你实现一个简化 ReAct Agent。

### 循环逻辑

1. 拼接系统 Prompt
2. 加入历史消息
3. 调用模型
4. 解析是否包含 Tool Call
5. 执行工具
6. 加入 Observation
7. 继续循环

直到：

* 模型输出 Final Answer
* 或达到最大步数

---

## Prompt 设计思路

固定格式：

Thought:
Action:
Action Input:

Final:

你只要让模型遵循这个结构。

---

# 六、工具系统设计

## 1️⃣ File Tool

* read_file
* write_file
* list_dir

限制根目录：

只允许操作当前项目路径。

---

## 2️⃣ Terminal Tool

child_process.spawn

流式返回 stdout。

禁止执行危险命令：

rm -rf
shutdown
format

简单黑名单即可。

---

## 3️⃣ Browser Tool

Electron BrowserView

实现：

open
evaluate
screenshot

流程：

Agent → browser.open(url)
Electron 执行
返回 DOM 或截图 base64

---

# 七、编辑器设计

核心：

Monaco Editor

你需要实现：

* Diff Viewer
* Patch 应用
* 文件树
* 快捷键

Agent 输出：

```diff
--- a/index.ts
+++ b/index.ts
```

用 Monaco Diff Editor 展示。

确认后才写入文件。

---

# 八、配置系统

设置页：

* 模型管理
* 默认模型
* Token 上限
* 最大 Agent 步数
* 浏览器启用开关

---

# 九、第一阶段功能边界（别做太多）

第一版只做：

* 单 Agent
* 单项目
* 多模型切换
* 文件 + 终端工具
* Diff 应用

不要做：

* 多 Agent
* 插件系统
* 云同步

控制复杂度，是工程成功的关键。

---

# 十、三阶段开发路线

第一阶段（2~3周）

* 基础 IDE 壳
* 单模型
* 文件工具
* Diff 应用

第二阶段（2周）

* 多模型适配
* SQLite 存储
* 浏览器工具
* Token 统计

第三阶段（2周）

* 多轮 Agent 优化
* Prompt 可编辑
* 会话管理

---

# 十一、技术难点预警

1. 不同模型的 tool call 格式不统一
2. 流式解析容易出错
3. Agent 容易死循环
4. 浏览器控制要处理异步时序

解决方案：

统一 Adapter 层。
限制最大循环次数。
工具执行必须有 timeout。

---

# 十二、一个现实判断

你做这个项目的价值，不在于“替代 Cursor”。

而在于：

你可以完全掌控：

* Prompt
* Agent 调度
* 多模型切换策略
* 自动修复逻辑
* 测试工作流

当你把“写代码 → 运行 → 修复 → 再运行”自动化后，你会明显感觉到：

编程开始像下棋。

而不是搬砖。

---

如果你愿意，我可以下一步给你：

* Agent 核心代码骨架
* 或 多模型 Adapter 的统一实现模板

你这个方向是对的。

未来几年，真正的效率提升不来自更快的 CPU。

来自“如何组织智能体”。

你现在就在构建那个组织结构。
