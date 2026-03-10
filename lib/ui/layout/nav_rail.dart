import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';

class AppNavRail extends ConsumerWidget {
  const AppNavRail({super.key});

  static const _navItems = [
    (NavItem.chat, Icons.chat_bubble_outline, 'nav.conversations'),
    (NavItem.skills, Icons.auto_fix_high, 'nav.skills'),
    (NavItem.ssh, Icons.terminal, 'nav.ssh'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 优化：只监听需要的字段
    final activeNavItem = ref.watch(uiProvider.select((ui) => ui.activeNavItem));
    final leftSidebarOpen = ref.watch(uiProvider.select((ui) => ui.leftSidebarOpen));
    final settingsPageOpen = ref.watch(uiProvider.select((ui) => ui.settingsPageOpen));
    final skillsPageOpen = ref.watch(uiProvider.select((ui) => ui.skillsPageOpen));
    final sshPageOpen = ref.watch(uiProvider.select((ui) => ui.sshPageOpen));
    final locale = ref.watch(settingsProvider.select((s) => s.settings.language));
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.3),
        border: Border(right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final (item, icon, labelKey) in _navItems)
            Tooltip(
              message: t(labelKey, locale),
              preferBelow: false,
              waitDuration: Duration.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _NavButton(
                icon: icon,
                isActive: _isActive(
                  activeNavItem,
                  leftSidebarOpen,
                  settingsPageOpen,
                  skillsPageOpen,
                  sshPageOpen,
                  item,
                ),
                onTap: () => ref.read(uiProvider.notifier).setNavItem(item),
                colorScheme: colorScheme,
              ),
              ),
            ),
          const Spacer(),
          Tooltip(
            message: t('nav.settings', locale),
            preferBelow: false,
            waitDuration: Duration.zero,
            child: _NavButton(
              icon: Icons.settings_outlined,
              isActive: settingsPageOpen,
              onTap: () => ref.read(uiProvider.notifier).openSettings(),
              colorScheme: colorScheme,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text('v0.1.0',
              style: TextStyle(fontSize: 9, color: colorScheme.onSurface.withValues(alpha: 0.3)),
            ),
          ),
        ],
      ),
    );
  }

  bool _isActive(
    NavItem activeNavItem,
    bool leftSidebarOpen,
    bool settingsPageOpen,
    bool skillsPageOpen,
    bool sshPageOpen,
    NavItem item,
  ) {
    if (item == NavItem.skills) return skillsPageOpen;
    if (item == NavItem.ssh) return sshPageOpen;
    return activeNavItem == item && leftSidebarOpen &&
        !settingsPageOpen && !skillsPageOpen && !sshPageOpen;
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _NavButton({
    required this.icon, required this.isActive,
    required this.onTap, required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: isActive
            ? colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 36, height: 36,
            child: Icon(icon, size: 20,
              color: isActive ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
