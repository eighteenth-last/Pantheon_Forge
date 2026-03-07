import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/core/theme/app_theme.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/ui/layout/main_layout.dart';

class PantheonForgeApp extends ConsumerWidget {
  const PantheonForgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).settings;

    final themeMode = switch (settings.theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp(
      title: 'Pantheon Forge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const MainLayout(),
    );
  }
}
