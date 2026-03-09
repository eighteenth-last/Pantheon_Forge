import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/agent/agent_events.dart';
import 'package:pantheon_forge/services/tools/local_workspace_service.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

typedef AgentToolInputRepair = Map<String, dynamic> Function({
  required AgentPendingToolCall call,
  required Map<String, dynamic> input,
  required String userText,
  required List<UnifiedMessage> history,
});

typedef AgentToolExecutor = Future<ToolExecutionResult> Function({
  required String workingFolder,
  required AgentPendingToolCall call,
  required Map<String, dynamic> input,
});

class AgentExecutedToolCall {
  AgentExecutedToolCall({required this.call, required this.result});

  final AgentPendingToolCall call;
  final ToolExecutionResult result;
}

class AgentToolExecutionBatch {
  const AgentToolExecutionBatch({
    required this.toolResults,
    required this.repeatedCalls,
    required this.toolMessages,
  });

  final List<AgentExecutedToolCall> toolResults;
  final List<AgentPendingToolCall> repeatedCalls;
  final List<UnifiedMessage> toolMessages;
}

Future<AgentToolExecutionBatch> executeAgentToolBatch({
  required String workingFolder,
  required List<AgentPendingToolCall> executableCalls,
  required String userText,
  required List<UnifiedMessage> history,
  required Map<String, int> executedCallCounts,
  required String Function(AgentPendingToolCall call, Map<String, dynamic> input)
  toolCallSignature,
  required AgentToolInputRepair repairToolInput,
  required AgentToolExecutor executeTool,
}) async {
  final toolResults = <AgentExecutedToolCall>[];
  final repeatedCalls = <AgentPendingToolCall>[];
  final toolMessages = <UnifiedMessage>[];

  for (final call in executableCalls) {
    var input = Map<String, dynamic>.from(
      call.input ?? call.tryParseInput() ?? <String, dynamic>{},
    );
    input = repairToolInput(
      call: call,
      input: input,
      userText: userText,
      history: history,
    );
    call.input = input;

    final signature = toolCallSignature(call, input);
    final executionCount = executedCallCounts[signature] ?? 0;
    if (executionCount >= 1) {
      repeatedCalls.add(call);
      continue;
    }
    executedCallCounts[signature] = executionCount + 1;

    final result = await executeTool(
      workingFolder: workingFolder,
      call: call,
      input: input,
    );
    toolResults.add(AgentExecutedToolCall(call: call, result: result));
    toolMessages.add(
      UnifiedMessage(
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
      ),
    );
  }

  return AgentToolExecutionBatch(
    toolResults: toolResults,
    repeatedCalls: repeatedCalls,
    toolMessages: toolMessages,
  );
}
