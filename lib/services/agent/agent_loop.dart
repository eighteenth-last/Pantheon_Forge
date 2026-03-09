import 'package:dio/dio.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/agent/agent_events.dart';
import 'package:pantheon_forge/services/api/llm_api.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

typedef AssistantMessageBuilder = UnifiedMessage Function({
  required String id,
  required int createdAt,
  required String text,
  required String thinking,
  required List<AgentPendingToolCall> toolCalls,
  TokenUsage? usage,
});

Future<AgentStreamTurn> streamAssistantTurn({
  required List<UnifiedMessage> messages,
  required ProviderConfig config,
  required List<ToolDefinition> tools,
  required CancelToken? cancelToken,
  required String assistantId,
  required int assistantCreatedAt,
  required AssistantMessageBuilder buildAssistantMessage,
  required void Function(UnifiedMessage message) onAssistantUpdated,
}) async {
  var assistantMsg = UnifiedMessage(
    id: assistantId,
    role: MessageRole.assistant,
    content: '',
    createdAt: assistantCreatedAt,
  );

  for (var attempt = 0; attempt < 2; attempt++) {
    final textBuf = StringBuffer();
    final thinkingBuf = StringBuffer();
    final toolCalls = <String, AgentPendingToolCall>{};
    var responseEnded = false;
    var hasError = false;

    await for (final event in sendMessageStream(
      messages: messages,
      config: config,
      tools: tools,
      cancelToken: cancelToken,
    )) {
      switch (event.type) {
        case StreamEventType.textDelta:
          textBuf.write(event.text ?? '');
          assistantMsg = buildAssistantMessage(
            id: assistantId,
            createdAt: assistantCreatedAt,
            text: textBuf.toString(),
            thinking: thinkingBuf.toString(),
            toolCalls: toolCalls.values.toList(),
          );
          onAssistantUpdated(assistantMsg);
          break;
        case StreamEventType.thinkingDelta:
          thinkingBuf.write(event.thinking ?? '');
          assistantMsg = buildAssistantMessage(
            id: assistantId,
            createdAt: assistantCreatedAt,
            text: textBuf.toString(),
            thinking: thinkingBuf.toString(),
            toolCalls: toolCalls.values.toList(),
          );
          onAssistantUpdated(assistantMsg);
          break;
        case StreamEventType.toolCallStart:
          final toolCallId = event.toolCallId ?? _uuid.v4();
          toolCalls[toolCallId] = AgentPendingToolCall(
            id: toolCallId,
            name: event.toolName ?? 'unknown_tool',
          );
          assistantMsg = buildAssistantMessage(
            id: assistantId,
            createdAt: assistantCreatedAt,
            text: textBuf.toString(),
            thinking: thinkingBuf.toString(),
            toolCalls: toolCalls.values.toList(),
          );
          onAssistantUpdated(assistantMsg);
          break;
        case StreamEventType.toolCallDelta:
          final toolCallId = event.toolCallId ??
              (toolCalls.isNotEmpty ? toolCalls.keys.last : null);
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
              () => AgentPendingToolCall(
                id: toolCallId,
                name: event.toolName ?? 'unknown_tool',
              ),
            );
            call.input = event.toolCallInput ?? call.tryParseInput();
          }
          assistantMsg = buildAssistantMessage(
            id: assistantId,
            createdAt: assistantCreatedAt,
            text: textBuf.toString(),
            thinking: thinkingBuf.toString(),
            toolCalls: toolCalls.values.toList(),
            usage: event.usage,
          );
          onAssistantUpdated(assistantMsg);
          break;
        case StreamEventType.messageEnd:
          responseEnded = true;
          assistantMsg = buildAssistantMessage(
            id: assistantId,
            createdAt: assistantCreatedAt,
            text: textBuf.toString(),
            thinking: thinkingBuf.toString(),
            toolCalls: toolCalls.values.toList(),
            usage: event.usage,
          );
          onAssistantUpdated(assistantMsg);
          break;
        case StreamEventType.error:
          final errorContent = textBuf.isEmpty
              ? '⚠️ ${event.errorMessage ?? "Unknown error"}'
              : '${textBuf.toString()}\n\n⚠️ ${event.errorMessage}';
          assistantMsg = UnifiedMessage(
            id: assistantId,
            role: MessageRole.assistant,
            content: errorContent,
            createdAt: assistantCreatedAt,
          );
          onAssistantUpdated(assistantMsg);
          responseEnded = true;
          hasError = true;
          toolCalls.clear();
          break;
        default:
          break;
      }
    }

    final isEmptyVisibleResponse =
        !hasError &&
        responseEnded &&
        textBuf.isEmpty &&
        thinkingBuf.isEmpty &&
        toolCalls.isEmpty;

    if (isEmptyVisibleResponse && attempt == 0) {
      continue;
    }

    return AgentStreamTurn(
      assistantMessage: assistantMsg,
      toolCalls: toolCalls,
      responseEnded: responseEnded,
    );
  }

  return AgentStreamTurn(
    assistantMessage: assistantMsg,
    toolCalls: const {},
    responseEnded: true,
  );
}