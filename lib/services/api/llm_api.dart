import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:pantheon_forge/models/models.dart';

/// Build request headers based on provider type
Map<String, String> _buildHeaders(ProviderConfig config) {
  return {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${config.apiKey}',
  };
}

/// Sends messages to an LLM provider and yields streaming events.
Stream<StreamEvent> sendMessageStream({
  required List<UnifiedMessage> messages,
  required ProviderConfig config,
  List<ToolDefinition> tools = const [],
  CancelToken? cancelToken,
}) {
  switch (config.type) {
    case ProviderType.openai:
      return _sendOpenAI(messages, config, tools, cancelToken);
    case ProviderType.anthropic:
      return _sendAnthropic(messages, config, tools, cancelToken);
  }
}

// ──────────────── OpenAI Chat Completions ────────────────

Stream<StreamEvent> _sendOpenAI(
  List<UnifiedMessage> messages,
  ProviderConfig config,
  List<ToolDefinition> tools,
  CancelToken? cancelToken,
) async* {
  final dio = Dio();
  final baseUrl = (config.baseUrl ?? 'https://api.openai.com').replaceAll(
    RegExp(r'/+$'),
    '',
  );
  final isReasoningModel = RegExp(
    r'^(o[1-9]|o\d+-mini)',
    caseSensitive: false,
  ).hasMatch(config.model);

  // Construct URL - if baseUrl already ends with /v1, just add /chat/completions
  String url;
  if (baseUrl.endsWith('/v1') || baseUrl.endsWith('/compatible-mode/v1')) {
    url = '$baseUrl/chat/completions';
  } else {
    url = '$baseUrl/v1/chat/completions';
  }

  final body = <String, dynamic>{
    'model': config.model,
    'messages': messages.map((m) => _formatOpenAIMessage(m)).toList(),
    'stream': true,
    'stream_options': {'include_usage': true},
  };

  if (config.maxTokens > 0) {
    if (isReasoningModel) {
      body['max_completion_tokens'] = config.maxTokens;
    } else {
      body['max_tokens'] = config.maxTokens;
    }
  }

  if (!isReasoningModel) {
    body['temperature'] = config.temperature;
  }

  if (tools.isNotEmpty) {
    body['tools'] = tools
        .map(
          (t) => {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.inputSchema,
            },
          },
        )
        .toList();
    body['tool_choice'] = 'auto';
  }

  yield const StreamEvent(type: StreamEventType.messageStart);

  try {
    final response = await dio.post<ResponseBody>(
      url,
      data: jsonEncode(body),
      options: Options(
        headers: _buildHeaders(config),
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
    );

    final stream = response.data!.stream;
    String buffer = '';
    final toolCallArgs = <String, StringBuffer>{};

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed == 'data: [DONE]') continue;
        if (!trimmed.startsWith('data: ')) continue;

        final jsonStr = trimmed.substring(6);
        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final choices = data['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          // Text content
          if (delta['content'] != null) {
            yield StreamEvent(
              type: StreamEventType.textDelta,
              text: delta['content'] as String,
            );
          }

          // Tool calls
          final toolCalls = delta['tool_calls'] as List?;
          if (toolCalls != null) {
            for (final tc in toolCalls) {
              final tcMap = tc as Map<String, dynamic>;
              final fn = tcMap['function'] as Map<String, dynamic>?;
              if (fn == null) continue;
              final id = tcMap['id'] as String?;
              final name = fn['name'] as String?;
              final argsDelta = fn['arguments'] as String? ?? '';

              if (id != null && name != null) {
                toolCallArgs[id] = StringBuffer();
                yield StreamEvent(
                  type: StreamEventType.toolCallStart,
                  toolCallId: id,
                  toolName: name,
                );
              }

              if (argsDelta.isNotEmpty) {
                final activeId = id ?? toolCallArgs.keys.lastOrNull;
                if (activeId != null) {
                  toolCallArgs[activeId]?.write(argsDelta);
                  yield StreamEvent(
                    type: StreamEventType.toolCallDelta,
                    toolCallId: activeId,
                    argumentsDelta: argsDelta,
                  );
                }
              }
            }
          }

          // Parse usage if present
          final usage = data['usage'] as Map<String, dynamic>?;
          TokenUsage? tokenUsage;
          if (usage != null) {
            tokenUsage = TokenUsage(
              inputTokens: usage['prompt_tokens'] as int? ?? 0,
              outputTokens: usage['completion_tokens'] as int? ?? 0,
              contextTokens:
                  usage['total_tokens'] as int? ??
                  (usage['prompt_tokens'] as int? ?? 0) +
                      (usage['completion_tokens'] as int? ?? 0),
            );
          }

          // Finish
          final finishReason = choices[0]['finish_reason'] as String?;
          if (finishReason != null) {
            // Emit tool call ends
            for (final entry in toolCallArgs.entries) {
              Map<String, dynamic>? input;
              try {
                input = jsonDecode(entry.value.toString());
              } catch (_) {}
              yield StreamEvent(
                type: StreamEventType.toolCallEnd,
                toolCallId: entry.key,
                toolCallInput: input,
              );
            }

            yield StreamEvent(
              type: StreamEventType.messageEnd,
              stopReason: finishReason,
              usage: tokenUsage,
            );
          }
        } catch (_) {}
      }
    }
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) return;
    yield StreamEvent(
      type: StreamEventType.error,
      errorMessage: _formatDioError(e),
    );
  } catch (e) {
    yield StreamEvent(type: StreamEventType.error, errorMessage: e.toString());
  }
}

String _formatDioError(DioException error) {
  final response = error.response;
  if (response == null) {
    return error.message ?? 'Request failed';
  }

  final data = response.data;
  if (data is Map<String, dynamic>) {
    final errorField = data['error'];
    if (errorField is Map<String, dynamic>) {
      final message = errorField['message'] as String?;
      final code = errorField['code'] as Object?;
      if (message != null && message.isNotEmpty) {
        return code != null ? '$message (code: $code)' : message;
      }
    }
    final message = data['message'] as String?;
    if (message != null && message.isNotEmpty) {
      return message;
    }
  }

  if (data is String && data.isNotEmpty) {
    return data;
  }

  return 'HTTP ${response.statusCode}: ${response.statusMessage ?? error.message ?? 'Request failed'}';
}

Map<String, dynamic> _formatOpenAIMessage(UnifiedMessage m) {
  if (m.content is String) {
    return {'role': m.role.name, 'content': m.content};
  }

  final blocks = m.blocks;
  final textBlocks = blocks.where((b) => b.type == 'text').toList();
  final toolUseBlocks = blocks.where((b) => b.type == 'tool_use').toList();
  final toolResultBlocks = blocks.where((b) => b.type == 'tool_result').toList();

  if (toolResultBlocks.isNotEmpty) {
    final resultBlock = toolResultBlocks.first;
    return {
      'role': 'tool',
      'tool_call_id': resultBlock.toolCallId,
      'content': resultBlock.toolResultContent ?? '',
    };
  }

  if (toolUseBlocks.isNotEmpty && m.role == MessageRole.assistant) {
    return {
      'role': 'assistant',
      'content': textBlocks.isEmpty
          ? null
          : textBlocks.map((b) => b.text ?? '').join('\n'),
      'tool_calls': toolUseBlocks
          .map(
            (b) => {
              'id': b.toolCallId,
              'type': 'function',
              'function': {
                'name': b.toolName,
                'arguments': jsonEncode(b.toolInput ?? {}),
              },
            },
          )
          .toList(),
    };
  }

  return {
    'role': m.role.name,
    'content': textBlocks.isEmpty
        ? m.textContent
        : textBlocks.map((b) => b.text ?? '').join('\n'),
  };
}


// ──────────────── Anthropic Messages ────────────────

Stream<StreamEvent> _sendAnthropic(
  List<UnifiedMessage> messages,
  ProviderConfig config,
  List<ToolDefinition> tools,
  CancelToken? cancelToken,
) async* {
  final dio = Dio();
  final baseUrl = (config.baseUrl ?? 'https://api.anthropic.com').replaceAll(
    RegExp(r'/+$'),
    '',
  );
  final url = '$baseUrl/v1/messages';

  // Separate system message
  String? systemPrompt;
  final apiMessages = <Map<String, dynamic>>[];
  for (final m in messages) {
    if (m.role == MessageRole.system) {
      systemPrompt = m.textContent;
      continue;
    }
    if (m.content is String) {
      apiMessages.add({
        'role': m.role == MessageRole.assistant ? 'assistant' : 'user',
        'content': m.textContent,
      });
      continue;
    }

    final blocks = m.blocks;
    apiMessages.add({
      'role': m.role == MessageRole.assistant ? 'assistant' : 'user',
      'content': blocks.map((b) {
        switch (b.type) {
          case 'thinking':
            return {'type': 'thinking', 'thinking': b.thinking};
          case 'tool_use':
            return {
              'type': 'tool_use',
              'id': b.toolCallId,
              'name': b.toolName,
              'input': b.toolInput ?? <String, dynamic>{},
            };
          case 'tool_result':
            return {
              'type': 'tool_result',
              'tool_use_id': b.toolCallId,
              'content': b.toolResultContent ?? '',
              if (b.isError == true) 'is_error': true,
            };
          case 'text':
          default:
            return {'type': 'text', 'text': b.text ?? ''};
        }
      }).toList(),
    });
  }

  final body = <String, dynamic>{
    'model': config.model,
    'messages': apiMessages,
    'max_tokens': config.maxTokens,
    'stream': true,
  };
  if (systemPrompt != null && systemPrompt.isNotEmpty) {
    body['system'] = systemPrompt;
  }
  if (tools.isNotEmpty) {
    body['tools'] = tools
        .map(
          (t) => {
            'name': t.name,
            'description': t.description,
            'input_schema': t.inputSchema,
          },
        )
        .toList();
    body['tool_choice'] = {'type': 'auto'};
  }
  if (config.thinkingEnabled) {
    body['thinking'] = {
      'type': 'enabled',
      'budget_tokens': config.maxTokens > 4096 ? 4096 : config.maxTokens,
    };
  }

  yield const StreamEvent(type: StreamEventType.messageStart);

  try {
    final response = await dio.post<ResponseBody>(
      url,
      data: jsonEncode(body),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
        },
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
    );

    final stream = response.data!.stream;
    String buffer = '';
    String? currentToolId;
    final toolArgsBuf = StringBuffer();

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
        final jsonStr = trimmed.substring(6);
        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final eventType = data['type'] as String?;

          switch (eventType) {
            case 'content_block_start':
              final block = data['content_block'] as Map<String, dynamic>?;
              if (block?['type'] == 'tool_use') {
                currentToolId = block!['id'] as String;
                toolArgsBuf.clear();
                yield StreamEvent(
                  type: StreamEventType.toolCallStart,
                  toolCallId: currentToolId,
                  toolName: block['name'] as String?,
                );
              }
              break;
            case 'content_block_delta':
              final delta = data['delta'] as Map<String, dynamic>?;
              if (delta?['type'] == 'text_delta') {
                yield StreamEvent(
                  type: StreamEventType.textDelta,
                  text: delta!['text'] as String?,
                );
              } else if (delta?['type'] == 'thinking_delta') {
                yield StreamEvent(
                  type: StreamEventType.thinkingDelta,
                  thinking: delta!['thinking'] as String?,
                );
              } else if (delta?['type'] == 'input_json_delta') {
                final partial = delta!['partial_json'] as String? ?? '';
                toolArgsBuf.write(partial);
                yield StreamEvent(
                  type: StreamEventType.toolCallDelta,
                  toolCallId: currentToolId,
                  argumentsDelta: partial,
                );
              }
              break;
            case 'content_block_stop':
              if (currentToolId != null) {
                Map<String, dynamic>? input;
                try {
                  input = jsonDecode(toolArgsBuf.toString());
                } catch (_) {}
                yield StreamEvent(
                  type: StreamEventType.toolCallEnd,
                  toolCallId: currentToolId,
                  toolCallInput: input,
                );
                currentToolId = null;
                toolArgsBuf.clear();
              }
              break;
            case 'message_delta':
              final delta = data['delta'] as Map<String, dynamic>?;
              final usage = data['usage'] as Map<String, dynamic>?;
              yield StreamEvent(
                type: StreamEventType.messageEnd,
                stopReason: delta?['stop_reason'] as String?,
                usage: usage != null
                    ? TokenUsage(
                        inputTokens: usage['input_tokens'] as int? ?? 0,
                        outputTokens: usage['output_tokens'] as int? ?? 0,
                      )
                    : null,
              );
              break;
          }
        } catch (_) {}
      }
    }
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) return;
    yield StreamEvent(
      type: StreamEventType.error,
      errorMessage: e.message ?? 'Request failed',
    );
  } catch (e) {
    yield StreamEvent(type: StreamEventType.error, errorMessage: e.toString());
  }
}
