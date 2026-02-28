/**
 * MCP Client — Model Context Protocol 客户端
 *
 * 通过 stdio (stdin/stdout) JSON-RPC 与 MCP 服务器通信
 * 支持 initialize → tools/list → tools/call 完整生命周期
 */
import { spawn, type ChildProcess } from 'child_process'
import type { ToolDefinition } from '../models/base-adapter'

export interface MCPTool {
  name: string
  description: string
  inputSchema: Record<string, any>
  serverName: string
}

interface PendingRequest {
  resolve: (value: any) => void
  reject: (reason: any) => void
  timeout: ReturnType<typeof setTimeout>
}

interface MCPServerConnection {
  name: string
  process: ChildProcess
  tools: MCPTool[]
  status: 'connecting' | 'ready' | 'error' | 'closed'
  requestId: number
  pendingRequests: Map<number, PendingRequest>
  buffer: string
}

export interface McpServerConfig {
  name: string
  command: string
  args: string[]
  env?: Record<string, string>
  enabled: boolean
}

export class MCPClient {
  private connections = new Map<string, MCPServerConnection>()

  /** 连接所有已启用的 MCP 服务器 */
  async connectAll(servers: McpServerConfig[]): Promise<void> {
    const enabled = servers.filter(s => s.enabled)
    for (const server of enabled) {
      try {
        await this.connect(server)
      } catch (err) {
        console.error(`[MCP] 连接 "${server.name}" 失败:`, err)
      }
    }
  }

  /** 启动并连接单个 MCP 服务器 */
  async connect(server: McpServerConfig): Promise<MCPTool[]> {
    // 如果已连接，先关闭
    if (this.connections.has(server.name)) {
      await this.disconnectOne(server.name)
    }

    const proc = spawn(server.command, server.args, {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, ...server.env },
      shell: true
    })

    const conn: MCPServerConnection = {
      name: server.name,
      process: proc,
      tools: [],
      status: 'connecting',
      requestId: 0,
      pendingRequests: new Map(),
      buffer: ''
    }

    this.connections.set(server.name, conn)

    // 监听 stdout（JSON-RPC 响应）
    proc.stdout?.on('data', (data: Buffer) => {
      conn.buffer += data.toString()
      this.processBuffer(conn)
    })

    proc.stderr?.on('data', (data: Buffer) => {
      console.error(`[MCP:${server.name}] stderr:`, data.toString())
    })

    proc.on('close', () => {
      conn.status = 'closed'
      // reject 所有 pending requests
      for (const [, pending] of conn.pendingRequests) {
        clearTimeout(pending.timeout)
        pending.reject(new Error('MCP 服务器已关闭'))
      }
      conn.pendingRequests.clear()
    })

    proc.on('error', (err) => {
      console.error(`[MCP:${server.name}] 进程错误:`, err)
      conn.status = 'error'
    })

    try {
      // 1. initialize
      await this.sendRequest(conn, 'initialize', {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'pantheon-forge', version: '1.0.0' }
      }, 10000)

      // 2. initialized 通知
      this.sendNotification(conn, 'notifications/initialized', {})

      // 3. tools/list
      const toolsResult = await this.sendRequest(conn, 'tools/list', {}, 10000)
      const tools: MCPTool[] = (toolsResult?.tools || []).map((t: any) => ({
        name: t.name,
        description: t.description || '',
        inputSchema: t.inputSchema || {},
        serverName: server.name
      }))

      conn.tools = tools
      conn.status = 'ready'
      console.log(`[MCP] "${server.name}" 已连接，发现 ${tools.length} 个工具`)
      return tools
    } catch (err) {
      conn.status = 'error'
      console.error(`[MCP] "${server.name}" 初始化失败:`, err)
      proc.kill()
      throw err
    }
  }

  /** 获取所有已连接服务器的工具定义，转换为模型可用格式 */
  getAllToolDefinitions(): ToolDefinition[] {
    const defs: ToolDefinition[] = []
    for (const [, conn] of this.connections) {
      if (conn.status !== 'ready') continue
      for (const tool of conn.tools) {
        defs.push({
          name: `mcp_${conn.name}_${tool.name}`,
          description: `[MCP:${conn.name}] ${tool.description}`,
          parameters: tool.inputSchema
        })
      }
    }
    return defs
  }

  /** 调用 MCP 工具 */
  async callTool(prefixedName: string, args: Record<string, any>): Promise<string> {
    // 解析 mcp_{serverName}_{toolName}
    const parts = prefixedName.replace(/^mcp_/, '').split('_')
    const serverName = parts[0]
    const toolName = parts.slice(1).join('_')

    const conn = this.connections.get(serverName)
    if (!conn || conn.status !== 'ready') {
      return `❌ MCP 服务器 "${serverName}" 不可用 (状态: ${conn?.status || '未连接'})`
    }

    try {
      const result = await this.sendRequest(conn, 'tools/call', {
        name: toolName,
        arguments: args
      }, 30000)

      // MCP 返回 content 数组
      if (result?.content && Array.isArray(result.content)) {
        return result.content.map((c: any) => c.text || JSON.stringify(c)).join('\n')
      }
      return JSON.stringify(result)
    } catch (err: any) {
      return `❌ MCP 工具调用失败: ${err.message}`
    }
  }

  /** 关闭所有连接 */
  async shutdown(): Promise<void> {
    for (const [name] of this.connections) {
      await this.disconnectOne(name)
    }
  }

  private async disconnectOne(name: string): Promise<void> {
    const conn = this.connections.get(name)
    if (!conn) return
    for (const [, pending] of conn.pendingRequests) {
      clearTimeout(pending.timeout)
      pending.reject(new Error('连接关闭'))
    }
    conn.pendingRequests.clear()
    conn.status = 'closed'
    try { conn.process.kill() } catch { /* ignore */ }
    this.connections.delete(name)
  }

  /** 发送 JSON-RPC 请求并等待响应 */
  private sendRequest(conn: MCPServerConnection, method: string, params: any, timeoutMs = 10000): Promise<any> {
    return new Promise((resolve, reject) => {
      const id = ++conn.requestId
      const timeout = setTimeout(() => {
        conn.pendingRequests.delete(id)
        reject(new Error(`请求超时: ${method} (${timeoutMs}ms)`))
      }, timeoutMs)

      conn.pendingRequests.set(id, { resolve, reject, timeout })

      const msg = JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n'
      try {
        conn.process.stdin?.write(msg)
      } catch (err) {
        conn.pendingRequests.delete(id)
        clearTimeout(timeout)
        reject(err)
      }
    })
  }

  /** 发送 JSON-RPC 通知（无需响应） */
  private sendNotification(conn: MCPServerConnection, method: string, params: any): void {
    const msg = JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n'
    try {
      conn.process.stdin?.write(msg)
    } catch { /* ignore */ }
  }

  /** 处理 stdout 缓冲区，解析完整的 JSON-RPC 消息 */
  private processBuffer(conn: MCPServerConnection): void {
    const lines = conn.buffer.split('\n')
    conn.buffer = lines.pop() || '' // 保留不完整的最后一行

    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed) continue
      try {
        const msg = JSON.parse(trimmed)
        if (msg.id !== undefined) {
          const pending = conn.pendingRequests.get(msg.id)
          if (pending) {
            conn.pendingRequests.delete(msg.id)
            clearTimeout(pending.timeout)
            if (msg.error) {
              pending.reject(new Error(msg.error.message || JSON.stringify(msg.error)))
            } else {
              pending.resolve(msg.result)
            }
          }
        }
        // 忽略通知消息（无 id）
      } catch {
        // 非 JSON 行，忽略
      }
    }
  }
}
