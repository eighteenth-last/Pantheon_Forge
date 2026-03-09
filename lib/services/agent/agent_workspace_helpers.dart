import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/tools/local_workspace_service.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

const _broadKeywords = <String>[
  '\u9605\u8bfb\u6574\u4e2a\u9879\u76ee',
  '\u8bfb\u53d6\u6574\u4e2a\u9879\u76ee',
  '\u67e5\u770b\u6574\u4e2a\u9879\u76ee',
  '\u6d4f\u89c8\u6574\u4e2a\u9879\u76ee',
  '\u5206\u6790\u6574\u4e2a\u9879\u76ee',
  '\u9605\u8bfb\u9879\u76ee',
  '\u9879\u76ee\u7ed3\u6784',
  '\u6574\u4e2a\u9879\u76ee',
  '\u901a\u8bfb\u9879\u76ee',
  '\u770b\u4e0b\u9879\u76ee',
  '\u603b\u7ed3\u9879\u76ee',
  'read the whole project',
  'read the project',
  'project structure',
  'summarize project',
];

const _writeIntentKeywords = <String>[
  '\u5199',
  '\u521b\u5efa',
  '\u65b0\u5efa',
  '\u751f\u6210',
  '\u65b0\u589e',
  '\u4fdd\u5b58\u5230',
  '\u5199\u5165',
  '\u4fee\u6539',
  '\u7f16\u8f91',
  '\u91cd\u5199',
  '\u8986\u76d6',
  'create',
  'write',
  'generate',
  'edit',
  'update',
];

const _choosePathPhrases = <String>[
  '\u4f60\u81ea\u5df1\u51b3\u5b9a',
  '\u4f60\u51b3\u5b9a',
  '\u4f60\u6765\u5b9a',
  '\u6587\u4ef6\u540d\u81ea\u5b9a\u4e49',
  '\u6587\u4ef6\u540d\u968f\u610f',
  '\u6587\u4ef6\u540d\u4f60\u5b9a',
  '\u8def\u5f84\u4f60\u5b9a',
  '\u540d\u5b57\u4f60\u5b9a',
  '\u6587\u4ef6\u540d\u90fd\u53ef\u4ee5',
  '\u6587\u4ef6\u540d\u90fd\u884c',
  '\u4f60\u5e2e\u6211\u5b9a',
  '\u4f60\u5e2e\u6211\u8d77',
  '\u968f\u4fbf',
  '\u90fd\u53ef\u4ee5',
  '\u90fd\u884c',
  '\u4efb\u610f',
  '\u81ea\u884c\u51b3\u5b9a',
  'you decide',
  'your choice',
  'up to you',
  'anything is fine',
];

const _affirmativeReplies = <String>[
  '\u662f',
  '\u53ef\u4ee5',
  '\u597d',
  '\u597d\u7684',
  '\u884c',
  '\u53ef\u4ee5\u7684',
  'ok',
  'okay',
  'yes',
];

bool isBroadWorkspaceIntent(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return _broadKeywords.any(normalized.contains);
}

Future<List<UnifiedMessage>> buildBatchReadPrefetch({
  required String text,
  required String? workspacePath,
  required List<UnifiedMessage> history,
}) async {
  if (workspacePath == null || workspacePath.isEmpty) {
    return const [];
  }

  if (looksLikeWriteIntent(text)) {
    return const [];
  }

  final extension = detectBatchReadExtension(text);
  if (extension == null) {
    return const [];
  }

  final knownFiles = extractKnownWorkspaceFiles(
    history,
  ).where((path) => path.toLowerCase().endsWith(extension)).toList();

  final paths = knownFiles.isNotEmpty
      ? knownFiles
      : await _findFilesByExtension(workspacePath, extension);
  if (paths.isEmpty) {
    return const [];
  }

  return (await prefetchToolMessage(
        workingFolder: workspacePath,
        toolName: 'read_files',
        input: {'paths': paths.take(12).toList(), 'max_chars_per_file': 12000},
      )) ??
      const [];
}

Future<List<String>> _findFilesByExtension(
  String workspacePath,
  String extension,
) async {
  final result = await LocalWorkspaceService.execute(
    workingFolder: workspacePath,
    toolName: 'find_files',
    input: {'query': extension, 'limit': 50},
  );
  if (result.isError) {
    return const [];
  }
  try {
    final decoded = jsonDecode(result.content) as Map<String, dynamic>;
    final matches = (decoded['matches'] as List?) ?? const [];
    return matches.whereType<String>().toList();
  } catch (_) {
    return const [];
  }
}

Future<List<UnifiedMessage>?> prefetchToolMessage({
  required String? workingFolder,
  required String toolName,
  required Map<String, dynamic> input,
}) async {
  if (workingFolder == null || workingFolder.isEmpty) {
    return null;
  }
  final result = await LocalWorkspaceService.execute(
    workingFolder: workingFolder,
    toolName: toolName,
    input: input,
  );
  if (result.isError) {
    return null;
  }
  final toolCallId = _uuid.v4();
  return [
    UnifiedMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: [
        ContentBlock(
          type: 'tool_use',
          toolCallId: toolCallId,
          toolName: toolName,
          toolInput: input,
        ),
      ],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ),
    UnifiedMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: [
        ContentBlock(
          type: 'tool_result',
          toolCallId: toolCallId,
          toolName: toolName,
          toolResultContent: result.content,
          isError: false,
        ),
      ],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ),
  ];
}

List<String> extractKnownWorkspaceFiles(List<UnifiedMessage> history) {
  final files = <String>[];
  for (final message in history.reversed) {
    for (final block in message.blocks) {
      if (block.type != 'tool_result' || block.toolResultContent == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(block.toolResultContent!) as Map<String, dynamic>;
        if (block.toolName == 'summarize_project') {
          final topLevelEntries = (decoded['topLevelEntries'] as List?) ?? const [];
          for (final entry in topLevelEntries) {
            if (entry is Map<String, dynamic> && entry['type'] == 'file') {
              final path = entry['path'] as String?;
              if (path != null && path.isNotEmpty) {
                files.add(path);
              }
            }
          }
        }
        if (block.toolName == 'find_files') {
          final matches = (decoded['matches'] as List?) ?? const [];
          for (final match in matches.whereType<String>()) {
            files.add(match);
          }
        }
      } catch (_) {
        continue;
      }
    }
  }
  return files.toSet().toList();
}

String? detectBatchReadExtension(String text) {
  final normalized = text.trim().toLowerCase();
  const extensionMap = <String, List<String>>{
    '.java': [
      'java\u4ee3\u7801',
      'java \u6587\u4ef6',
      '\u6240\u6709java',
      '\u5168\u90e8java',
      'all java',
      'java files',
    ],
    '.dart': [
      'dart\u4ee3\u7801',
      'dart \u6587\u4ef6',
      '\u6240\u6709dart',
      '\u5168\u90e8dart',
      'all dart',
      'dart files',
    ],
    '.py': [
      'python\u4ee3\u7801',
      'python \u6587\u4ef6',
      'python\u811a\u672c',
      'py \u6587\u4ef6',
      '\u6240\u6709python',
      '\u5168\u90e8python',
      'all python',
      'python files',
    ],
    '.sql': [
      'sql\u4ee3\u7801',
      'sql \u6587\u4ef6',
      '\u6240\u6709sql',
      '\u5168\u90e8sql',
      'all sql',
      'sql files',
    ],
    '.html': [
      'html\u4ee3\u7801',
      'html \u6587\u4ef6',
      '\u7f51\u9875\u6587\u4ef6',
      '\u6240\u6709html',
      '\u5168\u90e8html',
      'all html',
      'html files',
    ],
    '.js': [
      'js\u4ee3\u7801',
      'javascript\u4ee3\u7801',
      'js \u6587\u4ef6',
      '\u6240\u6709js',
      '\u5168\u90e8js',
      'all js',
      'javascript files',
    ],
    '.ts': [
      'ts\u4ee3\u7801',
      'typescript\u4ee3\u7801',
      'ts \u6587\u4ef6',
      '\u6240\u6709ts',
      '\u5168\u90e8ts',
      'all ts',
      'typescript files',
    ],
  };

  for (final entry in extensionMap.entries) {
    if (entry.value.any(normalized.contains)) {
      return entry.key;
    }
  }
  return null;
}

bool looksLikeWriteIntent(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return _writeIntentKeywords.any(normalized.contains);
}

bool containsLikelyFileName(String text) {
  final fileNamePattern = RegExp(
    r'(^|[\\/\s])[^\\/\s]+\.[a-zA-Z0-9]{1,12}(?=$|[\\/\s])',
  );
  return fileNamePattern.hasMatch(text);
}

List<String> extractKnownWorkspaceDirectories(List<UnifiedMessage> history) {
  final directories = <String>[];

  for (final message in history.reversed) {
    for (final block in message.blocks) {
      if (block.type != 'tool_result' || block.toolResultContent == null) {
        continue;
      }

      try {
        final decoded = jsonDecode(block.toolResultContent!) as Map<String, dynamic>;

        if (block.toolName == 'summarize_project') {
          final topLevelEntries = (decoded['topLevelEntries'] as List?) ?? const [];
          for (final entry in topLevelEntries) {
            if (entry is Map<String, dynamic> && entry['type'] == 'dir') {
              final path = entry['path'] as String?;
              if (path != null && path.isNotEmpty) {
                directories.add(path);
              }
            }
          }
        }

        if (block.toolName == 'list_directory') {
          final rawEntries = (decoded['entries'] as List?) ?? const [];
          for (final entry in rawEntries.whereType<String>()) {
            if (entry.startsWith('[DIR] ')) {
              directories.add(entry.substring(6).trim());
            }
          }
        }
      } catch (_) {
        continue;
      }
    }
  }

  return directories.toSet().toList();
}

String? extractMentionedWorkspaceDirectory(
  String text,
  List<UnifiedMessage> history,
) {
  final directories = extractKnownWorkspaceDirectories(history)
    ..sort((a, b) => b.length.compareTo(a.length));

  final candidateTexts = <String>[text, ...recentConversationTexts(history)];
  final atWord = '\u5728';
  final folderWord = '\u6587\u4ef6\u5939';
  final directoryWord = '\u76ee\u5f55';
  final underWords = <String>[
    '\u4e0b\u9762',
    '\u4e0b',
    '\u91cc',
    '\u5185',
  ];
  final actionWords = <String>[
    '\u5199\u5230',
    '\u653e\u5230',
    '\u4fdd\u5b58\u5230',
    '\u521b\u5efa\u5230',
  ];
  final pathCapture = r"""`?([^`\s"']+?)`?""";
  final explicitAtPattern = RegExp(
    '${RegExp.escape(atWord)}\\s*$pathCapture\\s*'
    '(${RegExp.escape(folderWord)}|${RegExp.escape(directoryWord)})\\s*'
    '(${underWords.map(RegExp.escape).join('|')})',
  );
  final explicitActionPattern = RegExp(
    '(${actionWords.map(RegExp.escape).join('|')})\\s*$pathCapture\\s*'
    '(${RegExp.escape(folderWord)}|${RegExp.escape(directoryWord)})',
  );

  for (final candidate in candidateTexts) {
    final candidateNormalized = candidate.trim().toLowerCase();
    if (candidateNormalized.isEmpty) {
      continue;
    }

    final atMatch = explicitAtPattern.firstMatch(candidate);
    final atFolder = atMatch?.group(1)?.trim();
    if (atFolder != null && atFolder.isNotEmpty) {
      return atFolder;
    }

    final actionMatch = explicitActionPattern.firstMatch(candidate);
    final actionFolder = actionMatch?.group(2)?.trim();
    if (actionFolder != null && actionFolder.isNotEmpty) {
      return actionFolder;
    }

    for (final directory in directories) {
      if (candidateNormalized.contains(directory.toLowerCase())) {
        return directory;
      }
    }
  }
  return null;
}


List<String> recentConversationTexts(
  List<UnifiedMessage> history, {
  int limit = 8,
}) {
  final texts = <String>[];
  for (final message in history.reversed) {
    if (message.role != MessageRole.user &&
        message.role != MessageRole.assistant) {
      continue;
    }
    final text = message.textContent.trim();
    if (text.isEmpty) {
      continue;
    }
    texts.add(text);
    if (texts.length >= limit) {
      break;
    }
  }
  return texts;
}

List<String> recentUserTexts(List<UnifiedMessage> history, {int limit = 6}) {
  final texts = <String>[];
  for (final message in history.reversed) {
    if (message.role != MessageRole.user) {
      continue;
    }
    final text = message.textContent.trim();
    if (text.isEmpty) {
      continue;
    }
    texts.add(text);
    if (texts.length >= limit) {
      break;
    }
  }
  return texts;
}

bool allowsAssistantToChoosePath(String text, List<UnifiedMessage> history) {
  final combined = [text, ...recentConversationTexts(history)].join('\n').toLowerCase();
  final normalized = text.trim().toLowerCase();
  if (_choosePathPhrases.any(combined.contains)) {
    return true;
  }
  if (_affirmativeReplies.contains(normalized)) {
    return recentConversationTexts(history).any(looksLikeWriteIntent);
  }
  return false;
}

String? inferDefaultWritePath(String text, List<UnifiedMessage> history) {
  final explicitPath = extractMentionedWorkspaceFilePath(text, history);
  if (explicitPath != null && explicitPath.isNotEmpty) {
    return explicitPath;
  }

  final directory = extractMentionedWorkspaceDirectory(text, history);
  final extension = inferRequestedCodeExtension(text, history) ?? '.txt';
  final fileName = inferDefaultFileName(text, history, extension);

  if (directory == null || directory.trim().isEmpty) {
    return fileName;
  }
  return p.join(directory, fileName);
}


String? extractMentionedWorkspaceFilePath(
  String text,
  List<UnifiedMessage> history,
) {
  final candidateTexts = <String>[text, ...recentConversationTexts(history)];
  final pathPattern = RegExp(
    r'`?([^.\s`][^`\n\r]*?[\\/][^`\n\r]*?\.[a-zA-Z0-9]{1,12})`?',
  );

  for (final candidate in candidateTexts) {
    final match = pathPattern.firstMatch(candidate);
    final path = match?.group(1)?.trim();
    if (path != null && path.isNotEmpty) {
      return path.replaceAll('/', p.separator).replaceAll('\\', p.separator);
    }
  }
  return null;
}

String? inferDefaultWriteContent({
  required String text,
  required List<UnifiedMessage> history,
  String? path,
}) {
  final combined = [text, ...recentConversationTexts(history)].join('\n').toLowerCase();
  final extension = path != null && path.contains('.')
      ? '.${path.split('.').last.toLowerCase()}'
      : (inferRequestedCodeExtension(text, history) ?? '.txt');

  if ((combined.contains('\u4e5d\u4e5d\u4e58\u6cd5\u8868') ||
          combined.contains('\u4e58\u6cd5\u8868')) &&
      extension == '.py') {
    return '''for i in range(1, 10):
    for j in range(1, i + 1):
        print(f"{j}x{i}={i * j}", end="\t")
    print()
''';
  }

  if ((combined.contains('hello') || combined.contains('\u4f60\u597d')) &&
      extension == '.py') {
    return 'print("Hello, world!")\n';
  }

  return null;
}

String? inferRequestedCodeExtension(
  String text,
  List<UnifiedMessage> history,
) {
  final combined = [text, ...recentConversationTexts(history)].join('\n').toLowerCase();
  final explicitFileMatch = RegExp(r'[^\\/\s]+\.(\w{1,12})').firstMatch(combined);
  if (explicitFileMatch != null) {
    return '.${explicitFileMatch.group(1)!.toLowerCase()}';
  }

  if (combined.contains('python') ||
      combined.contains(' py ') ||
      combined.contains('py\u4ee3\u7801') ||
      combined.contains('py \u6587\u4ef6') ||
      combined.contains('python\u811a\u672c')) {
    return '.py';
  }
  if (combined.contains('dart')) {
    return '.dart';
  }
  if (combined.contains('typescript') || combined.contains(' ts ')) {
    return '.ts';
  }
  if (combined.contains('javascript') || combined.contains(' js ')) {
    return '.js';
  }
  if (combined.contains('java')) {
    return '.java';
  }
  if (combined.contains('html')) {
    return '.html';
  }
  if (combined.contains('sql')) {
    return '.sql';
  }
  if (combined.contains('markdown') || combined.contains('.md')) {
    return '.md';
  }
  return null;
}

String inferDefaultFileName(
  String text,
  List<UnifiedMessage> history,
  String extension,
) {
  final combined = [text, ...recentConversationTexts(history)].join('\n').toLowerCase();

  if (combined.contains('\u4e5d\u4e5d\u4e58\u6cd5\u8868') ||
      combined.contains('\u4e58\u6cd5\u8868')) {
    return 'multiplication_table$extension';
  }
  if (combined.contains('\u767b\u5f55') || combined.contains('login')) {
    return 'login$extension';
  }
  if (combined.contains('\u6ce8\u518c') || combined.contains('register')) {
    return 'register$extension';
  }
  if (combined.contains('\u9996\u9875') || combined.contains('home page')) {
    return 'home$extension';
  }
  if (combined.contains('hello') || combined.contains('\u4f60\u597d')) {
    return 'hello$extension';
  }
  if (combined.contains('readme')) {
    return extension == '.md' ? 'README.md' : 'README$extension';
  }
  if (extension == '.py') {
    return 'main.py';
  }
  if (extension == '.dart') {
    return 'main.dart';
  }
  return 'main$extension';
}

String? extractPathFromToolResult(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      for (final key in ['path', 'file', 'target_path', 'directory']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          return value;
        }
      }
    }
  } catch (_) {}
  return null;
}
