import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';
import 'package:pantheon_forge/models/models.dart';
import 'package:pantheon_forge/core/storage/storage_manager.dart';
import 'package:pantheon_forge/ui/settings/provider_panel.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiProvider);
    final settings = ref.watch(settingsProvider).settings;
    final locale = settings.language;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: () => ref.read(uiProvider.notifier).closeSettings(),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Text(t('settings.title', locale),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
            ],
          ),
        ),

        // Tab bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              for (final tab in SettingsTab.values)
                _TabButton(
                  label: t('settings.${tab.name}', locale),
                  isActive: ui.settingsTab == tab,
                  onTap: () => ref.read(uiProvider.notifier).setSettingsTab(tab),
                  colorScheme: colorScheme,
                ),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: switch (ui.settingsTab) {
            SettingsTab.general => _GeneralTab(settings: settings, locale: locale, ref: ref),
            SettingsTab.provider => const ProviderPanel(),
            SettingsTab.about => _AboutTab(locale: locale, colorScheme: colorScheme),
          },
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _TabButton({required this.label, required this.isActive,
    required this.onTap, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: isActive ? colorScheme.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(label, style: TextStyle(fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
        ),
      ),
    );
  }
}

// ──────────── General Tab ────────────

class _GeneralTab extends StatelessWidget {
  final AppSettings settings;
  final String locale;
  final WidgetRef ref;

  const _GeneralTab({required this.settings, required this.locale, required this.ref});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Theme
          _SettingRow(
            label: t('settings.theme', locale),
            colorScheme: colorScheme,
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'system', label: Text(t('settings.theme.system', locale), style: const TextStyle(fontSize: 11))),
                ButtonSegment(value: 'light', label: Text(t('settings.theme.light', locale), style: const TextStyle(fontSize: 11))),
                ButtonSegment(value: 'dark', label: Text(t('settings.theme.dark', locale), style: const TextStyle(fontSize: 11))),
              ],
              selected: {settings.theme},
              onSelectionChanged: (v) => ref.read(settingsProvider.notifier)
                  .update((s) => s.copyWith(theme: v.first)),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Language
          _SettingRow(
            label: t('settings.language', locale),
            colorScheme: colorScheme,
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'zh', label: Text(t('settings.language.zh', locale), style: const TextStyle(fontSize: 11))),
                ButtonSegment(value: 'en', label: Text(t('settings.language.en', locale), style: const TextStyle(fontSize: 11))),
              ],
              selected: {settings.language},
              onSelectionChanged: (v) => ref.read(settingsProvider.notifier)
                  .update((s) => s.copyWith(language: v.first)),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Max Tokens
          _SettingRow(
            label: t('settings.maxTokens', locale),
            colorScheme: colorScheme,
            child: SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Slider(
                    value: settings.maxTokens.toDouble(),
                    min: 1000, max: 128000, divisions: 127,
                    onChanged: (v) => ref.read(settingsProvider.notifier)
                        .update((s) => s.copyWith(maxTokens: v.round())),
                  ),
                  Text('${settings.maxTokens}',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Temperature
          _SettingRow(
            label: t('settings.temperature', locale),
            colorScheme: colorScheme,
            child: SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Slider(
                    value: settings.temperature,
                    min: 0, max: 2, divisions: 20,
                    onChanged: (v) => ref.read(settingsProvider.notifier)
                        .update((s) => s.copyWith(temperature: double.parse(v.toStringAsFixed(1)))),
                  ),
                  Text(settings.temperature.toStringAsFixed(1),
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // System Prompt
          Text(t('settings.systemPrompt', locale),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorScheme.onSurface)),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: settings.systemPrompt),
            maxLines: 4,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'You are a helpful assistant...',
              hintStyle: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.3)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (v) => ref.read(settingsProvider.notifier)
                .update((s) => s.copyWith(systemPrompt: v)),
          ),
          const SizedBox(height: 16),

          // Auto-approve
          SwitchListTile.adaptive(
            value: settings.autoApprove,
            onChanged: (v) => ref.read(settingsProvider.notifier)
                .update((s) => s.copyWith(autoApprove: v)),
            title: Text(t('settings.autoApprove', locale),
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),

          // Thinking
          SwitchListTile.adaptive(
            value: settings.thinkingEnabled,
            onChanged: (v) => ref.read(settingsProvider.notifier)
                .update((s) => s.copyWith(thinkingEnabled: v)),
            title: Text(t('settings.thinking', locale),
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;
  final ColorScheme colorScheme;

  const _SettingRow({required this.label, required this.child, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
          color: colorScheme.onSurface)),
        child,
      ],
    );
  }
}

// ──────────── About Tab ────────────

class _AboutTab extends StatelessWidget {
  final String locale;
  final ColorScheme colorScheme;

  const _AboutTab({required this.locale, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/logo.png', width: 48, height: 48,
                errorBuilder: (_, __, ___) => Icon(Icons.auto_awesome, size: 48, color: colorScheme.primary)),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pantheon Forge',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(t('about.description', locale),
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          _InfoRow(label: t('about.version', locale), value: '0.1.0', colorScheme: colorScheme),
          const SizedBox(height: 8),
          _InfoRow(label: t('about.dataDir', locale),
            value: StorageManager.instance.dataDir, colorScheme: colorScheme),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _InfoRow({required this.label, required this.value, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: TextStyle(fontSize: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.5))),
        ),
        Expanded(
          child: SelectableText(value, style: TextStyle(fontSize: 12,
            color: colorScheme.onSurface)),
        ),
      ],
    );
  }
}
