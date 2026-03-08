import 'package:sqlite3/sqlite3.dart';
import 'package:pantheon_forge/core/storage/storage_manager.dart';

class AppDatabase {
  AppDatabase._();
  static AppDatabase? _instance;
  static AppDatabase get instance => _instance ??= AppDatabase._();

  late Database _db;
  bool _initialized = false;
  Database get db => _db;

  void initialize() {
    if (_initialized) return;
    _db = sqlite3.open(StorageManager.instance.dbPath);
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA foreign_keys = ON');
    _migrateDatabase();
    _initialized = true;
  }

  void _migrateDatabase() {
    // Check if database is empty
    final tables = _db.select("SELECT name FROM sqlite_master WHERE type='table'");
    final isEmpty = tables.isEmpty;
    
    if (isEmpty) {
      // Fresh database, create all tables
      _createTables();
    } else {
      // Existing database, run migrations
      _migrateSshTables();
    }
  }

  void _migrateSshTables() {
    // Check if ssh_connections table exists
    final tableExists = _db.select("SELECT name FROM sqlite_master WHERE type='table' AND name='ssh_connections'");
    
    if (tableExists.isEmpty) {
      // Table doesn't exist, create it
      _db.execute('''
        CREATE TABLE IF NOT EXISTS ssh_connections (
          id TEXT PRIMARY KEY, group_id TEXT, name TEXT NOT NULL,
          host TEXT NOT NULL, port INTEGER NOT NULL DEFAULT 22,
          username TEXT NOT NULL, auth_type TEXT NOT NULL DEFAULT 'password',
          private_key_path TEXT, startup_command TEXT, default_directory TEXT,
          proxy_jump TEXT, keep_alive_interval INTEGER NOT NULL DEFAULT 60,
          sort_order INTEGER NOT NULL DEFAULT 0,
          last_connected_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )''');
      return;
    }
    
    // Check if table has new columns
    final tableInfo = _db.select('PRAGMA table_info(ssh_connections)');
    final columnNames = tableInfo.map((r) => r['name'] as String).toList();
    
    final needsMigration = !columnNames.contains('private_key_path') ||
                          !columnNames.contains('startup_command') ||
                          !columnNames.contains('proxy_jump') ||
                          !columnNames.contains('keep_alive_interval');
    
    if (!needsMigration) return;
    
    // Migrate table
    _db.execute('ALTER TABLE ssh_connections RENAME TO ssh_connections_old');
    
    _db.execute('''
      CREATE TABLE ssh_connections (
        id TEXT PRIMARY KEY, group_id TEXT, name TEXT NOT NULL,
        host TEXT NOT NULL, port INTEGER NOT NULL DEFAULT 22,
        username TEXT NOT NULL, auth_type TEXT NOT NULL DEFAULT 'password',
        private_key_path TEXT, startup_command TEXT, default_directory TEXT,
        proxy_jump TEXT, keep_alive_interval INTEGER NOT NULL DEFAULT 60,
        sort_order INTEGER NOT NULL DEFAULT 0,
        last_connected_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');
    
    // Copy existing data
    _db.execute('''
      INSERT INTO ssh_connections 
      (id, group_id, name, host, port, username, auth_type, default_directory, 
       sort_order, last_connected_at, created_at, updated_at)
      SELECT id, group_id, name, host, port, username, auth_type, default_directory,
             sort_order, last_connected_at, created_at, updated_at
      FROM ssh_connections_old
    ''');
    
    _db.execute('DROP TABLE ssh_connections_old');
  }

  void _createTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, working_folder TEXT,
        ssh_connection_id TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_projects_updated ON projects(updated_at)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, mode TEXT NOT NULL DEFAULT 'chat',
        project_id TEXT REFERENCES projects(id), working_folder TEXT, icon TEXT,
        pinned INTEGER DEFAULT 0, provider_id TEXT, model_id TEXT,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_id)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        role TEXT NOT NULL, content TEXT NOT NULL, created_at INTEGER NOT NULL,
        usage TEXT, sort_order INTEGER NOT NULL
      )''');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, sort_order)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS plans (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        title TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'drafting',
        file_path TEXT, content TEXT,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        plan_id TEXT REFERENCES plans(id) ON DELETE SET NULL,
        subject TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending', owner TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS providers (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
        api_key TEXT NOT NULL DEFAULT '', base_url TEXT NOT NULL DEFAULT '',
        enabled INTEGER NOT NULL DEFAULT 0, models_json TEXT NOT NULL DEFAULT '[]',
        default_model TEXT, created_at INTEGER NOT NULL
      )''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY, value TEXT NOT NULL
      )''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS cron_jobs (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, schedule_kind TEXT NOT NULL,
        schedule_at INTEGER, schedule_every INTEGER, schedule_expr TEXT,
        prompt TEXT NOT NULL, agent_id TEXT, model TEXT, working_folder TEXT,
        session_id TEXT, enabled INTEGER DEFAULT 1, max_iterations INTEGER DEFAULT 15,
        last_fired_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');

    // Create SSH tables with migration support
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ssh_connections_old (
        id TEXT PRIMARY KEY, group_id TEXT, name TEXT NOT NULL,
        host TEXT NOT NULL, port INTEGER NOT NULL DEFAULT 22,
        username TEXT NOT NULL, auth_type TEXT NOT NULL DEFAULT 'password',
        default_directory TEXT, sort_order INTEGER NOT NULL DEFAULT 0,
        last_connected_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');

    // Check if we need to migrate
    final tableInfo = _db.select("PRAGMA table_info(ssh_connections_old)");
    final hasPrivateKeyPath = tableInfo.any((r) => r['name'] == 'private_key_path');
    
    if (!hasPrivateKeyPath) {
      // Migrate existing table
      _db.execute('''
        CREATE TABLE IF NOT EXISTS ssh_connections (
          id TEXT PRIMARY KEY, group_id TEXT, name TEXT NOT NULL,
          host TEXT NOT NULL, port INTEGER NOT NULL DEFAULT 22,
          username TEXT NOT NULL, auth_type TEXT NOT NULL DEFAULT 'password',
          private_key_path TEXT, startup_command TEXT, default_directory TEXT,
          proxy_jump TEXT, keep_alive_interval INTEGER NOT NULL DEFAULT 60,
          sort_order INTEGER NOT NULL DEFAULT 0,
          last_connected_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )''');
      
      // Copy data from old table
      _db.execute('''
        INSERT INTO ssh_connections 
        (id, group_id, name, host, port, username, auth_type, default_directory, 
         sort_order, last_connected_at, created_at, updated_at)
        SELECT id, group_id, name, host, port, username, auth_type, default_directory,
               sort_order, last_connected_at, created_at, updated_at
        FROM ssh_connections_old
      ''');
      
      _db.execute('DROP TABLE ssh_connections_old');
    } else {
      // Table already has new columns, just rename if needed
      _db.execute('DROP TABLE IF EXISTS ssh_connections');
      _db.execute('''
        CREATE TABLE ssh_connections (
          id TEXT PRIMARY KEY, group_id TEXT, name TEXT NOT NULL,
          host TEXT NOT NULL, port INTEGER NOT NULL DEFAULT 22,
          username TEXT NOT NULL, auth_type TEXT NOT NULL DEFAULT 'password',
          private_key_path TEXT, startup_command TEXT, default_directory TEXT,
          proxy_jump TEXT, keep_alive_interval INTEGER NOT NULL DEFAULT 60,
          sort_order INTEGER NOT NULL DEFAULT 0,
          last_connected_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )''');
      _db.execute('INSERT INTO ssh_connections SELECT * FROM ssh_connections_old');
      _db.execute('DROP TABLE ssh_connections_old');
    }

    _db.execute('''
      CREATE TABLE IF NOT EXISTS ssh_groups (
        id TEXT PRIMARY KEY, name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS ssh_credentials (
        connection_id TEXT PRIMARY KEY,
        password TEXT,
        passphrase TEXT,
        FOREIGN KEY (connection_id) REFERENCES ssh_connections(id) ON DELETE CASCADE
      )''');
  }

  String? getSetting(String key) {
    final r = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void setSetting(String key, String value) {
    _db.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
  }

  void close() {
    if (_initialized) { _db.dispose(); _initialized = false; }
  }
}
