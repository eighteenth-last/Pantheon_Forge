import 'dart:convert';
import 'dart:io';
import 'package:pantheon_forge/core/storage/storage_manager.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 会话记忆服务
/// 每个会话保存为独立的 JSON 文件，文件名为会话 UUID
class SessionMemoryService {
  SessionMemoryService._();
  static final SessionMemoryService instance = SessionMemoryService._();

  /// 保存会话消息到文件
  Future<void> saveSession(String sessionId, List<UnifiedMessage> messages) async {
    final path = StorageManager.instance.getMemoryPath(sessionId);
    final file = File(path);
    
    final data = {
      'sessionId': sessionId,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      mode: FileMode.writeOnly,
    );
  }

  /// 加载会话消息
  List<UnifiedMessage> loadSession(String sessionId) {
    final path = StorageManager.instance.getMemoryPath(sessionId);
    final file = File(path);
    
    if (!file.existsSync()) return [];
    
    try {
      final content = file.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final messages = data['messages'] as List? ?? [];
      
      return messages
          .map((m) => UnifiedMessage.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 删除会话记忆文件
  Future<void> deleteSession(String sessionId) async {
    final path = StorageManager.instance.getMemoryPath(sessionId);
    final file = File(path);
    
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// 列出所有会话 ID
  List<String> listSessions() {
    return StorageManager.instance.listMemoryFiles();
  }

  /// 创建新会话并返回 ID
  String createNewSession() {
    return _uuid.v4();
  }

  /// 获取会话元数据
  Map<String, dynamic>? getSessionMeta(String sessionId) {
    final path = StorageManager.instance.getMemoryPath(sessionId);
    final file = File(path);
    
    if (!file.existsSync()) return null;
    
    try {
      final content = file.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return {
        'sessionId': data['sessionId'],
        'updatedAt': data['updatedAt'],
        'messageCount': (data['messages'] as List?)?.length ?? 0,
      };
    } catch (e) {
      return null;
    }
  }
}
