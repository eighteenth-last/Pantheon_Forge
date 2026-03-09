import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/agent/agent_events.dart';
import 'package:pantheon_forge/services/agent/agent_tool_executor.dart';
import 'package:pantheon_forge/services/agent/agent_workspace_helpers.dart';

bool hasVisibleAssistantContent(UnifiedMessage message) {
  final blocks = message.blocks;
  if (blocks.isEmpty) {
    return message.textContent.trim().isNotEmpty;
  }
  for (final block in blocks) {
    if (block.type == 'text' && (block.text?.trim().isNotEmpty ?? false)) {
      return true;
    }
    if (block.type == 'thinking' &&
        (block.thinking?.trim().isNotEmpty ?? false)) {
      return true;
    }
  }
  return false;
}

String synthesizeToolCompletion(List<AgentExecutedToolCall> toolResults) {
  final successCalls = toolResults.where((entry) => !entry.result.isError).toList();
  if (successCalls.isEmpty) {
    return '\u5de5\u5177\u5df2\u7ecf\u6267\u884c\u5b8c\u6210\uff0c\u4f46\u6a21\u578b\u6ca1\u6709\u7ee7\u7eed\u7ed9\u51fa\u53ef\u89c1\u5185\u5bb9\u3002';
  }

  final first = successCalls.first;
  final targetPath = extractPathFromToolResult(first.result.content);

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

String buildRepeatedToolFallback({
  required String userText,
  required List<AgentPendingToolCall> repeatedCalls,
  required List<UnifiedMessage> history,
}) {
  if (looksLikeWriteIntent(userText)) {
    final directory = extractMentionedWorkspaceDirectory(userText, history);
    if (!containsLikelyFileName(userText)) {
      if (directory != null) {
        return '\u6211\u5df2\u7ecf\u5b9a\u4f4d\u5230\u76ee\u5f55 `$directory`\uff0c\u4f46\u6a21\u578b\u8fde\u7eed\u91cd\u590d\u8c03\u7528\u5de5\u5177\u4e14\u4ecd\u7f3a\u5c11\u660e\u786e\u6587\u4ef6\u4fe1\u606f\u3002\u8bf7\u76f4\u63a5\u7ed9\u4e00\u4e2a\u6587\u4ef6\u540d\uff0c\u4f8b\u5982 `$directory/hello.py`\u3002';
      }
      return '\u6211\u77e5\u9053\u4f60\u8981\u521b\u5efa\u4ee3\u7801\u6587\u4ef6\uff0c\u4f46\u6a21\u578b\u8fde\u7eed\u91cd\u590d\u8c03\u7528\u5de5\u5177\u4e14\u4ecd\u7f3a\u5c11\u660e\u786e\u6587\u4ef6\u540d\u3002\u8bf7\u76f4\u63a5\u8865\u4e00\u4e2a\u6587\u4ef6\u540d\uff0c\u4f8b\u5982 `scripts/hello.py`\u3002';
    }
  }

  final toolNames = repeatedCalls.map((call) => call.name).toSet().join('\u3001');
  return '\u6211\u521a\u68c0\u6d4b\u5230\u91cd\u590d\u7684\u5de5\u5177\u8c03\u7528\uff08$toolNames\uff09\uff0c\u7ee7\u7eed\u6267\u884c\u4e5f\u4e0d\u4f1a\u4ea7\u751f\u65b0\u7ed3\u679c\uff0c\u6240\u4ee5\u5148\u505c\u4e0b\u6765\u3002\u8bf7\u66f4\u5177\u4f53\u8bf4\u660e\u76ee\u6807\u6587\u4ef6\u3001\u76ee\u5f55\u6216\u4e0b\u4e00\u6b65\u64cd\u4f5c\u3002';
}

String buildToolErrorFallback({
  required String userText,
  required List<UnifiedMessage> history,
}) {
  if (looksLikeWriteIntent(userText) && !containsLikelyFileName(userText)) {
    final directory = extractMentionedWorkspaceDirectory(userText, history);
    if (directory != null) {
      return '\u6211\u5df2\u7ecf\u77e5\u9053\u76ee\u6807\u76ee\u5f55\u662f `$directory`\u3002\u8bf7\u8865\u5145\u8981\u521b\u5efa\u6216\u4fee\u6539\u7684\u6587\u4ef6\u540d\uff0c\u4f8b\u5982 `$directory/main.py`\u3002';
    }
    return '\u8fd9\u6b21\u5de5\u5177\u8c03\u7528\u7f3a\u5c11\u660e\u786e\u7684\u6587\u4ef6\u8def\u5f84\u3002\u8bf7\u544a\u8bc9\u6211\u8981\u521b\u5efa\u6216\u4fee\u6539\u7684\u6587\u4ef6\u540d\uff0c\u4f8b\u5982 `src/main.py`\u3002';
  }

  return '\u8fd9\u6b21\u5de5\u5177\u8c03\u7528\u7f3a\u5c11\u660e\u786e\u7684\u6587\u4ef6\u8def\u5f84\u6216\u53c2\u6570\u3002\u8bf7\u76f4\u63a5\u544a\u8bc9\u6211\u8981\u8bfb\u53d6\u7684\u6587\u4ef6\u3001\u8981\u521b\u5efa\u7684\u6587\u4ef6\u540d\uff0c\u6216\u8981\u6267\u884c\u7684\u547d\u4ee4\u3002';
}

String buildEmptyAssistantFallback({required bool responseEnded}) {
  if (responseEnded) {
    return '\u6a21\u578b\u672c\u6b21\u8fd4\u56de\u4e86\u7a7a\u54cd\u5e94\uff0c\u6ca1\u6709\u53ef\u663e\u793a\u5185\u5bb9\u3002\u8bf7\u91cd\u8bd5\u4e00\u6b21\uff0c\u6216\u6362\u4e00\u79cd\u8bf4\u6cd5\u3002';
  }
  return '\u8fd9\u6b21\u8bf7\u6c42\u6ca1\u6709\u6536\u5230\u5b8c\u6574\u54cd\u5e94\uff0c\u53ef\u80fd\u662f\u6d41\u5f0f\u8f93\u51fa\u88ab\u4e2d\u65ad\u4e86\u3002\u8bf7\u91cd\u8bd5\u4e00\u6b21\u3002';
}

String? buildImmediateClarificationForWriteIntent({
  required String text,
  required List<UnifiedMessage> history,
}) {
  if (!looksLikeWriteIntent(text) || containsLikelyFileName(text)) {
    return null;
  }

  if (allowsAssistantToChoosePath(text, history)) {
    return null;
  }

  final directory = extractMentionedWorkspaceDirectory(text, history);
  if (directory != null) {
    return '\u6211\u5df2\u7ecf\u5b9a\u4f4d\u5230\u76ee\u5f55 `$directory`\u3002\u8bf7\u518d\u544a\u8bc9\u6211\u4e24\u70b9\uff1a1\uff09\u6587\u4ef6\u540d\uff0c\u4f8b\u5982 `$directory/hello.py`\uff1b2\uff09\u8fd9\u6bb5\u4ee3\u7801\u8981\u5b9e\u73b0\u4ec0\u4e48\u529f\u80fd\u3002';
  }

  return '\u6211\u53ef\u4ee5\u76f4\u63a5\u5e2e\u4f60\u521b\u5efa\u4ee3\u7801\u6587\u4ef6\u3002\u8bf7\u544a\u8bc9\u6211\u6587\u4ef6\u540d\u548c\u529f\u80fd\uff0c\u4f8b\u5982 `scripts/hello.py`\uff0c\u4ee5\u53ca\u8fd9\u6bb5\u4ee3\u7801\u8981\u505a\u4ec0\u4e48\u3002';
}
