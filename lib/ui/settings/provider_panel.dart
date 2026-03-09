import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/services/api/model_fetcher.dart';
import 'package:pantheon_forge/ui/common/app_message.dart';

const _uuid = Uuid();

class ProviderPanel extends ConsumerStatefulWidget {
  const ProviderPanel({super.key});

  @override
  ConsumerState<ProviderPanel> createState() => _ProviderPanelState();
}

class _ProviderPanelState extends ConsumerState<ProviderPanel> {
  String? _editingProviderId;
  bool _isFetching = false;

  @override
  Widget build(BuildContext context) {
    final prov = ref.watch(providerProvider);
    final settings = ref.watch(settingsProvider).settings;
    final locale = settings.language;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Action bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                t('provider.title', locale),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () =>
                    _showAddProviderDialog(context, locale, colorScheme),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  t('provider.add', locale),
                  style: const TextStyle(fontSize: 11),
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Provider list
        Expanded(
          child: prov.providers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.electrical_services_outlined,
                        size: 36,
                        color: colorScheme.onSurface.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('provider.noProviders', locale),
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t('provider.noProviders.desc', locale),
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.25),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: prov.providers.length,
                  itemBuilder: (ctx, i) => _ProviderCard(
                    provider: prov.providers[i],
                    isActive: prov.activeProviderId == prov.providers[i].id,
                    activeModelId: prov.activeModelId,
                    locale: locale,
                    colorScheme: colorScheme,
                    isExpanded: _editingProviderId == prov.providers[i].id,
                    onToggle: () => setState(() {
                      _editingProviderId =
                          _editingProviderId == prov.providers[i].id
                          ? null
                          : prov.providers[i].id;
                    }),
                    onDelete: () => _confirmDelete(
                      context,
                      prov.providers[i],
                      locale,
                      colorScheme,
                    ),
                    onEdit: () => _showEditProviderDialog(
                      context,
                      prov.providers[i],
                      locale,
                      colorScheme,
                    ),
                    onSetActive: (modelId) => ref
                        .read(providerProvider.notifier)
                        .setActive(prov.providers[i].id, modelId),
                    onAddModel: () => _showAddModelDialog(
                      context,
                      prov.providers[i],
                      locale,
                      colorScheme,
                    ),
                    onAutoFetchModels: () => _autoFetchModels(
                      prov.providers[i],
                      locale,
                      colorScheme,
                    ),
                    onDeleteModel: (modelId) =>
                        _deleteModel(prov.providers[i], modelId),
                    isFetching: _isFetching,
                    onToggleEnabled: (enabled) {
                      ref
                          .read(providerProvider.notifier)
                          .updateProvider(
                            prov.providers[i].copyWith(enabled: enabled),
                          );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _showAddProviderDialog(
    BuildContext context,
    String locale,
    ColorScheme colorScheme,
  ) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    var type = ProviderType.openai;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            t('provider.add', locale),
            style: const TextStyle(fontSize: 16),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(
                  label: t('provider.name', locale),
                  controller: nameCtrl,
                  hint: 'My Provider',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      t('provider.type', locale),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<ProviderType>(
                        value: type,
                        isExpanded: true,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface,
                        ),
                        items: ProviderType.values
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t.value,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setDialogState(() => type = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _DialogField(
                  label: t('provider.baseUrl', locale),
                  controller: urlCtrl,
                  hint: 'https://api.example.com/v1',
                ),
                const SizedBox(height: 12),
                _DialogField(
                  label: t('provider.apiKey', locale),
                  controller: keyCtrl,
                  hint: 'sk-...',
                  obscure: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('common.cancel', locale)),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                final provider = AIProvider(
                  id: _uuid.v4(),
                  name: nameCtrl.text.trim(),
                  type: type,
                  baseUrl: urlCtrl.text.trim(),
                  apiKey: keyCtrl.text.trim(),
                  enabled: true,
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                );
                ref.read(providerProvider.notifier).addProvider(provider);
                Navigator.pop(ctx);
              },
              child: Text(t('common.save', locale)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProviderDialog(
    BuildContext context,
    AIProvider provider,
    String locale,
    ColorScheme colorScheme,
  ) {
    final nameCtrl = TextEditingController(text: provider.name);
    final urlCtrl = TextEditingController(text: provider.baseUrl);
    final keyCtrl = TextEditingController(text: provider.apiKey);
    var type = provider.type;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            t('provider.edit', locale),
            style: const TextStyle(fontSize: 16),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(
                  label: t('provider.name', locale),
                  controller: nameCtrl,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      t('provider.type', locale),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<ProviderType>(
                        value: type,
                        isExpanded: true,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface,
                        ),
                        items: ProviderType.values
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t.value,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setDialogState(() => type = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _DialogField(
                  label: t('provider.baseUrl', locale),
                  controller: urlCtrl,
                ),
                const SizedBox(height: 12),
                _DialogField(
                  label: t('provider.apiKey', locale),
                  controller: keyCtrl,
                  obscure: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('common.cancel', locale)),
            ),
            FilledButton(
              onPressed: () {
                ref
                    .read(providerProvider.notifier)
                    .updateProvider(
                      provider.copyWith(
                        name: nameCtrl.text.trim(),
                        type: type,
                        baseUrl: urlCtrl.text.trim(),
                        apiKey: keyCtrl.text.trim(),
                      ),
                    );
                Navigator.pop(ctx);
              },
              child: Text(t('common.save', locale)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddModelDialog(
    BuildContext context,
    AIProvider provider,
    String locale,
    ColorScheme colorScheme,
  ) {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          t('provider.addModel', locale),
          style: const TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(
                label: t('provider.modelId', locale),
                controller: idCtrl,
                hint: 'gpt-4o, claude-3-5-sonnet...',
              ),
              const SizedBox(height: 12),
              _DialogField(
                label: t('provider.modelName', locale),
                controller: nameCtrl,
                hint: 'GPT-4o',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('common.cancel', locale)),
          ),
          FilledButton(
            onPressed: () {
              if (idCtrl.text.trim().isEmpty) return;
              final model = AIModelConfig(
                id: idCtrl.text.trim(),
                name: nameCtrl.text.trim().isEmpty
                    ? idCtrl.text.trim()
                    : nameCtrl.text.trim(),
              );
              ref
                  .read(providerProvider.notifier)
                  .updateProvider(
                    provider.copyWith(models: [...provider.models, model]),
                  );
              Navigator.pop(ctx);
            },
            child: Text(t('common.save', locale)),
          ),
        ],
      ),
    );
  }

  void _deleteModel(AIProvider provider, String modelId) {
    ref
        .read(providerProvider.notifier)
        .updateProvider(
          provider.copyWith(
            models: provider.models.where((m) => m.id != modelId).toList(),
          ),
        );
  }

  Future<void> _autoFetchModels(
    AIProvider provider,
    String locale,
    ColorScheme colorScheme,
  ) async {
    if (_isFetching) return;
    if (provider.baseUrl.isEmpty || provider.apiKey.isEmpty) {
      AppMessage.info(context, '请先配置 Base URL 和 API Key');
      return;
    }

    setState(() => _isFetching = true);

    final result = await ModelFetcherService.fetchModels(
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      providerType: provider.type,
    );

    setState(() => _isFetching = false);

    if (!mounted) return;

    if (result.error != null) {
      AppMessage.error(
        context,
        '${t('provider.fetchError', locale)}: ${result.error}',
      );
      return;
    }

    if (result.models.isEmpty) {
      AppMessage.info(context, '未找到可用的聊天模型');
      return;
    }

    // Add fetched models, avoiding duplicates
    final existingIds = provider.models.map((m) => m.id).toSet();
    final newModels = result.models
        .where((m) => !existingIds.contains(m.id))
        .toList();

    ref
        .read(providerProvider.notifier)
        .updateProvider(
          provider.copyWith(models: [...provider.models, ...newModels]),
        );

    final msg = t(
      'provider.fetchSuccess',
      locale,
    ).replaceAll('{count}', '${newModels.length}');
    AppMessage.success(context, msg);
  }

  void _confirmDelete(
    BuildContext context,
    AIProvider provider,
    String locale,
    ColorScheme colorScheme,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          t('provider.delete', locale),
          style: const TextStyle(fontSize: 16),
        ),
        content: Text(
          '${provider.name}?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('common.cancel', locale)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () {
              ref.read(providerProvider.notifier).removeProvider(provider.id);
              Navigator.pop(ctx);
            },
            child: Text(t('common.delete', locale)),
          ),
        ],
      ),
    );
  }
}

// ──────────── Provider Card ────────────

class _ProviderCard extends StatelessWidget {
  final AIProvider provider;
  final bool isActive;
  final String activeModelId;
  final String locale;
  final ColorScheme colorScheme;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final void Function(String modelId) onSetActive;
  final VoidCallback onAddModel;
  final VoidCallback onAutoFetchModels;
  final void Function(String modelId) onDeleteModel;
  final void Function(bool) onToggleEnabled;
  final bool isFetching;

  const _ProviderCard({
    required this.provider,
    required this.isActive,
    required this.activeModelId,
    required this.locale,
    required this.colorScheme,
    required this.isExpanded,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
    required this.onSetActive,
    required this.onAddModel,
    required this.onAutoFetchModels,
    required this.onDeleteModel,
    required this.onToggleEnabled,
    required this.isFetching,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      color: isActive
          ? colorScheme.primary.withValues(alpha: 0.04)
          : colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Header
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.electrical_services,
                    size: 18,
                    color: provider.enabled
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              provider.name,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  t('provider.active', locale),
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          '${provider.type.value} · ${provider.models.length} models',
                          style: TextStyle(
                            fontSize: 9,
                            color: colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Auto-fetch button (always visible)
                  IconButton(
                    onPressed: isFetching ? null : onAutoFetchModels,
                    icon: isFetching
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : Icon(Icons.sync, size: 16),
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    tooltip: t('provider.autoFetch', locale),
                    color: colorScheme.primary,
                  ),
                  Switch.adaptive(
                    value: provider.enabled,
                    onChanged: onToggleEnabled,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // Expanded details
          if (isExpanded) ...[
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Base URL
                  if (provider.baseUrl.isNotEmpty)
                    _DetailRow(
                      label: 'URL',
                      value: provider.baseUrl,
                      colorScheme: colorScheme,
                    ),
                  _DetailRow(
                    label: 'API Key',
                    value: provider.apiKey.isNotEmpty
                        ? '${provider.apiKey.substring(0, (provider.apiKey.length > 8 ? 8 : provider.apiKey.length))}...'
                        : '(not set)',
                    colorScheme: colorScheme,
                  ),

                  const SizedBox(height: 8),
                  // Models
                  Row(
                    children: [
                      Text(
                        t('provider.models', locale),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: isFetching ? null : onAutoFetchModels,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isFetching)
                                SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.sync,
                                  size: 12,
                                  color: colorScheme.primary,
                                ),
                              const SizedBox(width: 3),
                              Text(
                                isFetching
                                    ? t('provider.fetching', locale)
                                    : t('provider.autoFetch', locale),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.primary.withValues(
                                    alpha: isFetching ? 0.5 : 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onAddModel,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add,
                                size: 12,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                t('provider.addModel', locale),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final model in provider.models)
                    _ModelTile(
                      model: model,
                      isActive: isActive && activeModelId == model.id,
                      colorScheme: colorScheme,
                      locale: locale,
                      onSetActive: () => onSetActive(model.id),
                      onDelete: () => onDeleteModel(model.id),
                    ),

                  // Actions
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 14),
                        label: Text(
                          t('provider.edit', locale),
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: colorScheme.error,
                        ),
                        label: Text(
                          t('provider.delete', locale),
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.error,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final AIModelConfig model;
  final bool isActive;
  final ColorScheme colorScheme;
  final String locale;
  final VoidCallback onSetActive;
  final VoidCallback onDelete;

  const _ModelTile({
    required this.model,
    required this.isActive,
    required this.colorScheme,
    required this.locale,
    required this.onSetActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 14,
            color: isActive
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  model.id,
                  style: TextStyle(
                    fontSize: 9,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          if (!isActive)
            InkWell(
              onTap: onSetActive,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  t('provider.setActive', locale),
                  style: TextStyle(fontSize: 9, color: colorScheme.primary),
                ),
              ),
            ),
          if (isActive)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.check_circle,
                size: 14,
                color: colorScheme.primary,
              ),
            ),
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 12,
                color: colorScheme.error.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;

  const _DialogField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }
}
