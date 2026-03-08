import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:pantheon_forge/core/database/database.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/storage/session_memory_service.dart';

const _uuid = Uuid();

// ════════════════════════ Settings ════════════════════════

class SettingsNotifier extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  void load() {
    final db = AppDatabase.instance;
    final theme = db.getSetting('theme') ?? 'system';
    final language = db.getSetting('language') ?? 'zh';
    final maxTokens = int.tryParse(db.getSetting('maxTokens') ?? '') ?? 32000;
    final temperature =
        double.tryParse(db.getSetting('temperature') ?? '') ?? 0.7;
    final systemPrompt = db.getSetting('systemPrompt') ?? '';
    final autoApprove = db.getSetting('autoApprove') == 'true';
    final thinkingEnabled = db.getSetting('thinkingEnabled') == 'true';
    final activeProviderId = db.getSetting('activeProviderId') ?? '';
    final activeModelId = db.getSetting('activeModelId') ?? '';

    _settings = AppSettings(
      theme: theme,
      language: language,
      maxTokens: maxTokens,
      temperature: temperature,
      systemPrompt: systemPrompt,
      autoApprove: autoApprove,
      thinkingEnabled: thinkingEnabled,
      activeProviderId: activeProviderId,
      activeModelId: activeModelId,
    );
    notifyListeners();
  }

  void update(AppSettings Function(AppSettings) updater) {
    _settings = updater(_settings);
    final db = AppDatabase.instance;
    db.setSetting('theme', _settings.theme);
    db.setSetting('language', _settings.language);
    db.setSetting('maxTokens', _settings.maxTokens.toString());
    db.setSetting('temperature', _settings.temperature.toString());
    db.setSetting('systemPrompt', _settings.systemPrompt);
    db.setSetting('autoApprove', _settings.autoApprove.toString());
    db.setSetting('thinkingEnabled', _settings.thinkingEnabled.toString());
    db.setSetting('activeProviderId', _settings.activeProviderId);
    db.setSetting('activeModelId', _settings.activeModelId);
    notifyListeners();
  }
}

final settingsProvider = ChangeNotifierProvider<SettingsNotifier>((ref) {
  final notifier = SettingsNotifier();
  notifier.load();
  return notifier;
});

// ════════════════════════ UI State ════════════════════════

enum AppMode { agent }

enum NavItem { chat, skills, translate, ssh }

enum ChatView { home, session }

enum RightPanelTab {
  steps,
  plan,
  team,
  files,
  artifacts,
  context,
  skills,
  cron,
}

enum SettingsTab { general, provider, about }

class UIState {
  final AppMode mode;
  final NavItem activeNavItem;
  final ChatView chatView;
  final bool leftSidebarOpen;
  final bool rightPanelOpen;
  final RightPanelTab rightPanelTab;
  final bool settingsPageOpen;
  final SettingsTab settingsTab;
  final bool skillsPageOpen;
  final bool translatePageOpen;
  final bool sshPageOpen;
  final bool sshSidebarOpen;

  const UIState({
    this.mode = AppMode.agent,
    this.activeNavItem = NavItem.chat,
    this.chatView = ChatView.home,
    this.leftSidebarOpen = true,
    this.rightPanelOpen = false,
    this.rightPanelTab = RightPanelTab.steps,
    this.settingsPageOpen = false,
    this.settingsTab = SettingsTab.general,
    this.skillsPageOpen = false,
    this.translatePageOpen = false,
    this.sshPageOpen = false,
    this.sshSidebarOpen = true,
  });

  UIState copyWith({
    AppMode? mode,
    NavItem? activeNavItem,
    ChatView? chatView,
    bool? leftSidebarOpen,
    bool? rightPanelOpen,
    RightPanelTab? rightPanelTab,
    bool? settingsPageOpen,
    SettingsTab? settingsTab,
    bool? skillsPageOpen,
    bool? translatePageOpen,
    bool? sshPageOpen,
    bool? sshSidebarOpen,
  }) => UIState(
    mode: mode ?? this.mode,
    activeNavItem: activeNavItem ?? this.activeNavItem,
    chatView: chatView ?? this.chatView,
    leftSidebarOpen: leftSidebarOpen ?? this.leftSidebarOpen,
    rightPanelOpen: rightPanelOpen ?? this.rightPanelOpen,
    rightPanelTab: rightPanelTab ?? this.rightPanelTab,
    settingsPageOpen: settingsPageOpen ?? this.settingsPageOpen,
    settingsTab: settingsTab ?? this.settingsTab,
    skillsPageOpen: skillsPageOpen ?? this.skillsPageOpen,
    translatePageOpen: translatePageOpen ?? this.translatePageOpen,
    sshPageOpen: sshPageOpen ?? this.sshPageOpen,
    sshSidebarOpen: sshSidebarOpen ?? this.sshSidebarOpen,
  );
}

class UINotifier extends StateNotifier<UIState> {
  UINotifier() : super(const UIState());

  void setMode(AppMode mode) =>
      state = state.copyWith(mode: mode, rightPanelOpen: true);

  void toggleLeftSidebar() =>
      state = state.copyWith(leftSidebarOpen: !state.leftSidebarOpen);

  void toggleRightPanel() =>
      state = state.copyWith(rightPanelOpen: !state.rightPanelOpen);

  void setRightPanelTab(RightPanelTab tab) =>
      state = state.copyWith(rightPanelTab: tab, rightPanelOpen: true);

  void navigateToHome() => state = state.copyWith(
    chatView: ChatView.home,
    settingsPageOpen: false,
    skillsPageOpen: false,
    translatePageOpen: false,
    sshPageOpen: false,
  );

  void navigateToSession() => state = state.copyWith(
    chatView: ChatView.session,
    settingsPageOpen: false,
    skillsPageOpen: false,
    translatePageOpen: false,
    sshPageOpen: false,
  );

  void openSettings({SettingsTab? tab}) => state = state.copyWith(
    settingsPageOpen: true,
    settingsTab: tab ?? SettingsTab.general,
    skillsPageOpen: false,
    translatePageOpen: false,
    sshPageOpen: false,
    leftSidebarOpen: false,
  );

  void closeSettings() => state = state.copyWith(settingsPageOpen: false);

  void setSettingsTab(SettingsTab tab) =>
      state = state.copyWith(settingsTab: tab);

  void openSkills() => state = state.copyWith(
    skillsPageOpen: true,
    settingsPageOpen: false,
    translatePageOpen: false,
    sshPageOpen: false,
    leftSidebarOpen: false,
  );

  void closeSkills() => state = state.copyWith(skillsPageOpen: false);

  void openTranslate() => state = state.copyWith(
    translatePageOpen: true,
    settingsPageOpen: false,
    skillsPageOpen: false,
    sshPageOpen: false,
    leftSidebarOpen: false,
  );

  void closeTranslate() => state = state.copyWith(translatePageOpen: false);

  void openSsh() => state = state.copyWith(
    sshPageOpen: true,
    settingsPageOpen: false,
    skillsPageOpen: false,
    translatePageOpen: false,
    leftSidebarOpen: false,
  );

  void closeSsh() => state = state.copyWith(sshPageOpen: false);

  void toggleSshSidebar() =>
      state = state.copyWith(sshSidebarOpen: !state.sshSidebarOpen);

  void setNavItem(NavItem item) {
    if (item == NavItem.skills) {
      openSkills();
      return;
    }
    if (item == NavItem.translate) {
      openTranslate();
      return;
    }
    if (item == NavItem.ssh) {
      // 如果 SSH 页面已打开，切换侧边栏；否则打开 SSH 页面
      if (state.sshPageOpen) {
        toggleSshSidebar();
      } else {
        openSsh();
      }
      return;
    }
    // chat
    state = state.copyWith(
      activeNavItem: item,
      settingsPageOpen: false,
      skillsPageOpen: false,
      translatePageOpen: false,
      sshPageOpen: false,
      leftSidebarOpen: true,
    );
  }
}

final uiProvider = StateNotifierProvider<UINotifier, UIState>(
  (ref) => UINotifier(),
);

// ════════════════════════ Provider (LLM) State ════════════════════════

class ProviderNotifier extends ChangeNotifier {
  List<AIProvider> _providers = [];
  String _activeProviderId = '';
  String _activeModelId = '';

  List<AIProvider> get providers => _providers;
  String get activeProviderId => _activeProviderId;
  String get activeModelId => _activeModelId;

  AIProvider? get activeProvider {
    if (_activeProviderId.isEmpty) return null;
    try {
      return _providers.firstWhere((p) => p.id == _activeProviderId);
    } catch (_) {
      return null;
    }
  }

  AIModelConfig? get activeModel {
    final prov = activeProvider;
    if (prov == null || prov.models.isEmpty) return null;
    try {
      return prov.models.firstWhere((m) => m.id == _activeModelId);
    } catch (_) {
      if (prov.defaultModel != null && prov.defaultModel!.isNotEmpty) {
        try {
          return prov.models.firstWhere((m) => m.id == prov.defaultModel);
        } catch (_) {}
      }
      return prov.models.first;
    }
  }

  ProviderConfig? get activeProviderConfig {
    final prov = activeProvider;
    final model = activeModel;
    if (prov == null || model == null) return null;
    return ProviderConfig(
      type: prov.type,
      apiKey: prov.apiKey,
      baseUrl: prov.baseUrl.isNotEmpty ? prov.baseUrl : null,
      model: model.id,
    );
  }

  void load() {
    final db = AppDatabase.instance;
    final rows = db.db.select('SELECT * FROM providers ORDER BY created_at');
    _providers = rows.map((r) => AIProvider.fromDbRow(r)).toList();
    _activeProviderId = db.getSetting('activeProviderId') ?? '';
    _activeModelId = db.getSetting('activeModelId') ?? '';
    notifyListeners();
  }

  void addProvider(AIProvider provider) {
    final row = provider.toDbRow();
    AppDatabase.instance.db.execute(
      '''INSERT INTO providers (id, name, type, api_key, base_url, enabled, models_json, default_model, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        row['id'],
        row['name'],
        row['type'],
        row['api_key'],
        row['base_url'],
        row['enabled'],
        row['models_json'],
        row['default_model'],
        row['created_at'],
      ],
    );
    _providers = [..._providers, provider];

    // Auto-activate if this is the first enabled provider with models
    if (_activeProviderId.isEmpty &&
        provider.enabled &&
        provider.models.isNotEmpty) {
      setActive(provider.id, provider.models.first.id);
    }
    notifyListeners();
  }

  void updateProvider(AIProvider provider) {
    final row = provider.toDbRow();
    AppDatabase.instance.db.execute(
      '''UPDATE providers SET name=?, type=?, api_key=?, base_url=?, enabled=?,
         models_json=?, default_model=? WHERE id=?''',
      [
        row['name'],
        row['type'],
        row['api_key'],
        row['base_url'],
        row['enabled'],
        row['models_json'],
        row['default_model'],
        row['id'],
      ],
    );
    _providers = _providers
        .map((p) => p.id == provider.id ? provider : p)
        .toList();
    notifyListeners();
  }

  void removeProvider(String id) {
    AppDatabase.instance.db.execute('DELETE FROM providers WHERE id = ?', [id]);
    _providers = _providers.where((p) => p.id != id).toList();
    if (_activeProviderId == id) {
      _activeProviderId = '';
      _activeModelId = '';
      AppDatabase.instance.setSetting('activeProviderId', '');
      AppDatabase.instance.setSetting('activeModelId', '');
    }
    notifyListeners();
  }

  void setActive(String providerId, String modelId) {
    _activeProviderId = providerId;
    _activeModelId = modelId;
    AppDatabase.instance.setSetting('activeProviderId', providerId);
    AppDatabase.instance.setSetting('activeModelId', modelId);
    notifyListeners();
  }
}

final providerProvider = ChangeNotifierProvider<ProviderNotifier>((ref) {
  final notifier = ProviderNotifier();
  notifier.load();
  return notifier;
});

// ════════════════════════ Chat State ════════════════════════

class ChatNotifier extends ChangeNotifier {
  List<ChatSession> _sessions = [];
  String? _activeSessionId;
  final Map<String, List<UnifiedMessage>> _messageCache = {};
  String? _streamingMessageId;

  List<ChatSession> get sessions => _sessions;
  String? get activeSessionId => _activeSessionId;
  bool get isStreaming => _streamingMessageId != null;
  String? get streamingMessageId => _streamingMessageId;

  ChatSession? get activeSession {
    if (_activeSessionId == null) return null;
    try {
      return _sessions.firstWhere((s) => s.id == _activeSessionId);
    } catch (_) {
      return null;
    }
  }

  ChatSession? getSessionById(String sessionId) {
    try {
      return _sessions.firstWhere((s) => s.id == sessionId);
    } catch (_) {
      return null;
    }
  }

  List<UnifiedMessage> getMessages(String sessionId) {
    return _messageCache[sessionId] ?? [];
  }

  void loadFromDb() {
    final db = AppDatabase.instance;
    final rows = db.db.select(
      '''SELECT s.*, (SELECT COUNT(*) FROM messages WHERE session_id = s.id) as msg_count
         FROM sessions s ORDER BY s.pinned DESC, s.updated_at DESC''',
    );
    _sessions = rows
        .map(
          (r) => ChatSession(
            id: r['id'] as String,
            title: r['title'] as String,
            mode: r['mode'] as String? ?? 'chat',
            projectId: r['project_id'] as String?,
            workingFolder: r['working_folder'] as String?,
            icon: r['icon'] as String?,
            pinned: (r['pinned'] as int? ?? 0) == 1,
            providerId: r['provider_id'] as String?,
            modelId: r['model_id'] as String?,
            createdAt: r['created_at'] as int,
            updatedAt: r['updated_at'] as int,
            messageCount: r['msg_count'] as int? ?? 0,
          ),
        )
        .toList();
    // Auto-restore last active session
    final lastActiveSessionId = db.getSetting('lastActiveSessionId');
    if (lastActiveSessionId != null && lastActiveSessionId.isNotEmpty) {
      final sessionExists = _sessions.any((s) => s.id == lastActiveSessionId);
      if (sessionExists) {
        _activeSessionId = lastActiveSessionId;
        loadMessages(lastActiveSessionId);
      }
    }
    notifyListeners();
  }

  void loadMessages(String sessionId) {
    if (_messageCache.containsKey(sessionId)) return;
    final db = AppDatabase.instance;
    final rows = db.db.select(
      'SELECT * FROM messages WHERE session_id = ? ORDER BY sort_order',
      [sessionId],
    );
    _messageCache[sessionId] = rows.map((r) {
      final contentRaw = r['content'] as String;
      dynamic content;
      try {
        final parsed = jsonDecode(contentRaw);
        if (parsed is List) {
          content = parsed
              .map((e) => ContentBlock.fromJson(e as Map<String, dynamic>))
              .toList();
        } else {
          content = contentRaw;
        }
      } catch (_) {
        content = contentRaw;
      }
      TokenUsage? usage;
      if (r['usage'] != null) {
        try {
          usage = TokenUsage.fromJson(jsonDecode(r['usage'] as String));
        } catch (_) {}
      }
      return UnifiedMessage(
        id: r['id'] as String,
        role: MessageRole.values.firstWhere(
          (e) => e.name == (r['role'] as String),
          orElse: () => MessageRole.user,
        ),
        content: content,
        createdAt: r['created_at'] as int,
        usage: usage,
      );
    }).toList();
    notifyListeners();
  }

  String createSession({
    String mode = 'chat',
    String title = 'New Chat',
    String? projectId,
    String? workingFolder,
    String? icon,
    String? providerId,
    String? modelId,
  }) {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    AppDatabase.instance.db.execute(
      '''INSERT INTO sessions (id, title, mode, project_id, working_folder, icon, provider_id, model_id, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        title,
        mode,
        projectId,
        workingFolder,
        icon,
        providerId,
        modelId,
        now,
        now,
      ],
    );
    final session = ChatSession(
      id: id,
      title: title,
      mode: mode,
      projectId: projectId,
      workingFolder: workingFolder,
      icon: icon,
      providerId: providerId,
      modelId: modelId,
      createdAt: now,
      updatedAt: now,
    );
    _sessions = [session, ..._sessions];
    _messageCache[id] = [];
    setActiveSession(id);
    return id;
  }

  String createLocalProjectSession({
    required String folderPath,
    String mode = 'chat',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final projectId = _uuid.v4();
    final folderName = p.basename(folderPath);
    final projectName = folderName.isEmpty ? folderPath : folderName;

    AppDatabase.instance.db.execute(
      '''INSERT INTO projects (id, name, working_folder, ssh_connection_id, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [projectId, projectName, folderPath, null, now, now],
    );

    return createSession(
      mode: mode,
      title: projectName,
      projectId: projectId,
      workingFolder: folderPath,
      icon: 'folder',
      providerId: refSafeProviderId(),
      modelId: refSafeModelId(),
    );
  }

  String? refSafeProviderId() =>
      AppDatabase.instance.getSetting('activeProviderId');

  String? refSafeModelId() => AppDatabase.instance.getSetting('activeModelId');

  void setActiveSession(String id) {
    _activeSessionId = id;
    loadMessages(id);
    // Save last active session
    AppDatabase.instance.setSetting('lastActiveSessionId', id);
    notifyListeners();
  }

  void addMessage(String sessionId, UnifiedMessage message) {
    final messages = _messageCache[sessionId] ?? [];
    final sortOrder = messages.length;
    String contentStr;
    if (message.content is String) {
      contentStr = message.content as String;
    } else {
      contentStr = jsonEncode(
        (message.content as List<ContentBlock>).map((b) => b.toJson()).toList(),
      );
    }
    AppDatabase.instance.db.execute(
      '''INSERT INTO messages (id, session_id, role, content, created_at, usage, sort_order)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        message.id,
        sessionId,
        message.role.name,
        contentStr,
        message.createdAt,
        message.usage != null ? jsonEncode(message.usage!.toJson()) : null,
        sortOrder,
      ],
    );
    _messageCache[sessionId] = [...messages, message];

    // Save to memory file
    SessionMemoryService.instance.saveSession(
      sessionId,
      _messageCache[sessionId]!,
    );

    // Update session title from first user message
    if (message.role == MessageRole.user && messages.isEmpty) {
      final title = message.textContent.length > 50
          ? '${message.textContent.substring(0, 50)}...'
          : message.textContent;
      if (title.isNotEmpty) {
        _updateSessionTitle(sessionId, title);
      }
    }
    _touchSession(sessionId);
    notifyListeners();
  }

  void updateLastAssistantMessage(String sessionId, UnifiedMessage message) {
    final messages = _messageCache[sessionId] ?? [];
    if (messages.isEmpty) return;
    final idx = messages.lastIndexWhere((m) => m.id == message.id);
    if (idx == -1) return;
    final updated = List<UnifiedMessage>.from(messages);
    updated[idx] = message;
    _messageCache[sessionId] = updated;
    // Persist
    String contentStr;
    if (message.content is String) {
      contentStr = message.content as String;
    } else {
      contentStr = jsonEncode(
        (message.content as List<ContentBlock>).map((b) => b.toJson()).toList(),
      );
    }
    AppDatabase.instance.db
        .execute('UPDATE messages SET content = ?, usage = ? WHERE id = ?', [
          contentStr,
          message.usage != null ? jsonEncode(message.usage!.toJson()) : null,
          message.id,
        ]);
    // Save to memory file
    SessionMemoryService.instance.saveSession(sessionId, updated);
    notifyListeners();
  }

  void setStreaming(String? messageId) {
    _streamingMessageId = messageId;
    notifyListeners();
  }

  void deleteSession(String id) {
    AppDatabase.instance.db.execute(
      'DELETE FROM messages WHERE session_id = ?',
      [id],
    );
    AppDatabase.instance.db.execute('DELETE FROM sessions WHERE id = ?', [id]);
    _sessions = _sessions.where((s) => s.id != id).toList();
    _messageCache.remove(id);
    // Delete memory file
    SessionMemoryService.instance.deleteSession(id);
    if (_activeSessionId == id) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.first.id : null;
    }
    notifyListeners();
  }

  void togglePin(String id) {
    final session = _sessions.firstWhere((s) => s.id == id);
    final newPinned = !session.pinned;
    AppDatabase.instance.db.execute(
      'UPDATE sessions SET pinned = ? WHERE id = ?',
      [newPinned ? 1 : 0, id],
    );
    _sessions = _sessions
        .map((s) => s.id == id ? s.copyWith(pinned: newPinned) : s)
        .toList();
    _sessions.sort((a, b) {
      if (a.pinned && !b.pinned) return -1;
      if (!a.pinned && b.pinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    notifyListeners();
  }

  void clearMessages(String sessionId) {
    AppDatabase.instance.db.execute(
      'DELETE FROM messages WHERE session_id = ?',
      [sessionId],
    );
    _messageCache[sessionId] = [];
    // Clear memory file
    SessionMemoryService.instance.saveSession(sessionId, []);
    notifyListeners();
  }

  void _updateSessionTitle(String sessionId, String title) {
    AppDatabase.instance.db.execute(
      'UPDATE sessions SET title = ? WHERE id = ?',
      [title, sessionId],
    );
    _sessions = _sessions
        .map((s) => s.id == sessionId ? s.copyWith(title: title) : s)
        .toList();
  }

  void _touchSession(String sessionId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    AppDatabase.instance.db.execute(
      'UPDATE sessions SET updated_at = ? WHERE id = ?',
      [now, sessionId],
    );
    _sessions = _sessions
        .map((s) => s.id == sessionId ? s.copyWith(updatedAt: now) : s)
        .toList();
  }
}

final chatProvider = ChangeNotifierProvider<ChatNotifier>((ref) {
  final notifier = ChatNotifier();
  notifier.loadFromDb();
  return notifier;
});
