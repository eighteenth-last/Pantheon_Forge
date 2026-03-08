import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pantheon_forge/models/models.dart';

class LocalWorkspaceService {
  static const findFilesTool = ToolDefinition(
    name: 'find_files',
    description:
        'Find files by name pattern inside the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Case-insensitive filename keyword or partial name, such as "readme" or ".dart".',
        },
        'path': {
          'type': 'string',
          'description':
              'Relative subdirectory to search in. Empty means workspace root.',
        },
        'limit': {
          'type': 'integer',
          'description':
              'Maximum number of matched files to return. Defaults to 20.',
        },
      },
      'required': ['query'],
    },
  );

  static const searchInFilesTool = ToolDefinition(
    name: 'search_in_files',
    description:
        'Search text across files inside the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Text to search for, case-insensitive.',
        },
        'path': {
          'type': 'string',
          'description':
              'Relative subdirectory to search in. Empty means workspace root.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum number of matches to return. Defaults to 20.',
        },
      },
      'required': ['query'],
    },
  );

  static const listDirectoryTool = ToolDefinition(
    name: 'list_directory',
    description:
        'List files and folders inside the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description':
              'Relative path inside the workspace. Empty means workspace root.',
        },
      },
    },
  );

  static const summarizeProjectTool = ToolDefinition(
    name: 'summarize_project',
    description:
        'Summarize the current local workspace root, including top-level structure and key files.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'max_files': {
          'type': 'integer',
          'description': 'Maximum number of key files to sample. Defaults to 8.',
        },
      },
    },
  );


  static const writeFileTool = ToolDefinition(
    name: 'write_file',
    description:
        'Create or overwrite a UTF-8 text file inside the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative file path inside the workspace.',
        },
        'content': {
          'type': 'string',
          'description': 'Full file content to write.',
        },
      },
      'required': ['path', 'content'],
    },
  );

  static const editFileTool = ToolDefinition(
    name: 'edit_file',
    description:
        'Edit an existing UTF-8 text file by replacing exact text inside the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative file path inside the workspace.',
        },
        'old_string': {
          'type': 'string',
          'description': 'The exact old text to replace.',
        },
        'new_string': {
          'type': 'string',
          'description': 'The new text to replace it with.',
        },
        'replace_all': {
          'type': 'boolean',
          'description': 'Replace all occurrences. Defaults to false.',
        },
      },
      'required': ['path', 'old_string', 'new_string'],
    },
  );


  static const createDirectoryTool = ToolDefinition(
    name: 'create_directory',
    description:
        'Create a directory inside the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative directory path inside the workspace.',
        },
      },
      'required': ['path'],
    },
  );

  static const movePathTool = ToolDefinition(
    name: 'move_path',
    description:
        'Move or rename a file or directory inside the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'source_path': {
          'type': 'string',
          'description': 'Existing relative source path inside the workspace.',
        },
        'target_path': {
          'type': 'string',
          'description': 'New relative target path inside the workspace.',
        },
      },
      'required': ['source_path', 'target_path'],
    },
  );

  static const deletePathTool = ToolDefinition(
    name: 'delete_path',
    description:
        'Delete a file or directory inside the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative file or directory path inside the workspace.',
        },
        'recursive': {
          'type': 'boolean',
          'description': 'Delete directories recursively. Defaults to true.',
        },
      },
      'required': ['path'],
    },
  );


  static const runCommandTool = ToolDefinition(
    name: 'run_command',
    description:
        'Run a shell command inside the current local workspace directory and return exit code, stdout, and stderr.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'Shell command to run inside the workspace.',
        },
        'path': {
          'type': 'string',
          'description': 'Relative working directory inside the workspace. Empty means workspace root.',
        },
        'timeout_seconds': {
          'type': 'integer',
          'description': 'Command timeout in seconds. Defaults to 30 and is capped at 120.',
        },
      },
      'required': ['command'],
    },
  );


  static const readFilesTool = ToolDefinition(
    name: 'read_files',
    description:
        'Read multiple UTF-8 text files from the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'paths': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Relative file paths inside the workspace.',
        },
        'max_chars_per_file': {
          'type': 'integer',
          'description': 'Maximum characters to return per file. Defaults to 12000.',
        },
      },
      'required': ['paths'],
    },
  );

  static const readFileTool = ToolDefinition(
    name: 'read_file',
    description:
        'Read a UTF-8 text file from the current local workspace directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative file path inside the workspace.',
        },
        'max_chars': {
          'type': 'integer',
          'description': 'Maximum characters to return. Defaults to 12000.',
        },
      },
      'required': ['path'],
    },
  );

  static List<ToolDefinition> toolsForWorkspace(String? workingFolder) {
    if (workingFolder == null || workingFolder.trim().isEmpty) {
      return const [];
    }
    return const [
      summarizeProjectTool,
      findFilesTool,
      searchInFilesTool,
      listDirectoryTool,
      readFilesTool,
      readFileTool,
      writeFileTool,
      editFileTool,
      createDirectoryTool,
      movePathTool,
      deletePathTool,
      runCommandTool,
    ];
  }

  static Future<ToolExecutionResult> execute({
    required String workingFolder,
    required String toolName,
    required Map<String, dynamic> input,
  }) async {
    switch (toolName) {
      case 'find_files':
        return _findFiles(
          workingFolder,
          input['query'] as String?,
          input['path'] as String?,
          (input['limit'] as num?)?.toInt() ?? 20,
        );
      case 'search_in_files':
        return _searchInFiles(
          workingFolder,
          input['query'] as String?,
          input['path'] as String?,
          (input['limit'] as num?)?.toInt() ?? 20,
        );
      case 'list_directory':
        return _listDirectory(workingFolder, input['path'] as String?);
      case 'summarize_project':
        return _summarizeProject(
          workingFolder,
          (input['max_files'] as num?)?.toInt() ?? 8,
        );
      case 'read_files':
        return _readFiles(
          workingFolder,
          (input['paths'] as List?)?.cast<String>(),
          (input['max_chars_per_file'] as num?)?.toInt() ?? 12000,
        );
      case 'read_file':
        return _readFile(
          workingFolder,
          input['path'] as String?,
          (input['max_chars'] as num?)?.toInt() ?? 12000,
        );
      case 'write_file':
        return _writeFile(
          workingFolder,
          input['path'] as String?,
          input['content'] as String?,
        );
      case 'edit_file':
        return _editFile(
          workingFolder,
          input['path'] as String?,
          input['old_string'] as String?,
          input['new_string'] as String?,
          input['replace_all'] == true,
        );
      case 'create_directory':
        return _createDirectory(workingFolder, input['path'] as String?);
      case 'move_path':
        return _movePath(
          workingFolder,
          input['source_path'] as String?,
          input['target_path'] as String?,
        );
      case 'delete_path':
        return _deletePath(
          workingFolder,
          input['path'] as String?,
          input['recursive'] != false,
        );
      case 'run_command':
        return _runCommand(
          workingFolder,
          input['command'] as String?,
          input['path'] as String?,
          (input['timeout_seconds'] as num?)?.toInt() ?? 30,
        );
      default:
        throw UnsupportedError('Unsupported tool: $toolName');
    }
  }

  static ToolExecutionResult _listDirectory(String root, String? relativePath) {
    final dir = Directory(_resolvePath(root, relativePath));
    if (!dir.existsSync()) {
      return ToolExecutionResult(
        content: 'Directory not found: ${relativePath ?? '.'}',
        isError: true,
      );
    }

    final entries = dir.listSync(followLinks: false).map((entity) {
      final name = p.basename(entity.path);
      if (entity is Directory) return '[DIR] $name';
      if (entity is File) return '[FILE] $name';
      return '[OTHER] $name';
    }).toList()..sort();

    return ToolExecutionResult(
      content: jsonEncode({'path': relativePath ?? '.', 'entries': entries}),
    );
  }

  static ToolExecutionResult _findFiles(
    String root,
    String? query,
    String? relativePath,
    int limit,
  ) {
    if (query == null || query.trim().isEmpty) {
      return const ToolExecutionResult(
        content:
            'Missing query. Provide a filename keyword such as "readme" or ".dart".',
        isError: true,
      );
    }

    final dir = Directory(_resolvePath(root, relativePath));
    if (!dir.existsSync()) {
      return ToolExecutionResult(
        content: 'Directory not found: ${relativePath ?? '.'}',
        isError: true,
      );
    }

    final normalizedRoot = p.normalize(p.absolute(root));
    final keyword = query.toLowerCase();
    final results = <String>[];

    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.contains(keyword)) continue;
      results.add(p.relative(entity.path, from: normalizedRoot));
      if (results.length >= limit) break;
    }

    return ToolExecutionResult(
      content: jsonEncode({
        'query': query,
        'path': relativePath ?? '.',
        'matches': results,
      }),
    );
  }

  static ToolExecutionResult _searchInFiles(
    String root,
    String? query,
    String? relativePath,
    int limit,
  ) {
    if (query == null || query.trim().isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing query. Provide the text you want to search for.',
        isError: true,
      );
    }

    final dir = Directory(_resolvePath(root, relativePath));
    if (!dir.existsSync()) {
      return ToolExecutionResult(
        content: 'Directory not found: ${relativePath ?? '.'}',
        isError: true,
      );
    }

    final normalizedRoot = p.normalize(p.absolute(root));
    final needle = query.toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final lines = entity.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          if (!line.toLowerCase().contains(needle)) continue;
          results.add({
            'file': p.relative(entity.path, from: normalizedRoot),
            'line': index + 1,
            'text': line.trim(),
          });
          if (results.length >= limit) {
            return ToolExecutionResult(
              content: jsonEncode({
                'query': query,
                'path': relativePath ?? '.',
                'matches': results,
              }),
            );
          }
        }
      } catch (_) {
        continue;
      }
    }

    return ToolExecutionResult(
      content: jsonEncode({
        'query': query,
        'path': relativePath ?? '.',
        'matches': results,
      }),
    );
  }


  static ToolExecutionResult _summarizeProject(String root, int maxFiles) {
    final workspace = Directory(_resolvePath(root, '.'));
    if (!workspace.existsSync()) {
      return const ToolExecutionResult(
        content: 'Workspace directory not found.',
        isError: true,
      );
    }

    final normalizedRoot = p.normalize(p.absolute(root));
    final topLevelEntries = workspace
        .listSync(followLinks: false)
        .map((entity) => {
              'path': p.relative(entity.path, from: normalizedRoot),
              'type': entity is Directory ? 'dir' : 'file',
            })
        .toList()
      ..sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));

    final keyFiles = <String>[];
    final seen = <String>{};
    const preferredNames = {
      'readme.md',
      'readme',
      'pubspec.yaml',
      'package.json',
      'pnpm-workspace.yaml',
      'cargo.toml',
      'go.mod',
      'pom.xml',
      'build.gradle',
      'build.gradle.kts',
      'settings.gradle',
      'settings.gradle.kts',
      'requirements.txt',
      '.env.example',
      'dockerfile',
      'compose.yaml',
      'docker-compose.yml',
      'lib/main.dart',
      'src/main.dart',
      'src/main.ts',
      'src/main.js',
      'main.py',
      'main.go',
    };

    for (final entity in workspace.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: normalizedRoot);
      if (_isIgnoredPath(relative)) {
        continue;
      }
      final normalizedRelative = relative.replaceAll('\\', '/');
      final basename = p.basename(relative).toLowerCase();
      final normalizedLower = normalizedRelative.toLowerCase();
      final isKey = preferredNames.contains(basename) ||
          preferredNames.contains(normalizedLower) ||
          normalizedLower.endsWith('/pubspec.yaml') ||
          normalizedLower.endsWith('/package.json') ||
          normalizedLower.endsWith('/lib/main.dart') ||
          normalizedLower.endsWith('/src/main.dart');
      if (!isKey || !seen.add(normalizedRelative)) {
        continue;
      }
      keyFiles.add(normalizedRelative);
      if (keyFiles.length >= maxFiles) {
        break;
      }
    }

    final snippets = keyFiles
        .map(
          (relative) => {
            'path': relative,
            'snippet': _readSnippet(normalizedRoot, relative),
          },
        )
        .toList();

    return ToolExecutionResult(
      content: jsonEncode({
        'workspaceRoot': normalizedRoot,
        'topLevelEntries': topLevelEntries.take(40).toList(),
        'keyFiles': keyFiles,
        'snippets': snippets,
      }),
    );
  }

  static ToolExecutionResult _writeFile(
    String root,
    String? relativePath,
    String? content,
  ) {
    if (relativePath == null || relativePath.trim().isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing file path. Provide a relative path such as "src/main.py".',
        isError: true,
      );
    }
    if (content == null) {
      return const ToolExecutionResult(
        content: 'Missing content. Provide the full file content to write.',
        isError: true,
      );
    }

    final file = File(_resolvePath(root, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);

    return ToolExecutionResult(
      content: jsonEncode({
        'success': true,
        'path': relativePath,
        'bytes': content.length,
      }),
    );
  }

  static ToolExecutionResult _editFile(
    String root,
    String? relativePath,
    String? oldString,
    String? newString,
    bool replaceAll,
  ) {
    if (relativePath == null || relativePath.trim().isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing file path. Provide a relative path such as "lib/main.dart".',
        isError: true,
      );
    }
    if (oldString == null || oldString.isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing old_string. Provide the exact text to replace.',
        isError: true,
      );
    }
    if (newString == null) {
      return const ToolExecutionResult(
        content: 'Missing new_string. Provide the replacement text.',
        isError: true,
      );
    }

    final file = File(_resolvePath(root, relativePath));
    if (!file.existsSync()) {
      return ToolExecutionResult(
        content: 'File not found: $relativePath',
        isError: true,
      );
    }

    final original = file.readAsStringSync();
    final oldVariants = _buildOldStringVariants(oldString, original);
    String? matchedVariant;
    for (final variant in oldVariants) {
      if (variant.isNotEmpty && original.contains(variant)) {
        matchedVariant = variant;
        break;
      }
    }

    if (matchedVariant == null) {
      return const ToolExecutionResult(
        content: 'old_string not found in file.',
        isError: true,
      );
    }

    final matchCount = matchedVariant.allMatches(original).length;
    if (!replaceAll && matchCount > 1) {
      return ToolExecutionResult(
        content: jsonEncode({
          'error': 'old_string is not unique in file.',
          'occurrences': matchCount,
        }),
        isError: true,
      );
    }

    final replacement = _applyEolStyle(newString, _detectEolStyle(matchedVariant));
    final updated = replaceAll
        ? original.replaceAll(matchedVariant, replacement)
        : original.replaceFirst(matchedVariant, replacement);
    file.writeAsStringSync(updated);

    return ToolExecutionResult(
      content: jsonEncode({
        'success': true,
        'path': relativePath,
        'replaceAll': replaceAll,
        'occurrences': matchCount,
      }),
    );
  }



  static ToolExecutionResult _createDirectory(String root, String? relativePath) {
    if (relativePath == null || relativePath.trim().isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing directory path. Provide a relative path such as "src/components".',
        isError: true,
      );
    }

    final dir = Directory(_resolvePath(root, relativePath));
    dir.createSync(recursive: true);
    return ToolExecutionResult(
      content: jsonEncode({
        'success': true,
        'path': relativePath,
        'type': 'directory',
      }),
    );
  }

  static ToolExecutionResult _movePath(
    String root,
    String? sourcePath,
    String? targetPath,
  ) {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing source_path. Provide the existing relative path.',
        isError: true,
      );
    }
    if (targetPath == null || targetPath.trim().isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing target_path. Provide the new relative path.',
        isError: true,
      );
    }

    final sourceResolved = _resolvePath(root, sourcePath);
    final targetResolved = _resolvePath(root, targetPath);
    final sourceFile = File(sourceResolved);
    final sourceDir = Directory(sourceResolved);

    if (sourceFile.existsSync()) {
      File(targetResolved).parent.createSync(recursive: true);
      sourceFile.renameSync(targetResolved);
      return ToolExecutionResult(
        content: jsonEncode({
          'success': true,
          'source': sourcePath,
          'target': targetPath,
          'type': 'file',
        }),
      );
    }
    if (sourceDir.existsSync()) {
      Directory(targetResolved).parent.createSync(recursive: true);
      sourceDir.renameSync(targetResolved);
      return ToolExecutionResult(
        content: jsonEncode({
          'success': true,
          'source': sourcePath,
          'target': targetPath,
          'type': 'directory',
        }),
      );
    }

    return ToolExecutionResult(
      content: 'Path not found: $sourcePath',
      isError: true,
    );
  }

  static ToolExecutionResult _deletePath(
    String root,
    String? relativePath,
    bool recursive,
  ) {
    if (relativePath == null || relativePath.trim().isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing path. Provide a relative file or directory path to delete.',
        isError: true,
      );
    }

    final resolvedPath = _resolvePath(root, relativePath);
    final file = File(resolvedPath);
    if (file.existsSync()) {
      file.deleteSync();
      return ToolExecutionResult(
        content: jsonEncode({
          'success': true,
          'path': relativePath,
          'type': 'file',
        }),
      );
    }

    final dir = Directory(resolvedPath);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: recursive);
      return ToolExecutionResult(
        content: jsonEncode({
          'success': true,
          'path': relativePath,
          'type': 'directory',
          'recursive': recursive,
        }),
      );
    }

    return ToolExecutionResult(
      content: 'Path not found: $relativePath',
      isError: true,
    );
  }



  static ToolExecutionResult _readFiles(
    String root,
    List<String>? relativePaths,
    int maxCharsPerFile,
  ) {
    if (relativePaths == null || relativePaths.isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing paths. Provide a non-empty array of relative file paths.',
        isError: true,
      );
    }

    final results = <Map<String, dynamic>>[];
    for (final relativePath in relativePaths) {
      final single = _readFile(root, relativePath, maxCharsPerFile);
      results.add({
        'path': relativePath,
        'content': single.content,
        'isError': single.isError,
      });
    }

    return ToolExecutionResult(
      content: jsonEncode({
        'files': results,
      }),
      isError: results.every((entry) => entry['isError'] == true),
    );
  }

  static Future<ToolExecutionResult> _runCommand(
    String root,
    String? command,
    String? relativePath,
    int timeoutSeconds,
  ) async {
    final trimmed = command?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const ToolExecutionResult(
        content: 'Missing command. Provide a shell command to run.',
        isError: true,
      );
    }
    if (_isBlockedCommand(trimmed)) {
      return const ToolExecutionResult(
        content: 'Blocked command. Destructive or system-level commands are not allowed from the workspace tool.',
        isError: true,
      );
    }

    final workingDirectory = _resolvePath(root, relativePath);
    final boundedTimeout = timeoutSeconds.clamp(1, 120);

    try {
      final result = await _runShellCommand(
        trimmed,
        workingDirectory,
        Duration(seconds: boundedTimeout),
      );
      return ToolExecutionResult(
        content: jsonEncode({
          'command': trimmed,
          'path': relativePath ?? '.',
          'exitCode': result.exitCode,
          'stdout': _truncateOutput(result.stdout.toString()),
          'stderr': _truncateOutput(result.stderr.toString()),
        }),
        isError: result.exitCode != 0,
      );
    } on ProcessException catch (error) {
      return ToolExecutionResult(
        content: jsonEncode({
          'command': trimmed,
          'path': relativePath ?? '.',
          'error': error.message,
        }),
        isError: true,
      );
    } catch (error) {
      return ToolExecutionResult(
        content: jsonEncode({
          'command': trimmed,
          'path': relativePath ?? '.',
          'error': error.toString(),
        }),
        isError: true,
      );
    }
  }

  static ToolExecutionResult _readFile(
    String root,
    String? relativePath,
    int maxChars,
  ) {
    if (relativePath == null || relativePath.trim().isEmpty) {
      return const ToolExecutionResult(
        content:
            'Missing file path. For project-wide requests, call summarize_project or list_directory first. For file reads, provide a relative path such as "lib/main.dart".',
        isError: true,
      );
    }

    final file = File(_resolvePath(root, relativePath));
    if (!file.existsSync()) {
      return ToolExecutionResult(
        content: 'File not found: $relativePath',
        isError: true,
      );
    }

    final content = file.readAsStringSync();
    final truncated = content.length > maxChars
        ? '${content.substring(0, maxChars)}\n...[truncated]'
        : content;

    return ToolExecutionResult(content: truncated);
  }




  static Future<ProcessResult> _runShellCommand(
    String command,
    String workingDirectory,
    Duration timeout,
  ) {
    if (Platform.isWindows) {
      return Process.run(
        'powershell.exe',
        ['-NoProfile', '-Command', command],
        workingDirectory: workingDirectory,
        runInShell: false,
      ).timeout(timeout);
    }
    return Process.run(
      '/bin/sh',
      ['-lc', command],
      workingDirectory: workingDirectory,
      runInShell: false,
    ).timeout(timeout);
  }

  static bool _isBlockedCommand(String command) {
    final normalized = command.toLowerCase();
    const blockedPatterns = [
      'shutdown',
      'restart-computer',
      'stop-computer',
      'format ',
      'diskpart',
      'mkfs',
      'rm -rf /',
      'rd /s /q c:',
      'remove-item -recurse c:',
      'del /f /s /q c:',
    ];
    return blockedPatterns.any(normalized.contains);
  }

  static String _truncateOutput(String value, {int maxChars = 12000}) {
    if (value.length <= maxChars) {
      return value;
    }
    return '${value.substring(0, maxChars)}\n...[truncated]';
  }

  static String? _detectEolStyle(String value) {
    if (value.contains('\r\n')) {
      return '\r\n';
    }
    if (value.contains('\n')) {
      return '\n';
    }
    return null;
  }

  static String _applyEolStyle(String value, String? eolStyle) {
    if (eolStyle == null) {
      return value;
    }
    final normalized = value.replaceAll('\r\n', '\n');
    if (eolStyle == '\n') {
      return normalized;
    }
    return normalized.replaceAll('\n', '\r\n');
  }

  static List<String> _buildOldStringVariants(String oldString, String fileContent) {
    final variants = <String>[oldString];
    final fileHasCrlf = fileContent.contains('\r\n');
    final oldHasLf = oldString.contains('\n');
    final oldHasCrlf = oldString.contains('\r\n');
    if (oldHasLf && !oldHasCrlf && fileHasCrlf) {
      variants.add(oldString.replaceAll('\n', '\r\n'));
    } else if (oldHasCrlf && !fileHasCrlf) {
      variants.add(oldString.replaceAll('\r\n', '\n'));
    }
    return variants;
  }


  static String _readSnippet(String root, String relativePath) {
    try {
      final file = File(_resolvePath(root, relativePath));
      if (!file.existsSync()) {
        return '';
      }
      final content = file.readAsStringSync();
      if (content.length <= 1200) {
        return content;
      }
      return '${content.substring(0, 1200)}\n...[truncated]';
    } catch (_) {
      return '';
    }
  }

  static bool _isIgnoredPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/').toLowerCase();
    const ignoredSegments = [
      '/.git/',
      '/build/',
      '/dist/',
      '/node_modules/',
      '/.dart_tool/',
      '/.idea/',
      '/windows/flutter/ephemeral/',
      '/linux/flutter/ephemeral/',
      '/macos/flutter/ephemeral/',
    ];
    if (normalized.startsWith('.git/') ||
        normalized.startsWith('build/') ||
        normalized.startsWith('dist/') ||
        normalized.startsWith('node_modules/') ||
        normalized.startsWith('.dart_tool/') ||
        normalized.startsWith('.idea/')) {
      return true;
    }
    return ignoredSegments.any(normalized.contains);
  }

  static String _resolvePath(String root, String? relativePath) {
    final normalizedRoot = p.normalize(p.absolute(root));
    final normalizedPath = p.normalize(
      p.absolute(normalizedRoot, relativePath ?? '.'),
    );
    if (!p.isWithin(normalizedRoot, normalizedPath) &&
        normalizedRoot != normalizedPath) {
      throw const FileSystemException('Path escapes workspace root.');
    }
    return normalizedPath;
  }
}

class ToolExecutionResult {
  const ToolExecutionResult({required this.content, this.isError = false});

  final String content;
  final bool isError;
}
