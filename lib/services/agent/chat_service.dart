import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/services/agent/agent_events.dart';
import 'package:pantheon_forge/services/agent/agent_fallbacks.dart';
import 'package:pantheon_forge/services/agent/agent_runner.dart';
import 'package:pantheon_forge/services/agent/agent_tool_policy.dart';
import 'package:pantheon_forge/services/agent/agent_workspace_helpers.dart';
import 'package:pantheon_forge/services/tools/local_workspace_service.dart';
import 'package:pantheon_forge/services/tools/web_search_service.dart';

const _uuid = Uuid();

class ChatService {
  CancelToken? _cancelToken;

  static const _internalAssistantNoiseTexts = <String>{};
  static const _canonicalAssistantNoiseTexts = {
    '模型本次返回了空响应，没有可显示内容。请重试一次，或换一种说法。',
    '这次请求没有收到完整响应，可能是流式输出被中断了。请重试一次。',
  };

  Future<void> sendMessage({
    required String text,
    required String sessionId,
    required ChatNotifier chat,
    required ProviderNotifier providerNotifier,
    required AppSettings settings,
    bool webSearchEnabled = false,
  }) async {
    final config = providerNotifier.activeProviderConfig;
    if (config == null) return;

    final session = chat.getSessionById(sessionId);
    final workspacePath = session?.workingFolder;
    final history = chat.getMessages(sessionId);
    final activeModel = providerNotifier.activeModel;
    final shouldUseWorkspaceTools =
        workspacePath != null &&
        workspacePath.trim().isNotEmpty &&
        (activeModel?.supportsFunctionCall ?? false);
    final tools = shouldUseWorkspaceTools
        ? LocalWorkspaceService.toolsForWorkspace(workspacePath)
        : const <ToolDefinition>[];

    var userContent = text;
    if (webSearchEnabled) {
      try {
        final searchResult = await WebSearchService.search(
          query: text,
          provider: 'tavily',
          apiKey: '',
          maxResults: 5,
        );
        userContent = '${searchResult.toFormattedText()}\n\n用户问题: $text';
      } catch (_) {
        // Ignore web search failures and continue with the original text.
      }
    }

    final userMsg = UnifiedMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    chat.addMessage(sessionId, userMsg);

    if (_isSimpleGreeting(text)) {
      chat.addMessage(
        sessionId,
        UnifiedMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: '你好！有什么我可以帮你的吗？',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return;
    }

    final immediateClarification = buildImmediateClarificationForWriteIntent(
      text: text,
      history: history,
    );
    if (immediateClarification != null) {
      chat.addMessage(
        sessionId,
        UnifiedMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: immediateClarification,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return;
    }

    final isBroadWorkspaceRequest =
        workspacePath != null &&
        workspacePath.isNotEmpty &&
        isBroadWorkspaceIntent(text);
    final prefetchedMessages = <UnifiedMessage>[];
    if (isBroadWorkspaceRequest) {
      final summaryPrefetch = await prefetchToolMessage(
        workingFolder: workspacePath,
        toolName: 'summarize_project',
        input: const {},
      );
      if (summaryPrefetch != null) {
        prefetchedMessages.addAll(summaryPrefetch);
      }
    }

    final batchReadPrefetch = await buildBatchReadPrefetch(
      text: text,
      workspacePath: workspacePath,
      history: history,
    );
    if (batchReadPrefetch.isNotEmpty) {
      prefetchedMessages.addAll(batchReadPrefetch);
    }

    final messages = <UnifiedMessage>[];
    if (settings.systemPrompt.isNotEmpty) {
      messages.add(
        UnifiedMessage(
          id: 'system',
          role: MessageRole.system,
          content: settings.systemPrompt,
          createdAt: 0,
        ),
      );
    }
    final shouldInjectWorkspacePrompt =
        workspacePath != null && workspacePath.isNotEmpty;
    if (shouldInjectWorkspacePrompt) {
      messages.add(
        UnifiedMessage(
          id: 'workspace-system',
          role: MessageRole.system,
          content:
              'The current session is bound to a local workspace: $workspacePath. You can inspect, modify, and run commands in the local workspace by using tools. First decide whether the user request actually needs workspace access. For greetings, casual chat, explanations, brainstorming, translation, summarization, or general knowledge questions, answer directly without calling tools. Only call tools when the request requires reading files, searching code, listing directories, editing files, creating files, deleting files, moving files, or running commands. If the user asks to read or understand the whole project, start with summarize_project using an empty input object, and do not ask for a file path. If a project summary or tool result is already present in the conversation, use it before calling more tools. If the user wants to write or modify files but did not provide enough required information, ask one concise clarification instead of blindly calling a write tool. Prefer tools in this order: 1) summarize_project for project-wide overview, 2) find_files to locate filenames, 3) search_in_files to find text, 4) list_directory to inspect folders, 5) read_file when you know a file path, 6) edit_file for exact in-place text replacement, 7) write_file to create or fully overwrite a file, 8) create_directory to create folders, 9) move_path to rename or move files and folders, 10) delete_path to remove files or folders, 11) run_command to execute workspace commands such as tests, builds, or scripts. Never claim you cannot access or modify the local workspace. Do not call file tools with empty paths. Do not run destructive system-level commands unless the user explicitly asks.',
          createdAt: 0,
        ),
      );
    }

    if (webSearchEnabled && userContent != text) {
      messages.add(
        UnifiedMessage(
          id: _uuid.v4(),
          role: MessageRole.user,
          content: userContent,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else {
      messages.addAll(
        _sanitizeConversationForModel(chat.getMessages(sessionId)),
      );
    }
    if (prefetchedMessages.isNotEmpty) {
      messages.addAll(prefetchedMessages);
    }

    _cancelToken = CancelToken();

    try {
      final providerConfig = ProviderConfig(
        type: config.type,
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        model: config.model,
        maxTokens: settings.maxTokens,
        temperature: settings.temperature,
        thinkingEnabled: settings.thinkingEnabled,
      );

      final conversation = List<UnifiedMessage>.from(messages);
      await runAgentLoop(
        conversation: conversation,
        userText: text,
        workspacePath: workspacePath,
        providerConfig: providerConfig,
        tools: tools,
        cancelToken: _cancelToken,
        buildAssistantMessage: _buildAssistantMessage,
        onStreamingStarted: (assistantId) {
          chat.setStreaming(assistantId);
        },
        onAssistantPlaceholderAdded: (message) {
          chat.addMessage(sessionId, message);
        },
        onAssistantUpdated: (message) {
          chat.updateLastAssistantMessage(sessionId, message);
        },
        onMessageAdded: (message) {
          chat.addMessage(sessionId, message);
        },
        hasVisibleAssistantContent: hasVisibleAssistantContent,
        buildEmptyAssistantFallback: buildEmptyAssistantFallback,
        synthesizeToolCompletion: synthesizeToolCompletion,
        selectExecutableToolCalls: selectExecutableToolCalls,
        repairToolInput: repairToolInput,
        toolCallSignature: toolCallSignature,
        executeTool: _executeTool,
        buildRepeatedToolFallback: buildRepeatedToolFallback,
        shouldStopAfterToolErrors: shouldStopAfterToolErrors,
        buildToolErrorFallback: buildToolErrorFallback,
      );
    } catch (e) {
      if (e is! DioException || e.type != DioExceptionType.cancel) {
        final fallback = UnifiedMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: '⚠️ $e',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        chat.addMessage(sessionId, fallback);
      }
    } finally {
      chat.setStreaming(null);
      _cancelToken = null;
    }
  }

  List<UnifiedMessage> _sanitizeConversationForModel(
    List<UnifiedMessage> history,
  ) {
    final toolResultIds = <String>{};
    final toolUseIds = <String>{};
    final transientToolErrorIds = <String>{};

    for (final message in history) {
      for (final block in message.blocks) {
        if (block.type == 'tool_use' &&
            block.toolCallId != null &&
            block.toolCallId!.isNotEmpty) {
          toolUseIds.add(block.toolCallId!);
        }
        if (block.type == 'tool_result' &&
            block.toolCallId != null &&
            block.toolCallId!.isNotEmpty) {
          toolResultIds.add(block.toolCallId!);
          if ((block.isError ?? false) &&
              _isTransientToolError(block.toolResultContent ?? '')) {
            transientToolErrorIds.add(block.toolCallId!);
          }
        }
      }
    }

    final sanitized = <UnifiedMessage>[];
    for (final message in history) {
      if (message.role == MessageRole.assistant &&
          _isInternalAssistantNoise(message.textContent)) {
        continue;
      }

      if (message.content is String) {
        sanitized.add(message);
        continue;
      }

      final filteredBlocks = <ContentBlock>[];
      for (final block in message.blocks) {
        switch (block.type) {
          case 'tool_use':
            final callId = block.toolCallId;
            if (callId != null &&
                toolResultIds.contains(callId) &&
                !transientToolErrorIds.contains(callId)) {
              filteredBlocks.add(block);
            }
            break;
          case 'tool_result':
            final callId = block.toolCallId;
            if (callId != null &&
                toolUseIds.contains(callId) &&
                !transientToolErrorIds.contains(callId)) {
              filteredBlocks.add(block);
            }
            break;
          case 'text':
            if (message.role == MessageRole.assistant &&
                _isInternalAssistantNoise(block.text ?? '')) {
              continue;
            }
            filteredBlocks.add(block);
            break;
          default:
            filteredBlocks.add(block);
            break;
        }
      }

      if (filteredBlocks.isEmpty) {
        continue;
      }

      sanitized.add(
        UnifiedMessage(
          id: message.id,
          role: message.role,
          content: filteredBlocks,
          createdAt: message.createdAt,
          usage: message.usage,
        ),
      );
    }
    return sanitized;
  }

  bool _isInternalAssistantNoise(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (_internalAssistantNoiseTexts.contains(normalized) ||
        _canonicalAssistantNoiseTexts.contains(normalized)) {
      return true;
    }
    return normalized.startsWith('⚠️ ') ||
        normalized.startsWith('FormatException:') ||
        normalized.contains('Tool execution failed:') ||
        normalized.contains('Unterminated character class');
  }

  bool _isTransientToolError(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('missing file path') ||
        normalized.contains('missing content') ||
        normalized.contains('unterminated character class') ||
        normalized.contains(
          'for project-wide requests, call summarize_project',
        );
  }

  bool _isSimpleGreeting(String text) {
    final normalized = text.trim().toLowerCase();
    const greetings = {'你好', '您好', '嗨', '哈喽', 'hi', 'hello', 'hey'};
    return greetings.contains(normalized);
  }

  Future<ToolExecutionResult> _executeTool({
    required String workingFolder,
    required AgentPendingToolCall call,
    required Map<String, dynamic> input,
  }) async {
    try {
      if (call.name == 'read_file') {
        final path = (input['path'] as String?)?.trim();
        if (path == null || path.isEmpty) {
          final summary = await LocalWorkspaceService.execute(
            workingFolder: workingFolder,
            toolName: 'summarize_project',
            input: const {},
          );
          if (!summary.isError) {
            return summary;
          }
          return LocalWorkspaceService.execute(
            workingFolder: workingFolder,
            toolName: 'list_directory',
            input: const {'path': '.'},
          );
        }
      }
      return await LocalWorkspaceService.execute(
        workingFolder: workingFolder,
        toolName: call.name,
        input: input,
      );
    } catch (e) {
      return ToolExecutionResult(
        content: 'Tool execution failed: $e',
        isError: true,
      );
    }
  }

  UnifiedMessage _buildAssistantMessage({
    required String id,
    required int createdAt,
    required String text,
    required String thinking,
    required List<AgentPendingToolCall> toolCalls,
    TokenUsage? usage,
  }) {
    final blocks = <ContentBlock>[];
    if (thinking.isNotEmpty) {
      blocks.add(ContentBlock(type: 'thinking', thinking: thinking));
    }
    if (text.isNotEmpty) {
      blocks.add(ContentBlock(type: 'text', text: text));
    }
    for (final call in toolCalls) {
      blocks.add(
        ContentBlock(
          type: 'tool_use',
          toolCallId: call.id,
          toolName: call.name,
          toolInput: call.input ?? call.tryParseInput(),
        ),
      );
    }
    return UnifiedMessage(
      id: id,
      role: MessageRole.assistant,
      content: blocks.isEmpty ? text : blocks,
      createdAt: createdAt,
      usage: usage,
    );
  }

  void stopStreaming() {
    _cancelToken?.cancel('User stopped');
  }
}
