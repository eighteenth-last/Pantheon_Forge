import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:pantheon_forge/core/storage/storage_manager.dart';

const _skillMdFileName = 'SKILL.md';
const _skillsMpBaseUrl = 'https://skillsmp.com/api/v1';
const _downloadableTextExts = <String>{
  '.md',
  '.txt',
  '.py',
  '.js',
  '.ts',
  '.sh',
  '.bash',
  '.ps1',
  '.bat',
  '.cmd',
  '.rb',
  '.pl',
  '.yaml',
  '.yml',
  '.json',
  '.toml',
  '.cfg',
  '.ini',
  '.env',
};

class SkillRoot {
  const SkillRoot({
    required this.id,
    required this.path,
    required this.label,
    required this.readOnly,
    required this.builtin,
  });

  final String id;
  final String path;
  final String label;
  final bool readOnly;
  final bool builtin;
}

class SkillInfo {
  const SkillInfo({
    required this.name,
    required this.description,
    required this.skillDir,
    required this.skillMdPath,
    required this.rootId,
    required this.rootLabel,
    required this.readOnly,
    required this.builtin,
  });

  final String name;
  final String description;
  final String skillDir;
  final String skillMdPath;
  final String rootId;
  final String rootLabel;
  final bool readOnly;
  final bool builtin;
}

class SkillFileInfo {
  const SkillFileInfo({
    required this.name,
    required this.size,
    required this.type,
  });

  final String name;
  final int size;
  final String type;
}

class SkillInstallResult {
  const SkillInstallResult({required this.success, this.name, this.error});

  final bool success;
  final String? name;
  final String? error;
}

class MarketSkillInfo {
  const MarketSkillInfo({
    required this.id,
    required this.name,
    required this.owner,
    required this.repo,
    required this.rank,
    required this.installs,
    required this.url,
    required this.github,
    this.description,
    this.sourcePath,
  });

  final String id;
  final String name;
  final String owner;
  final String repo;
  final int rank;
  final int installs;
  final String url;
  final String github;
  final String? description;
  final String? sourcePath;
}

class MarketSkillPageResult {
  const MarketSkillPageResult({required this.total, required this.skills});

  final int total;
  final List<MarketSkillInfo> skills;
}

enum MarketSortBy { stars, recent }

class _GitHubRepoRef {
  const _GitHubRepoRef({required this.owner, required this.repo});

  final String owner;
  final String repo;
}

class SkillsService {
  SkillsService._();

  static final SkillsService instance = SkillsService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 20),
    ),
  );

  bool _builtinInitialized = false;

  Future<List<SkillInfo>> listSkills() async {
    await _ensureBuiltinSkills();

    final roots = _resolveSkillRoots();
    final seenNames = <String>{};
    final skills = <SkillInfo>[];

    for (final root in roots) {
      final dir = Directory(root.path);
      if (!await dir.exists()) continue;

      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        if (!seenNames.add(name)) continue;

        final mdPath = p.join(entry.path, _skillMdFileName);
        final mdFile = File(mdPath);
        if (!await mdFile.exists()) continue;

        var description = name;
        try {
          final content = await mdFile.readAsString();
          description = _extractDescription(content, name);
        } catch (_) {}

        skills.add(
          SkillInfo(
            name: name,
            description: description,
            skillDir: entry.path,
            skillMdPath: mdPath,
            rootId: root.id,
            rootLabel: root.label,
            readOnly: root.readOnly,
            builtin: root.builtin,
          ),
        );
      }
    }

    skills.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return skills;
  }

  Future<String?> readSkillContent(SkillInfo skill) async {
    final file = File(skill.skillMdPath);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<List<SkillFileInfo>> listSkillFiles(SkillInfo skill) async {
    final dir = Directory(skill.skillDir);
    if (!await dir.exists()) return const [];

    final files = <SkillFileInfo>[];
    final root = p.normalize(dir.path);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        final relPath = p
            .relative(entity.path, from: root)
            .replaceAll('\\', '/');
        files.add(
          SkillFileInfo(
            name: relPath,
            size: stat.size,
            type: p.extension(entity.path).toLowerCase(),
          ),
        );
      } catch (_) {}
    }
    files.sort((a, b) => a.name.compareTo(b.name));
    return files;
  }

  Future<bool> deleteSkill(SkillInfo skill) async {
    if (skill.readOnly) return false;
    final dir = Directory(skill.skillDir);
    if (!await dir.exists()) return false;
    try {
      await dir.delete(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openSkillFolder(SkillInfo skill) async {
    final folder = skill.skillDir;
    if (!await Directory(folder).exists()) return;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [folder], runInShell: false);
        return;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [folder], runInShell: false);
        return;
      }
      await Process.start('xdg-open', [folder], runInShell: false);
    } catch (_) {}
  }

  Future<void> openExternalUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    try {
      if (Platform.isWindows) {
        await Process.start('cmd.exe', [
          '/c',
          'start',
          '',
          trimmed,
        ], runInShell: false);
        return;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [trimmed], runInShell: false);
        return;
      }
      await Process.start('xdg-open', [trimmed], runInShell: false);
    } catch (_) {}
  }

  Future<SkillInstallResult> addSkillFromFolder(String sourcePath) async {
    final sourceDir = Directory(sourcePath);
    if (!await sourceDir.exists()) {
      return const SkillInstallResult(success: false, error: '目录不存在');
    }

    final mdFile = File(p.join(sourcePath, _skillMdFileName));
    if (!await mdFile.exists()) {
      return const SkillInstallResult(success: false, error: '所选目录缺少 SKILL.md');
    }

    final skillName = p.basename(sourcePath);
    final targetRoot = StorageManager.instance.skillsDir;
    final targetDir = Directory(p.join(targetRoot, skillName));
    if (await targetDir.exists()) {
      return SkillInstallResult(success: false, error: '技能 "$skillName" 已存在');
    }

    try {
      await Directory(targetRoot).create(recursive: true);
      await _copyDirRecursive(sourceDir, targetDir);
      return SkillInstallResult(success: true, name: skillName);
    } catch (error) {
      return SkillInstallResult(success: false, error: error.toString());
    }
  }

  Future<MarketSkillPageResult> listMarketSkills({
    required String apiKey,
    String query = '',
    int offset = 0,
    int limit = 24,
    MarketSortBy sortBy = MarketSortBy.stars,
    bool useAiSearch = false,
  }) async {
    if (apiKey.trim().isEmpty) {
      return const MarketSkillPageResult(total: 0, skills: []);
    }

    final q = query.trim();
    final headers = {'Authorization': 'Bearer ${apiKey.trim()}'};
    late final String endpoint;
    if (useAiSearch && q.isNotEmpty) {
      endpoint =
          '$_skillsMpBaseUrl/skills/ai-search?q=${Uri.encodeQueryComponent(q)}';
    } else {
      final boundedLimit = limit.clamp(1, 100);
      final page = (offset ~/ boundedLimit) + 1;
      final params = Uri(
        queryParameters: {
          'q': q.isEmpty ? '*' : q,
          'page': '$page',
          'limit': '$boundedLimit',
          'sortBy': sortBy == MarketSortBy.recent ? 'recent' : 'stars',
        },
      ).query;
      endpoint = '$_skillsMpBaseUrl/skills/search?$params';
    }

    try {
      final response = await _dio.getUri(
        Uri.parse(endpoint),
        options: Options(headers: headers),
      );
      final data = response.data;
      if (data is! Map) {
        return const MarketSkillPageResult(total: 0, skills: []);
      }
      return _parseSkillsMpResponse(Map<String, dynamic>.from(data));
    } catch (_) {
      return const MarketSkillPageResult(total: 0, skills: []);
    }
  }

  Future<MarketSkillPageResult> fetchTopRankedMarketSkills({
    required String apiKey,
    int limit = 30,
  }) async {
    if (apiKey.trim().isEmpty) {
      return const MarketSkillPageResult(total: 0, skills: []);
    }

    final deduped = <String, MarketSkillInfo>{};
    const fallbackQueries = ['*', 'agent', 'ai', 'automation', 'python'];
    for (final query in fallbackQueries) {
      final page = await listMarketSkills(
        apiKey: apiKey,
        query: query,
        offset: 0,
        limit: 50,
        sortBy: MarketSortBy.stars,
      );
      for (final skill in page.skills) {
        final key = skill.id.isNotEmpty
            ? skill.id
            : '${skill.owner}/${skill.repo}/${skill.name}';
        deduped[key] = skill;
      }
      if (deduped.length >= limit) break;
    }

    final merged = deduped.values.toList()
      ..sort((a, b) {
        final byRank = b.rank.compareTo(a.rank);
        if (byRank != 0) return byRank;
        final byInstall = b.installs.compareTo(a.installs);
        if (byInstall != 0) return byInstall;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final top = merged.take(limit).toList();
    return MarketSkillPageResult(total: top.length, skills: top);
  }

  Future<SkillInstallResult> addSkillFromMarket(
    MarketSkillInfo skill, {
    void Function(double progress)? onProgress,
  }) async {
    final repoRef = _resolveGitHubRepo(skill);
    if (repoRef == null) {
      return const SkillInstallResult(
        success: false,
        error: '技能市场条目缺少 GitHub 仓库信息',
      );
    }

    final tempBase = Directory(
      p.join(
        Directory.systemTemp.path,
        'pantheon-forge-skills',
        'download-${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    final tempDir = Directory(p.join(tempBase.path, skill.name));

    try {
      onProgress?.call(0);
      await tempDir.create(recursive: true);
      final files = await _downloadFromGitHub(
        owner: repoRef.owner,
        repo: repoRef.repo,
        sourcePath: skill.sourcePath,
        tempDir: tempDir.path,
        onProgress: onProgress,
      );
      if (files.isEmpty) {
        return const SkillInstallResult(
          success: false,
          error: '下载失败：未获取到可安装文件',
        );
      }
      if (!files.any((file) => file == _skillMdFileName)) {
        return const SkillInstallResult(
          success: false,
          error: '下载失败：缺少 SKILL.md',
        );
      }
      onProgress?.call(1);

      final installResult = await addSkillFromFolder(tempDir.path);
      if (!installResult.success &&
          (installResult.error?.contains('已存在') ?? false)) {
        return SkillInstallResult(success: true, name: skill.name);
      }
      return installResult;
    } on DioException catch (error) {
      return SkillInstallResult(
        success: false,
        error: _friendlyDioError(error),
      );
    } catch (error) {
      return SkillInstallResult(
        success: false,
        error: '下载失败：${error.toString()}',
      );
    } finally {
      try {
        if (await tempBase.exists()) {
          await tempBase.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> _ensureBuiltinSkills() async {
    if (_builtinInitialized) return;
    _builtinInitialized = true;

    final targetRoot = Directory(StorageManager.instance.skillsDir);
    if (!await targetRoot.exists()) {
      await targetRoot.create(recursive: true);
    }

    final bundledRoots = _resolveBundledSkillDirs();
    for (final bundled in bundledRoots) {
      final bundledDir = Directory(bundled);
      if (!await bundledDir.exists()) continue;

      await for (final entry in bundledDir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final mdPath = p.join(entry.path, _skillMdFileName);
        if (!await File(mdPath).exists()) continue;

        final targetPath = p.join(targetRoot.path, p.basename(entry.path));
        final targetDir = Directory(targetPath);
        if (await targetDir.exists()) continue;
        try {
          await _copyDirRecursive(entry, targetDir);
        } catch (_) {}
      }
    }
  }

  List<SkillRoot> _resolveSkillRoots() {
    final roots = <SkillRoot>[];
    final homeDir = _resolveHomeDir();
    if (homeDir != null && homeDir.isNotEmpty) {
      roots.add(
        SkillRoot(
          id: 'user',
          path: p.join(homeDir, '.agents', 'skills'),
          label: '~/.agents/skills',
          readOnly: false,
          builtin: false,
        ),
      );
    }

    roots.add(
      SkillRoot(
        id: 'app',
        path: StorageManager.instance.skillsDir,
        label: 'Memory/skills',
        readOnly: false,
        builtin: true,
      ),
    );

    for (final refPath in _resolveBundledSkillDirs()) {
      roots.add(
        SkillRoot(
          id: 'reference:$refPath',
          path: refPath,
          label: '源码借鉴/resources/skills',
          readOnly: true,
          builtin: true,
        ),
      );
    }

    return roots;
  }

  List<String> _resolveBundledSkillDirs() {
    final appDir = StorageManager.instance.appDir;
    final candidates = <String>[
      p.join(appDir, 'resources', 'skills'),
      p.normalize(p.join(appDir, '..', '源码借鉴', 'resources', 'skills')),
      p.normalize(
        p.join(Directory.current.path, '源码借鉴', 'resources', 'skills'),
      ),
      p.normalize(p.join(Directory.current.path, 'resources', 'skills')),
    ];

    final existing = <String>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (!seen.add(normalized)) continue;
      if (Directory(normalized).existsSync()) {
        existing.add(normalized);
      }
    }
    return existing;
  }

  String _extractDescription(String content, String fallback) {
    final fmMatch = RegExp(
      r'^---\s*\r?\n([\s\S]*?)\r?\n---',
    ).firstMatch(content);
    if (fmMatch != null) {
      final fm = fmMatch.group(1) ?? '';
      final descMatch = RegExp(
        r'^description:\s*(.+)$',
        multiLine: true,
      ).firstMatch(fm);
      final raw = descMatch?.group(1)?.trim();
      if (raw != null && raw.isNotEmpty) {
        final clean = raw.replaceAll(RegExp(r"""^["']|["']$"""), '');
        if (clean.isNotEmpty) {
          return clean.length > 200 ? '${clean.substring(0, 200)}...' : clean;
        }
      }
    }

    var inFrontMatter = false;
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed == '---') {
        inFrontMatter = !inFrontMatter;
        continue;
      }
      if (inFrontMatter || trimmed.isEmpty || trimmed.startsWith('#')) continue;
      return trimmed.length > 120 ? '${trimmed.substring(0, 120)}...' : trimmed;
    }
    return fallback;
  }

  MarketSkillPageResult _parseSkillsMpResponse(Map<String, dynamic> json) {
    if (json['success'] == false) {
      return const MarketSkillPageResult(total: 0, skills: []);
    }

    final dataRaw = json['data'];
    final data = dataRaw is Map<String, dynamic> ? dataRaw : json;

    final rawSkills = _listFromAny(
      data['skills'] ??
          data['items'] ??
          data['results'] ??
          data['data'] ??
          const [],
    );

    var total = _intFromAny(data['total']) ?? rawSkills.length;
    final pagination = data['pagination'];
    if (pagination is Map<String, dynamic>) {
      total = _intFromAny(pagination['total']) ?? total;
    }

    final skills = <MarketSkillInfo>[];
    for (var index = 0; index < rawSkills.length; index++) {
      final item = rawSkills[index];
      if (item is! Map) continue;
      skills.add(
        _normaliseSkillsMpItem(Map<String, dynamic>.from(item), index),
      );
    }
    return MarketSkillPageResult(total: total, skills: skills);
  }

  MarketSkillInfo _normaliseSkillsMpItem(Map<String, dynamic> item, int index) {
    final github = _stringFromAny(
      item['github'] ?? item['github_url'] ?? item['githubUrl'],
    );
    final parsed = github.isNotEmpty ? _parseGitHubOwnerRepo(github) : null;
    final owner = parsed?.owner.isNotEmpty == true
        ? parsed!.owner
        : _stringFromAny(
            item['owner'] ?? item['github_owner'] ?? item['author'],
          );
    final repo = parsed?.repo.isNotEmpty == true
        ? parsed!.repo
        : _stringFromAny(item['repo'] ?? item['github_repo'] ?? item['name']);

    return MarketSkillInfo(
      id: _stringFromAny(item['id'] ?? item['name'] ?? index),
      name: _stringFromAny(item['name']),
      owner: owner,
      repo: repo,
      rank: _intFromAny(item['stars'] ?? item['rank']) ?? 0,
      installs: _intFromAny(item['installs'] ?? item['downloads']) ?? 0,
      url: _stringFromAny(
        item['url'] ??
            item['skillUrl'] ??
            item['marketplace_url'] ??
            'https://skillsmp.com/skills/${_stringFromAny(item['name'])}',
      ),
      github: github,
      description: _stringOrNull(item['description']),
      sourcePath: _stringOrNull(item['source_path']),
    );
  }

  _GitHubRepoRef? _parseGitHubOwnerRepo(String url) {
    final reg = RegExp(r'github\.com/([^/]+)/([^/]+?)(?:\.git)?(?:/|$)');
    final match = reg.firstMatch(url);
    if (match == null) return null;
    final owner = match.group(1);
    final repo = match.group(2);
    if (owner == null || repo == null || owner.isEmpty || repo.isEmpty) {
      return null;
    }
    return _GitHubRepoRef(owner: owner, repo: repo);
  }

  _GitHubRepoRef? _resolveGitHubRepo(MarketSkillInfo skill) {
    final fromUrl = _parseGitHubOwnerRepo(skill.github);
    if (fromUrl != null) return fromUrl;
    if (skill.owner.isEmpty || skill.repo.isEmpty) return null;
    return _GitHubRepoRef(owner: skill.owner, repo: skill.repo);
  }

  Future<List<String>> _downloadFromGitHub({
    required String owner,
    required String repo,
    required String? sourcePath,
    required String tempDir,
    void Function(double progress)? onProgress,
  }) async {
    final prefix = sourcePath == null
        ? ''
        : sourcePath.replaceAll(RegExp(r'^/+|/+$'), '');
    final treeUrl = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/git/trees/HEAD?recursive=1',
    );
    final treeResponse = await _dio.getUri(
      treeUrl,
      options: Options(
        headers: {
          'User-Agent': 'PantheonForge',
          'Accept': 'application/vnd.github+json',
        },
      ),
    );

    final treeData = treeResponse.data;
    if (treeData is! Map) return const [];
    final treeItems = _listFromAny(treeData['tree']);
    final downloaded = <String>[];
    final candidates = <MapEntry<String, String>>[];

    for (final treeItem in treeItems) {
      if (treeItem is! Map) continue;
      final pathValue = _stringFromAny(treeItem['path']);
      final type = _stringFromAny(treeItem['type']);
      if (type != 'blob' || pathValue.isEmpty) continue;
      String relPath;
      if (prefix.isEmpty) {
        relPath = pathValue;
      } else if (pathValue == prefix) {
        relPath = p.basename(pathValue);
      } else if (pathValue.startsWith('$prefix/')) {
        relPath = pathValue.substring(prefix.length + 1);
      } else {
        continue;
      }
      if (relPath.isEmpty) continue;
      final ext = p.extension(relPath).toLowerCase();
      if (!_downloadableTextExts.contains(ext) && relPath != _skillMdFileName) {
        continue;
      }
      candidates.add(MapEntry(pathValue, relPath));
    }

    if (candidates.isEmpty) {
      return const [];
    }

    onProgress?.call(0);
    var processed = 0;
    for (final candidate in candidates) {
      final pathValue = candidate.key;
      final relPath = candidate.value;
      final rawUrl = Uri.parse(
        'https://raw.githubusercontent.com/$owner/$repo/HEAD/$pathValue',
      );
      try {
        final fileResponse = await _dio.getUri(
          rawUrl,
          options: Options(
            headers: {'User-Agent': 'PantheonForge'},
            responseType: ResponseType.plain,
          ),
        );
        final data = fileResponse.data;
        if (data == null) continue;

        final content = data is String ? data : jsonEncode(data);
        final output = File(p.join(tempDir, relPath));
        await output.parent.create(recursive: true);
        await output.writeAsString(content);
        downloaded.add(relPath);
      } catch (_) {
      } finally {
        processed++;
        onProgress?.call(processed / candidates.length);
      }
    }

    return downloaded;
  }

  String _friendlyDioError(DioException error) {
    final code = error.response?.statusCode;
    if (code == 401 || code == 403) {
      return '下载失败：访问 GitHub 受限，请稍后重试';
    }
    if (code == 404) {
      return '下载失败：仓库或分支不存在';
    }
    if (code == 429) {
      return '下载失败：请求过于频繁，请稍后重试';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '下载失败：网络超时';
    }
    if (error.type == DioExceptionType.connectionError) {
      return '下载失败：网络连接异常';
    }
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return '下载失败：$message';
    }
    return '下载失败：未知网络错误';
  }

  Future<void> _copyDirRecursive(Directory src, Directory dst) async {
    if (!await dst.exists()) {
      await dst.create(recursive: true);
    }
    await for (final entity in src.list(followLinks: false)) {
      final targetPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirRecursive(entity, Directory(targetPath));
      } else if (entity is File) {
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  String? _resolveHomeDir() {
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) return home;
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return userProfile;
    }
    return null;
  }

  static List<dynamic> _listFromAny(dynamic value) {
    if (value is List<dynamic>) return value;
    if (value is List) return value.cast<dynamic>();
    return const [];
  }

  static int? _intFromAny(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _stringFromAny(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
