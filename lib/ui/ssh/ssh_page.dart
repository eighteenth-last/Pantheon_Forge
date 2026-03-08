import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/models/ssh_models.dart';
import 'package:pantheon_forge/providers/ssh_provider.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:xterm/xterm.dart';

class SshPage extends ConsumerStatefulWidget {
  const SshPage({super.key});

  @override
  ConsumerState<SshPage> createState() => _SshPageState();
}

class _SshPageState extends ConsumerState<SshPage> {
  bool _showForm = false;
  String? _editingConnectionId;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ssh = ref.watch(sshProvider);
    final ui = ref.watch(uiProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // SSH 连接列表（可收起）
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: ui.sshSidebarOpen ? 280 : 0,
          child: ui.sshSidebarOpen
              ? _buildConnectionList(ssh, colorScheme)
              : const SizedBox.shrink(),
        ),
        // 缁堢鍖哄煙
        Expanded(child: _buildTerminalArea(ssh, colorScheme)),
      ],
    );
  }

  Widget _buildConnectionList(SshNotifier ssh, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'SSH 连接',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () {
                    setState(() {
                      _showForm = true;
                      _editingConnectionId = null;
                    });
                  },
                  tooltip: '添加连接',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: '搜索连接...',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
            ),
          ),
          // 连接鍒楄〃
          Expanded(child: _buildConnectionListContent(ssh, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildConnectionListContent(SshNotifier ssh, ColorScheme colorScheme) {
    final connections = ssh.connections.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.host.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // 按分组组织
    final grouped = <String?, List<SshConnection>>{};
    for (final conn in connections) {
      grouped.putIfAbsent(conn.groupId, () => []).add(conn);
    }

    if (connections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal,
              size: 48,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无 SSH 连接',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加连接'),
              onPressed: () {
                setState(() {
                  _showForm = true;
                  _editingConnectionId = null;
                });
              },
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        // 鏈垎缁勭殑连接
        if (grouped.containsKey(null))
          ...grouped[null]!.map(
            (conn) => _buildConnectionItem(conn, ssh, colorScheme),
          ),
        // 分组连接
        for (final groupId in grouped.keys.where((id) => id != null))
          _buildGroupSection(groupId!, grouped[groupId]!, ssh, colorScheme),
      ],
    );
  }

  Widget _buildGroupSection(
    String groupId,
    List<SshConnection> connections,
    SshNotifier ssh,
    ColorScheme colorScheme,
  ) {
    final group = ssh.getGroup(groupId);

    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(
        group?.name ?? '未分组',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      children: connections
          .map((conn) => _buildConnectionItem(conn, ssh, colorScheme) as Widget)
          .toList(),
    );
  }

  Widget _buildConnectionItem(
    SshConnection conn,
    SshNotifier ssh,
    ColorScheme colorScheme,
  ) {
    final isSelected = ssh.selectedConnectionId == conn.id;
    final session = ssh.sessions.values
        .where((s) => s.connectionId == conn.id)
        .firstOrNull;
    final isConnected = session?.status == SshSessionStatus.connected;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => ssh.setSelectedConnection(conn.id),
        onDoubleTap: () => _connect(conn, ssh),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isConnected ? Icons.terminal : Icons.computer,
                size: 16,
                color: isConnected
                    ? Colors.green
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conn.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      conn.displayHost,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 16,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      setState(() {
                        _showForm = true;
                        _editingConnectionId = conn.id;
                      });
                      break;
                    case 'delete':
                      _deleteConnection(conn, ssh);
                      break;
                    case 'duplicate':
                      _duplicateConnection(conn, ssh);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'duplicate', child: Text('复制')),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalArea(SshNotifier ssh, ColorScheme colorScheme) {
    if (_showForm) {
      return _SshConnectionForm(
        connectionId: _editingConnectionId,
        onSave: () => setState(() => _showForm = false),
        onCancel: () => setState(() => _showForm = false),
      );
    }

    final selectedId = ssh.selectedConnectionId;
    final connection = selectedId != null
        ? ssh.getConnection(selectedId)
        : null;

    if (connection == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              '选择一个连接或创建新连接',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return _buildMainContent(connection, ssh, colorScheme);
  }

  void _showConnectionForm(BuildContext context, WidgetRef ref) {
    setState(() {
      _showForm = true;
      _editingConnectionId = null;
    });
  }

  Widget _buildMainContent(
    SshConnection connection,
    SshNotifier ssh,
    ColorScheme colorScheme,
  ) {
    final ui = ref.watch(uiProvider);

    return Column(
      children: [
        // 顶部工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.terminal, size: 18, color: Colors.green[400]),
              const SizedBox(width: 8),
              Text(
                connection.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${connection.username}@${connection.host}:${connection.port}',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _showConnectionForm(context, ref),
                tooltip: '新建连接',
              ),
            ],
          ),
        ),
        // 缁堢鍖哄煙
        Expanded(
          child: ssh.sessions.values.any((s) => s.connectionId == connection.id)
              ? _SshTerminalView(
                  sessionId: ssh.sessions.values
                      .firstWhere(
                        (s) => s.connectionId == connection.id,
                        orElse: () => SshSession(
                          id: '',
                          connectionId: connection.id,
                          status: SshSessionStatus.disconnected,
                        ),
                      )
                      .id,
                  connection: connection,
                )
              : _buildConnectionInfo(connection, colorScheme),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 64,
            color: colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            '选择一个连接或创建新连接',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionView(
    SshConnection connection,
    SshNotifier ssh,
    ColorScheme colorScheme,
  ) {
    // 鏌ユ壘璇ヨ繛鎺ョ殑浼氳瘽锛堝彲鑳芥湁澶氫釜锛屽彇鏈€鏂扮殑涓€涓級
    final sessions = ssh.sessions.values
        .where((s) => s.connectionId == connection.id)
        .toList();
    final session = sessions.isNotEmpty ? sessions.last : null;

    return Column(
      children: [
        // 标题栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                session?.status == SshSessionStatus.connected
                    ? Icons.terminal
                    : Icons.computer,
                color: session?.status == SshSessionStatus.connected
                    ? Colors.green
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      connection.displayHost,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              if (session?.status != SshSessionStatus.connected)
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('连接'),
                  onPressed: () => _connect(connection, ssh),
                )
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('断开'),
                  onPressed: () => _disconnect(session!.id, ssh),
                ),
            ],
          ),
        ),
        // 缁堢鍖哄煙
        Expanded(
          child: session?.status == SshSessionStatus.connected
              ? _SshTerminalView(sessionId: session!.id, connection: connection)
              : _buildConnectionInfo(connection, colorScheme),
        ),
      ],
    );
  }

  Widget _buildConnectionInfo(SshConnection conn, ColorScheme colorScheme) {
    final ssh = ref.watch(sshProvider);
    final session = ssh.sessions.values
        .where((s) => s.connectionId == conn.id)
        .firstOrNull;
    final isConnecting = session?.status == SshSessionStatus.connecting;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '连接信息',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                _infoRow('主机', conn.host, colorScheme),
                _infoRow('端口', conn.port.toString(), colorScheme),
                _infoRow('用户名', conn.username, colorScheme),
                _infoRow('认证方式', _authTypeLabel(conn.authType), colorScheme),
                if (conn.defaultDirectory != null)
                  _infoRow('默认目录', conn.defaultDirectory!, colorScheme),
                if (conn.startupCommand != null)
                  _infoRow('启动命令', conn.startupCommand!, colorScheme),
                const SizedBox(height: 20),
                if (isConnecting)
                  const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('正在连接...'),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('连接'),
                      onPressed: () => _connect(conn, ref.read(sshProvider)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  String _authTypeLabel(SshAuthType type) {
    switch (type) {
      case SshAuthType.password:
        return '密码';
      case SshAuthType.privateKey:
        return '私钥';
      case SshAuthType.agent:
        return 'SSH Agent';
    }
  }

  Future<void> _connect(SshConnection conn, SshNotifier ssh) async {
    final sessionId = await ssh.connect(conn.id);
    if (sessionId != null) {
      // 连接成功时 UI 会通过 session.status 自动切换到终端视图
    } else {
      // 连接失败时显示错误信息
      final session = ssh.sessions.values.firstWhere(
        (s) => s.connectionId == conn.id,
        orElse: () => SshSession(
          id: '',
          connectionId: conn.id,
          status: SshSessionStatus.error,
        ),
      );
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接失败'),
            content: Text(session.error ?? '未知错误'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _disconnect(String sessionId, SshNotifier ssh) async {
    await ssh.disconnect(sessionId);
  }

  void _deleteConnection(SshConnection conn, SshNotifier ssh) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除连接'),
        content: Text('确定要删除连接 "${conn.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ssh.deleteConnection(conn.id);
    }
  }

  Future<void> _duplicateConnection(SshConnection conn, SshNotifier ssh) async {
    await ssh.createConnection(
      name: '${conn.name} (副本)',
      host: conn.host,
      port: conn.port,
      username: conn.username,
      authType: conn.authType,
      privateKeyPath: conn.privateKeyPath,
      groupId: conn.groupId,
      startupCommand: conn.startupCommand,
      defaultDirectory: conn.defaultDirectory,
      proxyJump: conn.proxyJump,
      keepAliveInterval: conn.keepAliveInterval,
    );
  }
}

class _SshConnectionForm extends ConsumerStatefulWidget {
  final String? connectionId;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _SshConnectionForm({
    this.connectionId,
    required this.onSave,
    required this.onCancel,
  });

  @override
  ConsumerState<_SshConnectionForm> createState() => _SshConnectionFormState();
}

class _SshConnectionFormState extends ConsumerState<_SshConnectionForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _startupCommandController = TextEditingController();
  final _defaultDirController = TextEditingController();
  final _proxyJumpController = TextEditingController();
  final _keepAliveController = TextEditingController(text: '60');

  SshAuthType _authType = SshAuthType.password;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    if (widget.connectionId != null) {
      final ssh = ref.read(sshProvider);
      final conn = ssh.getConnection(widget.connectionId!);
      if (conn != null) {
        _nameController.text = conn.name;
        _hostController.text = conn.host;
        _portController.text = conn.port.toString();
        _usernameController.text = conn.username;
        _authType = conn.authType;
        _passwordController.text = conn.password ?? ''; // 鍔犺浇密码
        _privateKeyController.text = conn.privateKeyPath ?? '';
        _startupCommandController.text = conn.startupCommand ?? '';
        _defaultDirController.text = conn.defaultDirectory ?? '';
        _proxyJumpController.text = conn.proxyJump ?? '';
        _keepAliveController.text = conn.keepAliveInterval.toString();
        _selectedGroupId = conn.groupId;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _startupCommandController.dispose();
    _defaultDirController.dispose();
    _proxyJumpController.dispose();
    _keepAliveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ssh = ref.watch(sshProvider);

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.connectionId != null ? '编辑连接' : '新建连接',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                // 鍩烘湰淇℃伅
                _buildTextField(
                  _nameController,
                  '名称',
                  Icons.label_outline,
                  required: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTextField(
                        _hostController,
                        '主机',
                        Icons.computer,
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        _portController,
                        '端口',
                        Icons.numbers,
                        required: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  _usernameController,
                  '用户名',
                  Icons.person_outline,
                  required: true,
                ),
                const SizedBox(height: 16),
                // 认证方式
                Text(
                  '认证方式',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<SshAuthType>(
                  segments: const [
                    ButtonSegment(
                      value: SshAuthType.password,
                      label: Text('密码'),
                    ),
                    ButtonSegment(
                      value: SshAuthType.privateKey,
                      label: Text('私钥'),
                    ),
                    ButtonSegment(
                      value: SshAuthType.agent,
                      label: Text('Agent'),
                    ),
                  ],
                  selected: {_authType},
                  onSelectionChanged: (types) =>
                      setState(() => _authType = types.first),
                ),
                const SizedBox(height: 12),
                if (_authType == SshAuthType.password)
                  _buildTextField(
                    _passwordController,
                    '密码',
                    Icons.lock_outline,
                    obscure: true,
                  )
                else if (_authType == SshAuthType.privateKey)
                  _buildTextField(_privateKeyController, '私钥路径', Icons.key),
                const SizedBox(height: 16),
                // 高级设置
                ExpansionTile(
                  title: const Text('高级设置'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildTextField(
                            _startupCommandController,
                            '启动命令',
                            Icons.terminal,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            _defaultDirController,
                            '默认目录',
                            Icons.folder_outlined,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            _proxyJumpController,
                            '代理跳转',
                            Icons.swap_horiz,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            _keepAliveController,
                            '心跳间隔 (秒)',
                            Icons.timer_outlined,
                          ),
                          const SizedBox(height: 12),
                          // 分组閫夋嫨
                          DropdownButtonFormField<String>(
                            value: _selectedGroupId,
                            decoration: const InputDecoration(
                              labelText: '分组',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('无分组'),
                              ),
                              ...ssh.groups.map(
                                (g) => DropdownMenuItem(
                                  value: g.id,
                                  child: Text(g.name),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedGroupId = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // 鎸夐挳
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: widget.onCancel,
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(onPressed: _save, child: const Text('保存')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: required
          ? (v) => v == null || v.isEmpty ? '请输入$label' : null
          : null,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final ssh = ref.read(sshProvider);

    if (widget.connectionId != null) {
      await ssh.updateConnection(widget.connectionId!, {
        'name': _nameController.text,
        'host': _hostController.text,
        'port': int.tryParse(_portController.text) ?? 22,
        'username': _usernameController.text,
        'auth_type': _authType.name,
        'private_key_path': _privateKeyController.text.isEmpty
            ? null
            : _privateKeyController.text,
        'group_id': _selectedGroupId,
        'startup_command': _startupCommandController.text.isEmpty
            ? null
            : _startupCommandController.text,
        'default_directory': _defaultDirController.text.isEmpty
            ? null
            : _defaultDirController.text,
        'proxy_jump': _proxyJumpController.text.isEmpty
            ? null
            : _proxyJumpController.text,
        'keep_alive_interval': int.tryParse(_keepAliveController.text) ?? 60,
      });
    } else {
      await ssh.createConnection(
        name: _nameController.text,
        host: _hostController.text,
        port: int.tryParse(_portController.text) ?? 22,
        username: _usernameController.text,
        authType: _authType,
        password: _passwordController.text,
        privateKeyPath: _privateKeyController.text.isEmpty
            ? null
            : _privateKeyController.text,
        groupId: _selectedGroupId,
        startupCommand: _startupCommandController.text.isEmpty
            ? null
            : _startupCommandController.text,
        defaultDirectory: _defaultDirController.text.isEmpty
            ? null
            : _defaultDirController.text,
        proxyJump: _proxyJumpController.text.isEmpty
            ? null
            : _proxyJumpController.text,
        keepAliveInterval: int.tryParse(_keepAliveController.text) ?? 60,
      );
    }

    widget.onSave();
  }
}

class _SshTerminalView extends ConsumerStatefulWidget {
  final String sessionId;
  final SshConnection connection;

  const _SshTerminalView({required this.sessionId, required this.connection});

  @override
  ConsumerState<_SshTerminalView> createState() => _SshTerminalViewState();
}

class _SshTerminalViewState extends ConsumerState<_SshTerminalView>
    with AutomaticKeepAliveClientMixin {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  late final FocusNode _terminalFocusNode;
  StreamSubscription<String>? _outputSubscription;
  String _title = '';
  bool _hasFocus = false;

  bool get _useHardwareKeyboardOnly {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => true,
      TargetPlatform.linux => true,
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _title = widget.connection.name;
    _terminal = Terminal(maxLines: 10000);
    _terminalController = TerminalController();
    _terminalFocusNode = FocusNode();
    _terminal.onOutput = _sendToSession;
    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      ref.read(sshProvider).resizePty(widget.sessionId, width, height);
    };
    _terminal.onTitleChange = (title) {
      if (!mounted || title.trim().isEmpty) return;
      setState(() => _title = title.trim());
    };
    _terminalFocusNode.addListener(_handleFocusChange);
    _listenToOutput();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _terminalFocusNode.requestFocus();
      }
    });
  }

  void _sendToSession(String data) {
    ref.read(sshProvider).send(widget.sessionId, data);
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _terminalFocusNode.hasFocus);
  }

  void _listenToOutput() {
    final ssh = ref.read(sshProvider);
    _outputSubscription = ssh
        .getOutputStream(widget.sessionId)
        .transform(utf8.decoder)
        .listen(
          _terminal.write,
          onError: (Object error, StackTrace stackTrace) {
            _terminal.write('\r\n[SSH stream error] $error\r\n');
          },
          onDone: () {
            _terminal.write('\r\n[SSH session closed]\r\n');
          },
        );
  }

  Future<void> _handleSecondaryTap() async {
    final selection = _terminalController.selection;
    if (selection != null) {
      final text = _terminal.buffer.getText(selection);
      _terminalController.clearSelection();
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }

    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _terminal.paste(text);
    }
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _terminalFocusNode.removeListener(_handleFocusChange);
    _terminalFocusNode.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      color: const Color(0xFF0B0B0B),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: Colors.green[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    '${widget.connection.username}@${widget.connection.host}:${widget.connection.port}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hasFocus ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TerminalView(
              _terminal,
              controller: _terminalController,
              focusNode: _terminalFocusNode,
              autofocus: true,
              backgroundOpacity: 1,
              hardwareKeyboardOnly: _useHardwareKeyboardOnly,
              padding: const EdgeInsets.all(12),
              textStyle: const TerminalStyle(fontSize: 14, height: 1.2),
              theme: TerminalThemes.defaultTheme,
              onSecondaryTapDown: (details, offset) => _handleSecondaryTap(),
            ),
          ),
        ],
      ),
    );
  }
}
