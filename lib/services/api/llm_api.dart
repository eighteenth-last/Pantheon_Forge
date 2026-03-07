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
  List<UnifiedMessage> messages, ProviderConfig config,
  List<ToolDefinition> tools, CancelToken? cancelToken,
) async* {
  final dio = Dio();
  final baseUrl = (config.baseUrl ?? 'https://api.openai.com').replaceAll(RegExp(r'/+$'), '');
  
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
    'max_tokens': config.maxTokens,
    'temperature': config.temperature,
  };

  if (tools.isNotEmpty) {
    body['tools'] = tools.map((t) => {
      'type': 'function',
      'function': {
        'name': t.name,
        'description': t.description,
        'parameters': t.inputSchema,
      },
    }).toList();
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
                  toolCallId: id, toolName: name,
                );
              }

              if (argsDelta.isNotEmpty) {
                final activeId = id ?? toolCallArgs.keys.lastOrNull;
                if (activeId != null) {
                  toolCallArgs[activeId]?.write(argsDelta);
                  yield StreamEvent(
                    type: StreamEventType.toolCallDelta,
                    toolCallId: activeId, argumentsDelta: argsDelta,
                  );
                }
              }
            }
          }

          // Finish
          final finishReason = choices[0]['finish_reason'] as String?;
          if (finishReason != null) {
            // Emit tool call ends
            for (final entry in toolCallArgs.entries) {
              Map<String, dynamic>? input;
              try { input = jsonDecode(entry.value.toString()); } catch (_) {}
              yield StreamEvent(
                type: StreamEventType.toolCallEnd,
                toolCallId: entry.key, toolCallInput: input,
              );
            }

            final usage = data['usage'] as Map<String, dynamic>?;
            yield StreamEvent(
              type: StreamEventType.messageEnd,
              stopReason: finishReason,
              usage: usage != null ? TokenUsage(
                inputTokens: usage['prompt_tokens'] as int? ?? 0,
                outputTokens: usage['completion_tokens'] as int? ?? 0,
              ) : null,
            );
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

Map<String, dynamic> _formatOpenAIMessage(UnifiedMessage m) {
  final msg = <String, dynamic>{'role': m.role.name};
  if (m.content is String) {
    msg['content'] = m.content;
  } else {
    msg['content'] = m.textContent;
  }
  return msg;
}

// ──────────────── Anthropic Messages ────────────────

Stream<StreamEvent> _sendAnthropic(
  List<UnifiedMessage> messages, ProviderConfig config,
  List<ToolDefinition> tools, CancelToken? cancelToken,
) async* {
  final dio = Dio();
  final baseUrl = (config.baseUrl ?? 'https://api.anthropic.com').replaceAll(RegExp(r'/+$'), '');
  final url = '$baseUrl/v1/messages';

  // Separate system message
  String? systemPrompt;
  final apiMessages = <Map<String, dynamic>>[];
  for (final m in messages) {
    if (m.role == MessageRole.system) {
      systemPrompt = m.textContent;
      continue;
    }
    apiMessages.add({
      'role': m.role == MessageRole.assistant ? 'assistant' : 'user',
      'content': m.textContent,
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
    body['tools'] = tools.map((t) => {
      'name': t.name,
      'description': t.description,
      'input_schema': t.inputSchema,
    }).toList();
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
                  toolCallId: currentToolId, toolName: block['name'] as String?,
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
                  toolCallId: currentToolId, argumentsDelta: partial,
                );
              }
              break;
            case 'content_block_stop':
              if (currentToolId != null) {
                Map<String, dynamic>? input;
                try { input = jsonDecode(toolArgsBuf.toString()); } catch (_) {}
                yield StreamEvent(
                  type: StreamEventType.toolCallEnd,
                  toolCallId: currentToolId, toolCallInput: input,
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
                usage: usage != null ? TokenUsage(
                  inputTokens: usage['input_tokens'] as int? ?? 0,
                  outputTokens: usage['output_tokens'] as int? ?? 0,
                ) : null,
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
