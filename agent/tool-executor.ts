import type { ToolDefinition } from '../models/base-adapter'
import { readFile, writeFile, readdir, stat, mkdir } from 'fs/promises'
import { join, relative, resolve } from 'path'
import { spawn } from 'child_process'
import type { ServiceManager } from './service-manager'
import type { SkillLoader } from './skill-loader'

/** 危险命令黑名单 */
const DANGEROUS_COMMANDS = ['rm -rf /', 'format', 'shutdown', 'del /f /s /q', 'rmdir /s /q c:']

/** 转义正则特殊字符 */
function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, (ch) => '\\' + ch)
}

export class ToolExecutor {
  private projectRoot = ''
  private serviceManager: ServiceManager | null = null
  private searchFn: ((cwd: string, query: string, options: Record<string, any>) => Promise<any>) | null = null
  private skillLoader: SkillLoader | null = null

  setProjectRoot(root: string) { this.projectRoot = root }
  setServiceManager(sm: ServiceManager) { this.serviceManager = sm }
  setSkillLoader(loader: SkillLoader) { this.skillLoader = loader }

  /** 注入搜索函数（由主进程提供，委托给 SearchWorker） */
  setSearchFunction(fn: (cwd: string, query: string, options: Record<string, any>) => Promise<any>) {
    this.searchFn = fn
  }

  /** 获取所有工具定义（传给模型） */
  getToolDefinitions(): ToolDefinition[] {
    return [
      {
        name: 'read_file',
        description: '读取项目中的文件内容，返回带行号的内容。可指定行范围只读取部分内容。',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: '相对于项目根目录的文件路径' },
            start_line: { type: 'number', description: '起始行号（从1开始），可选' },
            end_line: { type: 'number', description: '结束行号（包含），可选' }
          },
          required: ['path']
        }
      },
      {
        name: 'write_file',
        description: '写入或创建文件',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: '相对于项目根目录的文件路径' },
            content: { type: 'string', description: '文件内容' }
          },
          required: ['path', 'content']
        }
      },
      {
        name: 'list_dir',
        description: '列出目录下的文件和子目录',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: '相对于项目根目录的目录路径，默认为根目录' }
          }
        }
      },
      {
        name: 'run_terminal',
        description: '在终端执行短时间命令（30秒超时）。对于需要长时间运行的服务（如 npm run dev、mvn spring-boot:run），请使用 start_service 工具',
        parameters: {
          type: 'object',
          properties: {
            command: { type: 'string', description: '要执行的终端命令' }
          },
          required: ['command']
        }
      },
      {
        name: 'search_files',
        description: '在项目中搜索包含指定文本的文件，返回匹配行的行号、内容和上下文',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string', description: '搜索关键词或正则表达式' },
            pattern: { type: 'string', description: '文件名匹配模式，如 *.ts' },
            is_regex: { type: 'boolean', description: '是否使用正则表达式搜索，默认 false' }
          },
          required: ['query']
        }
      },
      {
        name: 'edit_file',
        description: '通过查找替换修改文件的局部内容。比 write_file 更高效，适合局部修改。',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: '相对于项目根目录的文件路径' },
            old_str: { type: 'string', description: '要查找的旧文本片段（必须在文件中唯一匹配）' },
            new_str: { type: 'string', description: '替换为的新文本片段' }
          },
          required: ['path', 'old_str', 'new_str']
        }
      },
      {
        name: 'start_service',
        description: '在内置终端中启动长时间运行的服务。会自动监听输出，匹配成功/失败模式来判断启动状态。',
        parameters: {
          type: 'object',
          properties: {
            service_id: { type: 'string', description: '服务唯一标识' },
            command: { type: 'string', description: '启动命令' },
            success_pattern: { type: 'string', description: '启动成功的输出匹配正则' },
            error_pattern: { type: 'string', description: '启动失败的输出匹配正则' },
            timeout_ms: { type: 'number', description: '等待启动的超时时间（毫秒），默认 60000' }
          },
          required: ['service_id', 'command']
        }
      },
      {
        name: 'check_service',
        description: '检查已启动服务的运行状态和最近输出',
        parameters: { type: 'object', properties: { service_id: { type: 'string', description: '服务唯一标识' } }, required: ['service_id'] }
      },
      {
        name: 'stop_service',
        description: '停止一个正在运行的服务',
        parameters: { type: 'object', properties: { service_id: { type: 'string', description: '服务唯一标识' } }, required: ['service_id'] }
      },
      {
        name: 'load_skill',
        description: '加载指定编程技能的详细指导内容。当你需要某个技能的具体指导时调用此工具，传入技能的 slug。',
        parameters: {
          type: 'object',
          properties: {
            slug: { type: 'string', description: '技能的 slug 标识，如 "community/code-review"' }
          },
          required: ['slug']
        }
      }
    ]
  }

  /** 执行工具调用 */
  async execute(toolName: string, args: Record<string, any>): Promise<string> {
    try {
      switch (toolName) {
        case 'read_file': return await this.readFile(args.path, args.start_line, args.end_line)
        case 'write_file': return await this.writeFile(args.path, args.content)
        case 'list_dir': return await this.listDir(args.path || '.')
        case 'run_terminal': return await this.runTerminal(args.command)
        case 'search_files': return await this.searchFiles(args.query, args.pattern, args.is_regex)
        case 'edit_file': return await this.editFile(args.path, args.old_str, args.new_str)
        case 'start_service': return await this.startService(args.service_id, args.command, args.success_pattern, args.error_pattern, args.timeout_ms)
        case 'check_service': return await this.checkService(args.service_id)
        case 'stop_service': return await this.stopService(args.service_id)
        case 'load_skill': return await this.loadSkill(args.slug)
        default:
          // MCP 工具路由（以 mcp_ 前缀识别）
          if (toolName.startsWith('mcp_') && this.mcpCallFn) {
            return await this.mcpCallFn(toolName, args)
          }
          return `未知工具: ${toolName}`
      }
    } catch (err: any) {
      return `工具执行错误: ${err.message}`
    }
  }

  private mcpCallFn: ((toolName: string, args: Record<string, any>) => Promise<string>) | null = null

  /** 注入 MCP 工具调用函数 */
  setMcpCallFunction(fn: (toolName: string, args: Record<string, any>) => Promise<string>) {
    this.mcpCallFn = fn
  }

  private safePath(p: string): string {
    const full = resolve(this.projectRoot, p)
    const rel = relative(this.projectRoot, full)
    if (rel.startsWith('..')) throw new Error('不允许访问项目目录之外的文件')
    return full
  }

  private async readFile(path: string, startLine?: number, endLine?: number): Promise<string> {
    const content = await readFile(this.safePath(path), 'utf-8')
    const allLines = content.split('\n')
    const totalLines = allLines.length

    const start = Math.max(1, startLine || 1)
    const end = Math.min(totalLines, endLine || totalLines)
    const lines = allLines.slice(start - 1, end)

    const padWidth = String(end).length
    const numbered = lines.map((line, i) => {
      const lineNum = String(start + i).padStart(padWidth, ' ')
      return `${lineNum} | ${line}`
    }).join('\n')

    // 截断检查（仅在未指定行范围时）
    if (!startLine && !endLine && content.length > 10000) {
      let charCount = 0
      let shownLines = 0
      for (const line of allLines) {
        charCount += line.length + 1
        shownLines++
        if (charCount > 10000) break
      }
      const truncLines = allLines.slice(0, shownLines)
      const padW = String(shownLines).length
      const truncNumbered = truncLines.map((line, i) => {
        const ln = String(i + 1).padStart(padW, ' ')
        return `${ln} | ${line}`
      }).join('\n')
      return `${truncNumbered}\n\n...(文件过长，已截断。总行数: ${totalLines}，已显示: ${shownLines} 行)`
    }

    if (startLine || endLine) {
      return `${numbered}\n\n(显示第 ${start}-${end} 行，共 ${totalLines} 行)`
    }
    return numbered
  }

  private async writeFile(path: string, content: string): Promise<string> {
    const fullPath = this.safePath(path)
    const dir = fullPath.substring(0, fullPath.lastIndexOf('/') > 0 ? fullPath.lastIndexOf('/') : fullPath.lastIndexOf('\\'))
    await mkdir(dir, { recursive: true })

    // 读取旧内容计算差异
    let oldLines = 0
    let isNew = true
    try {
      const oldContent = await readFile(fullPath, 'utf-8')
      oldLines = oldContent.split('\n').length
      isNew = false
    } catch { /* 新文件 */ }

    await writeFile(fullPath, content, 'utf-8')
    const newLines = content.split('\n').length

    if (isNew) {
      return `文件已写入: ${path} (+${newLines} 行, 新文件)`
    }
    const added = Math.max(0, newLines - oldLines)
    const removed = Math.max(0, oldLines - newLines)
    return `文件已写入: ${path} (+${added} -${removed} 行)`
  }

  private async listDir(path: string): Promise<string> {
    const entries = await readdir(this.safePath(path), { withFileTypes: true })
    return entries.map(e => `${e.isDirectory() ? '📁' : '📄'} ${e.name}`).join('\n')
  }

  private async runTerminal(command: string): Promise<string> {
    if (DANGEROUS_COMMANDS.some(dc => command.toLowerCase().includes(dc))) {
      return '⚠️ 该命令被安全策略阻止'
    }
    return new Promise((resolve) => {
      // Windows 下先设置 UTF-8 代码页，避免中文乱码
      const isWin = process.platform === 'win32'
      const actualCmd = isWin ? `chcp 65001 >nul && ${command}` : command
      const proc = spawn(actualCmd, {
        shell: true,
        cwd: this.projectRoot,
        env: { ...process.env, PYTHONIOENCODING: 'utf-8', LANG: 'zh_CN.UTF-8' }
      })
      let stdout = ''
      let stderr = ''
      proc.stdout?.on('data', d => { stdout += d.toString('utf-8') })
      // stderr 单独收集并标注，便于 Agent 识别错误
      proc.stderr?.on('data', d => { stderr += d.toString('utf-8') })
      proc.on('close', code => {
        let result = stdout
        if (stderr.trim()) {
          result += (result ? '\n' : '') + `[STDERR]\n${stderr}`
        }
        if (!result.trim()) result = `进程退出，代码: ${code}`
        if (code !== 0 && code !== null) {
          result += `\n⚠️ 命令以非零状态退出 (exit code: ${code})`
        }
        resolve(result)
      })
      setTimeout(() => { proc.kill(); resolve((stdout || '') + (stderr ? `\n[STDERR]\n${stderr}` : '') + '\n⚠️ 命令执行超时(30s)') }, 30000)
    })
  }

  private async searchFiles(query: string, pattern?: string, isRegex?: boolean): Promise<string> {
    // 优先使用注入的搜索函数（Worker 线程）
    if (this.searchFn) {
      try {
        const { results, truncated } = await this.searchFn(this.projectRoot, query, {
          pattern, isRegex, maxResults: 50, contextLines: 2
        })
        if (!results || results.length === 0) return '未找到匹配内容'

        const output = results.map((r: any) =>
          r.matches.map((m: any) => {
            const ctx: string[] = []
            if (m.contextBefore) m.contextBefore.forEach((l: string, i: number) => ctx.push(`  ${m.line - m.contextBefore.length + i} | ${l}`))
            ctx.push(`> ${m.line} | ${m.text}`)
            if (m.contextAfter) m.contextAfter.forEach((l: string, i: number) => ctx.push(`  ${m.line + 1 + i} | ${l}`))
            return `${r.relPath}:${m.line}\n${ctx.join('\n')}`
          }).join('\n\n')
        ).join('\n\n')

        const totalMatches = results.reduce((sum: number, r: any) => sum + r.matches.length, 0)
        const truncMsg = truncated ? '\n\n⚠️ 结果已截断，仅显示前 50 个匹配项' : ''
        return `找到 ${totalMatches} 个匹配:\n\n${output}${truncMsg}`
      } catch (err: any) {
        return `搜索错误: ${err.message}`
      }
    }

    // 降级：主线程直接搜索
    const MAX_MATCHES = 50
    const CONTEXT_LINES = 2
    let regex: RegExp
    try {
      regex = isRegex ? new RegExp(query, 'g') : new RegExp(escapeRegex(query), 'g')
    } catch (err: any) {
      return `正则表达式语法错误: ${err.message}`
    }

    interface Match { file: string; line: number; text: string; contextBefore: string[]; contextAfter: string[] }
    const matches: Match[] = []
    let totalMatches = 0

    const walk = async (dir: string) => {
      if (totalMatches >= MAX_MATCHES) return
      const entries = await readdir(dir, { withFileTypes: true })
      for (const entry of entries) {
        if (totalMatches >= MAX_MATCHES) return
        if (entry.name.startsWith('.') || entry.name === 'node_modules' || entry.name === 'dist') continue
        const fullPath = join(dir, entry.name)
        if (entry.isDirectory()) {
          await walk(fullPath)
        } else {
          if (pattern && !entry.name.match(new RegExp(pattern.replace(/\*/g, '.*')))) continue
          try {
            const content = await readFile(fullPath, 'utf-8')
            const lines = content.split('\n')
            for (let i = 0; i < lines.length; i++) {
              if (totalMatches >= MAX_MATCHES) break
              regex.lastIndex = 0
              if (regex.test(lines[i])) {
                totalMatches++
                matches.push({
                  file: relative(this.projectRoot, fullPath), line: i + 1, text: lines[i],
                  contextBefore: lines.slice(Math.max(0, i - CONTEXT_LINES), i),
                  contextAfter: lines.slice(i + 1, i + 1 + CONTEXT_LINES)
                })
              }
            }
          } catch { /* skip binary files */ }
        }
      }
    }
    await walk(this.projectRoot)

    if (matches.length === 0) return '未找到匹配内容'
    const output = matches.map(m => {
      const ctx: string[] = []
      m.contextBefore.forEach((l, i) => ctx.push(`  ${m.line - m.contextBefore.length + i} | ${l}`))
      ctx.push(`> ${m.line} | ${m.text}`)
      m.contextAfter.forEach((l, i) => ctx.push(`  ${m.line + 1 + i} | ${l}`))
      return `${m.file}:${m.line}\n${ctx.join('\n')}`
    }).join('\n\n')
    const truncMsg = totalMatches >= MAX_MATCHES ? '\n\n⚠️ 结果已截断，仅显示前 50 个匹配项' : ''
    return `找到 ${matches.length} 个匹配:\n\n${output}${truncMsg}`
  }

  /** edit_file: 文本片段查找替换 */
  private async editFile(path: string, oldStr: string, newStr: string): Promise<string> {
    const fullPath = this.safePath(path)
    const content = await readFile(fullPath, 'utf-8')

    let count = 0
    let idx = -1
    let searchFrom = 0
    while ((idx = content.indexOf(oldStr, searchFrom)) !== -1) {
      count++
      searchFrom = idx + 1
      if (count > 1) break
    }

    if (count === 0) return '❌ 未找到匹配内容，请检查旧文本是否正确'
    if (count > 1) return `❌ 找到 ${count} 处匹配，请提供更多上下文以唯一定位`

    const newContent = content.replace(oldStr, newStr)
    await writeFile(fullPath, newContent, 'utf-8')
    const lineNum = content.substring(0, content.indexOf(oldStr)).split('\n').length
    const oldLineCount = oldStr.split('\n').length
    const newLineCount = newStr.split('\n').length
    const added = Math.max(0, newLineCount - oldLineCount)
    const removed = Math.max(0, oldLineCount - newLineCount)
    return `✅ 文件已修改: ${path} (第 ${lineNum} 行附近, +${added} -${removed} 行)`
  }

  private async startService(serviceId: string, command: string, successPattern?: string, errorPattern?: string, timeoutMs?: number): Promise<string> {
    if (DANGEROUS_COMMANDS.some(dc => command.toLowerCase().includes(dc))) return '⚠️ 该命令被安全策略阻止'
    if (!this.serviceManager) return '⚠️ ServiceManager 未初始化'
    const result = await this.serviceManager.startService(serviceId, command, this.projectRoot, { successPattern, errorPattern, timeoutMs })
    if (result.success) {
      return `✅ 服务 [${serviceId}] 启动成功\n状态: ${result.status}\n终端ID: ${result.termId}\n最近输出:\n${result.output}`
    }
    return `❌ 服务 [${serviceId}] 启动失败\n状态: ${result.status}\n最近输出:\n${result.output}`
  }

  private async checkService(serviceId: string): Promise<string> {
    if (!this.serviceManager) return '⚠️ ServiceManager 未初始化'
    const info = this.serviceManager.checkService(serviceId)
    if (!info.exists) return `服务 [${serviceId}] 不存在`
    const uptimeStr = info.uptime ? `${Math.floor(info.uptime / 1000)}秒` : '未知'
    return `服务 [${serviceId}]\n状态: ${info.status}\n命令: ${info.command}\n运行时间: ${uptimeStr}\n最近输出:\n${info.output}`
  }

  private async stopService(serviceId: string): Promise<string> {
    if (!this.serviceManager) return '⚠️ ServiceManager 未初始化'
    const result = this.serviceManager.stopService(serviceId)
    return result.success ? `✅ 服务 [${serviceId}] 已停止` : `❌ ${result.error}`
  }

  private async loadSkill(slug: string): Promise<string> {
    if (!this.skillLoader) return '⚠️ SkillLoader 未初始化'
    const skill = await this.skillLoader.loadSkillBySlug(slug)
    if (!skill) return `❌ 未找到技能: ${slug}`
    return `## 技能: ${slug}\n\n${skill.content}`
  }
}
