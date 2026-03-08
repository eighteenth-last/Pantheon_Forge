import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';

class SessionListPanel extends ConsumerWidget {
  const SessionListPanel({super.key});

  Future<void> _handleCreateAction(
    BuildContext context,
    WidgetRef ref,
    _CreateAction action,
  ) async {
    switch (action) {
      case _CreateAction.chat:
        ref
            .read(chatProvider)
            .createSession(mode: ref.read(uiProvider).mode.name);
        ref.read(uiProvider.notifier).navigateToSession();
        break;
      case _CreateAction.localProject:
        final folderPath = await getDirectoryPath(
          confirmButtonText: '选择此目录',
          initialDirectory: null,
        );
        if (folderPath == null || folderPath.isEmpty || !context.mounted) {
          return;
        }
        ref
            .read(chatProvider)
            .createLocalProjectSession(
              folderPath: folderPath,
              mode: ref.read(uiProvider).mode.name,
            );
        ref.read(uiProvider.notifier).navigateToSession();
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final locale = ref.watch(settingsProvider).settings.language;
    final colorScheme = Theme.of(context).colorScheme;
    final sessions = chat.sessions;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  t('nav.conversations', locale),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<_CreateAction>(
                  tooltip: t('chat.newChat', locale),
                  padding: EdgeInsets.zero,
                  splashRadius: 18,
                  icon: Icon(
                    Icons.add,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onSelected: (action) =>
                      _handleCreateAction(context, ref, action),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _CreateAction.chat,
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 16),
                          SizedBox(width: 8),
                          Text('新会话'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _CreateAction.localProject,
                      child: Row(
                        children: [
                          Icon(Icons.folder_open_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('打开本地目录'),
                        ],
                      ),
                    ),
                  ],
                ),
                _IconBtn(
                  icon: Icons.chevron_left,
                  tooltip: 'Collapse',
                  onTap: () =>
                      ref.read(uiProvider.notifier).toggleLeftSidebar(),
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
          // Session list
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Text(
                      t('common.noData', locale),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = session.id == chat.activeSessionId;
                      return _SessionTile(
                        session: session,
                        isActive: isActive,
                        locale: locale,
                        colorScheme: colorScheme,
                        onTap: () {
                          ref.read(chatProvider).setActiveSession(session.id);
                          ref.read(uiProvider.notifier).navigateToSession();
                        },
                        onDelete: () =>
                            ref.read(chatProvider).deleteSession(session.id),
                        onTogglePin: () =>
                            ref.read(chatProvider).togglePin(session.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatefulWidget {
  final dynamic session;
  final bool isActive;
  final String locale;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.locale,
    required this.colorScheme,
    required this.onTap,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Material(
          color: widget.isActive
              ? cs.primary.withValues(alpha: 0.1)
              : _hovering
              ? cs.onSurface.withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (widget.session.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.push_pin,
                        size: 10,
                        color: cs.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      widget.session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isActive
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  if (_hovering) ...[
                    _TinyBtn(Icons.push_pin_outlined, widget.onTogglePin, cs),
                    _TinyBtn(Icons.close, widget.onDelete, cs),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TinyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _TinyBtn(this.icon, this.onTap, this.cs);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 12, color: cs.onSurface.withValues(alpha: 0.4)),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

enum _CreateAction { chat, localProject }
