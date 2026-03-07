import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/agent/chat_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import 'dart:convert';

const _imageUuid = Uuid();

final _chatService = ChatService();

class ChatViewPage extends ConsumerStatefulWidget {
  const ChatViewPage({super.key});

  @override
  ConsumerState<ChatViewPage> createState() => _ChatViewPageState();
}

class _ChatViewPageState extends ConsumerState<ChatViewPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final settings = ref.watch(settingsProvider).settings;
    final ui = ref.watch(uiProvider);
    final locale = settings.language;
    final colorScheme = Theme.of(context).colorScheme;
    final sessionId = chat.activeSessionId;
    final messages = sessionId != null ? chat.getMessages(sessionId) : <UnifiedMessage>[];

    // Auto-scroll when streaming
    if (chat.isStreaming) _scrollToBottom();

    return Column(
      children: [
        // Message list
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 40,
                        color: colorScheme.onSurface.withValues(alpha: 0.15)),
                      const SizedBox(height: 8),
                      Text(t('chat.noMessages', locale),
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.4))),
                      const SizedBox(height: 3),
                      Text(t('chat.noMessages.desc', locale),
                        style: TextStyle(fontSize: 10, color: colorScheme.onSurface.withValues(alpha: 0.25))),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: messages[index], locale: locale, colorScheme: colorScheme),
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

  const _MessageBubble({required this.message, required this.locale, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.system) return const SizedBox.shrink();

    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(Icons.smart_toy_outlined, size: 16, color: colorScheme.primary),
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
                    SelectableText(message.textContent,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurface))
                  else
                    MarkdownBody(
                      data: message.textContent,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(fontSize: 12, color: colorScheme.onSurface, height: 1.4),
                        code: TextStyle(
                          fontSize: 11, fontFamily: 'Consolas',
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          color: colorScheme.onSurface,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  if (message.usage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${message.usage!.inputTokens} in / ${message.usage!.outputTokens} out',
                        style: TextStyle(fontSize: 9, color: colorScheme.onSurface.withValues(alpha: 0.3)),
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

class _AdvancedModelSwitcher extends ConsumerWidget {
  final ColorScheme colorScheme;
  final String locale;
  
  const _AdvancedModelSwitcher({required this.colorScheme, required this.locale});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(providerProvider);
    final activeProvider = provider.activeProvider;
    final activeModel = provider.activeModel;
    final hasCustomPrompt = ref.watch(settingsProvider).settings.systemPrompt.isNotEmpty;
    
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.transparent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 主模型选择器
          InkWell(
            onTap: () => _showModelPicker(context, ref),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 模型图标 - 可以根据不同提供商显示不同图标
                  _getProviderIcon(activeProvider?.type),
                  if (hasCustomPrompt)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: const BoxDecoration(
                        color: Colors.purple,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      activeModel?.name ?? '无模型',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
          
          // 模型设置按钮（如果支持思维模式等）
          if (activeModel?.supportsThinking == true)
            Container(
              width: 1,
              height: 20,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
          if (activeModel?.supportsThinking == true)
            Tooltip(
              message: '模型设置',
              child: InkWell(
                onTap: () => _showModelSettings(context, ref, activeModel!),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(
                    Icons.settings,
                    size: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _getProviderIcon(ProviderType? type) {
    switch (type) {
      case ProviderType.anthropic:
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Icon(Icons.psychology, size: 12, color: Colors.orange),
        );
      case ProviderType.openai:
      default:
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Icon(Icons.smart_toy, size: 12, color: Colors.green),
        );
    }
  }
  
  void _showModelPicker(BuildContext context, WidgetRef ref) {
    final provider = ref.read(providerProvider);
    final allModels = <MapEntry<AIProvider, AIModelConfig>>[];
    
    // 收集所有可用模型
    for (final prov in provider.providers) {
      if (prov.enabled) {
        for (final model in prov.models) {
          if (model.enabled) {
            allModels.add(MapEntry(prov, model));
          }
        }
      }
    }
    
    if (allModels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的模型，请先添加提供商')),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.psychology, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('选择模型', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: allModels.length,
            itemBuilder: (context, index) {
              final entry = allModels[index];
              final prov = entry.key;
              final model = entry.value;
              final isActive = provider.activeProviderId == prov.id && 
                             provider.activeModelId == model.id;
              
              return ListTile(
                leading: _getProviderIcon(prov.type),
                title: Text(
                  model.name,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  prov.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (model.supportsVision)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text('视觉', style: TextStyle(fontSize: 8, color: Colors.green)),
                      ),
                    if (model.supportsFunctionCall)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text('工具', style: TextStyle(fontSize: 8, color: Colors.blue)),
                      ),
                    if (isActive) const Icon(Icons.check, color: Colors.green, size: 16),
                  ],
                ),
                onTap: () {
                  ref.read(providerProvider.notifier).setActive(prov.id, model.id);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
  
  void _showModelSettings(BuildContext context, WidgetRef ref, AIModelConfig model) {
    // TODO: 实现模型设置对话框（思维模式等）
  }
}

// ──────────── Context Ring ────────────

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

  const _InputArea({
    required this.controller, required this.focusNode,
    required this.isStreaming, required this.locale,
    required this.colorScheme, required this.onSend,
    required this.onStop, this.providerName, this.modelName,
  });

  @override
  ConsumerState<_InputArea> createState() => _InputAreaState();
}

class _InputAreaState extends ConsumerState<_InputArea> {
  final List<ImageAttachment> _attachedImages = [];
  bool _webSearchEnabled = false;
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
  
  void _toggleWebSearch() {
    setState(() {
      _webSearchEnabled = !_webSearchEnabled;
    });
  }
  
  void _togglePlanMode() {
    setState(() {
      _planMode = !_planMode;
    });
  }
  
  Future<void> _handleImagePaste() async {
    try {
      // 简单的截图粘贴实现 - 模拟从剪切板获取截图
      // 在真实应用中，这里应该使用原生插件来获取剪切板中的图片数据
      final imageId = _imageUuid.v4();
      final attachment = ImageAttachment(
        id: imageId,
        dataUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAGA4fnPAAAAAElFTkSuQmCC', // 1x1 透明像素
        mediaType: 'image/png',
        fileName: 'screenshot.png',
      );
      
      setState(() {
        _attachedImages.add(attachment);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('截图已粘贴')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('粘贴截图失败: $e')),
      );
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
    final hasMessages = chat.activeSessionId != null && 
        chat.getMessages(chat.activeSessionId!).isNotEmpty;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 768),
        child: Container(
          decoration: BoxDecoration(
            color: widget.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 12,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                            Icon(Icons.auto_fix_high, size: 12, color: Colors.purple),
                            const SizedBox(width: 4),
                            Text(
                              _selectedSkill!,
                              style: const TextStyle(fontSize: 11, color: Colors.purple),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => setState(() => _selectedSkill = null),
                              child: const Icon(Icons.close, size: 12, color: Colors.purple),
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
                      children: _attachedImages.map((img) => Container(
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
                                    color: widget.colorScheme.outlineVariant.withValues(alpha: 0.6),
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
                                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ),
              
              // 文本输入区域
              Container(
                height: 100,
                padding: EdgeInsets.fromLTRB(
                  12,
                  _selectedSkill != null || _attachedImages.isNotEmpty ? 6 : 12,
                  12,
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
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    maxLines: null,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.colorScheme.onSurface,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: t('agent.placeholder', widget.locale),
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: widget.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
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
              
              // 底部工具栏
              Container(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                            _AdvancedModelSwitcher(colorScheme: widget.colorScheme, locale: widget.locale),
                            const SizedBox(width: 1),
                            
                            // Web搜索切换
                            _buildToolButton(
                              icon: Icons.language,
                              onPressed: _toggleWebSearch,
                              tooltip: _webSearchEnabled ? '禁用网络搜索' : '启用网络搜索',
                              isActive: _webSearchEnabled,
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
                                color: widget.colorScheme.onSurface.withValues(alpha: 0.5),
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
                              size: 14,
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
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: (hasText || hasAttachments) 
                                  ? widget.colorScheme.primary
                                  : widget.colorScheme.onSurface.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: (hasText || hasAttachments) ? widget.onSend : null,
                                borderRadius: BorderRadius.circular(8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t('action.start', widget.locale),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: (hasText || hasAttachments)
                                            ? widget.colorScheme.onPrimary
                                            : widget.colorScheme.onSurface.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.send,
                                      size: 14,
                                      color: (hasText || hasAttachments)
                                          ? widget.colorScheme.onPrimary
                                          : widget.colorScheme.onSurface.withValues(alpha: 0.4),
                                    ),
                                  ],
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
    double size = 16,
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
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
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
                size: 16,
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
