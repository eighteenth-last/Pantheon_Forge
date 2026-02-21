/**
 * Agent 规划器
 * 负责构建系统 Prompt 和解析模型输出
 */

/** 构建系统 Prompt */
export function buildSystemPrompt(projectPath: string): string {
  return `你是 Pantheon Forge 的 AI 编程助手。

当前项目路径: ${projectPath}

你可以使用以下工具:
1. read_file(path) - 读取文件内容
2. write_file(path, content) - 写入/创建文件
3. list_dir(path) - 列出目录内容
4. run_terminal(command) - 执行终端命令
5. search_files(query, pattern?) - 搜索项目文件

工作原则:
- 先理解需求，再动手
- 修改文件前先读取了解上下文
- 一步一步执行，每步都有明确目的
- 用中文回复用户
- 代码修改要完整，不要省略

当你完成任务后，给出简洁的总结。`
}

/** 解析模型输出中的 Thought/Action 结构（用于非 function calling 的模型） */
export function parseReActOutput(text: string): {
  thought?: string
  action?: string
  actionInput?: string
  finalAnswer?: string
} {
  const thoughtMatch = text.match(/Thought:\s*(.*?)(?=Action:|Final:|$)/s)
  const actionMatch = text.match(/Action:\s*(.*?)(?=Action Input:|$)/s)
  const inputMatch = text.match(/Action Input:\s*(.*?)(?=Thought:|Final:|$)/s)
  const finalMatch = text.match(/Final:\s*(.*?)$/s)

  return {
    thought: thoughtMatch?.[1]?.trim(),
    action: actionMatch?.[1]?.trim(),
    actionInput: inputMatch?.[1]?.trim(),
    finalAnswer: finalMatch?.[1]?.trim()
  }
}
