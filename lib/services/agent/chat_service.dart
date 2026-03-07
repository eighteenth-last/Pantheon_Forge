import 'dart:async';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/services/api/llm_api.dart';

const _uuid = Uuid();

class ChatService {
  CancelToken? _cancelToken;

  Future<void> sendMessage({
    required String text,
    required String sessionId,
    required ChatNotifier chat,
    required ProviderNotifier providerNotifier,
    required AppSettings settings,
  }) async {
    final config = providerNotifier.activeProviderConfig;
    if (config == null) return;

    // Add user message
    final userMsg = UnifiedMessage(
      id: _uuid.v4(), role: MessageRole.user, content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    chat.addMessage(sessionId, userMsg);

    // Add system prompt if set
    final messages = <UnifiedMessage>[];
    if (settings.systemPrompt.isNotEmpty) {
      messages.add(UnifiedMessage(
        id: 'system', role: MessageRole.system, content: settings.systemPrompt,
        createdAt: 0,
      ));
    }
    messages.addAll(chat.getMessages(sessionId));

    // Create assistant message placeholder
    final assistantId = _uuid.v4();
    var assistantMsg = UnifiedMessage(
      id: assistantId, role: MessageRole.assistant, content: '',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    chat.addMessage(sessionId, assistantMsg);
    chat.setStreaming(assistantId);

    _cancelToken = CancelToken();
    final textBuf = StringBuffer();

    try {
      final providerConfig = ProviderConfig(
        type: config.type, apiKey: config.apiKey,
        baseUrl: config.baseUrl, model: config.model,
        maxTokens: settings.maxTokens,
        temperature: settings.temperature,
      );

      await for (final event in sendMessageStream(
        messages: messages, config: providerConfig, cancelToken: _cancelToken,
      )) {
        switch (event.type) {
          case StreamEventType.textDelta:
            textBuf.write(event.text ?? '');
            assistantMsg = UnifiedMessage(
              id: assistantId, role: MessageRole.assistant,
              content: textBuf.toString(),
              createdAt: assistantMsg.createdAt,
            );
            chat.updateLastAssistantMessage(sessionId, assistantMsg);
            break;
          case StreamEventType.messageEnd:
            assistantMsg = UnifiedMessage(
              id: assistantId, role: MessageRole.assistant,
              content: textBuf.toString(),
              createdAt: assistantMsg.createdAt,
              usage: event.usage,
            );
            chat.updateLastAssistantMessage(sessionId, assistantMsg);
            break;
          case StreamEventType.error:
            final errorContent = textBuf.isEmpty
                ? '⚠️ ${event.errorMessage ?? "Unknown error"}'
                : '${textBuf}\n\n⚠️ ${event.errorMessage}';
            assistantMsg = UnifiedMessage(
              id: assistantId, role: MessageRole.assistant,
              content: errorContent,
              createdAt: assistantMsg.createdAt,
            );
            chat.updateLastAssistantMessage(sessionId, assistantMsg);
            break;
          default:
            break;
        }
      }
    } catch (e) {
      if (e is! DioException || e.type != DioExceptionType.cancel) {
        assistantMsg = UnifiedMessage(
          id: assistantId, role: MessageRole.assistant,
          content: '${textBuf}${textBuf.isEmpty ? '' : '\n\n'}⚠️ $e',
          createdAt: assistantMsg.createdAt,
        );
        chat.updateLastAssistantMessage(sessionId, assistantMsg);
      }
    } finally {
      chat.setStreaming(null);
      _cancelToken = null;
    }
  }

  void stopStreaming() {
    _cancelToken?.cancel('User stopped');
  }
}
