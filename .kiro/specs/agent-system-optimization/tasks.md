# 实施计划：Agent 系统级优化

## 概述

基于需求文档和设计文档，将 Agent 系统优化拆分为增量式编码任务。每个任务构建在前一个任务之上，最终将所有组件集成到 AgentCore 的 ReAct 循环中。实现语言为 TypeScript，测试使用 Vitest + fast-check。

## Tasks

- [x] 1. ToolExecutor 工具增强：read_file、edit_file、search_files
  - [x] 1.1 增强 `read_file` 工具：添加行号前缀和行范围读取
    - 修改 `agent/tool-executor.ts` 中的 `readFile` 方法
    - 在 `getToolDefinitions()` 中为 `read_file` 添加 `start_line` 和 `end_line` 可选参数
    - 每行输出格式：`行号 | 内容`，行号从 1 开始
    - 当指定 `start_line`/`end_line` 时只返回该范围内的行
    - 文件超过 10000 字符时截断并标注总行数和已显示行数
    - 在 `execute()` 方法中传递新参数到 `readFile`
    - _需求: 5.1, 5.2, 5.3_

  - [ ]* 1.2 为 `read_file` 编写属性测试
    - **Property 10: read_file 行号格式** — 对于任意多行文件内容，输出每行以 `行号 | ` 为前缀，行号从 1 连续递增
    - **验证需求: 5.1**
    - **Property 11: read_file 行范围读取** — 对于任意文件和合法行范围 [start, end]，返回恰好 (end - start + 1) 行
    - **验证需求: 5.2**
    - 测试文件：`tests/tool-executor.property.test.ts`

  - [x] 1.3 新增 `edit_file` 工具：文本片段查找替换
    - 在 `agent/tool-executor.ts` 中新增 `editFile(path, oldStr, newStr)` 私有方法
    - 在文件中查找 `oldStr`，找到恰好一处时替换为 `newStr`
    - 找不到匹配返回错误 "未找到匹配内容，请检查旧文本是否正确"
    - 找到多处匹配返回错误 "找到 N 处匹配，请提供更多上下文以唯一定位"
    - 在 `getToolDefinitions()` 中添加 `edit_file` 工具定义（参数：path, old_str, new_str）
    - 在 `execute()` 的 switch 中添加 `edit_file` 分支
    - _需求: 6.1, 6.2, 6.3, 6.4_

  - [ ]* 1.4 为 `edit_file` 编写属性测试
    - **Property 12: edit_file 查找替换正确性** — 对于任意文件内容和恰好出现一次的子字符串 oldStr，替换后文件内容等于原内容中 oldStr 被 newStr 替换的结果
    - **验证需求: 6.2**
    - 测试文件：`tests/tool-executor.property.test.ts`

  - [x] 1.5 增强 `search_files` 工具：返回行号、匹配内容和上下文
    - 修改 `agent/tool-executor.ts` 中的 `searchFiles` 方法
    - 返回每个匹配的文件路径、行号、匹配行内容、上下各 2 行上下文
    - 支持正则表达式搜索模式（新增 `is_regex` 参数）
    - 结果限制 50 个匹配项，超出时提示已截断
    - 在 `getToolDefinitions()` 中为 `search_files` 添加 `is_regex` 可选参数
    - _需求: 4.1, 4.2, 4.4_

  - [ ]* 1.6 为 `search_files` 编写属性测试
    - **Property 8: 搜索结果格式与上下文** — 每个匹配项包含文件路径、行号（≥1）、匹配行文本、上下各 2 行上下文
    - **验证需求: 4.1, 4.4**
    - **Property 9: 搜索结果截断** — 超过 50 个匹配项时，返回 ≤ 50 项且包含截断提示
    - **验证需求: 4.2**
    - 测试文件：`tests/search.property.test.ts`

- [ ] 2. Checkpoint — 确保所有工具增强测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 3. SearchWorker：将搜索操作移到 Worker 线程
  - [x] 3.1 创建 `electron/search-worker.ts` Worker 线程
    - 参照 `electron/git-worker.ts` 的模式，使用 `worker_threads` 的 `parentPort` 通信
    - 实现 `SearchRequest` 消息处理：接收搜索参数，执行文件遍历和内容匹配
    - 支持正则和纯文本搜索、大小写敏感、文件模式过滤
    - 每个匹配返回文件路径、行号、匹配行内容、上下各 2 行上下文
    - 结果限制 50 项（Agent 搜索）或 500 项（IPC 全局搜索），超出标记 truncated
    - _需求: 4.1, 4.2, 4.3, 9.1, 9.2_

  - [x] 3.2 在 `electron/main.ts` 中初始化 SearchWorker 并重构 `search:files` IPC
    - 新增 `initSearchWorker()` 函数，启动 Worker 线程
    - 新增 `searchExec()` 函数，通过 `postMessage` 发送请求并等待结果
    - 将 `search:files` IPC handler 的搜索逻辑委托给 SearchWorker
    - _需求: 9.3_

  - [x] 3.3 在 `agent/tool-executor.ts` 中将 `searchFiles` 委托给 SearchWorker
    - ToolExecutor 接收一个搜索函数（由主进程注入），通过 Worker 执行搜索
    - 新增 `setSearchFunction(fn)` 方法，在 `main.ts` 中注入
    - `searchFiles` 方法调用注入的搜索函数而非自行遍历文件
    - _需求: 4.3, 9.1, 9.2_

- [x] 4. SkillLoader：Skills 内容实际加载
  - [x] 4.1 创建 `agent/skill-loader.ts`
    - 实现 `SkillLoader` 类，包含 `loadSkill`、`loadAllSkills`、`isCloned`、`cloneRepo`、`readSkillContent` 方法
    - 缓存目录：`app.getPath('userData')/skills-cache/`
    - 使用 `git clone --depth 1` 浅克隆
    - 缓存目录命名：将 repo URL hash 为目录名
    - 内容文件查找顺序：skill 字段指定文件 → README.md → 第一个 .md 文件
    - 克隆/读取失败时 `console.error` 记录日志并返回 null，不中断其他 Skill
    - 导出 `SkillContent` 接口
    - _需求: 1.1, 1.2, 1.4, 1.6_

  - [ ]* 4.2 为 SkillLoader 编写属性测试
    - **Property 2: Skill 加载容错性** — 混合有效/无效 SkillItem 列表，`loadAllSkills` 返回所有有效 Skill 的内容，不因无效 Skill 中断
    - **验证需求: 1.4**
    - **Property 3: Skill 缓存幂等性** — 连续两次 `loadSkill` 返回相同内容，第二次不触发 git clone
    - **验证需求: 1.1, 1.6**
    - 测试文件：`tests/skill-loader.property.test.ts`

- [x] 5. MCPClient：MCP 协议客户端实现
  - [x] 5.1 创建 `agent/mcp-client.ts`
    - 实现 `MCPClient` 类，包含 `connect`、`connectAll`、`getAllToolDefinitions`、`callTool`、`shutdown`、`sendRequest` 方法
    - 通过 stdio（stdin/stdout）JSON-RPC 与 MCP 服务器通信
    - `connect`：spawn 进程 → 发送 initialize → 调用 tools/list 发现工具
    - MCP 工具名添加 `mcp_{serverName}_` 前缀，调用时去除前缀还原
    - `shutdown`：优雅关闭所有进程和连接
    - 超时处理：initialize 10s 超时，tools/call 30s 超时
    - 导出 `MCPTool`、`MCPServerConnection` 接口
    - _需求: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [ ]* 5.2 为 MCPClient 编写属性测试
    - **Property 4: MCP 工具合并完整性** — 合并后工具列表长度 = 内置工具数 + MCP 工具数，每个 MCP 工具名带 `mcp_{serverName}_` 前缀
    - **验证需求: 2.3**
    - **Property 5: MCP 连接生命周期** — `shutdown()` 后所有连接 status 为 'closed'，活跃连接数为 0
    - **验证需求: 2.6**
    - 测试文件：`tests/mcp-client.property.test.ts`

- [ ] 6. Checkpoint — 确保 SkillLoader 和 MCPClient 测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 7. buildSystemPrompt 改造与 Rules 增强
  - [x] 7.1 改造 `agent/agent-core.ts` 中的 `buildSystemPrompt` 函数
    - 接受新参数 `skillContents?: SkillContent[]`
    - Rules 注入格式改为 `规则 N: {内容}`（带编号前缀和遵守指令）
    - Skills 注入实际内容文本（`### {name}\n{content}`）而非仅名称/URL
    - 添加 edit_file 工具使用指导：优先使用 edit_file 局部修改，仅创建新文件或大范围重写时用 write_file
    - 移除 MCP 服务器的旧文本注入（改为通过工具列表合并）
    - _需求: 1.3, 1.5, 3.1, 6.5_

  - [ ]* 7.2 为 buildSystemPrompt 编写属性测试
    - **Property 1: Skill 内容注入完整性** — 输出包含所有 enabled Skill 的内容文本，不包含 disabled Skill 的内容
    - **验证需求: 1.3, 1.5**
    - **Property 6: Rules 结构化注入** — 每条规则前有 `规则 N:` 编号前缀，从 1 连续递增
    - **验证需求: 3.1**
    - **Property 7: Rules 动态更新** — 用 R2 构建的 prompt 包含 R2 所有规则且不包含 R1 中被移除的规则
    - **验证需求: 3.3**
    - 测试文件：`tests/build-prompt.property.test.ts`

- [x] 8. AgentMemory 集成：上下文窗口管理
  - [x] 8.1 增强 `agent/memory.ts` 的 `trimMessages` 方法
    - 裁剪时在裁剪点插入摘要消息，概述被裁剪的对话内容要点
    - 支持动态设置 `maxTokens`（新增 `setMaxTokens(n)` 方法）
    - 裁剪阈值：估算 token 超过 maxTokens 的 80% 时触发
    - _需求: 7.2, 7.3, 7.4_

  - [ ]* 8.2 为 AgentMemory 编写属性测试
    - **Property 13: 上下文裁剪保留系统消息** — 裁剪后始终包含系统消息，被移除的是最早的非系统消息
    - **验证需求: 7.2**
    - 测试文件：`tests/memory.property.test.ts`

- [x] 9. AgentCore 集成：并行工具调用、Memory、Skills、MCP
  - [x] 9.1 集成并行工具调用到 AgentCore ReAct 循环
    - 修改 `agent/agent-core.ts` 的 `run` 方法
    - 收集模型一次响应中的所有 `tool_call`（数组而非单个）
    - 使用 `Promise.allSettled` 并行执行所有工具调用
    - 将所有工具结果按 `tool_call_id` 组装为消息数组一次性回传
    - 单个工具失败时将错误信息作为该工具结果，不影响其他工具
    - 更新 BASE_SYSTEM_PROMPT 中 "每次只调用一个工具" 的指导为支持多工具并行
    - _需求: 8.1, 8.2, 8.3_

  - [ ]* 9.2 为并行工具调用编写属性测试
    - **Property 14: 并行工具调用结果完整性** — N 个 tool_call 产生恰好 N 条 tool role 消息，每条 tool_call_id 匹配，部分失败不影响结果数量
    - **验证需求: 8.1, 8.2, 8.3**
    - 测试文件：`tests/agent-core.property.test.ts`

  - [x] 9.3 集成 AgentMemory 到 ReAct 循环
    - 在 AgentCore 构造函数中接收 `AgentMemory` 实例
    - 在每轮 ReAct 迭代前调用 `memory.trimMessages(messages)` 裁剪上下文
    - 根据当前活跃模型的上下文窗口大小动态设置 `memory.setMaxTokens()`
    - _需求: 7.1, 7.4_

  - [x] 9.4 集成 SkillLoader 和 MCPClient 到 AgentCore
    - 在 AgentCore 构造函数中接收 `SkillLoader` 和 `MCPClient` 实例
    - `run` 方法开始时：加载 Skills 内容 → 连接 MCP 服务器 → 构建 system prompt（注入 Skill 内容）→ 合并工具列表（内置 + MCP）
    - MCP 工具调用通过 `mcpClient.callTool()` 转发
    - 在 `execute()` 的 switch 中添加 MCP 工具分支（以 `mcp_` 前缀识别）
    - 对话结束或 stop 时调用 `mcpClient.shutdown()`
    - _需求: 1.3, 2.3, 2.4, 2.6_

  - [x] 9.5 集成 Rules 检查点提示
    - 在 AgentCore 每轮工具调用完成后，在回传给模型的消息中附加规则回顾提示
    - 当用户中途修改规则时，下一轮 ReAct 迭代使用更新后的规则重建 system prompt
    - _需求: 3.2, 3.3_

- [x] 10. 主进程集成：初始化和 IPC 注入
  - [x] 10.1 在 `electron/main.ts` 中初始化新组件并注入到 AgentCore
    - 初始化 SkillLoader（传入 `app.getPath('userData') + '/skills-cache'`）
    - 初始化 MCPClient
    - 初始化 SearchWorker
    - 将 SkillLoader、MCPClient、AgentMemory 注入到 AgentCore 构造函数
    - 将 SearchWorker 的搜索函数注入到 ToolExecutor
    - 更新 `agent:setConfig` IPC handler 传递完整配置（含 maxContextTokens）
    - _需求: 1.1, 2.1, 7.4, 9.3_

  - [x] 10.2 确保 `shell:exec` IPC 的 stdout/stderr 处理不阻塞主进程
    - 检查现有 `shell:exec` handler，确认 spawn 的 stdout/stderr 数据处理使用异步回调
    - 如有阻塞风险，添加流式缓冲处理
    - _需求: 9.4_

- [ ] 11. 最终 Checkpoint — 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户。

## Notes

- 标记 `*` 的任务为可选测试任务，可跳过以加速 MVP
- 每个任务引用了具体的需求编号，确保可追溯性
- 属性测试验证设计文档中的正确性属性，每个属性为独立子任务
- Checkpoint 任务确保增量验证，及早发现问题
- 所有代码使用 TypeScript，测试使用 Vitest + fast-check
