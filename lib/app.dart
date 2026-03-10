import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pantheon_forge/core/theme/app_theme.dart';
import 'package:pantheon_forge/providers/app_providers.dart';
import 'package:pantheon_forge/ui/layout/main_layout.dart';

class PantheonForgeApp extends ConsumerWidget {
  const PantheonForgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 优化：只监听主题设置
    final theme = ref.watch(settingsProvider.select((s) => s.settings.theme));

    final themeMode = switch (theme) {
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
      // 添加性能优化配置
      builder: (context, child) {
        return MediaQuery(
          // 禁用文本缩放，提高性能
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          child: child!,
        );
      },
    );
  }
}
