import 'package:dio/dio.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/agent/agent_events.dart';
import 'package:pantheon_forge/services/agent/agent_loop.dart';
import 'package:pantheon_forge/services/agent/agent_tool_executor.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

typedef AgentVisibleContentChecker = bool Function(UnifiedMessage message);
typedef AgentEmptyAssistantFallback = String Function({
  required bool responseEnded,
});
typedef AgentToolCompletionFallback = String Function(
  List<AgentExecutedToolCall> toolResults,
);
typedef AgentToolCallSelector = List<AgentPendingToolCall> Function(
  List<AgentPendingToolCall> calls,
);
typedef AgentRepeatedToolFallback = String Function({
  required String userText,
  required List<AgentPendingToolCall> repeatedCalls,
  required List<UnifiedMessage> history,
});
typedef AgentStopAfterToolErrors = bool Function(
  List<AgentExecutedToolCall> toolResults,
);
typedef AgentToolErrorFallback = String Function({
  required String userText,
  required List<UnifiedMessage> history,
});

Future<void> runAgentLoop({
  required List<UnifiedMessage> conversation,
  required String userText,
  required String? workspacePath,
  required ProviderConfig providerConfig,
  required List<ToolDefinition> tools,
  required CancelToken? cancelToken,
  required AssistantMessageBuilder buildAssistantMessage,
  required void Function(String assistantId) onStreamingStarted,
  required void Function(UnifiedMessage message) onAssistantPlaceholderAdded,
  required void Function(UnifiedMessage message) onAssistantUpdated,
  required void Function(UnifiedMessage message) onMessageAdded,
  required AgentVisibleContentChecker hasVisibleAssistantContent,
  required AgentEmptyAssistantFallback buildEmptyAssistantFallback,
  required AgentToolCompletionFallback synthesizeToolCompletion,
  required AgentToolCallSelector selectExecutableToolCalls,
  required AgentToolInputRepair repairToolInput,
  required String Function(AgentPendingToolCall call, Map<String, dynamic> input)
  toolCallSignature,
  required AgentToolExecutor executeTool,
  required AgentRepeatedToolFallback buildRepeatedToolFallback,
  required AgentStopAfterToolErrors shouldStopAfterToolErrors,
  required AgentToolErrorFallback buildToolErrorFallback,
}) async {
  var previousToolResults = <AgentExecutedToolCall>[];
  final executedCallCounts = <String, int>{};
  var consecutiveEmptyIterations = 0;

  for (var iteration = 0; iteration < 6; iteration++) {
    final assistantId = _uuid.v4();
    final assistantCreatedAt = DateTime.now().millisecondsSinceEpoch;
    var assistantMsg = UnifiedMessage(
      id: assistantId,
      role: MessageRole.assistant,
      content: '',
      createdAt: assistantCreatedAt,
    );
    onAssistantPlaceholderAdded(assistantMsg);
    onStreamingStarted(assistantId);

    final turn = await streamAssistantTurn(
      messages: conversation,
      config: providerConfig,
      tools: tools,
      cancelToken: cancelToken,
      assistantId: assistantId,
      assistantCreatedAt: assistantCreatedAt,
      buildAssistantMessage: buildAssistantMessage,
      onAssistantUpdated: (message) {
        assistantMsg = message;
        onAssistantUpdated(message);
      },
    );
    final toolCalls = turn.toolCalls;
    final responseEnded = turn.responseEnded;
    assistantMsg = turn.assistantMessage;

    if (previousToolResults.isEmpty &&
        toolCalls.isEmpty &&
        !hasVisibleAssistantContent(assistantMsg)) {
      assistantMsg = UnifiedMessage(
        id: assistantId,
        role: MessageRole.assistant,
        content: buildEmptyAssistantFallback(responseEnded: responseEnded),
        createdAt: assistantCreatedAt,
        usage: assistantMsg.usage,
      );
      onAssistantUpdated(assistantMsg);
    }

    conversation.add(assistantMsg);

    if ((toolCalls.isEmpty || workspacePath == null) &&
        previousToolResults.isNotEmpty &&
        !hasVisibleAssistantContent(assistantMsg)) {
      final fallback = UnifiedMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: synthesizeToolCompletion(previousToolResults),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      onMessageAdded(fallback);
      conversation.add(fallback);
      previousToolResults = <AgentExecutedToolCall>[];
      break;
    }

    if (!responseEnded || toolCalls.isEmpty || workspacePath == null) {
      previousToolResults = <AgentExecutedToolCall>[];
      break;
    }

    final executableCalls = selectExecutableToolCalls(toolCalls.values.toList());
    final toolBatch = await executeAgentToolBatch(
      workingFolder: workspacePath,
      executableCalls: executableCalls,
      userText: userText,
      history: conversation,
      executedCallCounts: executedCallCounts,
      toolCallSignature: toolCallSignature,
      repairToolInput: repairToolInput,
      executeTool: executeTool,
    );
    final toolResults = toolBatch.toolResults;
    final repeatedCalls = toolBatch.repeatedCalls;
    for (final toolMessage in toolBatch.toolMessages) {
      onMessageAdded(toolMessage);
      conversation.add(toolMessage);
    }
    previousToolResults = toolResults;

    // 检测连续空迭代（工具调用但没有实际执行）
    if (toolResults.isEmpty && repeatedCalls.isEmpty) {
      consecutiveEmptyIterations++;
      if (consecutiveEmptyIterations >= 2) {
        final fallback = UnifiedMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: '检测到循环调用，已自动停止。请提供更具体的文件路径或操作指令。',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        onMessageAdded(fallback);
        conversation.add(fallback);
        break;
      }
    } else {
      consecutiveEmptyIterations = 0;
    }

    if (toolResults.isEmpty && repeatedCalls.isNotEmpty) {
      final fallback = UnifiedMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: buildRepeatedToolFallback(
          userText: userText,
          repeatedCalls: repeatedCalls,
          history: conversation,
        ),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      onMessageAdded(fallback);
      conversation.add(fallback);
      break;
    }

    if (toolResults.isEmpty) {
      final fallback = UnifiedMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content:
            'No effective tool call was executed. I stopped retrying. Please specify the target file, directory, or next action.',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      onMessageAdded(fallback);
      conversation.add(fallback);
      break;
    }

    if (shouldStopAfterToolErrors(toolResults)) {
      final fallback = UnifiedMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: buildToolErrorFallback(
          userText: userText,
          history: conversation,
        ),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      onMessageAdded(fallback);
      conversation.add(fallback);
      break;
    }
  }
}
