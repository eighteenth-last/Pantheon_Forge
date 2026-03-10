import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';

class CoworkRightPanel extends ConsumerWidget {
  const CoworkRightPanel({super.key});

  static const _tabs = [
    (RightPanelTab.steps, 'panel.steps', Icons.format_list_numbered),
    (RightPanelTab.plan, 'panel.plan', Icons.description_outlined),
    (RightPanelTab.team, 'panel.team', Icons.group_outlined),
    (RightPanelTab.files, 'panel.files', Icons.folder_outlined),
    (RightPanelTab.artifacts, 'panel.artifacts', Icons.widgets_outlined),
    (RightPanelTab.context, 'panel.context', Icons.data_object),
    (RightPanelTab.skills, 'panel.skills', Icons.auto_awesome_outlined),
    (RightPanelTab.cron, 'panel.cron', Icons.schedule_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 优化：只监听需要的字段
    final rightPanelTab = ref.watch(uiProvider.select((ui) => ui.rightPanelTab));
    final locale = ref.watch(settingsProvider.select((s) => s.settings.language));
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Column(
        children: [
          // Tab bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.2))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (tab, labelKey, icon) in _tabs)
                    _PanelTab(
                      icon: icon,
                      label: t(labelKey, locale),
                      isActive: rightPanelTab == tab,
                      onTap: () => ref.read(uiProvider.notifier).setRightPanelTab(tab),
                      colorScheme: colorScheme,
                    ),
                  const SizedBox(width: 4),
                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    onPressed: () => ref.read(uiProvider.notifier).toggleRightPanel(),
                    visualDensity: VisualDensity.compact,
                    iconSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // Panel content
          Expanded(
            child: _buildPanelContent(rightPanelTab, locale, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelContent(RightPanelTab tab, String locale, ColorScheme colorScheme) {
    final labelKey = _tabs.firstWhere((t) => t.$1 == tab).$2;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_tabs.firstWhere((t) => t.$1 == tab).$3, size: 32,
            color: colorScheme.onSurface.withValues(alpha: 0.12)),
          const SizedBox(height: 8),
          Text(t(labelKey, locale),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
              color: colorScheme.onSurface.withValues(alpha: 0.3))),
          const SizedBox(height: 4),
          Text(t('common.noData', locale),
            style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withValues(alpha: 0.2))),
        ],
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _PanelTab({required this.icon, required this.label,
    required this.isActive, required this.onTap, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: isActive ? colorScheme.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Tooltip(
            message: label,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Icon(icon, size: 16,
                color: isActive ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.4)),
            ),
          ),
        ),
      ),
    );
  }
}
