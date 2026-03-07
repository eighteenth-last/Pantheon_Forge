import 'dart:convert';

// ──────────────────── Provider Types ────────────────────

enum ProviderType {
  openai('openai'),
  anthropic('anthropic');

  const ProviderType(this.value);
  final String value;

  static ProviderType fromString(String s) {
    return ProviderType.values.firstWhere(
      (e) => e.value == s,
      orElse: () => ProviderType.openai,
    );
  }
}

enum ModelCategory { chat, speech, embedding, image }

// ──────────────────── AI Model Config ────────────────────

class AIModelConfig {
  final String id;
  final String name;
  final bool enabled;
  final ProviderType? type;
  final ModelCategory category;
  final int? contextLength;
  final int? maxOutputTokens;
  final bool supportsVision;
  final bool supportsFunctionCall;
  final bool supportsThinking;

  const AIModelConfig({
    required this.id,
    required this.name,
    this.enabled = true,
    this.type,
    this.category = ModelCategory.chat,
    this.contextLength,
    this.maxOutputTokens,
    this.supportsVision = false,
    this.supportsFunctionCall = true,
    this.supportsThinking = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'enabled': enabled,
    'type': type?.value, 'category': category.name,
    'contextLength': contextLength, 'maxOutputTokens': maxOutputTokens,
    'supportsVision': supportsVision, 'supportsFunctionCall': supportsFunctionCall,
    'supportsThinking': supportsThinking,
  };

  factory AIModelConfig.fromJson(Map<String, dynamic> json) => AIModelConfig(
    id: json['id'] as String,
    name: json['name'] as String? ?? json['id'] as String,
    enabled: json['enabled'] as bool? ?? true,
    type: json['type'] != null ? ProviderType.fromString(json['type'] as String) : null,
    category: ModelCategory.values.firstWhere(
      (e) => e.name == (json['category'] as String? ?? 'chat'),
      orElse: () => ModelCategory.chat,
    ),
    contextLength: json['contextLength'] as int?,
    maxOutputTokens: json['maxOutputTokens'] as int?,
    supportsVision: json['supportsVision'] as bool? ?? false,
    supportsFunctionCall: json['supportsFunctionCall'] as bool? ?? true,
    supportsThinking: json['supportsThinking'] as bool? ?? false,
  );

  AIModelConfig copyWith({
    String? id, String? name, bool? enabled, ProviderType? type,
    ModelCategory? category, int? contextLength, int? maxOutputTokens,
    bool? supportsVision, bool? supportsFunctionCall, bool? supportsThinking,
  }) => AIModelConfig(
    id: id ?? this.id, name: name ?? this.name, enabled: enabled ?? this.enabled,
    type: type ?? this.type, category: category ?? this.category,
    contextLength: contextLength ?? this.contextLength,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    supportsVision: supportsVision ?? this.supportsVision,
    supportsFunctionCall: supportsFunctionCall ?? this.supportsFunctionCall,
    supportsThinking: supportsThinking ?? this.supportsThinking,
  );
}

// ──────────────────── AI Provider ────────────────────

class AIProvider {
  final String id;
  final String name;
  final ProviderType type;
  final String apiKey;
  final String baseUrl;
  final bool enabled;
  final List<AIModelConfig> models;
  final String? defaultModel;
  final int createdAt;

  const AIProvider({
    required this.id, required this.name, required this.type,
    this.apiKey = '', this.baseUrl = '', this.enabled = false,
    this.models = const [], this.defaultModel, required this.createdAt,
  });

  AIProvider copyWith({
    String? id, String? name, ProviderType? type, String? apiKey,
    String? baseUrl, bool? enabled, List<AIModelConfig>? models,
    String? defaultModel, int? createdAt,
  }) => AIProvider(
    id: id ?? this.id, name: name ?? this.name, type: type ?? this.type,
    apiKey: apiKey ?? this.apiKey, baseUrl: baseUrl ?? this.baseUrl,
    enabled: enabled ?? this.enabled, models: models ?? this.models,
    defaultModel: defaultModel ?? this.defaultModel,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toDbRow() => {
    'id': id, 'name': name, 'type': type.value,
    'api_key': apiKey, 'base_url': baseUrl,
    'enabled': enabled ? 1 : 0,
    'models_json': jsonEncode(models.map((m) => m.toJson()).toList()),
    'default_model': defaultModel, 'created_at': createdAt,
  };

  factory AIProvider.fromDbRow(Map<String, dynamic> row) {
    final modelsRaw = row['models_json'] as String? ?? '[]';
    final modelsList = (jsonDecode(modelsRaw) as List)
        .map((e) => AIModelConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    return AIProvider(
      id: row['id'] as String,
      name: row['name'] as String,
      type: ProviderType.fromString(row['type'] as String),
      apiKey: row['api_key'] as String? ?? '',
      baseUrl: row['base_url'] as String? ?? '',
      enabled: (row['enabled'] as int? ?? 0) == 1,
      models: modelsList,
      defaultModel: row['default_model'] as String?,
      createdAt: row['created_at'] as int,
    );
  }
}

// ──────────────────── Provider Config (for API calls) ────────────────────

class ProviderConfig {
  final ProviderType type;
  final String apiKey;
  final String? baseUrl;
  final String model;
  final int maxTokens;
  final double temperature;
  final String? systemPrompt;
  final bool thinkingEnabled;

  const ProviderConfig({
    required this.type, required this.apiKey, this.baseUrl,
    required this.model, this.maxTokens = 32000, this.temperature = 0.7,
    this.systemPrompt, this.thinkingEnabled = false,
  });
}

// ──────────────────── Messages ────────────────────

enum MessageRole { system, user, assistant, tool }

class TokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int? reasoningTokens;

  const TokenUsage({
    this.inputTokens = 0, this.outputTokens = 0, this.reasoningTokens,
  });

  Map<String, dynamic> toJson() => {
    'inputTokens': inputTokens, 'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
  };

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
    inputTokens: json['inputTokens'] as int? ?? 0,
    outputTokens: json['outputTokens'] as int? ?? 0,
    reasoningTokens: json['reasoningTokens'] as int?,
  );
}

class ContentBlock {
  final String type; // 'text', 'image', 'tool_use', 'tool_result', 'thinking'
  final String? text;
  final String? thinking;
  final String? toolCallId;
  final String? toolName;
  final Map<String, dynamic>? toolInput;
  final String? toolResultContent;
  final bool? isError;

  const ContentBlock({
    required this.type, this.text, this.thinking,
    this.toolCallId, this.toolName, this.toolInput,
    this.toolResultContent, this.isError,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type};
    if (text != null) map['text'] = text;
    if (thinking != null) map['thinking'] = thinking;
    if (toolCallId != null) map['toolCallId'] = toolCallId;
    if (toolName != null) map['toolName'] = toolName;
    if (toolInput != null) map['toolInput'] = toolInput;
    if (toolResultContent != null) map['toolResultContent'] = toolResultContent;
    if (isError != null) map['isError'] = isError;
    return map;
  }

  factory ContentBlock.fromJson(Map<String, dynamic> json) => ContentBlock(
    type: json['type'] as String,
    text: json['text'] as String?,
    thinking: json['thinking'] as String?,
    toolCallId: json['toolCallId'] as String?,
    toolName: json['toolName'] as String?,
    toolInput: json['toolInput'] as Map<String, dynamic>?,
    toolResultContent: json['toolResultContent'] as String?,
    isError: json['isError'] as bool?,
  );
}

class UnifiedMessage {
  final String id;
  final MessageRole role;
  final dynamic content; // String or List<ContentBlock>
  final int createdAt;
  final TokenUsage? usage;

  const UnifiedMessage({
    required this.id, required this.role, required this.content,
    required this.createdAt, this.usage,
  });

  String get textContent {
    if (content is String) return content as String;
    if (content is List) {
      return (content as List)
          .whereType<ContentBlock>()
          .where((b) => b.type == 'text')
          .map((b) => b.text ?? '')
          .join('\n');
    }
    return '';
  }

  List<ContentBlock> get blocks {
    if (content is List) return (content as List).cast<ContentBlock>();
    return [ContentBlock(type: 'text', text: content as String)];
  }

  bool get hasToolCalls => blocks.any((b) => b.type == 'tool_use');

  Map<String, dynamic> toJson() {
    dynamic contentJson;
    if (content is String) {
      contentJson = content;
    } else if (content is List<ContentBlock>) {
      contentJson = (content as List<ContentBlock>).map((b) => b.toJson()).toList();
    }
    return {
      'id': id, 'role': role.name, 'content': contentJson,
      'createdAt': createdAt,
      if (usage != null) 'usage': usage!.toJson(),
    };
  }

  factory UnifiedMessage.fromJson(Map<String, dynamic> json) {
    dynamic content;
    if (json['content'] is String) {
      content = json['content'] as String;
    } else if (json['content'] is List) {
      content = (json['content'] as List)
          .map((e) => ContentBlock.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      content = '';
    }
    return UnifiedMessage(
      id: json['id'] as String,
      role: MessageRole.values.firstWhere(
        (e) => e.name == (json['role'] as String),
        orElse: () => MessageRole.user,
      ),
      content: content,
      createdAt: json['createdAt'] as int? ?? 0,
      usage: json['usage'] != null
          ? TokenUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
    );
  }
}

// ──────────────────── Stream Events ────────────────────

enum StreamEventType {
  messageStart, textDelta, thinkingDelta,
  toolCallStart, toolCallDelta, toolCallEnd,
  messageEnd, error,
}

class StreamEvent {
  final StreamEventType type;
  final String? text;
  final String? thinking;
  final String? toolCallId;
  final String? toolName;
  final String? argumentsDelta;
  final Map<String, dynamic>? toolCallInput;
  final String? stopReason;
  final TokenUsage? usage;
  final String? errorMessage;

  const StreamEvent({
    required this.type, this.text, this.thinking,
    this.toolCallId, this.toolName, this.argumentsDelta,
    this.toolCallInput, this.stopReason, this.usage,
    this.errorMessage,
  });
}

// ──────────────────── Tool Definition ────────────────────

class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const ToolDefinition({
    required this.name, required this.description, required this.inputSchema,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'description': description, 'inputSchema': inputSchema,
  };
}

// ──────────────────── Session ────────────────────

class ChatSession {
  final String id;
  final String title;
  final String mode;
  final String? projectId;
  final String? workingFolder;
  final String? icon;
  final bool pinned;
  final String? providerId;
  final String? modelId;
  final int createdAt;
  final int updatedAt;
  final int messageCount;

  const ChatSession({
    required this.id, required this.title, this.mode = 'chat',
    this.projectId, this.workingFolder, this.icon, this.pinned = false,
    this.providerId, this.modelId,
    required this.createdAt, required this.updatedAt, this.messageCount = 0,
  });

  ChatSession copyWith({
    String? title, String? mode, String? projectId, String? workingFolder,
    String? icon, bool? pinned, String? providerId, String? modelId,
    int? updatedAt, int? messageCount,
  }) => ChatSession(
    id: id, title: title ?? this.title, mode: mode ?? this.mode,
    projectId: projectId ?? this.projectId,
    workingFolder: workingFolder ?? this.workingFolder,
    icon: icon ?? this.icon, pinned: pinned ?? this.pinned,
    providerId: providerId ?? this.providerId,
    modelId: modelId ?? this.modelId,
    createdAt: createdAt, updatedAt: updatedAt ?? this.updatedAt,
    messageCount: messageCount ?? this.messageCount,
  );
}

// ──────────────────── Project ────────────────────

class Project {
  final String id;
  final String name;
  final String? workingFolder;
  final String? sshConnectionId;
  final int createdAt;
  final int updatedAt;

  const Project({
    required this.id, required this.name, this.workingFolder,
    this.sshConnectionId, required this.createdAt, required this.updatedAt,
  });
}

// ──────────────────── App Settings ────────────────────

class AppSettings {
  final ProviderType provider;
  final String model;
  final int maxTokens;
  final double temperature;
  final String systemPrompt;
  final String theme; // 'light', 'dark', 'system'
  final String language; // 'en', 'zh'
  final bool autoApprove;
  final bool thinkingEnabled;
  final bool teamToolsEnabled;
  final String activeProviderId;
  final String activeModelId;

  const AppSettings({
    this.provider = ProviderType.openai,
    this.model = '', this.maxTokens = 32000,
    this.temperature = 0.7, this.systemPrompt = '',
    this.theme = 'system', this.language = 'zh',
    this.autoApprove = false, this.thinkingEnabled = false,
    this.teamToolsEnabled = false, this.activeProviderId = '',
    this.activeModelId = '',
  });

  AppSettings copyWith({
    ProviderType? provider, String? model, int? maxTokens,
    double? temperature, String? systemPrompt, String? theme,
    String? language, bool? autoApprove, bool? thinkingEnabled,
    bool? teamToolsEnabled, String? activeProviderId, String? activeModelId,
  }) => AppSettings(
    provider: provider ?? this.provider, model: model ?? this.model,
    maxTokens: maxTokens ?? this.maxTokens,
    temperature: temperature ?? this.temperature,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    theme: theme ?? this.theme, language: language ?? this.language,
    autoApprove: autoApprove ?? this.autoApprove,
    thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
    teamToolsEnabled: teamToolsEnabled ?? this.teamToolsEnabled,
    activeProviderId: activeProviderId ?? this.activeProviderId,
    activeModelId: activeModelId ?? this.activeModelId,
  );
}
