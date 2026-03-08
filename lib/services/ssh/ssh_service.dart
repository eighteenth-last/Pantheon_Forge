import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_models.dart';

class SshService {
  static const _connectTimeout = Duration(seconds: 15);
  static const _shellTimeout = Duration(seconds: 10);
  static const _defaultPty = SSHPtyConfig(
    type: 'xterm-256color',
    width: 80,
    height: 24,
  );

  final _sessions = <String, SshServiceSession>{};
  final _outputControllers = <String, StreamController<List<int>>>{};
  final _connectionStatusController =
      StreamController<SshConnectionStatus>.broadcast();

  Stream<SshConnectionStatus> get connectionStatusStream =>
      _connectionStatusController.stream;

  Stream<List<int>> getOutputStream(String sessionId) {
    return _ensureOutputController(sessionId).stream;
  }

  Future<SshConnectionResult> connect(
    SshConnection connection, {
    String? sessionId,
  }) async {
    final resolvedSessionId =
        sessionId ?? 'ssh-${DateTime.now().millisecondsSinceEpoch}';

    if (_sessions.containsKey(resolvedSessionId)) {
      await disconnect(resolvedSessionId, emitStatus: false);
    }

    _ensureOutputController(resolvedSessionId);
    _emitStatus(
      sessionId: resolvedSessionId,
      connectionId: connection.id,
      status: SshSessionStatus.connecting,
    );

    SSHClient? client;

    try {
      client = await _createClient(connection);

      final shell = await _startShell(client).timeout(_shellTimeout);

      final stdoutSubscription = shell.stdout.listen(
        (data) => _writeOutput(resolvedSessionId, data),
        onError: (Object error, StackTrace stackTrace) {
          _handleRemoteFailure(resolvedSessionId, connection.id, error);
        },
      );

      final stderrSubscription = shell.stderr.listen(
        (data) => _writeOutput(resolvedSessionId, data),
        onError: (Object error, StackTrace stackTrace) {
          _handleRemoteFailure(resolvedSessionId, connection.id, error);
        },
      );

      _sessions[resolvedSessionId] = SshServiceSession(
        id: resolvedSessionId,
        connectionId: connection.id,
        client: client,
        shell: shell,
        status: SshSessionStatus.connected,
        stdoutSubscription: stdoutSubscription,
        stderrSubscription: stderrSubscription,
      );

      unawaited(
        shell.done.then(
          (_) => _handleRemoteClosure(
            resolvedSessionId,
            connection.id,
            SshSessionStatus.disconnected,
          ),
          onError: (Object error, StackTrace stackTrace) {
            _handleRemoteFailure(resolvedSessionId, connection.id, error);
          },
        ),
      );

      unawaited(
        client.done.catchError((Object error, StackTrace stackTrace) {
          _handleRemoteFailure(resolvedSessionId, connection.id, error);
        }),
      );

      _emitStatus(
        sessionId: resolvedSessionId,
        connectionId: connection.id,
        status: SshSessionStatus.connected,
      );

      await _runStartupSequence(shell, connection);

      return SshConnectionResult(success: true, sessionId: resolvedSessionId);
    } on Object catch (error) {
      await _cleanupFailedConnect(resolvedSessionId, client);

      final message = _mapConnectionError(error, connection);
      _emitStatus(
        sessionId: resolvedSessionId,
        connectionId: connection.id,
        status: SshSessionStatus.error,
        error: message,
      );

      return SshConnectionResult(success: false, error: message);
    }
  }

  Future<SSHSession> _startShell(SSHClient client) async {
    Object? lastError;

    final attempts = <Future<SSHSession> Function()>[
      () => client.shell(pty: _defaultPty),
      () => client.shell(pty: const SSHPtyConfig(width: 80, height: 24)),
      () => client.shell(),
    ];

    for (final attempt in attempts) {
      try {
        return await attempt();
      } on Object catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        const SshServiceException('Failed to start remote shell.');
  }

  Future<SSHClient> _createClient(SshConnection connection) async {
    final socket = await SSHSocket.connect(
      connection.host,
      connection.port,
    ).timeout(_connectTimeout);

    final keepAliveInterval = connection.keepAliveInterval > 0
        ? Duration(seconds: connection.keepAliveInterval)
        : null;

    switch (connection.authType) {
      case SshAuthType.password:
        final password = connection.password;
        if (password == null || password.isEmpty) {
          throw const SshServiceException('Missing password for SSH login.');
        }
        return SSHClient(
          socket,
          username: connection.username,
          keepAliveInterval: keepAliveInterval,
          onPasswordRequest: () => password,
          onUserInfoRequest: (request) =>
              List<String>.filled(request.prompts.length, password),
        );
      case SshAuthType.privateKey:
        final keyPairs = await _loadPrivateKeys(connection);
        return SSHClient(
          socket,
          username: connection.username,
          keepAliveInterval: keepAliveInterval,
          identities: keyPairs,
        );
      case SshAuthType.agent:
        return SSHClient(
          socket,
          username: connection.username,
          keepAliveInterval: keepAliveInterval,
        );
    }
  }

  Future<List<SSHKeyPair>> _loadPrivateKeys(SshConnection connection) async {
    final privateKeyPath = connection.privateKeyPath;
    if (privateKeyPath == null || privateKeyPath.isEmpty) {
      throw const SshServiceException('Missing private key path.');
    }

    try {
      final pemText = await File(privateKeyPath).readAsString();
      if (connection.passphrase != null && connection.passphrase!.isNotEmpty) {
        return SSHKeyPair.fromPem(pemText, connection.passphrase);
      }
      return SSHKeyPair.fromPem(pemText);
    } on FileSystemException catch (error) {
      throw SshServiceException('Failed to read private key: ${error.message}');
    } on Object catch (error) {
      throw SshServiceException('Failed to parse private key: $error');
    }
  }

  Future<void> _runStartupSequence(
    SSHSession shell,
    SshConnection connection,
  ) async {
    final commands = <String>[];

    if (connection.defaultDirectory != null &&
        connection.defaultDirectory!.trim().isNotEmpty) {
      commands.add('cd ${_shellQuote(connection.defaultDirectory!.trim())}');
    }

    if (connection.startupCommand != null &&
        connection.startupCommand!.trim().isNotEmpty) {
      commands.add(connection.startupCommand!.trim());
    }

    if (commands.isEmpty) {
      return;
    }

    shell.write(Uint8List.fromList(utf8.encode('${commands.join('\n')}\n')));
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  void send(String sessionId, String data) {
    final session = _sessions[sessionId];
    if (session == null || session.status != SshSessionStatus.connected) {
      return;
    }

    session.shell.write(Uint8List.fromList(utf8.encode(data)));
  }

  Future<void> resizePty(String sessionId, int cols, int rows) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }

    final safeCols = cols < 1 ? 1 : cols;
    final safeRows = rows < 1 ? 1 : rows;
    session.shell.resizeTerminal(safeCols, safeRows);
  }

  Future<void> disconnect(String sessionId, {bool emitStatus = true}) async {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      _closeOutputController(sessionId);
      return;
    }

    session.status = SshSessionStatus.disconnected;

    await session.stdoutSubscription.cancel();
    await session.stderrSubscription.cancel();

    session.shell.close();
    session.client.close();

    if (emitStatus) {
      _emitStatus(
        sessionId: sessionId,
        connectionId: session.connectionId,
        status: SshSessionStatus.disconnected,
      );
    }

    _closeOutputController(sessionId);
  }

  Future<void> _cleanupFailedConnect(
    String sessionId,
    SSHClient? client,
  ) async {
    client?.close();
    _sessions.remove(sessionId);
    _closeOutputController(sessionId);
  }

  void _handleRemoteClosure(
    String sessionId,
    String connectionId,
    SshSessionStatus status,
  ) {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      return;
    }

    session.status = status;
    unawaited(session.stdoutSubscription.cancel());
    unawaited(session.stderrSubscription.cancel());

    _emitStatus(
      sessionId: sessionId,
      connectionId: connectionId,
      status: status,
    );

    _closeOutputController(sessionId);
  }

  void _handleRemoteFailure(
    String sessionId,
    String connectionId,
    Object error,
  ) {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      return;
    }

    session.status = SshSessionStatus.error;
    unawaited(session.stdoutSubscription.cancel());
    unawaited(session.stderrSubscription.cancel());

    _emitStatus(
      sessionId: sessionId,
      connectionId: connectionId,
      status: SshSessionStatus.error,
      error: 'SSH session failed: $error',
    );

    _closeOutputController(sessionId);
  }

  void _writeOutput(String sessionId, List<int> data) {
    final controller = _ensureOutputController(sessionId);
    if (!controller.isClosed) {
      controller.add(data);
    }
  }

  StreamController<List<int>> _ensureOutputController(String sessionId) {
    final existing = _outputControllers[sessionId];
    if (existing != null && !existing.isClosed) {
      return existing;
    }

    final controller = StreamController<List<int>>.broadcast();
    _outputControllers[sessionId] = controller;
    return controller;
  }

  void _closeOutputController(String sessionId) {
    final controller = _outputControllers.remove(sessionId);
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }

  void _emitStatus({
    required String sessionId,
    required String connectionId,
    required SshSessionStatus status,
    String? error,
  }) {
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(
        SshConnectionStatus(
          sessionId: sessionId,
          connectionId: connectionId,
          status: status,
          error: error,
        ),
      );
    }
  }

  String _mapConnectionError(Object error, SshConnection connection) {
    if (error is TimeoutException) {
      return 'Connection timed out.';
    }
    if (error is SocketException) {
      if (error.message.contains('Connection refused')) {
        return 'Connection refused by remote host.';
      }
      if (error.message.contains('timed out')) {
        return 'Connection timed out.';
      }
      if (error.message.contains('Failed host lookup')) {
        return 'Unable to resolve host name.';
      }
      return 'Network error: ${error.message}';
    }
    if (error is SSHAuthFailError) {
      switch (connection.authType) {
        case SshAuthType.password:
          return 'Password authentication failed.';
        case SshAuthType.privateKey:
          return 'Private key authentication failed.';
        case SshAuthType.agent:
          return 'SSH agent authentication failed.';
      }
    }
    if (error is SSHChannelRequestError) {
      return 'Remote shell request was rejected.';
    }
    if (error is SshServiceException) {
      return error.message;
    }
    return 'SSH connection failed: $error';
  }

  void dispose() {
    for (final sessionId in _sessions.keys.toList()) {
      unawaited(disconnect(sessionId, emitStatus: false));
    }
    for (final sessionId in _outputControllers.keys.toList()) {
      _closeOutputController(sessionId);
    }
    _connectionStatusController.close();
  }
}

class SshServiceSession {
  final String id;
  final String connectionId;
  final SSHClient client;
  final SSHSession shell;
  final StreamSubscription<Uint8List> stdoutSubscription;
  final StreamSubscription<Uint8List> stderrSubscription;
  SshSessionStatus status;

  SshServiceSession({
    required this.id,
    required this.connectionId,
    required this.client,
    required this.shell,
    required this.stdoutSubscription,
    required this.stderrSubscription,
    required this.status,
  });
}

class SshConnectionResult {
  final bool success;
  final String? sessionId;
  final String? error;

  SshConnectionResult({required this.success, this.sessionId, this.error});
}

class SshConnectionStatus {
  final String sessionId;
  final String connectionId;
  final SshSessionStatus status;
  final String? error;

  SshConnectionStatus({
    required this.sessionId,
    required this.connectionId,
    required this.status,
    this.error,
  });
}

class SshServiceException implements Exception {
  final String message;

  const SshServiceException(this.message);

  @override
  String toString() => message;
}
