# 需求文档：Agent 系统级优化

## 简介

对 Pantheon Forge 编辑器的 Agent 系统进行全面优化，涵盖三大核心领域：
1. Skills/MCP/Rules 系统的真正落地执行（当前仅写入 system prompt 文本，未实际加载和调用）
2. 工具系统增强（搜索结果缺少上下文、文件读取缺少行号、缺少 diff/patch 能力）
3. 系统性能优化（上下文窗口管理、搜索阻塞主进程、并行工具调用）

## 术语表

- **Agent_Core**: Agent 核心引擎，负责 ReAct 循环、消息管理和工具调度（`agent/agent-core.ts`）
- **Tool_Executor**: 工具执行器，负责接收工具调用请求并执行具体操作（`agent/tool-executor.ts`）
- **Skill_Loader**: 待实现的 Skills 加载器，负责从 Git 仓库克隆并读取 Skill 内容文件
- **MCP_Client**: 待实现的 MCP 协议客户端，负责连接 MCP 服务器、发现工具、转发调用
- **Agent_Memory**: 上下文窗口管理器，负责裁剪消息历史防止 token 超限（`agent/memory.ts`，已实现但未集成）
- **Model_Router**: 模型路由器，负责选择和配置活跃模型适配器（`agent/model-router.ts`）
- **Service_Manager**: 服务管理器，负责管理长时间运行的进程（`agent/service-manager.ts`）
- **System_Prompt**: 发送给大模型的系统提示词，包含工具定义、规则、Skills 内容等
- **MCP_Protocol**: Model Context Protocol，标准化的模型上下文协议，定义了工具发现和调用的 JSON-RPC 接口
- **ReAct_Loop**: Agent 的推理-行动循环，模型输出思考和工具调用，执行后将结果回传继续推理
- **IPC_Handler**: Electron 主进程中的进程间通信处理器

## 需求

### 需求 1：Skills 内容实际加载与注入

**用户故事：** 作为开发者，我希望配置的 Skills 能被真正加载并注入到模型上下文中，以便大模型获得具体的编程指导和最佳实践内容，而不是只看到一个名字和 URL。

#### 验收标准

1. WHEN 用户启用一个 Skill 且该 Skill 的 Git 仓库尚未克隆, THE Skill_Loader SHALL 将该仓库克隆到本地缓存目录
2. WHEN Skill 仓库已克隆到本地, THE Skill_Loader SHALL 读取该 Skill 对应的内容文件（如 README.md 或指定的 skill 描述文件）
3. WHEN 构建 System_Prompt 时存在已启用且已加载的 Skills, THE Agent_Core SHALL 将 Skill 的实际内容文本注入到 System_Prompt 中
4. IF Skill 仓库克隆失败或内容文件不存在, THEN THE Skill_Loader SHALL 记录错误日志并跳过该 Skill，继续加载其余 Skills
5. WHEN 用户禁用一个 Skill, THE Agent_Core SHALL 在下次构建 System_Prompt 时排除该 Skill 的内容
6. THE Skill_Loader SHALL 将克隆的仓库缓存在用户数据目录下，避免重复克隆

### 需求 2：MCP 协议客户端实现

**用户故事：** 作为开发者，我希望配置的 MCP 服务器能被真正启动和连接，以便大模型可以通过标准 MCP 协议调用 Playwright、Chrome DevTools 等外部工具能力。

#### 验收标准

1. WHEN Agent_Core 启动一次对话且存在已启用的 MCP 服务器配置, THE MCP_Client SHALL 启动对应的 MCP 服务器进程并建立 JSON-RPC 连接
2. WHEN MCP 连接建立成功, THE MCP_Client SHALL 调用 `tools/list` 方法发现该服务器提供的所有工具
3. WHEN MCP 工具发现完成, THE Agent_Core SHALL 将 MCP 工具的定义合并到传给模型的工具列表中
4. WHEN 模型发出对 MCP 工具的调用请求, THE MCP_Client SHALL 通过 JSON-RPC 的 `tools/call` 方法转发调用并返回结果
5. IF MCP 服务器进程启动失败或连接超时, THEN THE MCP_Client SHALL 记录错误日志并通知用户该 MCP 服务器不可用
6. WHEN 对话结束或用户关闭项目, THE MCP_Client SHALL 优雅关闭所有 MCP 服务器进程和连接
7. THE MCP_Client SHALL 通过 stdio 传输方式与 MCP 服务器通信（stdin/stdout JSON-RPC）

### 需求 3：Rules 系统执行增强

**用户故事：** 作为开发者，我希望 Rules 不仅被注入到 system prompt，还能在 Agent 执行过程中被验证和提醒，以确保模型行为符合我设定的规则。

#### 验收标准

1. THE Agent_Core SHALL 在 System_Prompt 中以结构化格式注入所有已启用的规则，包含规则编号和明确的遵守指令
2. WHEN Agent_Core 完成一轮工具调用后, THE Agent_Core SHALL 在内部检查点提示模型回顾当前规则列表
3. WHEN 用户在对话中途修改规则, THE Agent_Core SHALL 在下一轮 ReAct_Loop 迭代中使用更新后的规则

### 需求 4：搜索工具增强

**用户故事：** 作为开发者，我希望 `search_files` 工具返回匹配行的具体内容和行号，以便大模型能精确定位代码位置而不需要再次读取整个文件。

#### 验收标准

1. WHEN search_files 工具找到匹配结果, THE Tool_Executor SHALL 返回每个匹配的文件路径、行号、匹配行内容以及上下各 2 行的上下文
2. THE Tool_Executor SHALL 将 search_files 的结果数量限制在 50 个匹配项以内，超出时提示结果已截断
3. WHEN search_files 在大型项目中执行, THE Tool_Executor SHALL 在 Worker 线程中执行文件遍历和内容搜索，避免阻塞 Electron 主进程事件循环
4. THE Tool_Executor SHALL 支持 search_files 的正则表达式搜索模式

### 需求 5：文件读取工具增强

**用户故事：** 作为开发者，我希望 `read_file` 工具返回带行号的内容并支持行范围读取，以便大模型能精确引用和修改代码。

#### 验收标准

1. WHEN read_file 工具读取文件, THE Tool_Executor SHALL 在每行内容前添加行号前缀（格式：`行号 | 内容`）
2. WHEN read_file 工具接收到 start_line 和 end_line 参数, THE Tool_Executor SHALL 只返回指定行范围内的内容
3. WHEN 文件内容超过 10000 字符, THE Tool_Executor SHALL 截断内容并在末尾标注总行数和已显示行数

### 需求 6：Diff/Patch 工具

**用户故事：** 作为开发者，我希望 Agent 能通过 diff/patch 方式修改文件，而不是每次都覆写整个文件，以减少 token 消耗和降低出错风险。

#### 验收标准

1. THE Tool_Executor SHALL 提供 `edit_file` 工具，接受文件路径、旧文本片段和新文本片段作为参数
2. WHEN edit_file 工具执行时, THE Tool_Executor SHALL 在目标文件中查找旧文本片段并替换为新文本片段
3. IF edit_file 工具在文件中找不到指定的旧文本片段, THEN THE Tool_Executor SHALL 返回错误信息，说明未找到匹配内容
4. IF edit_file 工具在文件中找到多处匹配的旧文本片段, THEN THE Tool_Executor SHALL 返回错误信息，要求提供更多上下文以唯一定位
5. THE Agent_Core SHALL 在 System_Prompt 中指导模型优先使用 edit_file 进行局部修改，仅在创建新文件或需要大范围重写时使用 write_file

### 需求 7：上下文窗口管理

**用户故事：** 作为开发者，我希望 Agent 能自动管理对话上下文长度，避免长对话导致 token 超限报错或性能下降。

#### 验收标准

1. THE Agent_Core SHALL 在每轮 ReAct_Loop 迭代前使用 Agent_Memory 对消息历史进行 token 估算和裁剪
2. WHEN 消息历史的估算 token 数超过模型上下文窗口的 80%, THE Agent_Memory SHALL 从最早的非系统消息开始裁剪，保留系统消息和最近的对话
3. WHEN Agent_Memory 裁剪消息时, THE Agent_Memory SHALL 在裁剪点插入一条摘要消息，概述被裁剪的对话内容要点
4. THE Agent_Core SHALL 根据当前活跃模型的上下文窗口大小动态设置 Agent_Memory 的 maxTokens 参数

### 需求 8：并行工具调用支持

**用户故事：** 作为开发者，我希望 Agent 能在一轮中同时执行多个独立的工具调用，以提高执行效率。

#### 验收标准

1. WHEN 模型在一次响应中返回多个 tool_call, THE Agent_Core SHALL 使用 Promise.all 并行执行所有工具调用
2. WHEN 并行工具调用全部完成, THE Agent_Core SHALL 将所有工具结果按对应的 tool_call_id 组装为消息数组，一次性回传给模型
3. IF 并行工具调用中某个工具执行失败, THEN THE Agent_Core SHALL 将该工具的错误信息作为其结果回传，不影响其他工具的结果

### 需求 9：主进程性能优化

**用户故事：** 作为开发者，我希望文件搜索和命令执行不会阻塞 Electron 主进程，以避免 UI 卡顿。

#### 验收标准

1. THE Tool_Executor SHALL 在 Worker 线程中执行 search_files 的文件遍历和内容匹配操作
2. WHEN search_files 在 Worker 线程中执行时, THE Tool_Executor SHALL 通过消息传递将结果返回主线程
3. THE IPC_Handler 中的 `search:files` 处理器 SHALL 将搜索操作委托给 Worker 线程执行，避免在主进程事件循环中进行递归文件遍历
4. WHEN `shell:exec` IPC_Handler 执行命令时, THE IPC_Handler SHALL 确保 stdout/stderr 数据处理不阻塞主进程事件循环
