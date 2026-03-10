import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/ui/layout/nav_rail.dart';
import 'package:pantheon_forge/ui/layout/session_list_panel.dart';
import 'package:pantheon_forge/ui/layout/title_bar.dart';
import 'package:pantheon_forge/ui/chat/chat_home_page.dart';
import 'package:pantheon_forge/ui/chat/chat_view.dart';
import 'package:pantheon_forge/ui/settings/settings_page.dart';
import 'package:pantheon_forge/ui/cowork/right_panel.dart';
import 'package:pantheon_forge/ui/ssh/ssh_page.dart';
import 'package:pantheon_forge/ui/skills/skills_page.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  @override
  void initState() {
    super.initState();
    // 延迟执行自动导航，避免阻塞初始渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoNavigation();
    });
  }

  void _checkAutoNavigation() {
    final chat = ref.read(chatProvider);
    final ui = ref.read(uiProvider);
    if (chat.activeSessionId != null && ui.chatView == ChatView.home) {
      ref.read(uiProvider.notifier).navigateToSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 select 优化，只监听需要的字段
    final leftSidebarOpen = ref.watch(uiProvider.select((ui) => ui.leftSidebarOpen));
    final rightPanelOpen = ref.watch(uiProvider.select((ui) => ui.rightPanelOpen));
    final settingsPageOpen = ref.watch(uiProvider.select((ui) => ui.settingsPageOpen));
    final skillsPageOpen = ref.watch(uiProvider.select((ui) => ui.skillsPageOpen));
    final sshPageOpen = ref.watch(uiProvider.select((ui) => ui.sshPageOpen));
    final chatView = ref.watch(uiProvider.select((ui) => ui.chatView));
    
    final colorScheme = Theme.of(context).colorScheme;

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
                    if (leftSidebarOpen && !sshPageOpen) 
                      const SessionListPanel(),

                    // Main Content - 使用 AnimatedSwitcher 实现平滑切换
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        child: _buildMainContent(
                          settingsPageOpen,
                          skillsPageOpen,
                          sshPageOpen,
                          chatView,
                        ),
                      ),
                    ),

                    // Right Panel
                    if (rightPanelOpen)
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

  Widget _buildMainContent(
    bool settingsPageOpen,
    bool skillsPageOpen,
    bool sshPageOpen,
    ChatView chatView,
  ) {
    // 使用 key 确保 AnimatedSwitcher 正确识别不同页面
    if (settingsPageOpen) {
      return const SettingsPage(key: ValueKey('settings'));
    }
    if (skillsPageOpen) {
      // 使用 RepaintBoundary 隔离技能页面的重绘
      return RepaintBoundary(
        child: const SkillsPage(key: ValueKey('skills')),
      );
    }
    if (sshPageOpen) {
      return const SshPage(key: ValueKey('ssh'));
    }
    if (chatView == ChatView.home) {
      return const ChatHomePage(key: ValueKey('chat-home'));
    }
    return const ChatViewPage(key: ValueKey('chat-view'));
  }
}
