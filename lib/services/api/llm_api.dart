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

String _resolveOpenAIUrl(String baseUrl, String path) {
  if (baseUrl.endsWith('/v1') || baseUrl.endsWith('/compatible-mode/v1')) {
    return '$baseUrl$path';
  }
  return '$baseUrl/v1$path';
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
    case ProviderType.openaiResponses:
      return _sendOpenAIResponses(messages, config, tools, cancelToken);
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
  final url = _resolveOpenAIUrl(baseUrl, '/chat/completions');

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
    TokenUsage? lastTokenUsage;
    var messageEnded = false;

    Iterable<String> extractTextParts(dynamic rawContent) sync* {
      if (rawContent is String) {
        yield rawContent;
        return;
      }
      if (rawContent is! List) {
        return;
      }
      for (final item in rawContent) {
        if (item is String) {
          yield item;
          continue;
        }
        if (item is! Map) {
          continue;
        }
        final type = item['type'] as String?;
        if (type == 'text' || type == 'output_text' || type == null) {
          final text = item['text'] ?? item['content'];
          if (text is String) {
            yield text;
          }
        }
      }
    }

    Iterable<String> extractThinkingParts(Map<String, dynamic> delta) sync* {
      for (final key in const [
        'reasoning_content',
        'reasoning',
        'thinking',
        'reasoningContent',
      ]) {
        final value = delta[key];
        if (value is String) {
          yield value;
        } else if (value is List) {
          for (final item in value) {
            if (item is String) {
              yield item;
              continue;
            }
            if (item is! Map) {
              continue;
            }
            final text = item['text'] ?? item['content'] ?? item['thinking'];
            if (text is String) {
              yield text;
            }
          }
        }
      }

      final content = delta['content'];
      if (content is! List) {
        return;
      }
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final type = item['type'] as String?;
        if (type == 'reasoning' || type == 'thinking') {
          final text = item['text'] ?? item['content'] ?? item['thinking'];
          if (text is String) {
            yield text;
          }
        }
      }
    }

    TokenUsage? parseUsage(Map<String, dynamic> data) {
      final usage = data['usage'] as Map<String, dynamic>?;
      if (usage == null) {
        return null;
      }
      return TokenUsage(
        inputTokens: usage['prompt_tokens'] as int? ?? 0,
        outputTokens: usage['completion_tokens'] as int? ?? 0,
        reasoningTokens:
            usage['reasoning_tokens'] as int? ??
            (usage['completion_tokens_details'] is Map<String, dynamic>
                ? (usage['completion_tokens_details']
                    as Map<String, dynamic>)['reasoning_tokens'] as int?
                : null),
        contextTokens:
            usage['total_tokens'] as int? ??
            (usage['prompt_tokens'] as int? ?? 0) +
                (usage['completion_tokens'] as int? ?? 0),
      );
    }

    Iterable<StreamEvent> parseSseLine(String line) sync* {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed == 'data: [DONE]') return;
      if (!trimmed.startsWith('data: ')) return;

      final jsonStr = trimmed.substring(6);
      try {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final tokenUsage = parseUsage(data);
        if (tokenUsage != null) {
          lastTokenUsage = tokenUsage;
        }

        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          return;
        }

        final choice = choices.first;
        if (choice is! Map<String, dynamic>) {
          return;
        }

        final delta =
            (choice['delta'] ?? choice['message']) as Map<String, dynamic>?;
        if (delta != null) {
          for (final text in extractTextParts(delta['content'])) {
            yield StreamEvent(type: StreamEventType.textDelta, text: text);
          }

          for (final thinking in extractThinkingParts(delta)) {
            yield StreamEvent(
              type: StreamEventType.thinkingDelta,
              thinking: thinking,
            );
          }

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

          final functionCall = delta['function_call'] as Map<String, dynamic>?;
          if (functionCall != null) {
            final id = 'function_call_legacy';
            final name = functionCall['name'] as String?;
            final argsDelta = functionCall['arguments'] as String? ?? '';
            if (!toolCallArgs.containsKey(id) && name != null) {
              toolCallArgs[id] = StringBuffer();
              yield StreamEvent(
                type: StreamEventType.toolCallStart,
                toolCallId: id,
                toolName: name,
              );
            }
            if (argsDelta.isNotEmpty) {
              toolCallArgs[id]?.write(argsDelta);
              yield StreamEvent(
                type: StreamEventType.toolCallDelta,
                toolCallId: id,
                argumentsDelta: argsDelta,
              );
            }
          }
        }

        final finishReason = choice['finish_reason'] as String?;
        if (finishReason != null) {
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
            usage: tokenUsage ?? lastTokenUsage,
          );
          messageEnded = true;
        }
      } catch (_) {}
    }

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        for (final event in parseSseLine(line)) {
          yield event;
        }
      }
    }

    if (buffer.trim().isNotEmpty) {
      for (final event in parseSseLine(buffer)) {
        yield event;
      }
    }

    if (!messageEnded) {
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
        stopReason: 'stream_end',
        usage: lastTokenUsage,
      );
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


List<Map<String, dynamic>> _formatOpenAIResponsesInput(
  List<UnifiedMessage> messages,
) {
  final input = <Map<String, dynamic>>[];

  for (final message in messages) {
    if (message.role == MessageRole.system) {
      input.add({
        'type': 'message',
        'role': 'developer',
        'content': message.textContent,
      });
      continue;
    }

    if (message.content is String) {
      input.add({
        'type': 'message',
        'role': message.role.name,
        'content': message.content,
      });
      continue;
    }

    for (final block in message.blocks) {
      switch (block.type) {
        case 'text':
          input.add({
            'type': 'message',
            'role': message.role.name,
            'content': block.text ?? '',
          });
          break;
        case 'thinking':
          break;
        case 'tool_use':
          if (message.role == MessageRole.assistant) {
            input.add({
              'type': 'function_call',
              'call_id': block.toolCallId,
              'name': block.toolName,
              'arguments': jsonEncode(block.toolInput ?? <String, dynamic>{}),
              'status': 'completed',
            });
          }
          break;
        case 'tool_result':
          input.add({
            'type': 'function_call_output',
            'call_id': block.toolCallId,
            'output': block.toolResultContent ?? '',
          });
          break;
      }
    }
  }

  return input;
}

Stream<StreamEvent> _sendOpenAIResponses(
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
  final url = _resolveOpenAIUrl(baseUrl, '/responses');

  final body = <String, dynamic>{
    'model': config.model,
    'input': _formatOpenAIResponsesInput(messages),
    'stream': true,
  };
  if (config.maxTokens > 0) {
    body['max_output_tokens'] = config.maxTokens;
  }
  body['temperature'] = config.temperature;
  if (config.thinkingEnabled) {
    body['reasoning'] = {'summary': 'auto'};
    body['include'] = ['reasoning.encrypted_content'];
  }
  if (tools.isNotEmpty) {
    body['tools'] = tools
        .map(
          (t) => {
            'type': 'function',
            'name': t.name,
            'description': t.description,
            'parameters': t.inputSchema,
          },
        )
        .toList();
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
    String? currentEvent;
    final dataLines = <String>[];
    final responseItemToCallId = <String, String>{};
    final responseToolCallArgs = <String, StringBuffer>{};
    final responseToolNames = <String, String>{};
    final finishedToolCalls = <String>{};
    TokenUsage? lastUsage;
    var messageEnded = false;
    var emittedThinkingDelta = false;

    Iterable<StreamEvent> processFrame(String? eventName, String dataText) sync* {
      if (dataText.isEmpty || dataText == '[DONE]') {
        return;
      }
      try {
        final data = jsonDecode(dataText) as Map<String, dynamic>;
        switch (eventName) {
          case 'response.output_text.delta':
            final delta = data['delta'] as String?;
            if (delta != null && delta.isNotEmpty) {
              yield StreamEvent(type: StreamEventType.textDelta, text: delta);
            }
            break;
          case 'response.reasoning_summary_text.delta':
            final delta = data['delta'] as String?;
            if (delta != null && delta.isNotEmpty) {
              emittedThinkingDelta = true;
              yield StreamEvent(
                type: StreamEventType.thinkingDelta,
                thinking: delta,
              );
            }
            break;
          case 'response.reasoning_summary_text.done':
            final delta = data['text'] as String? ?? data['delta'] as String?;
            if (!emittedThinkingDelta && delta != null && delta.isNotEmpty) {
              emittedThinkingDelta = true;
              yield StreamEvent(
                type: StreamEventType.thinkingDelta,
                thinking: delta,
              );
            }
            break;
          case 'response.output_item.added':
            final item = data['item'] as Map<String, dynamic>?;
            if (item?['type'] == 'function_call') {
              final itemId = item?['id'] as String?;
              final callId = item?['call_id'] as String?;
              final name = item?['name'] as String?;
              if (itemId != null && callId != null) {
                responseItemToCallId[itemId] = callId;
              }
              if (callId != null) {
                responseToolCallArgs.putIfAbsent(callId, StringBuffer.new);
                if (name != null && name.isNotEmpty) {
                  responseToolNames[callId] = name;
                }
                yield StreamEvent(
                  type: StreamEventType.toolCallStart,
                  toolCallId: callId,
                  toolName: name,
                );
              }
            }
            break;
          case 'response.function_call_arguments.delta':
            final delta = data['delta'] as String? ?? '';
            final itemId = data['item_id'] as String?;
            final callId =
                data['call_id'] as String? ??
                (itemId != null ? responseItemToCallId[itemId] : null);
            if (delta.isNotEmpty && callId != null) {
              responseToolCallArgs.putIfAbsent(callId, StringBuffer.new);
              responseToolCallArgs[callId]!.write(delta);
              yield StreamEvent(
                type: StreamEventType.toolCallDelta,
                toolCallId: callId,
                argumentsDelta: delta,
              );
            }
            break;
          case 'response.function_call_arguments.done':
            final itemId = data['item_id'] as String?;
            final callId =
                data['call_id'] as String? ??
                (itemId != null ? responseItemToCallId[itemId] : null);
            final name =
                data['name'] as String? ??
                (callId != null ? responseToolNames[callId] : null);
            final rawArgs =
                data['arguments'] as String? ??
                (callId != null ? responseToolCallArgs[callId]?.toString() : null) ??
                '';
            Map<String, dynamic>? input;
            try {
              if (rawArgs.isNotEmpty) {
                input = jsonDecode(rawArgs) as Map<String, dynamic>;
              }
            } catch (_) {}
            if (callId != null) {
              finishedToolCalls.add(callId);
              responseToolCallArgs.remove(callId);
              responseToolNames.remove(callId);
            }
            if (itemId != null) {
              responseItemToCallId.remove(itemId);
            }
            yield StreamEvent(
              type: StreamEventType.toolCallEnd,
              toolCallId: callId,
              toolName: name,
              toolCallInput: input,
            );
            break;
          case 'response.completed':
            final responseData = data['response'] as Map<String, dynamic>?;
            final responseOutput = responseData?['output'] as List?;
            if (responseOutput != null) {
              for (final rawItem in responseOutput) {
                if (rawItem is! Map<String, dynamic>) {
                  continue;
                }
                if (rawItem['type'] != 'function_call') {
                  continue;
                }
                final itemId = rawItem['id'] as String?;
                final callId =
                    rawItem['call_id'] as String? ??
                    (itemId != null ? responseItemToCallId[itemId] : null);
                if (callId == null || finishedToolCalls.contains(callId)) {
                  continue;
                }
                final name =
                    rawItem['name'] as String? ?? responseToolNames[callId];
                final rawArgs =
                    rawItem['arguments'] as String? ??
                    responseToolCallArgs[callId]?.toString() ??
                    '';
                Map<String, dynamic>? input;
                try {
                  if (rawArgs.isNotEmpty) {
                    input = jsonDecode(rawArgs) as Map<String, dynamic>;
                  }
                } catch (_) {}
                finishedToolCalls.add(callId);
                yield StreamEvent(
                  type: StreamEventType.toolCallEnd,
                  toolCallId: callId,
                  toolName: name,
                  toolCallInput: input,
                );
              }
            }
            responseItemToCallId.clear();
            responseToolCallArgs.clear();
            responseToolNames.clear();

            final usage = responseData?['usage'] as Map<String, dynamic>?;
            if (usage != null) {
              final inputTokens = usage['input_tokens'] as int? ?? 0;
              final outputTokens = usage['output_tokens'] as int? ?? 0;
              final inputDetails = usage['input_tokens_details'];
              final outputDetails = usage['output_tokens_details'];
              lastUsage = TokenUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                contextTokens: inputTokens,
                cacheReadTokens: inputDetails is Map<String, dynamic>
                    ? inputDetails['cached_tokens'] as int?
                    : null,
                reasoningTokens: outputDetails is Map<String, dynamic>
                    ? outputDetails['reasoning_tokens'] as int?
                    : null,
              );
            }
            yield StreamEvent(
              type: StreamEventType.messageEnd,
              stopReason: responseData?['status'] as String? ?? 'completed',
              usage: lastUsage,
            );
            messageEnded = true;
            break;
          case 'response.failed':
          case 'error':
            yield StreamEvent(
              type: StreamEventType.error,
              errorMessage: jsonEncode(data),
            );
            break;
        }
      } catch (_) {}
    }

    void flushFrameState() {
      dataLines.clear();
      currentEvent = null;
    }

    Iterable<StreamEvent> consumeLine(String line) sync* {
      final normalizedLine = line.replaceAll('\r', '');
      if (normalizedLine.isEmpty) {
        if (dataLines.isNotEmpty) {
          yield* processFrame(currentEvent, dataLines.join('\n'));
        }
        flushFrameState();
        return;
      }
      if (normalizedLine.startsWith('event:')) {
        currentEvent = normalizedLine.substring(6).trim();
        return;
      }
      if (normalizedLine.startsWith('data:')) {
        dataLines.add(normalizedLine.substring(5).trimLeft());
      }
    }

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final line in lines) {
        for (final event in consumeLine(line)) {
          yield event;
        }
      }
    }

    if (buffer.trim().isNotEmpty) {
      for (final event in consumeLine(buffer)) {
        yield event;
      }
    }

    if (dataLines.isNotEmpty) {
      for (final event in processFrame(currentEvent, dataLines.join('\n'))) {
        yield event;
      }
      flushFrameState();
    }

    if (!messageEnded) {
      yield StreamEvent(
        type: StreamEventType.messageEnd,
        stopReason: 'stream_end',
        usage: lastUsage,
      );
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
    TokenUsage? lastTokenUsage;
    var messageEnded = false;

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
              if (usage != null) {
                lastTokenUsage = TokenUsage(
                  inputTokens: usage['input_tokens'] as int? ?? 0,
                  outputTokens: usage['output_tokens'] as int? ?? 0,
                );
              }
              yield StreamEvent(
                type: StreamEventType.messageEnd,
                stopReason: delta?['stop_reason'] as String?,
                usage: lastTokenUsage,
              );
              messageEnded = true;
              break;
          }
        } catch (_) {}
      }
    }

    if (!messageEnded) {
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
      }

      yield StreamEvent(
        type: StreamEventType.messageEnd,
        stopReason: 'stream_end',
        usage: lastTokenUsage,
      );
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
