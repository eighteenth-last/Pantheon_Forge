import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/core/database/database.dart';
import 'package:pantheon_forge/models/ssh_models.dart';
import 'package:pantheon_forge/services/ssh/ssh_service.dart';

class SshNotifier extends ChangeNotifier {
  final SshService _sshService = SshService();
  late final StreamSubscription<SshConnectionStatus> _statusSubscription;

  List<SshGroup> _groups = [];
  List<SshConnection> _connections = [];
  Map<String, SshSession> _sessions = {};
  List<SshTab> _openTabs = [];
  String? _activeTabId;
  String? _selectedConnectionId;
  bool _loaded = false;

  SshNotifier() {
    _statusSubscription = _sshService.connectionStatusStream.listen(
      _handleServiceStatus,
    );
  }

  SshService get sshService => _sshService;
  List<SshGroup> get groups => _groups;
  List<SshConnection> get connections => _connections;
  Map<String, SshSession> get sessions => _sessions;
  List<SshTab> get openTabs => _openTabs;
  String? get activeTabId => _activeTabId;
  String? get selectedConnectionId => _selectedConnectionId;
  bool get loaded => _loaded;

  SshConnection? getConnection(String id) {
    try {
      return _connections.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  SshGroup? getGroup(String? id) {
    if (id == null) return null;
    try {
      return _groups.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  SshSession? getSession(String? id) {
    if (id == null) return null;
    return _sessions[id];
  }

  SshTab? get activeTab {
    if (_activeTabId == null) return null;
    try {
      return _openTabs.firstWhere((t) => t.id == _activeTabId);
    } catch (_) {
      return null;
    }
  }

  List<SshConnection> getConnectionsByGroup(String? groupId) {
    return _connections.where((c) => c.groupId == groupId).toList();
  }

  void _handleServiceStatus(SshConnectionStatus status) {
    final session = _sessions[status.sessionId];
    if (session == null) {
      _sessions[status.sessionId] = SshSession(
        id: status.sessionId,
        connectionId: status.connectionId,
        status: status.status,
        error: status.error,
      );
    } else {
      session.status = status.status;
      session.error = status.error;
    }

    if (status.status == SshSessionStatus.disconnected) {
      final tabsToRemove = _openTabs
          .where((tab) => tab.sessionId == status.sessionId)
          .map((tab) => tab.id)
          .toList();
      for (final tabId in tabsToRemove) {
        closeTab(tabId);
      }
      _sessions.remove(status.sessionId);
      notifyListeners();
      return;
    }

    notifyListeners();
  }

  void loadAll() {
    if (_loaded) return;

    final db = AppDatabase.instance.db;

    final groupRows = db.select('SELECT * FROM ssh_groups ORDER BY sort_order');
    _groups = groupRows.map((r) => SshGroup.fromDbRow(r)).toList();

    final connRows = db.select(
      'SELECT * FROM ssh_connections ORDER BY sort_order',
    );
    _connections = connRows.map((r) {
      final credRow = db.select(
        'SELECT password, passphrase FROM ssh_credentials WHERE connection_id = ?',
        [r['id']],
      ).firstOrNull;
      return SshConnection.fromDbRow(
        r,
        password: credRow?['password'] as String?,
        passphrase: credRow?['passphrase'] as String?,
      );
    }).toList();

    _loaded = true;
    notifyListeners();
  }

  Future<String> createGroup(String name) async {
    final id = 'sshg-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxOrder = _groups.isEmpty
        ? 0
        : _groups.map((g) => g.sortOrder).reduce((a, b) => a > b ? a : b);

    final group = SshGroup(
      id: id,
      name: name,
      sortOrder: maxOrder + 1,
      createdAt: now,
      updatedAt: now,
    );

    final row = group.toDbRow();
    AppDatabase.instance.db.execute(
      'INSERT INTO ssh_groups (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [
        row['id'],
        row['name'],
        row['sort_order'],
        row['created_at'],
        row['updated_at'],
      ],
    );

    _groups = [..._groups, group];
    notifyListeners();
    return id;
  }

  Future<void> updateGroup(String id, String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    AppDatabase.instance.db.execute(
      'UPDATE ssh_groups SET name = ?, updated_at = ? WHERE id = ?',
      [name, now, id],
    );

    _groups = _groups
        .map(
          (g) => g.id == id
              ? SshGroup(
                  id: g.id,
                  name: name,
                  sortOrder: g.sortOrder,
                  createdAt: g.createdAt,
                  updatedAt: now,
                )
              : g,
        )
        .toList();
    notifyListeners();
  }

  Future<void> deleteGroup(String id) async {
    AppDatabase.instance.db.execute('DELETE FROM ssh_groups WHERE id = ?', [
      id,
    ]);
    AppDatabase.instance.db.execute(
      'UPDATE ssh_connections SET group_id = NULL WHERE group_id = ?',
      [id],
    );

    _groups = _groups.where((g) => g.id != id).toList();
    _connections = _connections
        .map((c) => c.groupId == id ? c.copyWith(groupId: null) : c)
        .toList();
    notifyListeners();
  }

  Future<String> createConnection({
    required String name,
    required String host,
    int port = 22,
    required String username,
    SshAuthType authType = SshAuthType.password,
    String? password,
    String? privateKeyPath,
    String? passphrase,
    String? groupId,
    String? startupCommand,
    String? defaultDirectory,
    String? proxyJump,
    int keepAliveInterval = 60,
  }) async {
    final id = 'sshc-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxOrder = _connections.isEmpty
        ? 0
        : _connections.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b);

    final connection = SshConnection(
      id: id,
      groupId: groupId,
      name: name,
      host: host,
      port: port,
      username: username,
      authType: authType,
      privateKeyPath: privateKeyPath,
      startupCommand: startupCommand,
      defaultDirectory: defaultDirectory,
      proxyJump: proxyJump,
      keepAliveInterval: keepAliveInterval,
      sortOrder: maxOrder + 1,
      createdAt: now,
      updatedAt: now,
    );

    final row = connection.toDbRow();
    AppDatabase.instance.db.execute(
      '''INSERT INTO ssh_connections
         (id, group_id, name, host, port, username, auth_type, private_key_path,
          startup_command, default_directory, proxy_jump, keep_alive_interval, sort_order, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        row['id'],
        row['group_id'],
        row['name'],
        row['host'],
        row['port'],
        row['username'],
        row['auth_type'],
        row['private_key_path'],
        row['startup_command'],
        row['default_directory'],
        row['proxy_jump'],
        row['keep_alive_interval'],
        row['sort_order'],
        row['created_at'],
        row['updated_at'],
      ],
    );

    if (password != null && password.isNotEmpty) {
      AppDatabase.instance.db.execute(
        'INSERT OR REPLACE INTO ssh_credentials (connection_id, password, passphrase) VALUES (?, ?, ?)',
        [id, password, passphrase],
      );
    }

    _connections = [
      ..._connections,
      connection.copyWith(password: password, passphrase: passphrase),
    ];
    notifyListeners();
    return id;
  }

  Future<void> updateConnection(String id, Map<String, dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final conn = getConnection(id);
    if (conn == null) return;

    final updates = <String, dynamic>{...data, 'updated_at': now};
    final setClauses = <String>[];
    final values = <dynamic>[];

    updates.forEach((key, value) {
      if (key != 'id') {
        setClauses.add('$key = ?');
        values.add(value);
      }
    });

    values.add(id);

    AppDatabase.instance.db.execute(
      'UPDATE ssh_connections SET ${setClauses.join(', ')} WHERE id = ?',
      values,
    );

    if (data.containsKey('password') || data.containsKey('passphrase')) {
      AppDatabase.instance.db.execute(
        'INSERT OR REPLACE INTO ssh_credentials (connection_id, password, passphrase) VALUES (?, ?, ?)',
        [
          id,
          data['password'] ?? conn.password,
          data['passphrase'] ?? conn.passphrase,
        ],
      );
    }

    _connections = _connections.map((c) {
      if (c.id != id) return c;
      return c.copyWith(
        name: data['name'] as String?,
        host: data['host'] as String?,
        port: data['port'] as int?,
        username: data['username'] as String?,
        authType: data['auth_type'] != null
            ? SshAuthType.values.firstWhere((e) => e.name == data['auth_type'])
            : null,
        privateKeyPath: data['private_key_path'] as String?,
        groupId: data['group_id'] as String?,
        startupCommand: data['startup_command'] as String?,
        defaultDirectory: data['default_directory'] as String?,
        proxyJump: data['proxy_jump'] as String?,
        keepAliveInterval: data['keep_alive_interval'] as int?,
        updatedAt: now,
      );
    }).toList();

    final credRow = AppDatabase.instance.db.select(
      'SELECT password, passphrase FROM ssh_credentials WHERE connection_id = ?',
      [id],
    ).firstOrNull;
    _connections = _connections.map((c) {
      if (c.id != id) return c;
      return c.copyWith(
        password: credRow?['password'] as String?,
        passphrase: credRow?['passphrase'] as String?,
      );
    }).toList();

    notifyListeners();
  }

  Future<void> deleteConnection(String id) async {
    AppDatabase.instance.db.execute(
      'DELETE FROM ssh_connections WHERE id = ?',
      [id],
    );
    AppDatabase.instance.db.execute(
      'DELETE FROM ssh_credentials WHERE connection_id = ?',
      [id],
    );

    _connections = _connections.where((c) => c.id != id).toList();
    if (_selectedConnectionId == id) {
      _selectedConnectionId = null;
    }
    notifyListeners();
  }

  void openTab(SshTab tab) {
    final exists = _openTabs.any((t) => t.id == tab.id);
    if (exists) {
      _activeTabId = tab.id;
    } else {
      _openTabs = [..._openTabs, tab];
      _activeTabId = tab.id;
    }
    notifyListeners();
  }

  void closeTab(String tabId) {
    final idx = _openTabs.indexWhere((t) => t.id == tabId);
    _openTabs = _openTabs.where((t) => t.id != tabId).toList();

    if (_activeTabId == tabId) {
      _activeTabId = _openTabs.isNotEmpty
          ? _openTabs[(idx < _openTabs.length ? idx : _openTabs.length - 1)].id
          : null;
    }
    notifyListeners();
  }

  void setActiveTab(String? tabId) {
    _activeTabId = tabId;
    notifyListeners();
  }

  void replaceTab(String oldTabId, SshTab newTab) {
    _openTabs = _openTabs.map((t) => t.id == oldTabId ? newTab : t).toList();
    if (_activeTabId == oldTabId) {
      _activeTabId = newTab.id;
    }
    notifyListeners();
  }

  Future<String?> connect(String connectionId) async {
    final conn = getConnection(connectionId);
    if (conn == null) return null;

    final sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';
    _sessions[sessionId] = SshSession(
      id: sessionId,
      connectionId: connectionId,
      status: SshSessionStatus.connecting,
    );
    notifyListeners();

    final result = await _sshService.connect(conn, sessionId: sessionId);

    if (!result.success || result.sessionId == null) {
      final session = _sessions[sessionId];
      if (session != null) {
        session.status = SshSessionStatus.error;
        session.error = result.error;
        notifyListeners();
      }
      return null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    AppDatabase.instance.db.execute(
      'UPDATE ssh_connections SET last_connected_at = ? WHERE id = ?',
      [now, connectionId],
    );
    _connections = _connections
        .map((c) => c.id == connectionId ? c.copyWith(lastConnectedAt: now) : c)
        .toList();
    notifyListeners();

    return result.sessionId;
  }

  Future<void> disconnect(String sessionId) async {
    await _sshService.disconnect(sessionId);
    _sessions.remove(sessionId);

    final tabsToRemove = _openTabs
        .where((t) => t.sessionId == sessionId)
        .map((t) => t.id)
        .toList();
    for (final tabId in tabsToRemove) {
      closeTab(tabId);
    }

    notifyListeners();
  }

  Stream<List<int>> getOutputStream(String sessionId) {
    return _sshService.getOutputStream(sessionId);
  }

  void send(String sessionId, String data) {
    _sshService.send(sessionId, data);
  }

  Future<void> resizePty(String sessionId, int cols, int rows) async {
    await _sshService.resizePty(sessionId, cols, rows);
  }

  @override
  void dispose() {
    _statusSubscription.cancel();
    _sshService.dispose();
    super.dispose();
  }

  void updateSessionStatus(
    String sessionId,
    SshSessionStatus status, {
    String? error,
  }) {
    final session = _sessions[sessionId];
    if (session == null) return;

    session.status = status;
    session.error = error;
    notifyListeners();
  }

  void removeSession(String sessionId) {
    _sessions.remove(sessionId);
    notifyListeners();
  }

  void setSelectedConnection(String? connectionId) {
    _selectedConnectionId = connectionId;
    notifyListeners();
  }
}

final sshProvider = ChangeNotifierProvider<SshNotifier>((ref) {
  final notifier = SshNotifier();
  notifier.loadAll();
  return notifier;
});
