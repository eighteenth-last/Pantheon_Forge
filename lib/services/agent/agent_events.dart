import 'dart:convert';

import 'package:pantheon_forge/models/models.dart';

class AgentPendingToolCall {
  AgentPendingToolCall({required this.id, required this.name});

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
    } catch (_) {
      try {
        final loose = _parseInputLoosely(argumentsBuffer.toString());
        if (loose.isNotEmpty) {
          input = loose;
        }
      } catch (_) {
        return input;
      }
    }
    return input;
  }

  Map<String, dynamic> _parseInputLoosely(String rawArgs) {
    final parsed = <String, dynamic>{};

    String? readStringField(String key) {
      try {
        final pattern = RegExp(
          '"${RegExp.escape(key)}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"',
        );
        final match = pattern.firstMatch(rawArgs);
        if (match == null) {
          return null;
        }
        final value = match.group(1);
        if (value == null) {
          return null;
        }
        return value
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\r', '\r')
            .replaceAll(r'\t', '\t')
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', '\\');
      } catch (_) {
        return null;
      }
    }

    final path = readStringField('path') ??
        readStringField('file_path') ??
        readStringField('filename');
    if (path != null && path.trim().isNotEmpty) {
      parsed['path'] = path.trim();
    }

    if (name == 'write_file') {
      final content = readStringField('content') ??
          readStringField('code') ??
          readStringField('text');
      if (content != null) {
        parsed['content'] = content;
      }
    }

    if (name == 'edit_file') {
      final oldString = readStringField('old_string');
      final newString = readStringField('new_string');
      if (oldString != null) {
        parsed['old_string'] = oldString;
      }
      if (newString != null) {
        parsed['new_string'] = newString;
      }
    }

    return parsed;
  }
}

class AgentStreamTurn {
  const AgentStreamTurn({
    required this.assistantMessage,
    required this.toolCalls,
    required this.responseEnded,
  });

  final UnifiedMessage assistantMessage;
  final Map<String, AgentPendingToolCall> toolCalls;
  final bool responseEnded;
}
