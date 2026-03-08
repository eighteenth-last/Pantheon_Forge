import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/services/api/llm_api.dart';
import 'package:pantheon_forge/services/tools/local_workspace_service.dart';
import 'package:pantheon_forge/services/tools/web_search_service.dart';

const _uuid = Uuid();

class ChatService {
  CancelToken? _cancelToken;

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
    final workspaceTools = LocalWorkspaceService.toolsForWorkspace(
      session?.workingFolder,
    );
    final tools = [...workspaceTools];

    // Web search if enabled
    String userContent = text;
    if (webSearchEnabled) {
      try {
        // TODO: 从设置中获取搜索配置
        final searchResult = await WebSearchService.search(
          query: text,
          provider: 'tavily',
          apiKey: '', // 需要从设置中获取
          maxResults: 5,
        );
        userContent = '${searchResult.toFormattedText()}\n\n用户问题: $text';
      } catch (e) {
        // 搜索失败，继续使用原始文本
      }
    }

    // Add user message
    final userMsg = UnifiedMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    chat.addMessage(sessionId, userMsg);

    final immediateClarification = _buildImmediateClarificationForWriteIntent(
      text: text,
      history: chat.getMessages(sessionId),
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

    final workspacePath = session?.workingFolder;
    final isBroadWorkspaceRequest = workspacePath != null &&
        workspacePath.isNotEmpty &&
        _isBroadWorkspaceIntent(text);
    final prefetchedMessages = <UnifiedMessage>[];
    if (isBroadWorkspaceRequest) {
      final summaryPrefetch = await _prefetchToolMessage(
        workingFolder: workspacePath,
        toolName: 'summarize_project',
        input: const {},
      );
      if (summaryPrefetch != null) {
        prefetchedMessages.addAll(summaryPrefetch);
      }
    }

    final batchReadPrefetch = await _buildBatchReadPrefetch(
      text: text,
      workspacePath: workspacePath,
      history: chat.getMessages(sessionId),
    );
    if (batchReadPrefetch.isNotEmpty) {
      prefetchedMessages.addAll(batchReadPrefetch);
    }

    // Add system prompt if set
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
    if (workspacePath != null && workspacePath.isNotEmpty) {
      messages.add(
        UnifiedMessage(
          id: 'workspace-system',
          role: MessageRole.system,
          content:
              'The current session is bound to a local workspace: $workspacePath. You can inspect, modify, and run commands in the local workspace by using tools. Prefer tools in this order: 1) summarize_project for project-wide overview, 2) find_files to locate filenames, 3) search_in_files to find text, 4) list_directory to inspect folders, 5) read_file when you know a file path, 6) edit_file for exact in-place text replacement, 7) write_file to create or fully overwrite a file, 8) create_directory to create folders, 9) move_path to rename or move files and folders, 10) delete_path to remove files or folders, 11) run_command to execute workspace commands such as tests, builds, or scripts. Never claim you cannot access or modify the local workspace. Do not call file tools with empty paths. Do not run destructive system-level commands unless the user explicitly asks.',
          createdAt: 0,
        ),
      );
    }

    // If web search enabled, add search results as context
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
      messages.addAll(chat.getMessages(sessionId));
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
      var previousToolResults = <_ExecutedToolCall>[];
      final executedCallCounts = <String, int>{};
      for (var iteration = 0; iteration < 6; iteration++) {
        final assistantId = _uuid.v4();
        final assistantCreatedAt = DateTime.now().millisecondsSinceEpoch;
        var assistantMsg = UnifiedMessage(
          id: assistantId,
          role: MessageRole.assistant,
          content: '',
          createdAt: assistantCreatedAt,
        );
        chat.addMessage(sessionId, assistantMsg);
        chat.setStreaming(assistantId);

        final textBuf = StringBuffer();
        final thinkingBuf = StringBuffer();
        final toolCalls = <String, _PendingToolCall>{};
        var responseEnded = false;

        await for (final event in sendMessageStream(
          messages: conversation,
          config: providerConfig,
          tools: tools,
          cancelToken: _cancelToken,
        )) {
          switch (event.type) {
            case StreamEventType.textDelta:
              textBuf.write(event.text ?? '');
              assistantMsg = _buildAssistantMessage(
                id: assistantId,
                createdAt: assistantCreatedAt,
                text: textBuf.toString(),
                thinking: thinkingBuf.toString(),
                toolCalls: toolCalls.values.toList(),
              );
              chat.updateLastAssistantMessage(sessionId, assistantMsg);
              break;
            case StreamEventType.thinkingDelta:
              thinkingBuf.write(event.thinking ?? '');
              assistantMsg = _buildAssistantMessage(
                id: assistantId,
                createdAt: assistantCreatedAt,
                text: textBuf.toString(),
                thinking: thinkingBuf.toString(),
                toolCalls: toolCalls.values.toList(),
              );
              chat.updateLastAssistantMessage(sessionId, assistantMsg);
              break;
            case StreamEventType.toolCallStart:
              final toolCallId = event.toolCallId ?? _uuid.v4();
              toolCalls[toolCallId] = _PendingToolCall(
                id: toolCallId,
                name: event.toolName ?? 'unknown_tool',
              );
              assistantMsg = _buildAssistantMessage(
                id: assistantId,
                createdAt: assistantCreatedAt,
                text: textBuf.toString(),
                thinking: thinkingBuf.toString(),
                toolCalls: toolCalls.values.toList(),
              );
              chat.updateLastAssistantMessage(sessionId, assistantMsg);
              break;
            case StreamEventType.toolCallDelta:
              final toolCallId = event.toolCallId;
              if (toolCallId != null) {
                toolCalls[toolCallId]?.argumentsBuffer.write(
                  event.argumentsDelta ?? '',
                );
              }
              break;
            case StreamEventType.toolCallEnd:
              final toolCallId = event.toolCallId;
              if (toolCallId != null) {
                final call = toolCalls.putIfAbsent(
                  toolCallId,
                  () => _PendingToolCall(
                    id: toolCallId,
                    name: event.toolName ?? 'unknown_tool',
                  ),
                );
                call.input = event.toolCallInput ?? call.tryParseInput();
              }
              assistantMsg = _buildAssistantMessage(
                id: assistantId,
                createdAt: assistantCreatedAt,
                text: textBuf.toString(),
                thinking: thinkingBuf.toString(),
                toolCalls: toolCalls.values.toList(),
                usage: event.usage,
              );
              chat.updateLastAssistantMessage(sessionId, assistantMsg);
              break;
            case StreamEventType.messageEnd:
              responseEnded = true;
              assistantMsg = _buildAssistantMessage(
                id: assistantId,
                createdAt: assistantCreatedAt,
                text: textBuf.toString(),
                thinking: thinkingBuf.toString(),
                toolCalls: toolCalls.values.toList(),
                usage: event.usage,
              );
              chat.updateLastAssistantMessage(sessionId, assistantMsg);
              break;
            case StreamEventType.error:
              final errorContent = textBuf.isEmpty
                  ? '⚠️ ${event.errorMessage ?? "Unknown error"}'
                  : '$textBuf\n\n⚠️ ${event.errorMessage}';
              assistantMsg = UnifiedMessage(
                id: assistantId,
                role: MessageRole.assistant,
                content: errorContent,
                createdAt: assistantCreatedAt,
              );
              chat.updateLastAssistantMessage(sessionId, assistantMsg);
              responseEnded = true;
              toolCalls.clear();
              break;
            default:
              break;
          }
        }

        conversation.add(assistantMsg);

        if ((toolCalls.isEmpty || workspacePath == null) &&
            previousToolResults.isNotEmpty &&
            !_hasVisibleAssistantContent(assistantMsg)) {
          final fallback = UnifiedMessage(
            id: _uuid.v4(),
            role: MessageRole.assistant,
            content: _synthesizeToolCompletion(previousToolResults),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
          chat.addMessage(sessionId, fallback);
          conversation.add(fallback);
          previousToolResults = <_ExecutedToolCall>[];
          break;
        }

        if (!responseEnded || toolCalls.isEmpty || workspacePath == null) {
          previousToolResults = <_ExecutedToolCall>[];
          break;
        }

        final executableCalls = _selectExecutableToolCalls(
          toolCalls.values.toList(),
        );
        final toolResults = <_ExecutedToolCall>[];
        final repeatedCalls = <_PendingToolCall>[];

        for (final call in executableCalls) {
          final input =
              call.input ?? call.tryParseInput() ?? <String, dynamic>{};
          final signature = _toolCallSignature(call, input);
          final executionCount = executedCallCounts[signature] ?? 0;
          if (executionCount >= 1) {
            repeatedCalls.add(call);
            continue;
          }
          executedCallCounts[signature] = executionCount + 1;

          final result = await _executeTool(
            workingFolder: workspacePath,
            call: call,
            input: input,
          );
          toolResults.add(_ExecutedToolCall(call: call, result: result));
          final toolMessage = UnifiedMessage(
            id: _uuid.v4(),
            role: MessageRole.user,
            content: [
              ContentBlock(
                type: 'tool_result',
                toolCallId: call.id,
                toolName: call.name,
                toolResultContent: result.content,
                isError: result.isError,
              ),
            ],
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
          chat.addMessage(sessionId, toolMessage);
          conversation.add(toolMessage);
        }

        previousToolResults = toolResults;

        if (toolResults.isEmpty && repeatedCalls.isNotEmpty) {
          final fallback = UnifiedMessage(
            id: _uuid.v4(),
            role: MessageRole.assistant,
            content: _buildRepeatedToolFallback(
              userText: text,
              repeatedCalls: repeatedCalls,
              history: conversation,
            ),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
          chat.addMessage(sessionId, fallback);
          conversation.add(fallback);
          break;
        }

        if (toolResults.isEmpty) {
          final fallback = UnifiedMessage(
            id: _uuid.v4(),
            role: MessageRole.assistant,
            content: '这次没有执行任何有效的工具调用。我已经停止重复尝试。请更具体说明目标文件、文件名、目录或命令。',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
          chat.addMessage(sessionId, fallback);
          conversation.add(fallback);
          break;
        }

        if (_shouldStopAfterToolErrors(toolResults)) {
          final fallback = UnifiedMessage(
            id: _uuid.v4(),
            role: MessageRole.assistant,
            content: _buildToolErrorFallback(
              userText: text,
              history: conversation,
            ),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
          chat.addMessage(sessionId, fallback);
          conversation.add(fallback);
          break;
        }
      }
    } catch (e) {
      if (e is! DioException || e.type != DioExceptionType.cancel) {
        final errorMessage = '⚠️ $e';
        final fallback = UnifiedMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: errorMessage,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        chat.addMessage(sessionId, fallback);
      }
    } finally {
      chat.setStreaming(null);
      _cancelToken = null;
    }
  }

  Future<ToolExecutionResult> _executeTool({
    required String workingFolder,
    required _PendingToolCall call,
    required Map<String, dynamic> input,
  }) async {
    try {
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
    required List<_PendingToolCall> toolCalls,
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

List<_PendingToolCall> _selectExecutableToolCalls(
  List<_PendingToolCall> calls,
) {
  final selected = <_PendingToolCall>[];
  final seen = <String>{};
  var invalidReadFileHandled = false;
  var hasDiscoveryTool = false;

  for (final call in calls) {
    final input = call.input ?? call.tryParseInput() ?? <String, dynamic>{};
    final signature = '${call.name}:${jsonEncode(input)}';
    if (!seen.add(signature)) {
      continue;
    }

    if (call.name == 'summarize_project' ||
        call.name == 'find_files' ||
        call.name == 'search_in_files' ||
        call.name == 'list_directory') {
      hasDiscoveryTool = true;
    }

    if (call.name == 'read_file') {
      final path = input['path'] as String?;
      if (path == null || path.trim().isEmpty) {
        if (invalidReadFileHandled) continue;
        invalidReadFileHandled = true;
        if (hasDiscoveryTool) continue;
      }
    }

    selected.add(call);
    if (selected.length >= 3) break;
  }

  return selected;
}

bool _shouldStopAfterToolErrors(List<_ExecutedToolCall> toolResults) {
  if (toolResults.isEmpty) return false;
  return toolResults.every((entry) {
    if (!entry.result.isError) return false;
    return entry.call.name == 'read_file';
  });
}

class _PendingToolCall {
  _PendingToolCall({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer argumentsBuffer = StringBuffer();
  Map<String, dynamic>? input;

  Map<String, dynamic>? tryParseInput() {
    if (argumentsBuffer.isEmpty) return input;
    try {
      final parsed = jsonDecode(argumentsBuffer.toString());
      if (parsed is Map<String, dynamic>) {
        input = parsed;
      }
    } catch (_) {}
    return input;
  }
}

class _ExecutedToolCall {
  _ExecutedToolCall({required this.call, required this.result});

  final _PendingToolCall call;
  final ToolExecutionResult result;
}


bool _isBroadWorkspaceIntent(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  const broadKeywords = [
    '\u9605\u8bfb\u6574\u4e2a\u9879\u76ee',
    '\u8bfb\u53d6\u6574\u4e2a\u9879\u76ee',
    '\u67e5\u770b\u6574\u4e2a\u9879\u76ee',
    '\u6d4f\u89c8\u6574\u4e2a\u9879\u76ee',
    '\u5206\u6790\u6574\u4e2a\u9879\u76ee',
    '\u9605\u8bfb\u9879\u76ee',
    '\u9879\u76ee\u7ed3\u6784',
    '\u6574\u4e2a\u9879\u76ee',
    '\u7ee7\u7eed',
    'read the whole project',
    'read the project',
    'project structure',
    'continue',
    'summarize project',
  ];
  return broadKeywords.any(normalized.contains);
}

Future<List<UnifiedMessage>> _buildBatchReadPrefetch({
  required String text,
  required String? workspacePath,
  required List<UnifiedMessage> history,
}) async {
  if (workspacePath == null || workspacePath.isEmpty) {
    return const [];
  }

  if (_looksLikeWriteIntent(text)) {
    return const [];
  }

  final extension = _detectBatchReadExtension(text);
  if (extension == null) {
    return const [];
  }

  final knownFiles = _extractKnownWorkspaceFiles(history)
      .where((path) => path.toLowerCase().endsWith(extension))
      .toList();

  final paths = knownFiles.isNotEmpty
      ? knownFiles
      : await _findFilesByExtension(workspacePath, extension);
  if (paths.isEmpty) {
    return const [];
  }

  return (await _prefetchToolMessage(
        workingFolder: workspacePath,
        toolName: 'read_files',
        input: {
          'paths': paths.take(12).toList(),
          'max_chars_per_file': 12000,
        },
      )) ??
      const [];
}

Future<List<String>> _findFilesByExtension(
  String workspacePath,
  String extension,
) async {
  final result = await LocalWorkspaceService.execute(
    workingFolder: workspacePath,
    toolName: 'find_files',
    input: {
      'query': extension,
      'limit': 50,
    },
  );
  if (result.isError) {
    return const [];
  }
  try {
    final decoded = jsonDecode(result.content) as Map<String, dynamic>;
    final matches = (decoded['matches'] as List?) ?? const [];
    return matches.whereType<String>().toList();
  } catch (_) {
    return const [];
  }
}

Future<List<UnifiedMessage>?> _prefetchToolMessage({
  required String? workingFolder,
  required String toolName,
  required Map<String, dynamic> input,
}) async {
  if (workingFolder == null || workingFolder.isEmpty) {
    return null;
  }
  final result = await LocalWorkspaceService.execute(
    workingFolder: workingFolder,
    toolName: toolName,
    input: input,
  );
  if (result.isError) {
    return null;
  }
  final toolCallId = _uuid.v4();
  return [
    UnifiedMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: [
        ContentBlock(
          type: 'tool_use',
          toolCallId: toolCallId,
          toolName: toolName,
          toolInput: input,
        ),
      ],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ),
    UnifiedMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: [
        ContentBlock(
          type: 'tool_result',
          toolCallId: toolCallId,
          toolName: toolName,
          toolResultContent: result.content,
          isError: false,
        ),
      ],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ),
  ];
}

List<String> _extractKnownWorkspaceFiles(List<UnifiedMessage> history) {
  final files = <String>[];
  for (final message in history.reversed) {
    for (final block in message.blocks) {
      if (block.type != 'tool_result' || block.toolResultContent == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(block.toolResultContent!) as Map<String, dynamic>;
        if (block.toolName == 'summarize_project') {
          final topLevelEntries = (decoded['topLevelEntries'] as List?) ?? const [];
          for (final entry in topLevelEntries) {
            if (entry is Map<String, dynamic> && entry['type'] == 'file') {
              final path = entry['path'] as String?;
              if (path != null && path.isNotEmpty) {
                files.add(path);
              }
            }
          }
        }
        if (block.toolName == 'find_files') {
          final matches = (decoded['matches'] as List?) ?? const [];
          for (final match in matches.whereType<String>()) {
            files.add(match);
          }
        }
      } catch (_) {
        continue;
      }
    }
  }
  return files.toSet().toList();
}

String? _detectBatchReadExtension(String text) {
  final normalized = text.trim().toLowerCase();
  const extensionMap = {
    '.java': ['java\u4ee3\u7801', 'java \u6587\u4ef6', '\u6240\u6709java', '\u5168\u90e8java', 'all java', 'java files'],
    '.dart': ['dart\u4ee3\u7801', 'dart \u6587\u4ef6', '\u6240\u6709dart', '\u5168\u90e8dart', 'all dart', 'dart files'],
    '.py': ['python\u4ee3\u7801', 'python \u6587\u4ef6', 'py \u6587\u4ef6', '\u6240\u6709python', '\u5168\u90e8python', 'all python', 'python files'],
    '.sql': ['sql\u4ee3\u7801', 'sql \u6587\u4ef6', '\u6240\u6709sql', '\u5168\u90e8sql', 'all sql', 'sql files'],
    '.html': ['html\u4ee3\u7801', 'html \u6587\u4ef6', '\u7f51\u9875\u6587\u4ef6', '\u6240\u6709html', '\u5168\u90e8html', 'all html', 'html files'],
    '.js': ['js\u4ee3\u7801', 'javascript\u4ee3\u7801', 'js \u6587\u4ef6', '\u6240\u6709js', '\u5168\u90e8js', 'all js', 'javascript files'],
    '.ts': ['ts\u4ee3\u7801', 'typescript\u4ee3\u7801', 'ts \u6587\u4ef6', '\u6240\u6709ts', '\u5168\u90e8ts', 'all ts', 'typescript files'],
  };
  for (final entry in extensionMap.entries) {
    if (entry.value.any(normalized.contains)) {
      return entry.key;
    }
  }
  return null;
}

bool _hasVisibleAssistantContent(UnifiedMessage message) {
  final blocks = message.blocks;
  if (blocks.isEmpty) {
    return message.textContent.trim().isNotEmpty;
  }
  for (final block in blocks) {
    if (block.type == 'text' && (block.text?.trim().isNotEmpty ?? false)) {
      return true;
    }
    if (block.type == 'thinking' && (block.thinking?.trim().isNotEmpty ?? false)) {
      return true;
    }
  }
  return false;
}

String _synthesizeToolCompletion(List<_ExecutedToolCall> toolResults) {
  final successCalls = toolResults.where((entry) => !entry.result.isError).toList();
  if (successCalls.isEmpty) {
    return '\u5de5\u5177\u5df2\u7ecf\u6267\u884c\u5b8c\u6bd5\uff0c\u4f46\u6a21\u578b\u6ca1\u6709\u7ee7\u7eed\u8f93\u51fa\u53ef\u89c1\u5185\u5bb9\u3002';
  }

  final first = successCalls.first;
  final targetPath = _extractPathFromToolResult(first.result.content);

  switch (first.call.name) {
    case 'write_file':
      return targetPath == null
          ? '\u6587\u4ef6\u5df2\u5199\u5165\u5b8c\u6210\u3002'
          : '\u6587\u4ef6\u5df2\u5199\u5165\uff1a`$targetPath`\u3002';
    case 'edit_file':
      return targetPath == null
          ? '\u6587\u4ef6\u4fee\u6539\u5df2\u5b8c\u6210\u3002'
          : '\u6587\u4ef6\u4fee\u6539\u5df2\u5b8c\u6210\uff1a`$targetPath`\u3002';
    case 'create_directory':
      return targetPath == null
          ? '\u76ee\u5f55\u5df2\u521b\u5efa\u3002'
          : '\u76ee\u5f55\u5df2\u521b\u5efa\uff1a`$targetPath`\u3002';
    case 'move_path':
      return '\u79fb\u52a8\u6216\u91cd\u547d\u540d\u64cd\u4f5c\u5df2\u5b8c\u6210\u3002';
    case 'delete_path':
      return '\u5220\u9664\u64cd\u4f5c\u5df2\u5b8c\u6210\u3002';
    case 'run_command':
      return '\u547d\u4ee4\u5df2\u6267\u884c\u5b8c\u6210\u3002';
    case 'read_files':
      return '\u76f8\u5173\u6587\u4ef6\u5df2\u6279\u91cf\u8bfb\u53d6\uff0c\u6211\u4f1a\u57fa\u4e8e\u8fd9\u4e9b\u5185\u5bb9\u7ee7\u7eed\u6574\u7406\u3002';
    case 'read_file':
      return targetPath == null
          ? '\u6587\u4ef6\u5df2\u8bfb\u53d6\u5b8c\u6210\u3002'
          : '\u6587\u4ef6\u5df2\u8bfb\u53d6\uff1a`$targetPath`\u3002';
    case 'summarize_project':
      return '\u9879\u76ee\u6982\u89c8\u5df2\u8bfb\u53d6\u5b8c\u6210\u3002';
    case 'list_directory':
      return '\u76ee\u5f55\u5185\u5bb9\u5df2\u8bfb\u53d6\u5b8c\u6210\u3002';
    default:
      return '\u5de5\u5177\u6267\u884c\u5df2\u5b8c\u6210\u3002';
  }
}

String _toolCallSignature(
  _PendingToolCall call,
  Map<String, dynamic> input,
) {
  return '${call.name}:${jsonEncode(input)}';
}

String _buildRepeatedToolFallback({
  required String userText,
  required List<_PendingToolCall> repeatedCalls,
  required List<UnifiedMessage> history,
}) {
  if (_looksLikeWriteIntent(userText)) {
    final directory = _extractMentionedWorkspaceDirectory(userText, history);
    if (!_containsLikelyFileName(userText)) {
      if (directory != null) {
        return '\u6211\u5df2\u7ecf\u5b9a\u4f4d\u5230\u76ee\u5f55 `$directory`\uff0c\u4f46\u4f60\u8fd8\u6ca1\u6709\u7ed9\u51fa\u6587\u4ef6\u540d\u548c\u4ee3\u7801\u7528\u9014\u3002\u8bf7\u544a\u8bc9\u6211\u4f8b\u5982 `$directory/hello.py`\uff0c\u4ee5\u53ca\u8fd9\u6bb5\u4ee3\u7801\u8981\u5b9e\u73b0\u4ec0\u4e48\u529f\u80fd\u3002';
      }
      return '\u6211\u5df2\u7ecf\u77e5\u9053\u4f60\u8981\u521b\u5efa\u4ee3\u7801\u6587\u4ef6\uff0c\u4f46\u8fd8\u7f3a\u5c11\u6587\u4ef6\u540d\u548c\u5177\u4f53\u529f\u80fd\u3002\u8bf7\u8865\u5145\u4f8b\u5982 `scripts/hello.py`\uff0c\u5e76\u8bf4\u660e\u4ee3\u7801\u8981\u505a\u4ec0\u4e48\u3002';
    }
  }

  final toolNames = repeatedCalls
      .map((call) => call.name)
      .toSet()
      .join('\u3001');
  return '\u6211\u521a\u521a\u68c0\u6d4b\u5230\u91cd\u590d\u7684\u5de5\u5177\u8c03\u7528\uff08$toolNames\uff09\uff0c\u7ee7\u7eed\u6267\u884c\u4e5f\u4e0d\u4f1a\u4ea7\u751f\u65b0\u7ed3\u679c\uff0c\u6240\u4ee5\u6211\u5148\u505c\u4e0b\u6765\u3002\u8bf7\u66f4\u5177\u4f53\u8bf4\u660e\u76ee\u6807\u6587\u4ef6\u3001\u76ee\u5f55\u6216\u4e0b\u4e00\u6b65\u64cd\u4f5c\u3002';
}

String _buildToolErrorFallback({
  required String userText,
  required List<UnifiedMessage> history,
}) {
  if (_looksLikeWriteIntent(userText) && !_containsLikelyFileName(userText)) {
    final directory = _extractMentionedWorkspaceDirectory(userText, history);
    if (directory != null) {
      return '\u6211\u5df2\u7ecf\u77e5\u9053\u76ee\u6807\u76ee\u5f55\u662f `$directory`\u3002\u8bf7\u544a\u8bc9\u6211\u8981\u521b\u5efa\u6216\u4fee\u6539\u7684\u6587\u4ef6\u540d\uff0c\u4f8b\u5982 `$directory/main.py`\u3002';
    }
    return '\u8fd9\u6b21\u5de5\u5177\u8c03\u7528\u7f3a\u5c11\u660e\u786e\u7684\u6587\u4ef6\u8def\u5f84\u3002\u8bf7\u544a\u8bc9\u6211\u8981\u521b\u5efa\u6216\u4fee\u6539\u7684\u6587\u4ef6\u540d\uff0c\u4f8b\u5982 `src/main.py`\u3002';
  }

  return '\u8fd9\u6b21\u5de5\u5177\u8c03\u7528\u7f3a\u5c11\u660e\u786e\u7684\u6587\u4ef6\u8def\u5f84\u6216\u53c2\u6570\u3002\u8bf7\u76f4\u63a5\u544a\u8bc9\u6211\u8981\u8bfb\u53d6\u7684\u6587\u4ef6\u3001\u8981\u521b\u5efa\u7684\u6587\u4ef6\u540d\uff0c\u6216\u8981\u6267\u884c\u7684\u547d\u4ee4\u3002';
}

String? _buildImmediateClarificationForWriteIntent({
  required String text,
  required List<UnifiedMessage> history,
}) {
  if (!_looksLikeWriteIntent(text) || _containsLikelyFileName(text)) {
    return null;
  }

  final directory = _extractMentionedWorkspaceDirectory(text, history);
  if (directory != null) {
    return '\u6211\u5df2\u7ecf\u5b9a\u4f4d\u5230\u76ee\u5f55 `$directory`\u3002\u8bf7\u518d\u544a\u8bc9\u6211\u4e24\u70b9\uff1a1\uff09\u6587\u4ef6\u540d\uff0c\u4f8b\u5982 `$directory/hello.py`\uff1b2\uff09\u8fd9\u6bb5\u4ee3\u7801\u8981\u5b9e\u73b0\u4ec0\u4e48\u529f\u80fd\u3002';
  }

  return '\u6211\u53ef\u4ee5\u76f4\u63a5\u5e2e\u4f60\u521b\u5efa\u4ee3\u7801\u6587\u4ef6\u3002\u8bf7\u544a\u8bc9\u6211\u6587\u4ef6\u540d\u548c\u529f\u80fd\uff0c\u4f8b\u5982 `scripts/hello.py`\uff0c\u4ee5\u53ca\u8fd9\u6bb5\u4ee3\u7801\u8981\u505a\u4ec0\u4e48\u3002';
}

bool _looksLikeWriteIntent(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }

  const keywords = [
    '\u5199',
    '\u521b\u5efa',
    '\u65b0\u5efa',
    '\u751f\u6210',
    '\u65b0\u589e',
    '\u4fdd\u5b58\u5230',
    '\u5199\u5165',
    '\u4fee\u6539',
    '\u7f16\u8f91',
    'create',
    'write',
    'generate',
    'edit',
    'update',
  ];
  return keywords.any(normalized.contains);
}

bool _containsLikelyFileName(String text) {
  final fileNamePattern = RegExp(
    r'(^|[\\/\s])[^\\/\s]+\.[a-zA-Z0-9]{1,12}(?=$|[\\/\s])',
  );
  return fileNamePattern.hasMatch(text);
}

List<String> _extractKnownWorkspaceDirectories(List<UnifiedMessage> history) {
  final directories = <String>[];

  for (final message in history.reversed) {
    for (final block in message.blocks) {
      if (block.type != 'tool_result' || block.toolResultContent == null) {
        continue;
      }

      try {
        final decoded = jsonDecode(block.toolResultContent!) as Map<String, dynamic>;

        if (block.toolName == 'summarize_project') {
          final topLevelEntries = (decoded['topLevelEntries'] as List?) ?? const [];
          for (final entry in topLevelEntries) {
            if (entry is Map<String, dynamic> && entry['type'] == 'dir') {
              final path = entry['path'] as String?;
              if (path != null && path.isNotEmpty) {
                directories.add(path);
              }
            }
          }
        }

        if (block.toolName == 'list_directory') {
          final rawEntries = (decoded['entries'] as List?) ?? const [];
          for (final entry in rawEntries.whereType<String>()) {
            if (entry.startsWith('[DIR] ')) {
              directories.add(entry.substring(6).trim());
            }
          }
        }
      } catch (_) {
        continue;
      }
    }
  }

  return directories.toSet().toList();
}

String? _extractMentionedWorkspaceDirectory(
  String text,
  List<UnifiedMessage> history,
) {
  final normalized = text.trim().toLowerCase();
  final directories = _extractKnownWorkspaceDirectories(history)
    ..sort((a, b) => b.length.compareTo(a.length));

  for (final directory in directories) {
    if (normalized.contains(directory.toLowerCase())) {
      return directory;
    }
  }
  return null;
}

String? _extractPathFromToolResult(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      for (final key in ['path', 'file', 'target_path', 'directory']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          return value;
        }
      }
    }
  } catch (_) {}
  return null;
}
