import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/core/database/database.dart';
import 'package:pantheon_forge/services/skills/skills_service.dart';

enum SkillsTab { installed, market }

class _SkillDetail {
  const _SkillDetail({required this.content, required this.files});

  final String? content;
  final List<SkillFileInfo> files;
}

class SkillsNotifier extends ChangeNotifier {
  final SkillsService _service = SkillsService.instance;

  List<SkillInfo> _skills = const [];
  bool _loading = false;
  String _searchQuery = '';
  String? _selectedSkillName;
  String? _selectedContent;
  List<SkillFileInfo> _selectedFiles = const [];
  bool _detailLoading = false;
  int _detailRequestToken = 0;
  final Map<String, _SkillDetail> _detailCache = {};

  SkillsTab _activeTab = SkillsTab.installed;
  String _marketApiKey = '';
  bool _marketLoading = false;
  String _marketQuery = '';
  int _marketTotal = 0;
  int _marketOffset = 0;
  List<MarketSkillInfo> _marketSkills = const [];
  final Set<String> _marketInstallingIds = <String>{};
  final Map<String, double> _marketInstallProgress = <String, double>{};

  List<SkillInfo> get skills => _skills;
  bool get loading => _loading;
  String get searchQuery => _searchQuery;
  String? get selectedSkillName => _selectedSkillName;
  String? get selectedContent => _selectedContent;
  List<SkillFileInfo> get selectedFiles => _selectedFiles;
  bool get detailLoading => _detailLoading;

  SkillsTab get activeTab => _activeTab;
  String get marketApiKey => _marketApiKey;
  bool get marketLoading => _marketLoading;
  String get marketQuery => _marketQuery;
  int get marketTotal => _marketTotal;
  int get marketOffset => _marketOffset;
  List<MarketSkillInfo> get marketSkills => _marketSkills;

  List<SkillInfo> get filteredSkills {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _skills;
    return _skills.where((skill) {
      return skill.name.toLowerCase().contains(query) ||
          skill.description.toLowerCase().contains(query);
    }).toList();
  }

  bool isMarketSkillInstalling(String skillId) {
    return _marketInstallingIds.contains(skillId);
  }

  double marketInstallProgress(String skillId) {
    return _marketInstallProgress[skillId] ?? 0;
  }

  bool get hasMoreMarketSkills {
    return _marketSkills.length < _marketTotal;
  }

  SkillInfo? get selectedSkill {
    final selected = _selectedSkillName;
    if (selected == null) return null;
    for (final skill in _skills) {
      if (skill.name == selected) return skill;
    }
    return null;
  }

  Future<void> initialize() async {
    _marketApiKey = AppDatabase.instance.getSetting('skillsMarketApiKey') ?? '';
    notifyListeners();
    await loadSkills();
    if (_marketApiKey.isNotEmpty) {
      await loadMarketSkills(reset: true);
    }
  }

  Future<void> loadSkills({bool preserveSelection = true}) async {
    _loading = true;
    notifyListeners();

    final oldSelection = _selectedSkillName;
    final skills = await _service.listSkills();
    _skills = skills;
    _loading = false;
    _shrinkDetailCache();

    if (!preserveSelection) {
      _selectedSkillName = null;
      _selectedContent = null;
      _selectedFiles = const [];
      notifyListeners();
      return;
    }

    if (oldSelection != null && skills.any((s) => s.name == oldSelection)) {
      _selectedSkillName = oldSelection;
      notifyListeners();
      await selectSkill(oldSelection);
      return;
    }

    if (skills.isNotEmpty) {
      _selectedSkillName = skills.first.name;
      notifyListeners();
      await selectSkill(skills.first.name);
      return;
    }

    _selectedSkillName = null;
    _selectedContent = null;
    _selectedFiles = const [];
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setActiveTab(SkillsTab tab) {
    _activeTab = tab;
    notifyListeners();
    if (tab == SkillsTab.market &&
        _marketApiKey.isNotEmpty &&
        _marketSkills.isEmpty &&
        !_marketLoading) {
      loadMarketSkills(reset: true);
    }
  }

  void setMarketQuery(String query) {
    _marketQuery = query;
    notifyListeners();
  }

  void setMarketApiKey(String apiKey) {
    _marketApiKey = apiKey.trim();
    AppDatabase.instance.setSetting('skillsMarketApiKey', _marketApiKey);
    notifyListeners();
  }

  Future<void> loadMarketSkills({bool reset = true}) async {
    if (_marketLoading) return;
    if (_marketApiKey.isEmpty) {
      _marketSkills = const [];
      _marketTotal = 0;
      _marketOffset = 0;
      notifyListeners();
      return;
    }

    _marketLoading = true;
    notifyListeners();
    final offset = reset ? 0 : _marketOffset;
    final query = _marketQuery.trim();
    late final MarketSkillPageResult result;
    if (reset && query.isEmpty) {
      result = await _service.fetchTopRankedMarketSkills(
        apiKey: _marketApiKey,
        limit: 30,
      );
    } else {
      result = await _service.listMarketSkills(
        apiKey: _marketApiKey,
        query: query,
        offset: offset,
        limit: 24,
      );
    }
    if (reset) {
      _marketSkills = result.skills;
    } else {
      _marketSkills = [..._marketSkills, ...result.skills];
    }
    _marketTotal = result.total;
    _marketOffset = offset + result.skills.length;
    if (reset &&
        query.isNotEmpty &&
        result.skills.isEmpty &&
        _marketApiKey.isNotEmpty) {
      final fallback = await _service.fetchTopRankedMarketSkills(
        apiKey: _marketApiKey,
        limit: 30,
      );
      _marketSkills = fallback.skills;
      _marketTotal = fallback.total;
      _marketOffset = fallback.skills.length;
    }
    _marketLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreMarketSkills() async {
    if (_marketLoading || !hasMoreMarketSkills || _marketApiKey.isEmpty) return;
    await loadMarketSkills(reset: false);
  }

  Future<String?> installMarketSkill(MarketSkillInfo skill) async {
    if (_marketInstallingIds.contains(skill.id)) return null;
    if (_marketApiKey.isEmpty) return '请先配置 SkillsMP API Key';
    _marketInstallingIds.add(skill.id);
    _marketInstallProgress[skill.id] = 0;
    notifyListeners();

    try {
      final result = await _service.addSkillFromMarket(
        skill,
        onProgress: (progress) {
          _marketInstallProgress[skill.id] = progress
              .clamp(0.0, 1.0)
              .toDouble();
          notifyListeners();
        },
      );
      if (!result.success) {
        await loadSkills();
        final existing = _skills.where(
          (item) => item.name.toLowerCase() == skill.name.toLowerCase(),
        );
        if (existing.isNotEmpty) {
          await selectSkill(existing.first.name);
          return null;
        }
        return result.error ?? '从市场安装失败';
      }

      _marketInstallProgress[skill.id] = 1;
      notifyListeners();
      await loadSkills();
      if (result.name != null) {
        await selectSkill(result.name);
      }
      return null;
    } finally {
      _marketInstallingIds.remove(skill.id);
      _marketInstallProgress.remove(skill.id);
      notifyListeners();
    }
  }

  Future<void> selectSkill(String? name) async {
    if (name == null || name.trim().isEmpty) {
      _detailRequestToken++;
      _selectedSkillName = null;
      _selectedContent = null;
      _selectedFiles = const [];
      _detailLoading = false;
      notifyListeners();
      return;
    }

    final found = _skills.where((skill) => skill.name == name);
    if (found.isEmpty) return;

    final skill = found.first;
    _selectedSkillName = skill.name;

    final cached = _detailCache[skill.name];
    if (cached != null) {
      _selectedContent = cached.content;
      _selectedFiles = cached.files;
      _detailLoading = false;
      notifyListeners();
      return;
    }

    _detailLoading = true;
    _selectedContent = null;
    _selectedFiles = const [];
    final requestToken = ++_detailRequestToken;
    notifyListeners();

    final contentFuture = _service.readSkillContent(skill);
    final filesFuture = _service.listSkillFiles(skill);
    final content = await contentFuture;
    final files = await filesFuture;

    if (requestToken != _detailRequestToken ||
        _selectedSkillName != skill.name) {
      return;
    }

    _selectedContent = content;
    _selectedFiles = files;
    _detailLoading = false;
    _detailCache[skill.name] = _SkillDetail(content: content, files: files);
    notifyListeners();
  }

  Future<String?> addSkillFromFolder(String sourcePath) async {
    final result = await _service.addSkillFromFolder(sourcePath);
    if (!result.success) {
      return result.error ?? '添加技能失败';
    }

    await loadSkills();
    if (result.name != null) {
      await selectSkill(result.name);
    }
    return null;
  }

  Future<String?> deleteSelectedSkill() async {
    final skill = selectedSkill;
    if (skill == null) return '未选择技能';
    if (skill.readOnly) return '内置技能不可删除';

    final success = await _service.deleteSkill(skill);
    if (!success) {
      return '删除失败';
    }

    _detailCache.remove(skill.name);
    await loadSkills();
    return null;
  }

  Future<void> openSelectedSkillFolder() async {
    final skill = selectedSkill;
    if (skill == null) return;
    await _service.openSkillFolder(skill);
  }

  Future<void> openSkillsMarketDocs() async {
    await _service.openExternalUrl('https://skillsmp.com/');
  }

  void _shrinkDetailCache() {
    final validNames = _skills.map((skill) => skill.name).toSet();
    _detailCache.removeWhere((key, _) => !validNames.contains(key));
  }
}

final skillsProvider = ChangeNotifierProvider<SkillsNotifier>((ref) {
  final notifier = SkillsNotifier();
  notifier.initialize();
  return notifier;
});
