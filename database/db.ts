import BetterSqlite3 from 'better-sqlite3'
import { join } from 'path'
import { app } from 'electron'

const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS models (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  base_url TEXT NOT NULL,
  model_name TEXT NOT NULL,
  api_key TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL DEFAULT 'openai-compatible',
  is_active INTEGER NOT NULL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_path TEXT NOT NULL,
  model_id INTEGER REFERENCES models(id),
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  role TEXT NOT NULL CHECK(role IN ('system','user','assistant','tool')),
  content TEXT NOT NULL,
  tool_call_id TEXT,
  tool_calls TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS tool_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  tool_name TEXT NOT NULL,
  input TEXT,
  output TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS token_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  prompt_tokens INTEGER DEFAULT 0,
  completion_tokens INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS session_memory (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL UNIQUE REFERENCES sessions(id),
  summary TEXT NOT NULL DEFAULT '',
  updated_at TEXT DEFAULT (datetime('now'))
);
`

export interface ModelRecord {
  id?: number
  name: string
  base_url: string
  model_name: string
  api_key: string
  type: 'openai-compatible' | 'claude' | 'gemini'
  is_active: number
}

export interface SessionRecord {
  id?: number
  project_path: string
  model_id?: number
  created_at?: string
}

export interface MessageRecord {
  id?: number
  session_id: number
  role: 'system' | 'user' | 'assistant' | 'tool'
  content: string
  tool_call_id?: string
  tool_calls?: string // JSON string of tool_calls array
  created_at?: string
}

export class Database {
  private db: BetterSqlite3.Database

  constructor() {
    const dbPath = join(app.getPath('userData'), 'pantheon-forge.db')
    this.db = new BetterSqlite3(dbPath)
    this.db.pragma('journal_mode = WAL')
    this.init()
  }

  private init() {
    this.db.exec(SCHEMA_SQL)
    // 迁移：给 messages 表添加 tool_call_id 和 tool_calls 字段（如果不存在）
    try {
      const cols = this.db.prepare("PRAGMA table_info(messages)").all() as { name: string }[]
      const colNames = cols.map(c => c.name)
      if (!colNames.includes('tool_call_id')) {
        this.db.exec('ALTER TABLE messages ADD COLUMN tool_call_id TEXT')
      }
      if (!colNames.includes('tool_calls')) {
        this.db.exec('ALTER TABLE messages ADD COLUMN tool_calls TEXT')
      }
    } catch (err) {
      console.error('Migration error:', err)
    }
  }

  close() {
    this.db.close()
  }

  // ---- Models ----
  getModels(): ModelRecord[] {
    return this.db.prepare('SELECT * FROM models ORDER BY is_active DESC, id ASC').all() as ModelRecord[]
  }

  addModel(model: Omit<ModelRecord, 'id'>): ModelRecord {
    const stmt = this.db.prepare(
      'INSERT INTO models (name, base_url, model_name, api_key, type, is_active) VALUES (?, ?, ?, ?, ?, ?)'
    )
    const info = stmt.run(model.name, model.base_url, model.model_name, model.api_key, model.type, model.is_active ? 1 : 0)
    return { ...model, id: info.lastInsertRowid as number }
  }

  updateModel(id: number, model: Partial<ModelRecord>) {
    const fields = Object.keys(model).filter(k => k !== 'id')
    const sets = fields.map(f => `${f} = ?`).join(', ')
    const values = fields.map(f => (model as any)[f])
    this.db.prepare(`UPDATE models SET ${sets} WHERE id = ?`).run(...values, id)
  }

  deleteModel(id: number) {
    this.db.prepare('DELETE FROM models WHERE id = ?').run(id)
  }

  setActiveModel(id: number) {
    // Toggle: just activate this one without deactivating others
    this.db.prepare('UPDATE models SET is_active = 1 WHERE id = ?').run(id)
  }

  deactivateModel(id: number) {
    this.db.prepare('UPDATE models SET is_active = 0 WHERE id = ?').run(id)
  }

  getActiveModel(): ModelRecord | undefined {
    return this.db.prepare('SELECT * FROM models WHERE is_active = 1 LIMIT 1').get() as ModelRecord | undefined
  }

  getModelById(id: number): ModelRecord | undefined {
    return this.db.prepare('SELECT * FROM models WHERE id = ?').get(id) as ModelRecord | undefined
  }

  // ---- Sessions ----
  getSessions(): SessionRecord[] {
    return this.db.prepare('SELECT * FROM sessions ORDER BY created_at DESC').all() as SessionRecord[]
  }

  /** 获取会话列表，附带第一条用户消息作为标题预览 */
  getSessionsWithPreview(): (SessionRecord & { preview?: string })[] {
    const sessions = this.getSessions()
    const stmt = this.db.prepare(
      "SELECT content FROM messages WHERE session_id = ? AND role = 'user' ORDER BY id ASC LIMIT 1"
    )
    return sessions.map(s => {
      const row = stmt.get(s.id) as { content: string } | undefined
      return { ...s, preview: row?.content?.slice(0, 50) || '空会话' }
    })
  }

  createSession(projectPath: string): SessionRecord {
    const active = this.getActiveModel()
    const info = this.db.prepare('INSERT INTO sessions (project_path, model_id) VALUES (?, ?)').run(projectPath, active?.id ?? null)
    return { id: info.lastInsertRowid as number, project_path: projectPath, model_id: active?.id }
  }

  deleteSession(sessionId: number) {
    this.db.prepare('DELETE FROM messages WHERE session_id = ?').run(sessionId)
    this.db.prepare('DELETE FROM tool_logs WHERE session_id = ?').run(sessionId)
    this.db.prepare('DELETE FROM token_usage WHERE session_id = ?').run(sessionId)
    this.db.prepare('DELETE FROM session_memory WHERE session_id = ?').run(sessionId)
    this.db.prepare('DELETE FROM sessions WHERE id = ?').run(sessionId)
  }

  // ---- Messages ----
  getMessages(sessionId: number): MessageRecord[] {
    return this.db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY id ASC').all(sessionId) as MessageRecord[]
  }

  addMessage(sessionId: number, role: MessageRecord['role'], content: string, toolCallId?: string, toolCalls?: string): MessageRecord {
    const info = this.db.prepare('INSERT INTO messages (session_id, role, content, tool_call_id, tool_calls) VALUES (?, ?, ?, ?, ?)').run(sessionId, role, content, toolCallId || null, toolCalls || null)
    return { id: info.lastInsertRowid as number, session_id: sessionId, role, content, tool_call_id: toolCallId, tool_calls: toolCalls }
  }

  // ---- Tool Logs ----
  addToolLog(sessionId: number, toolName: string, input: string, output: string) {
    this.db.prepare('INSERT INTO tool_logs (session_id, tool_name, input, output) VALUES (?, ?, ?, ?)').run(sessionId, toolName, input, output)
  }

  // ---- Token Usage ----
  addTokenUsage(sessionId: number, promptTokens: number, completionTokens: number) {
    this.db.prepare('INSERT INTO token_usage (session_id, prompt_tokens, completion_tokens) VALUES (?, ?, ?)').run(sessionId, promptTokens, completionTokens)
  }

  // ---- Session Memory ----
  getSessionMemory(sessionId: number): string | undefined {
    const row = this.db.prepare('SELECT summary FROM session_memory WHERE session_id = ?').get(sessionId) as { summary: string } | undefined
    return row?.summary || undefined
  }

  saveSessionMemory(sessionId: number, summary: string) {
    this.db.prepare(
      `INSERT INTO session_memory (session_id, summary, updated_at) VALUES (?, ?, datetime('now'))
       ON CONFLICT(session_id) DO UPDATE SET summary = excluded.summary, updated_at = datetime('now')`
    ).run(sessionId, summary)
  }

  /** 删除会话时同时清理记忆 */
  deleteSessionMemory(sessionId: number) {
    this.db.prepare('DELETE FROM session_memory WHERE session_id = ?').run(sessionId)
  }
}
