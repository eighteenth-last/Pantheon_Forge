import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';
import 'package:pantheon_forge/ui/layout/nav_rail.dart';
import 'package:pantheon_forge/ui/layout/session_list_panel.dart';
import 'package:pantheon_forge/ui/layout/title_bar.dart';
import 'package:pantheon_forge/ui/chat/chat_home_page.dart';
import 'package:pantheon_forge/ui/chat/chat_view.dart';
import 'package:pantheon_forge/ui/settings/settings_page.dart';
import 'package:pantheon_forge/ui/cowork/right_panel.dart';
import 'package:pantheon_forge/ui/ssh/ssh_page.dart';

class MainLayout extends ConsumerWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiProvider);
    final chat = ref.watch(chatProvider);
    final settings = ref.watch(settingsProvider).settings;
    final locale = settings.language;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Auto-navigate to session if there's an active session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chat.activeSessionId != null && ui.chatView == ChatView.home) {
        ref.read(uiProvider.notifier).navigateToSession();
      }
    });

    return Scaffold(
      body: Column(
        children: [
          const AppTitleBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(1, 1, 1, 1.5),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    // NavRail
                    const AppNavRail(),

                    // Session List Panel (在 SSH 页面时隐藏)
                    if (ui.leftSidebarOpen && !ui.sshPageOpen) const SessionListPanel(),

                    // Main Content
                    Expanded(
                      child: _buildMainContent(ui, locale, colorScheme),
                    ),

                    // Right Panel
                    if (ui.rightPanelOpen)
                      const CoworkRightPanel(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(UIState ui, String locale, ColorScheme colorScheme) {
    if (ui.settingsPageOpen) {
      return const SettingsPage();
    }
    if (ui.skillsPageOpen) {
      return Center(
        child: Text(t('nav.skills', locale),
          style: TextStyle(color: colorScheme.onSurfaceVariant)),
      );
    }
    if (ui.translatePageOpen) {
      return Center(
        child: Text(t('nav.translate', locale),
          style: TextStyle(color: colorScheme.onSurfaceVariant)),
      );
    }
    if (ui.sshPageOpen) {
      return const SshPage();
    }
    if (ui.chatView == ChatView.home) {
      return const ChatHomePage();
    }
    return const ChatViewPage();
  }
}
