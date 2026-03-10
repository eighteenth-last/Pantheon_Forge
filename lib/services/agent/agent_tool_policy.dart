import 'dart:convert';

import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/agent/agent_events.dart';
import 'package:pantheon_forge/services/agent/agent_tool_executor.dart';
import 'package:pantheon_forge/services/agent/agent_workspace_helpers.dart';

List<AgentPendingToolCall> selectExecutableToolCalls(
  List<AgentPendingToolCall> calls,
) {
  final selected = <AgentPendingToolCall>[];
  final seen = <String>{};
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
        if (hasDiscoveryTool) {
          continue;
        }
        final autoSummaryCall = AgentPendingToolCall(
          id: '${call.id}_auto_summary',
          name: 'summarize_project',
        )..input = const <String, dynamic>{};
        final autoSignature = '${autoSummaryCall.name}:${jsonEncode(autoSummaryCall.input)}';
        if (seen.add(autoSignature)) {
          selected.add(autoSummaryCall);
          hasDiscoveryTool = true;
          if (selected.length >= 3) break;
        }
        continue;
      }
    }

    selected.add(call);
    if (selected.length >= 3) break;
  }

  return selected;
}

bool shouldStopAfterToolErrors(List<AgentExecutedToolCall> toolResults) {
  if (toolResults.isEmpty) return false;
  return toolResults.every((entry) {
    if (!entry.result.isError) return false;
    final message = entry.result.content.toLowerCase();

    if (entry.call.name == 'write_file') {
      return false;
    }

    if (entry.call.name == 'edit_file') {
      return message.contains('file not found') ||
          message.contains('old_string not found');
    }

    if (entry.call.name == 'read_file') {
      return false;
    }

    if (entry.call.name == 'run_command') {
      return message.contains('blocked command');
    }

    return message.startsWith('missing ');
  });
}

Map<String, dynamic> repairToolInput({
  required AgentPendingToolCall call,
  required Map<String, dynamic> input,
  required String userText,
  required List<UnifiedMessage> history,
}) {
  // 标准化 list_directory 的 path 参数
  if (call.name == 'list_directory') {
    final repaired = <String, dynamic>{...input};
    final path = (repaired['path'] as String?)?.trim();
    // 将空路径、null 或 '.' 统一标准化为 '.'
    if (path == null || path.isEmpty || path == '.') {
      repaired['path'] = '.';
    }
    return repaired;
  }

  if (call.name == 'write_file') {
    final repaired = <String, dynamic>{...input};

    final aliasPath = (repaired['path'] as String?)?.trim().isNotEmpty == true
        ? repaired['path'] as String
        : ((repaired['file_path'] as String?)?.trim().isNotEmpty == true
              ? repaired['file_path'] as String
              : ((repaired['filename'] as String?)?.trim().isNotEmpty == true
                    ? repaired['filename'] as String
                    : null));
    if (aliasPath != null && aliasPath.trim().isNotEmpty) {
      repaired['path'] = aliasPath.trim();
    }

    final aliasContent = repaired['content'] ?? repaired['code'] ?? repaired['text'];
    if (aliasContent is String && aliasContent.isNotEmpty) {
      repaired['content'] = aliasContent;
    }

    final currentPath = (repaired['path'] as String?)?.trim();
    if ((currentPath == null || currentPath.isEmpty) &&
        allowsAssistantToChoosePath(userText, history)) {
      final inferredPath = inferDefaultWritePath(userText, history);
      if (inferredPath != null && inferredPath.trim().isNotEmpty) {
        repaired['path'] = inferredPath;
      }
    }

    final currentContent = repaired['content'];
    if (currentContent is! String || currentContent.trim().isEmpty) {
      final inferredContent = inferDefaultWriteContent(
        text: userText,
        history: history,
        path: repaired['path'] as String?,
      );
      if (inferredContent != null && inferredContent.trim().isNotEmpty) {
        repaired['content'] = inferredContent;
      }
    }

    return repaired;
  }

  if (call.name == 'edit_file') {
    final repaired = <String, dynamic>{...input};
    final aliasPath = (repaired['path'] as String?)?.trim().isNotEmpty == true
        ? repaired['path'] as String
        : ((repaired['file_path'] as String?)?.trim().isNotEmpty == true
              ? repaired['file_path'] as String
              : null);
    if (aliasPath != null && aliasPath.trim().isNotEmpty) {
      repaired['path'] = aliasPath.trim();
    }
    return repaired;
  }

  return input;
}

String toolCallSignature(AgentPendingToolCall call, Map<String, dynamic> input) {
  return '${call.name}:${jsonEncode(input)}';
}
