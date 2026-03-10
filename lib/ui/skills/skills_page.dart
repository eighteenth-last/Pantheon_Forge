import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/providers/skills_provider.dart';
import 'package:pantheon_forge/services/skills/skills_service.dart';
import 'package:pantheon_forge/ui/common/app_message.dart';

class SkillsPage extends ConsumerStatefulWidget {
  const SkillsPage({super.key});

  @override
  ConsumerState<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends ConsumerState<SkillsPage> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // 使用 microtask 延迟初始化，不阻塞 UI
    Future.microtask(() {
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      // 显示加载占位符，避免阻塞
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    return const _SkillsPageContent();
  }
}

class _SkillsPageContent extends ConsumerWidget {
  const _SkillsPageContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 优化：只监听需要的字段
    final locale = ref.watch(settingsProvider.select((s) => s.settings.language));
    final colorScheme = Theme.of(context).colorScheme;
    final activeTab = ref.watch(skillsProvider.select((s) => s.activeTab));
    final searchQuery = ref.watch(skillsProvider.select((s) => s.searchQuery));
    final marketQuery = ref.watch(skillsProvider.select((s) => s.marketQuery));
    final marketApiKey = ref.watch(skillsProvider.select((s) => s.marketApiKey));
    
    // Market 相关字段
    final marketSkills = ref.watch(skillsProvider.select((s) => s.marketSkills));
    final marketLoading = ref.watch(skillsProvider.select((s) => s.marketLoading));
    final hasMoreMarketSkills = ref.watch(skillsProvider.select((s) => s.hasMoreMarketSkills));
    
    // Installed 相关字段
    final skills = ref.watch(skillsProvider.select((s) => s.skills));
    final skillsState = ref.watch(skillsProvider); // 用于传递给 _SkillsInstalledView

    return Column(
      children: [
        _SkillsTopBar(
          locale: locale,
          colorScheme: colorScheme,
          activeTab: activeTab,
          installedQuery: searchQuery,
          marketQuery: marketQuery,
          marketApiKey: marketApiKey,
          onBack: () => ref.read(uiProvider.notifier).closeSkills(),
          onTabChanged: (tab) => ref.read(skillsProvider).setActiveTab(tab),
          onInstalledQueryChanged: (value) =>
              ref.read(skillsProvider).setSearchQuery(value),
          onMarketQueryChanged: (value) =>
              ref.read(skillsProvider).setMarketQuery(value),
          onMarketApiKeyChanged: (value) =>
              ref.read(skillsProvider).setMarketApiKey(value),
          onReload: () {
            if (activeTab == SkillsTab.market) {
              ref.read(skillsProvider).loadMarketSkills(reset: true);
            } else {
              ref.read(skillsProvider).loadSkills();
            }
          },
          onAddSkill: () => _handleAddSkill(context, ref, locale),
          onOpenMarketDocs: () =>
              ref.read(skillsProvider).openSkillsMarketDocs(),
        ),
        Expanded(
          child: activeTab == SkillsTab.market
              ? _SkillsMarketView(
                  locale: locale,
                  colorScheme: colorScheme,
                  query: marketQuery,
                  apiKeyConfigured: marketApiKey.isNotEmpty,
                  skills: marketSkills,
                  loading: marketLoading,
                  hasMore: hasMoreMarketSkills,
                  installedNames: skills
                      .map((skill) => skill.name.toLowerCase())
                      .toSet(),
                  isInstalling: (id) => skillsState.isMarketSkillInstalling(id),
                  installProgress: (id) =>
                      skillsState.marketInstallProgress(id),
                  onInstall: (skill) =>
                      _handleInstallSkill(context, ref, locale, skill),
                  onLoadMore: () =>
                      ref.read(skillsProvider).loadMoreMarketSkills(),
                  onOpenDocs: () =>
                      ref.read(skillsProvider).openSkillsMarketDocs(),
                )
              : _SkillsInstalledView(
                  locale: locale,
                  colorScheme: colorScheme,
                  state: skillsState,
                  onSelect: (name) =>
                      ref.read(skillsProvider).selectSkill(name),
                  onOpenFolder: () =>
                      ref.read(skillsProvider).openSelectedSkillFolder(),
                  onDelete: () => _handleDeleteSkill(context, ref, locale),
                ),
        ),
      ],
    );
  }

  Future<void> _handleAddSkill(
    BuildContext context,
    WidgetRef ref,
    String locale,
  ) async {
    final sourcePath = await getDirectoryPath(confirmButtonText: '选择技能目录');
    if (sourcePath == null || sourcePath.trim().isEmpty || !context.mounted) {
      return;
    }
    final error = await ref.read(skillsProvider).addSkillFromFolder(sourcePath);
    if (!context.mounted) return;
    if (error == null) {
      AppMessage.success(context, t('skills.page.added', locale));
      return;
    }
    AppMessage.error(context, '${t('skills.page.addFailed', locale)}: $error');
  }

  Future<void> _handleDeleteSkill(
    BuildContext context,
    WidgetRef ref,
    String locale,
  ) async {
    final skill = ref.read(skillsProvider).selectedSkill;
    if (skill == null) return;
    if (skill.readOnly) {
      AppMessage.info(context, t('skills.page.readOnly', locale));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('skills.page.delete', locale)),
        content: Text(
          t(
            'skills.page.deleteConfirm',
            locale,
          ).replaceAll('{name}', skill.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('common.cancel', locale)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('common.confirm', locale)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await ref.read(skillsProvider).deleteSelectedSkill();
    if (!context.mounted) return;
    if (error == null) {
      AppMessage.success(context, t('skills.page.deleted', locale));
      return;
    }
    AppMessage.error(
      context,
      '${t('skills.page.deleteFailed', locale)}: $error',
    );
  }

  Future<void> _handleInstallSkill(
    BuildContext context,
    WidgetRef ref,
    String locale,
    MarketSkillInfo skill,
  ) async {
    final error = await ref.read(skillsProvider).installMarketSkill(skill);
    if (!context.mounted) return;
    if (error == null) {
      AppMessage.success(context, t('skills.market.installSuccess', locale));
      return;
    }
    AppMessage.error(
      context,
      '${t('skills.market.installFailed', locale)}: $error',
    );
  }
}

class _SkillsTopBar extends StatelessWidget {
  const _SkillsTopBar({
    required this.locale,
    required this.colorScheme,
    required this.activeTab,
    required this.installedQuery,
    required this.marketQuery,
    required this.marketApiKey,
    required this.onBack,
    required this.onTabChanged,
    required this.onInstalledQueryChanged,
    required this.onMarketQueryChanged,
    required this.onMarketApiKeyChanged,
    required this.onReload,
    required this.onAddSkill,
    required this.onOpenMarketDocs,
  });

  final String locale;
  final ColorScheme colorScheme;
  final SkillsTab activeTab;
  final String installedQuery;
  final String marketQuery;
  final String marketApiKey;
  final VoidCallback onBack;
  final ValueChanged<SkillsTab> onTabChanged;
  final ValueChanged<String> onInstalledQueryChanged;
  final ValueChanged<String> onMarketQueryChanged;
  final ValueChanged<String> onMarketApiKeyChanged;
  final VoidCallback onReload;
  final VoidCallback onAddSkill;
  final VoidCallback onOpenMarketDocs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            onPressed: onBack,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Text(
            t('skills.page.title', locale),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<SkillsTab>(
            segments: [
              ButtonSegment(
                value: SkillsTab.installed,
                icon: const Icon(Icons.folder_open_outlined, size: 14),
                label: Text(
                  t('skills.page.tabInstalled', locale),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              ButtonSegment(
                value: SkillsTab.market,
                icon: const Icon(Icons.storefront_outlined, size: 14),
                label: Text(
                  t('skills.page.tabMarket', locale),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
            selected: {activeTab},
            showSelectedIcon: false,
            onSelectionChanged: (value) => onTabChanged(value.first),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: _SyncTextField(
                      value: activeTab == SkillsTab.market
                          ? marketQuery
                          : installedQuery,
                      hintText: t('common.search', locale),
                      onChanged: activeTab == SkillsTab.market
                          ? onMarketQueryChanged
                          : onInstalledQueryChanged,
                      prefixIcon: const Icon(Icons.search, size: 16),
                    ),
                  ),
                ),
                if (activeTab == SkillsTab.market) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: _SyncTextField(
                        value: marketApiKey,
                        hintText: t('skills.market.apiKeyPlaceholder', locale),
                        onChanged: onMarketApiKeyChanged,
                        prefixIcon: const Icon(Icons.key, size: 14),
                        obscureText: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: t('skills.market.docs', locale),
                    onPressed: onOpenMarketDocs,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: t('skills.page.reload', locale),
                  onPressed: onReload,
                  visualDensity: VisualDensity.compact,
                ),
                if (activeTab == SkillsTab.installed)
                  FilledButton.tonalIcon(
                    onPressed: onAddSkill,
                    icon: const Icon(Icons.add, size: 15),
                    label: Text(
                      t('skills.page.add', locale),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillsMarketView extends StatelessWidget {
  const _SkillsMarketView({
    required this.locale,
    required this.colorScheme,
    required this.query,
    required this.apiKeyConfigured,
    required this.skills,
    required this.loading,
    required this.hasMore,
    required this.installedNames,
    required this.isInstalling,
    required this.installProgress,
    required this.onInstall,
    required this.onLoadMore,
    required this.onOpenDocs,
  });

  final String locale;
  final ColorScheme colorScheme;
  final String query;
  final bool apiKeyConfigured;
  final List<MarketSkillInfo> skills;
  final bool loading;
  final bool hasMore;
  final Set<String> installedNames;
  final bool Function(String skillId) isInstalling;
  final double Function(String skillId) installProgress;
  final ValueChanged<MarketSkillInfo> onInstall;
  final VoidCallback onLoadMore;
  final VoidCallback onOpenDocs;

  @override
  Widget build(BuildContext context) {
    if (!apiKeyConfigured) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('skills.market.emptyKeyTitle', locale),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('skills.market.emptyKeyDesc', locale),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: onOpenDocs,
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text(
                  t('skills.market.docs', locale),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (loading && skills.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.primary,
        ),
      );
    }

    if (skills.isEmpty) {
      return Center(
        child: Text(
          t('skills.market.noResult', locale),
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (query.trim().isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              t('skills.market.topRankedLabel', locale),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        Expanded(
          child: RepaintBoundary(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: skills.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              // 添加缓存范围以提高滚动性能
              cacheExtent: 500,
              itemBuilder: (context, index) {
                final skill = skills[index];
                return RepaintBoundary(
                  child: _MarketSkillTile(
                    key: ValueKey(skill.id),
                    locale: locale,
                    colorScheme: colorScheme,
                    skill: skill,
                    installed: installedNames.contains(skill.name.toLowerCase()),
                    installing: isInstalling(skill.id),
                    installProgress: installProgress(skill.id),
                    onInstall: () => onInstall(skill),
                  ),
                );
              },
            ),
          ),
        ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.tonalIcon(
              onPressed: loading ? null : onLoadMore,
              icon: loading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more, size: 14),
              label: Text(
                t('skills.market.loadMore', locale),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

class _MarketSkillTile extends StatelessWidget {
  const _MarketSkillTile({
    super.key,
    required this.locale,
    required this.colorScheme,
    required this.skill,
    required this.installed,
    required this.installing,
    required this.installProgress,
    required this.onInstall,
  });

  final String locale;
  final ColorScheme colorScheme;
  final MarketSkillInfo skill;
  final bool installed;
  final bool installing;
  final double installProgress;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = installProgress.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 16,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${skill.owner}/${skill.repo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                if (skill.description != null &&
                    skill.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    skill.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (installed)
            Text(
              t('skills.market.installed', locale),
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            FilledButton.tonal(
              onPressed: installing ? null : onInstall,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(110, 34),
              ),
              child: installing
                  ? SizedBox(
                      width: 92,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(normalizedProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 10),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            minHeight: 3,
                            value: normalizedProgress,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      t('skills.market.install', locale),
                      style: const TextStyle(fontSize: 11),
                    ),
            ),
        ],
      ),
    );
  }
}

class _SkillsInstalledView extends StatelessWidget {
  const _SkillsInstalledView({
    required this.locale,
    required this.colorScheme,
    required this.state,
    required this.onSelect,
    required this.onOpenFolder,
    required this.onDelete,
  });

  final String locale;
  final ColorScheme colorScheme;
  final SkillsNotifier state;
  final ValueChanged<String> onSelect;
  final VoidCallback onOpenFolder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SkillsListPane(
          locale: locale,
          colorScheme: colorScheme,
          skills: state.filteredSkills,
          loading: state.loading,
          selectedSkillName: state.selectedSkillName,
          onSelect: onSelect,
        ),
        Expanded(
          child: _SkillDetailPane(
            locale: locale,
            colorScheme: colorScheme,
            selectedSkill: state.selectedSkill,
            loading: state.detailLoading,
            content: state.selectedContent,
            files: state.selectedFiles,
            onOpenFolder: onOpenFolder,
            onDelete: onDelete,
          ),
        ),
      ],
    );
  }
}

class _SkillsListPane extends StatelessWidget {
  const _SkillsListPane({
    required this.locale,
    required this.colorScheme,
    required this.skills,
    required this.loading,
    required this.selectedSkillName,
    required this.onSelect,
  });

  final String locale;
  final ColorScheme colorScheme;
  final List<SkillInfo> skills;
  final bool loading;
  final String? selectedSkillName;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: loading
          ? Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : skills.isEmpty
          ? Center(
              child: Text(
                t('skills.page.empty', locale),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            )
          : RepaintBoundary(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: skills.length,
                // 添加缓存范围以提高滚动性能
                cacheExtent: 300,
                itemBuilder: (context, index) {
                  final skill = skills[index];
                  final selected = selectedSkillName == skill.name;
                  return RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        key: ValueKey(skill.name),
                        color: selected
                            ? colorScheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onSelect(skill.name),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  skill.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  skill.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _SkillDetailPane extends StatelessWidget {
  const _SkillDetailPane({
    required this.locale,
    required this.colorScheme,
    required this.selectedSkill,
    required this.loading,
    required this.content,
    required this.files,
    required this.onOpenFolder,
    required this.onDelete,
  });

  final String locale;
  final ColorScheme colorScheme;
  final SkillInfo? selectedSkill;
  final bool loading;
  final String? content;
  final List<SkillFileInfo> files;
  final VoidCallback onOpenFolder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (selectedSkill == null) {
      return Center(
        child: Text(
          t('skills.page.selectHint', locale),
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selectedSkill!.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                tooltip: t('skills.page.openFolder', locale),
                onPressed: onOpenFolder,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: t('skills.page.delete', locale),
                onPressed: selectedSkill!.readOnly ? null : onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : content == null
              ? Center(
                  child: Text(
                    t('skills.page.loadFailed', locale),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  children: [
                    MarkdownBody(
                      data: content!,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SkillFilesList(
                      locale: locale,
                      colorScheme: colorScheme,
                      files: files,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SkillFilesList extends StatelessWidget {
  const _SkillFilesList({
    required this.locale,
    required this.colorScheme,
    required this.files,
  });

  final String locale;
  final ColorScheme colorScheme;
  final List<SkillFileInfo> files;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Text(
        t('skills.page.noFiles', locale),
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      );
    }

    final total = files.fold<int>(0, (sum, file) => sum + file.size);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t('skills.page.files', locale)} (${files.length}, ${_formatSize(total)})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          for (final file in files)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  Text(
                    _formatSize(file.size),
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SyncTextField extends StatefulWidget {
  const _SyncTextField({
    required this.value,
    required this.hintText,
    required this.onChanged,
    this.prefixIcon,
    this.obscureText = false,
  });

  final String value;
  final String hintText;
  final ValueChanged<String> onChanged;
  final Widget? prefixIcon;
  final bool obscureText;

  @override
  State<_SyncTextField> createState() => _SyncTextFieldState();
}

class _SyncTextFieldState extends State<_SyncTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SyncTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      obscureText: widget.obscureText,
      onChanged: widget.onChanged,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface.withValues(alpha: 0.35),
        ),
        prefixIcon: widget.prefixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
