import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/core/l10n/translations.dart';

class ChatHomePage extends ConsumerWidget {
  const ChatHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(settingsProvider).settings.language;
    final colorScheme = Theme.of(context).colorScheme;
    final provNotifier = ref.watch(providerProvider);
    // Check if there's at least one enabled provider with models
    final hasProvider = provNotifier.providers.any(
      (p) => p.enabled && p.models.isNotEmpty,
    );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/logo.png', width: 64, height: 64),
          const SizedBox(height: 16),
          Text('Pantheon Forge',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600,
              color: colorScheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(t('about.description', locale),
            style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 24),
          if (!hasProvider) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, size: 16, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Text(t('provider.noProviders.desc', locale),
                    style: TextStyle(fontSize: 12, color: colorScheme.error),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => ref.read(uiProvider.notifier).openSettings(tab: SettingsTab.provider),
              icon: const Icon(Icons.add, size: 16),
              label: Text(t('provider.add', locale), style: const TextStyle(fontSize: 13)),
            ),
          ] else
            FilledButton.icon(
              onPressed: () {
                // Auto-activate first available provider if none is active
                if (provNotifier.activeProvider == null) {
                  final firstProvider = provNotifier.providers.firstWhere(
                    (p) => p.enabled && p.models.isNotEmpty,
                  );
                  ref.read(providerProvider.notifier).setActive(
                    firstProvider.id, firstProvider.models.first.id,
                  );
                }
                final sessionId = ref.read(chatProvider).createSession(
                  mode: 'agent',
                );
                ref.read(chatProvider).setActiveSession(sessionId);
                ref.read(uiProvider.notifier).navigateToSession();
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: Text(t('chat.newChat', locale), style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
