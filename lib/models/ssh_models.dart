import 'dart:convert';

class SshGroup {
  final String id;
  final String name;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  const SshGroup({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toDbRow() => {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory SshGroup.fromDbRow(Map<String, dynamic> row) => SshGroup(
    id: row['id'] as String,
    name: row['name'] as String,
    sortOrder: row['sort_order'] as int? ?? 0,
    createdAt: row['created_at'] as int,
    updatedAt: row['updated_at'] as int,
  );
}

enum SshAuthType { password, privateKey, agent }

enum SshSessionStatus { connecting, connected, disconnected, error }

class SshConnection {
  final String id;
  final String? groupId;
  final String name;
  final String host;
  final int port;
  final String username;
  final SshAuthType authType;
  final String? password;
  final String? privateKeyPath;
  final String? passphrase;
  final String? startupCommand;
  final String? defaultDirectory;
  final String? proxyJump;
  final int keepAliveInterval;
  final int sortOrder;
  final int? lastConnectedAt;
  final int createdAt;
  final int updatedAt;

  const SshConnection({
    required this.id,
    this.groupId,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = SshAuthType.password,
    this.password,
    this.privateKeyPath,
    this.passphrase,
    this.startupCommand,
    this.defaultDirectory,
    this.proxyJump,
    this.keepAliveInterval = 60,
    this.sortOrder = 0,
    this.lastConnectedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  SshConnection copyWith({
    String? id,
    String? groupId,
    String? name,
    String? host,
    int? port,
    String? username,
    SshAuthType? authType,
    String? password,
    String? privateKeyPath,
    String? passphrase,
    String? startupCommand,
    String? defaultDirectory,
    String? proxyJump,
    int? keepAliveInterval,
    int? sortOrder,
    int? lastConnectedAt,
    int? createdAt,
    int? updatedAt,
  }) => SshConnection(
    id: id ?? this.id,
    groupId: groupId ?? this.groupId,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    authType: authType ?? this.authType,
    password: password ?? this.password,
    privateKeyPath: privateKeyPath ?? this.privateKeyPath,
    passphrase: passphrase ?? this.passphrase,
    startupCommand: startupCommand ?? this.startupCommand,
    defaultDirectory: defaultDirectory ?? this.defaultDirectory,
    proxyJump: proxyJump ?? this.proxyJump,
    keepAliveInterval: keepAliveInterval ?? this.keepAliveInterval,
    sortOrder: sortOrder ?? this.sortOrder,
    lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toDbRow() => {
    'id': id,
    'group_id': groupId,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'auth_type': authType.name,
    'private_key_path': privateKeyPath,
    'startup_command': startupCommand,
    'default_directory': defaultDirectory,
    'proxy_jump': proxyJump,
    'keep_alive_interval': keepAliveInterval,
    'sort_order': sortOrder,
    'last_connected_at': lastConnectedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory SshConnection.fromDbRow(Map<String, dynamic> row, {String? password, String? passphrase}) => SshConnection(
    id: row['id'] as String,
    groupId: row['group_id'] as String?,
    name: row['name'] as String,
    host: row['host'] as String,
    port: row['port'] as int? ?? 22,
    username: row['username'] as String,
    authType: SshAuthType.values.firstWhere(
      (e) => e.name == (row['auth_type'] as String? ?? 'password'),
      orElse: () => SshAuthType.password,
    ),
    password: password ?? row['password'] as String?,
    privateKeyPath: row['private_key_path'] as String?,
    passphrase: passphrase ?? row['passphrase'] as String?,
    startupCommand: row['startup_command'] as String?,
    defaultDirectory: row['default_directory'] as String?,
    proxyJump: row['proxy_jump'] as String?,
    keepAliveInterval: row['keep_alive_interval'] as int? ?? 60,
    sortOrder: row['sort_order'] as int? ?? 0,
    lastConnectedAt: row['last_connected_at'] as int?,
    createdAt: row['created_at'] as int,
    updatedAt: row['updated_at'] as int,
  );

  String get displayHost => '$username@$host:$port';
}

class SshSession {
  final String id;
  final String connectionId;
  SshSessionStatus status;
  String? error;

  SshSession({
    required this.id,
    required this.connectionId,
    this.status = SshSessionStatus.connecting,
    this.error,
  });
}

class SshTab {
  final String id;
  final String type;
  final String? sessionId;
  final String connectionId;
  final String connectionName;
  final String title;
  final String? filePath;
  final SshSessionStatus? status;
  final String? error;

  const SshTab({
    required this.id,
    required this.type,
    this.sessionId,
    required this.connectionId,
    required this.connectionName,
    required this.title,
    this.filePath,
    this.status,
    this.error,
  });

  SshTab copyWith({
    String? id,
    String? type,
    String? sessionId,
    String? connectionId,
    String? connectionName,
    String? title,
    String? filePath,
    SshSessionStatus? status,
    String? error,
  }) => SshTab(
    id: id ?? this.id,
    type: type ?? this.type,
    sessionId: sessionId ?? this.sessionId,
    connectionId: connectionId ?? this.connectionId,
    connectionName: connectionName ?? this.connectionName,
    title: title ?? this.title,
    filePath: filePath ?? this.filePath,
    status: status ?? this.status,
    error: error ?? this.error,
  );
}

class SshFileEntry {
  final String name;
  final String path;
  final String type;
  final int size;
  final int modifyTime;

  const SshFileEntry({
    required this.name,
    required this.path,
    required this.type,
    this.size = 0,
    this.modifyTime = 0,
  });

  bool get isDirectory => type == 'directory';
  bool get isFile => type == 'file';
  bool get isSymlink => type == 'symlink';
}
