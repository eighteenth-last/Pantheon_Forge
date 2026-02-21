import type { ToolDefinition } from '../models/base-adapter'
import { readFile, writeFile, readdir, stat, mkdir } from 'fs/promises'
import { join, relative, resolve } from 'path'
import { spawn } from 'child_process'

/** 危险命令黑名单 */
const DANGEROUS_COMMANDS = ['rm -rf /', 'format', 'shutdown', 'del /f /s /q', 'rmdir /s /q c:']

export class ToolExecutor {
  private projectRoot = ''

  setProjectRoot(root: string) {
    this.projectRoot = root
  }

  /** 获取所有工具定义（传给模型） */
  getToolDefinitions(): ToolDefinition[] {
    return [
      {
        name: 'read_file',
        description: '读取项目中的文件内容',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: '相对于项目根目录的文件路径' }
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
        description: '在终端执行命令',
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
        description: '在项目中搜索包含指定文本的文件',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string', description: '搜索关键词' },
            pattern: { type: 'string', description: '文件名匹配模式，如 *.ts' }
          },
          required: ['query']
        }
      }
    ]
  }

  /** 执行工具调用 */
  async execute(toolName: string, args: Record<string, any>): Promise<string> {
    try {
      switch (toolName) {
        case 'read_file': return await this.readFile(args.path)
        case 'write_file': return await this.writeFile(args.path, args.content)
        case 'list_dir': return await this.listDir(args.path || '.')
        case 'run_terminal': return await this.runTerminal(args.command)
        case 'search_files': return await this.searchFiles(args.query, args.pattern)
        default: return `未知工具: ${toolName}`
      }
    } catch (err: any) {
      return `工具执行错误: ${err.message}`
    }
  }

  private safePath(p: string): string {
    const full = resolve(this.projectRoot, p)
    const rel = relative(this.projectRoot, full)
    if (rel.startsWith('..')) throw new Error('不允许访问项目目录之外的文件')
    return full
  }

  private async readFile(path: string): Promise<string> {
    const content = await readFile(this.safePath(path), 'utf-8')
    return content.length > 10000 ? content.slice(0, 10000) + '\n...(文件过长，已截断)' : content
  }

  private async writeFile(path: string, content: string): Promise<string> {
    const fullPath = this.safePath(path)
    const dir = fullPath.substring(0, fullPath.lastIndexOf('/') > 0 ? fullPath.lastIndexOf('/') : fullPath.lastIndexOf('\\'))
    await mkdir(dir, { recursive: true })
    await writeFile(fullPath, content, 'utf-8')
    return `文件已写入: ${path}`
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
      const proc = spawn(command, { shell: true, cwd: this.projectRoot })
      let output = ''
      proc.stdout?.on('data', d => { output += d.toString() })
      proc.stderr?.on('data', d => { output += d.toString() })
      proc.on('close', code => resolve(output || `进程退出，代码: ${code}`))
      setTimeout(() => { proc.kill(); resolve(output + '\n⚠️ 命令执行超时(30s)') }, 30000)
    })
  }

  private async searchFiles(query: string, pattern?: string): Promise<string> {
    const results: string[] = []
    const walk = async (dir: string) => {
      const entries = await readdir(dir, { withFileTypes: true })
      for (const entry of entries) {
        if (entry.name.startsWith('.') || entry.name === 'node_modules') continue
        const fullPath = join(dir, entry.name)
        if (entry.isDirectory()) {
          await walk(fullPath)
        } else {
          if (pattern && !entry.name.match(new RegExp(pattern.replace('*', '.*')))) continue
          try {
            const content = await readFile(fullPath, 'utf-8')
            if (content.includes(query)) {
              results.push(relative(this.projectRoot, fullPath))
            }
          } catch { /* skip binary files */ }
        }
      }
    }
    await walk(this.projectRoot)
    return results.length > 0 ? `找到 ${results.length} 个文件:\n${results.join('\n')}` : '未找到匹配文件'
  }
}
