import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/agent/chat_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

const _imageUuid = Uuid();

final _chatService = ChatService();

// 自定义拦截滚动条的行为，彻底隐藏输入框的侧边滚动条
class _NoScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class ChatViewPage extends ConsumerStatefulWidget {
  const ChatViewPage({super.key});

  @override
  ConsumerState<ChatViewPage> createState() => _ChatViewPageState();
}

class _ChatViewPageState extends ConsumerState<ChatViewPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _webSearchEnabled = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleWebSearch() {
    setState(() {
      _webSearchEnabled = !_webSearchEnabled;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final chat = ref.read(chatProvider);
    final sessionId = chat.activeSessionId;
    if (sessionId == null) return;
    if (chat.isStreaming) return;

    _controller.clear();
    _scrollToBottom();

    _chatService.sendMessage(
      text: text,
      sessionId: sessionId,
      chat: chat,
      providerNotifier: ref.read(providerProvider),
      settings: ref.read(settingsProvider).settings,
      webSearchEnabled: _webSearchEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final settings = ref.watch(settingsProvider).settings;
    final locale = settings.language;
    final colorScheme = Theme.of(context).colorScheme;
    final activeSession = chat.activeSession;
    final sessionId = chat.activeSessionId;
    final messages = sessionId != null
        ? chat.getMessages(sessionId)
        : <UnifiedMessage>[];

    // Auto-scroll when streaming
    if (chat.isStreaming) _scrollToBottom();

    return Column(
      children: [
        if (activeSession?.workingFolder != null &&
            activeSession!.workingFolder!.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_open, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activeSession.workingFolder!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // Message list
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 40,
                        color: colorScheme.onSurface.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('chat.noMessages', locale),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        t('chat.noMessages.desc', locale),
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurface.withValues(alpha: 0.25),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _MessageBubble(
                    message: messages[index],
                    locale: locale,
                    colorScheme: colorScheme,
                  ),
                ),
        ),

        // Input area
        _InputArea(
          controller: _controller,
          focusNode: _focusNode,
          isStreaming: chat.isStreaming,
          locale: locale,
          colorScheme: colorScheme,
          onSend: _sendMessage,
          onStop: () => _chatService.stopStreaming(),
          providerName: ref.watch(providerProvider).activeProvider?.name,
          modelName: ref.watch(providerProvider).activeModel?.name,
          webSearchEnabled: _webSearchEnabled,
          onToggleWebSearch: _toggleWebSearch,
        ),
      ],
    );
  }
}

// ──────────── Message Bubble ────────────

class _MessageBubble extends StatelessWidget {
  final UnifiedMessage message;
  final String locale;
  final ColorScheme colorScheme;

  const _MessageBubble({
    required this.message,
    required this.locale,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.system ||
        message.role == MessageRole.tool) {
      return const SizedBox.shrink();
    }

    final isUser = message.role == MessageRole.user;
    if (isUser && _isToolResultOnlyMessage(message)) {
      return const SizedBox.shrink();
    }
    if (!isUser && !_hasVisibleAssistantContent(message)) {
      return const SizedBox.shrink();
    }
    final isTool = message.role == MessageRole.tool;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary.withValues(alpha: 0.1)
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUser
                      ? colorScheme.primary.withValues(alpha: 0.2)
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    SelectableText(
                      message.textContent,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface,
                      ),
                    )
                  else
                    _AssistantContent(
                      message: message,
                      colorScheme: colorScheme,
                      isTool: isTool,
                    ),
                  // Token usage display
                  if (!isUser)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.token,
                            size: 10,
                            color: colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 4),
                          if (message.usage != null) ...[
                            Text(
                              '${message.usage!.inputTokens}↓ ${message.usage!.outputTokens}↑',
                              style: TextStyle(
                                fontSize: 9,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            if (message.usage!.contextTokens != null &&
                                message.usage!.contextTokens! > 0)
                              Text(
                                ' · ${message.usage!.contextTokens} total',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                          ] else
                            Text(
                              '${(message.textContent.length * 0.75).round()} tokens',
                              style: TextStyle(
                                fontSize: 9,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
              child: Icon(Icons.person, size: 16, color: colorScheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantContent extends StatelessWidget {
  const _AssistantContent({
    required this.message,
    required this.colorScheme,
    required this.isTool,
  });

  final UnifiedMessage message;
  final ColorScheme colorScheme;
  final bool isTool;

  @override
  Widget build(BuildContext context) {
    final blocks = message.blocks;
    if (blocks.isEmpty || (blocks.length == 1 && blocks.first.type == 'text')) {
      return MarkdownBody(
        data: message.textContent,
        selectable: true,
        styleSheet: _markdownStyle(colorScheme),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) ...[
          if (block.type == 'thinking' && (block.thinking?.isNotEmpty ?? false))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.tertiary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                block.thinking!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          if (block.type == 'text' && (block.text?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MarkdownBody(
                data: block.text!,
                selectable: true,
                styleSheet: _markdownStyle(colorScheme),
              ),
            ),
          if (block.type == 'tool_use') const SizedBox.shrink(),
          if (block.type == 'tool_result')
            _CollapsibleToolCard(
              title: '工具结果 · ${block.toolName ?? 'unknown'}',
              subtitle: block.toolCallId,
              color: (block.isError ?? false)
                  ? colorScheme.error.withValues(alpha: 0.08)
                  : (isTool
                        ? colorScheme.secondary.withValues(alpha: 0.08)
                        : colorScheme.surfaceContainerHighest),
              child: SelectableText(
                _formatToolContent(block.toolResultContent ?? ''),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: colorScheme.onSurface,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _CollapsibleToolCard extends StatefulWidget {
  const _CollapsibleToolCard({
    required this.title,
    required this.child,
    required this.color,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Color color;

  @override
  State<_CollapsibleToolCard> createState() => _CollapsibleToolCardState();
}

class _CollapsibleToolCardState extends State<_CollapsibleToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (widget.subtitle != null)
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}


bool _isToolResultOnlyMessage(UnifiedMessage message) {
  final blocks = message.blocks;
  return blocks.isNotEmpty && blocks.every((block) => block.type == 'tool_result');
}

bool _hasVisibleAssistantContent(UnifiedMessage message) {
  final blocks = message.blocks;
  if (blocks.isEmpty) {
    return message.textContent.trim().isNotEmpty;
  }
  return blocks.any((block) {
    if (block.type == 'tool_use') {
      return false;
    }
    if (block.type == 'text') {
      return (block.text?.trim().isNotEmpty ?? false);
    }
    if (block.type == 'thinking') {
      return (block.thinking?.trim().isNotEmpty ?? false);
    }
    if (block.type == 'tool_result') {
      return (block.toolResultContent?.trim().isNotEmpty ?? false);
    }
    return false;
  });
}

String _formatToolContent(String content) {
  try {
    final decoded = jsonDecode(content);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return content;
  }
}

MarkdownStyleSheet _markdownStyle(ColorScheme colorScheme) {
  return MarkdownStyleSheet(
    p: TextStyle(fontSize: 12, color: colorScheme.onSurface, height: 1.4),
    code: TextStyle(
      fontSize: 11,
      fontFamily: 'Consolas',
      backgroundColor: colorScheme.surfaceContainerHighest,
      color: colorScheme.onSurface,
    ),
    codeblockDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

// ──────────── Image Attachment ────────────

class ImageAttachment {
  final String id;
  final String dataUrl;
  final String mediaType;
  final String? fileName;

  ImageAttachment({
    required this.id,
    required this.dataUrl,
    required this.mediaType,
    this.fileName,
  });
}

// ──────────── Advanced Model Switcher ────────────

class _AdvancedModelSwitcher extends ConsumerStatefulWidget {
  final ColorScheme colorScheme;
  final String locale;

  const _AdvancedModelSwitcher({
    required this.colorScheme,
    required this.locale,
  });

  @override
  ConsumerState<_AdvancedModelSwitcher> createState() =>
      _AdvancedModelSwitcherState();
}

class _AdvancedModelSwitcherState
    extends ConsumerState<_AdvancedModelSwitcher> {
  final OverlayPortalController _overlayController =
      OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openPanel() {
    _searchController.clear();
    _overlayController.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
    setState(() {});
  }

  void _closePanel() {
    _overlayController.hide();
    _searchFocusNode.unfocus();
    setState(() {});
  }

  Widget _getProviderIcon(ProviderType? type, {double size = 16}) {
    switch (type) {
      case ProviderType.anthropic:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(Icons.psychology, size: size - 5, color: Colors.orange),
        );
      case ProviderType.openai:
      default:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(Icons.smart_toy, size: size - 5, color: Colors.green),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final providerState = ref.watch(providerProvider);
    final activeProvider = providerState.activeProvider;
    final activeModel = providerState.activeModel;
    final hasCustomPrompt =
        ref.watch(settingsProvider).settings.systemPrompt.isNotEmpty;
    final enabledProviders = providerState.providers
        .where((provider) => provider.enabled)
        .toList();
    final query = _searchController.text.trim().toLowerCase();
    final groups = enabledProviders
        .map((provider) {
          final models = provider.models.where((model) {
            if (!model.enabled) {
              return false;
            }
            if (query.isEmpty) {
              return true;
            }
            final name =
                (model.name.isNotEmpty ? model.name : model.id).toLowerCase();
            return name.contains(query) ||
                model.id.toLowerCase().contains(query) ||
                provider.name.toLowerCase().contains(query);
          }).toList();
          return MapEntry(provider, models);
        })
        .where((entry) => entry.value.isNotEmpty)
        .toList();

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (context) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _closePanel,
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topLeft,
                followerAnchor: Alignment.bottomLeft,
                offset: const Offset(0, 8),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 430,
                    constraints: const BoxConstraints(maxHeight: 520),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  '选择模型',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '??',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _closePanel,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 16,
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    onChanged: (_) => setState(() {}),
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(
                                      hintText: '搜索模型或提供商',
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Flexible(
                          child: groups.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      enabledProviders.isEmpty
                                          ? '没有可用的模型提供商'
                                          : '没有匹配的模型',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurface
                                            .withValues(alpha: 0.55),
                                      ),
                                    ),
                                  ),
                                )
                              : ScrollConfiguration(
                                  behavior: _NoScrollbarBehavior(),
                                  child: ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    shrinkWrap: true,
                                    itemCount: groups.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, groupIndex) {
                                      final group = groups[groupIndex];
                                      final provider = group.key;
                                      final models = group.value;
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 4,
                                              right: 4,
                                              bottom: 6,
                                            ),
                                            child: Row(
                                              children: [
                                                _getProviderIcon(provider.type),
                                                const SizedBox(width: 6),
                                                Text(
                                                  provider.name,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.6,
                                                    color: colorScheme.onSurface
                                                        .withValues(alpha: 0.55),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ...models.map((model) {
                                            final isActive =
                                                providerState.activeProviderId ==
                                                    provider.id &&
                                                providerState.activeModelId ==
                                                    model.id;
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                onTap: () {
                                                  ref
                                                      .read(
                                                        providerProvider.notifier,
                                                      )
                                                      .setActive(
                                                        provider.id,
                                                        model.id,
                                                      );
                                                  _closePanel();
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(10),
                                                  decoration: BoxDecoration(
                                                    color: isActive
                                                        ? colorScheme.primary
                                                            .withValues(
                                                              alpha: 0.08,
                                                            )
                                                        : colorScheme
                                                            .surfaceContainerLow,
                                                    borderRadius:
                                                        BorderRadius.circular(14),
                                                    border: Border.all(
                                                      color: isActive
                                                          ? colorScheme.primary
                                                              .withValues(
                                                                alpha: 0.35,
                                                              )
                                                          : colorScheme
                                                              .outlineVariant
                                                              .withValues(
                                                                alpha: 0.25,
                                                              ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Container(
                                                        width: 22,
                                                        height: 22,
                                                        decoration: BoxDecoration(
                                                          color: isActive
                                                              ? colorScheme
                                                                  .primary
                                                                  .withValues(
                                                                    alpha: 0.12,
                                                                  )
                                                              : colorScheme
                                                                  .surfaceContainerHighest,
                                                          shape: BoxShape.circle,
                                                        ),
                                                        alignment:
                                                            Alignment.center,
                                                        child: isActive
                                                            ? Icon(
                                                                Icons.check,
                                                                size: 14,
                                                                color:
                                                                    colorScheme
                                                                        .primary,
                                                              )
                                                            : _getProviderIcon(
                                                                provider.type,
                                                                size: 14,
                                                              ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              model.name,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    isActive
                                                                    ? FontWeight
                                                                          .w700
                                                                    : FontWeight
                                                                          .w600,
                                                                color: isActive
                                                                    ? colorScheme
                                                                          .primary
                                                                    : colorScheme
                                                                          .onSurface,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              model.id,
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: colorScheme
                                                                    .onSurface
                                                                    .withValues(
                                                                      alpha:
                                                                          0.5,
                                                                    ),
                                                              ),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            Wrap(
                                                              spacing: 4,
                                                              runSpacing: 4,
                                                              children: [
                                                                if (model
                                                                    .supportsVision)
                                                                  _capabilityChip(
                                                                    colorScheme,
                                                                    label: '??',
                                                                    icon: Icons
                                                                        .image_outlined,
                                                                    color: Colors
                                                                        .green,
                                                                  ),
                                                                if (model
                                                                    .supportsFunctionCall)
                                                                  _capabilityChip(
                                                                    colorScheme,
                                                                    label: '??',
                                                                    icon: Icons
                                                                        .build_outlined,
                                                                    color: Colors
                                                                        .blue,
                                                                  ),
                                                                if (model
                                                                    .supportsThinking)
                                                                  _capabilityChip(
                                                                    colorScheme,
                                                                    label: '??',
                                                                    icon: Icons
                                                                        .psychology_outlined,
                                                                    color: Colors
                                                                        .deepPurple,
                                                                  ),
                                                                if (model
                                                                        .contextLength !=
                                                                    null)
                                                                  _neutralChip(
                                                                    colorScheme,
                                                                    _formatContextLength(
                                                                      model
                                                                          .contextLength!,
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
            color: widget.colorScheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _overlayController.isShowing ? _closePanel : _openPanel,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _getProviderIcon(activeProvider?.type),
                      if (hasCustomPrompt)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: const BoxDecoration(
                            color: Colors.purple,
                            shape: BoxShape.circle,
                          ),
                        ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          activeModel?.name ?? '未选择模型',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: widget.colorScheme.onSurface.withValues(
                              alpha: 0.86,
                            ),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _overlayController.isShowing
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: widget.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (activeModel != null && activeModel.supportsThinking) ...[
                Container(
                  width: 1,
                  height: 18,
                  color: widget.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                Tooltip(
                  message: '选择模型',
                  child: InkWell(
                    onTap: () => _showModelSettings(context, ref, activeModel),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Icon(
                        Icons.settings_outlined,
                        size: 13,
                        color: widget.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showModelSettings(
    BuildContext context,
    WidgetRef ref,
    AIModelConfig model,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('模型设置面板稍后继续优化')),
    );
  }
}

Widget _capabilityChip(
  ColorScheme colorScheme, {
  required String label,
  required IconData icon,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

Widget _neutralChip(ColorScheme colorScheme, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface.withValues(alpha: 0.65),
      ),
    ),
  );
}

String _formatContextLength(int length) {
  if (length >= 1000000) {
    final value = length / 1000000;
    return value % 1 == 0
        ? '${value.toStringAsFixed(0)}M'
        : '${value.toStringAsFixed(1)}M';
  }
  if (length >= 1000) {
    return '${(length / 1000).round()}K';
  }
  return '$length';
}

class _ContextRing extends ConsumerWidget {
  final ColorScheme colorScheme;

  const _ContextRing({required this.colorScheme});

  double _calculateContextUsage(WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final provider = ref.watch(providerProvider);

    // 获取当前活跃会话的消息
    if (chat.activeSessionId == null) return 0.0;

    final messages = chat.getMessages(chat.activeSessionId!);
    if (messages.isEmpty) return 0.0;

    // 获取当前模型的上下文长度限制
    final activeModel = provider.activeModel;
    final maxTokens = activeModel?.contextLength ?? 4096;

    // 简单估算：每个字符约等于0.75个token（中英文混合）
    double totalChars = 0;
    for (final message in messages) {
      // 处理消息内容
      if (message.content is String) {
        totalChars += (message.content as String).length.toDouble();
      } else if (message.content is List) {
        final blocks = message.content as List;
        for (final block in blocks) {
          if (block is Map && block['type'] == 'text') {
            totalChars += (block['text'] as String? ?? '').length.toDouble();
          } else if (block is Map && block['type'] == 'image') {
            totalChars += 500; // 每张图片约500 tokens
          }
        }
      }
    }

    final estimatedTokens = (totalChars * 0.75).round();
    final percentage = (estimatedTokens / maxTokens * 100).clamp(0.0, 100.0);

    return percentage;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double percentage = _calculateContextUsage(ref);
    final Color strokeColor = percentage > 80
        ? Colors.red
        : percentage > 50
        ? Colors.amber
        : Colors.green;

    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percentage / 100,
            strokeWidth: 2.5,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(strokeColor),
          ),
          Text(
            '${percentage.toInt()}%',
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────── Input Area ────────────

class _InputArea extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final String locale;
  final ColorScheme colorScheme;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final String? providerName;
  final String? modelName;
  final bool webSearchEnabled;
  final VoidCallback onToggleWebSearch;

  const _InputArea({
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    required this.locale,
    required this.colorScheme,
    required this.onSend,
    required this.onStop,
    this.providerName,
    this.modelName,
    required this.webSearchEnabled,
    required this.onToggleWebSearch,
  });

  @override
  ConsumerState<_InputArea> createState() => _InputAreaState();
}

class _InputAreaState extends ConsumerState<_InputArea> {
  final List<ImageAttachment> _attachedImages = [];
  String? _selectedSkill;
  bool _planMode = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {}); // 更新发送按钮状态
    }
  }

  void _togglePlanMode() {
    setState(() {
      _planMode = !_planMode;
    });
  }

  Future<void> _handleImagePaste() async {
    try {
      // 简单的截图粘贴实现 - 模拟从剪切板获取截图
      final imageId = _imageUuid.v4();
      final attachment = ImageAttachment(
        id: imageId,
        dataUrl:
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAGA4fnPAAAAAElFTkSuQmCC', // 1x1 透明像素
        mediaType: 'image/png',
        fileName: 'screenshot.png',
      );

      setState(() {
        _attachedImages.add(attachment);
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('截图已粘贴')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('粘贴截图失败: $e')));
    }
  }

  void _removeImage(String id) {
    setState(() {
      _attachedImages.removeWhere((img) => img.id == id);
    });
  }

  void _clearMessages() {
    final chat = ref.read(chatProvider);
    final sessionId = chat.activeSessionId;
    if (sessionId != null) {
      chat.clearMessages(sessionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final hasAttachments = _attachedImages.isNotEmpty;
    final chat = ref.watch(chatProvider);
    final hasMessages =
        chat.activeSessionId != null &&
        chat.getMessages(chat.activeSessionId!).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 768),
        child: Container(
          decoration: BoxDecoration(
            color: widget.colorScheme.surface,
            borderRadius: BorderRadius.circular(16), // 稍微调大了圆角，更柔和
            border: Border.all(
              color: widget.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.colorScheme.shadow.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 技能标签
              if (_selectedSkill != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.purple.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_fix_high,
                              size: 12,
                              color: Colors.purple,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedSkill!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.purple,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedSkill = null),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),

              // 图片预览
              if (_attachedImages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _attachedImages
                          .map(
                            (img) => Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: widget
                                              .colorScheme
                                              .outlineVariant
                                              .withValues(alpha: 0.6),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.image, size: 24),
                                    ),
                                  ),
                                  Positioned(
                                    right: -6,
                                    top: -6,
                                    child: GestureDetector(
                                      onTap: () => _removeImage(img.id),
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: widget.colorScheme.error,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),

              // 文本输入区域优化：减小最大高度，彻底隐藏滚动条
              Container(
                constraints: const BoxConstraints(
                  minHeight: 32, // 设置合理的最小高度
                  maxHeight: 120, // 减半：将之前的250改为120，让输入框不会霸占太多屏幕空间
                ),
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    6,
                    _selectedSkill != null || _attachedImages.isNotEmpty
                        ? 4
                        : 8,
                    6,
                    4,
                  ),
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (event) {
                      if (event is KeyDownEvent) {
                        // 处理回车发送
                        if (event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          if (widget.controller.text.trim().isNotEmpty) {
                            widget.onSend();
                          }
                        }
                        // 处理 Ctrl+V 粘贴截图
                        else if (event.logicalKey == LogicalKeyboardKey.keyV &&
                            HardwareKeyboard.instance.isControlPressed) {
                          _handleImagePaste();
                        }
                      }
                    },
                    child: ScrollConfiguration(
                      // 使用自定义行为：彻底剥离桌面/Web端的默认滚动条
                      behavior: _NoScrollbarBehavior(),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        maxLines: null, // 允许多行且自适应高度
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.colorScheme.onSurface,
                          height: 1.5, // 优化行高
                        ),
                        decoration: InputDecoration(
                          hintText: '输入消息...',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: widget.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          fillColor: Colors.transparent, // 保持透明
                          filled: true,
                          hoverColor: Colors.transparent, // 避免悬停灰块
                        ),
                        onSubmitted: (_) {
                          if (widget.controller.text.trim().isNotEmpty) {
                            widget.onSend();
                          }
                        },
                        onTapOutside: (_) => widget.focusNode.unfocus(),
                      ),
                    ),
                  ),
                ),
              ),

              // 底部工具栏
              Container(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  4,
                  12,
                  12,
                ), // 调整底部 Padding 让视觉更平衡
                child: Row(
                  children: [
                    // 左侧工具
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 模型选择器 - 更精美的设计
                            _AdvancedModelSwitcher(
                              colorScheme: widget.colorScheme,
                              locale: widget.locale,
                            ),
                            const SizedBox(width: 4),

                            // Web搜索切换
                            _buildToolButton(
                              icon: Icons.language,
                              onPressed: widget.onToggleWebSearch,
                              tooltip: widget.webSearchEnabled
                                  ? '禁用网络搜索'
                                  : '启用网络搜索',
                              isActive: widget.webSearchEnabled,
                              activeColor: Colors.blue,
                            ),

                            // Skills 按钮
                            _buildSkillsButton(),

                            // Plan模式切换
                            _buildToolButton(
                              icon: Icons.assignment_outlined,
                              onPressed: _togglePlanMode,
                              tooltip: _planMode ? '退出Plan模式' : '进入Plan模式',
                              isActive: _planMode,
                              activeColor: Colors.purple,
                              showText: _planMode ? 'Plan' : null,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 右侧操作
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 上下文环形指示器
                        _ContextRing(colorScheme: widget.colorScheme),
                        const SizedBox(width: 8),

                        // Token 计数
                        if (hasText)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: Text(
                              '${widget.controller.text.length ~/ 4} tokens',
                              style: TextStyle(
                                fontSize: 10,
                                color: widget.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),

                        // 清理对话
                        if (hasMessages && !widget.isStreaming)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: _buildToolButton(
                              icon: Icons.delete_outline,
                              onPressed: _clearMessages,
                              tooltip: '清理对话',
                              size: 16,
                            ),
                          ),

                        // 优化提示词
                        if (!widget.isStreaming && hasText)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: _buildToolButton(
                              icon: Icons.auto_fix_high_outlined,
                              onPressed: () {},
                              tooltip: '优化提示词',
                              size: 16,
                            ),
                          ),

                        // 发送/停止按钮
                        if (widget.isStreaming)
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: widget.onStop,
                                borderRadius: BorderRadius.circular(8),
                                child: const Icon(
                                  Icons.stop_circle_outlined,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: (hasText || hasAttachments)
                                  ? widget.colorScheme.primary
                                  : widget.colorScheme.onSurface.withValues(
                                      alpha: 0.1,
                                    ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: (hasText || hasAttachments)
                                    ? widget.onSend
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                                child: Icon(
                                  Icons.arrow_upward_rounded, // 换成了更现代的向上箭头图标
                                  size: 20,
                                  color: (hasText || hasAttachments)
                                      ? widget.colorScheme.onPrimary
                                      : widget.colorScheme.onSurface.withValues(
                                          alpha: 0.4,
                                        ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    bool isActive = false,
    Color? activeColor,
    double size = 18, // 稍微调大了工具栏图标
    String? showText,
  }) {
    final color = isActive
        ? (activeColor ?? widget.colorScheme.primary)
        : widget.colorScheme.onSurface.withValues(alpha: 0.6);
    final bgColor = isActive
        ? (activeColor ?? widget.colorScheme.primary).withValues(alpha: 0.1)
        : Colors.transparent;

    return Tooltip(
      message: tooltip,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: showText != null ? 8 : 8,
                vertical: 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: size, color: color),
                  if (showText != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      showText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkillsButton() {
    return Tooltip(
      message: 'Skills',
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: _selectedSkill != null
              ? Colors.purple.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // 简单的技能选择
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('选择 Skill'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('代码优化'),
                        onTap: () {
                          setState(() => _selectedSkill = '代码优化');
                          Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        title: const Text('文档生成'),
                        onTap: () {
                          setState(() => _selectedSkill = '文档生成');
                          Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        title: const Text('问题分析'),
                        onTap: () {
                          setState(() => _selectedSkill = '问题分析');
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Icon(
                Icons.add,
                size: 18,
                color: _selectedSkill != null
                    ? Colors.purple
                    : widget.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
