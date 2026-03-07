import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pantheon_forge/core/storage/storage_manager.dart';
import 'package:pantheon_forge/core/database/database.dart';
import 'package:pantheon_forge/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1100, 700),
    minimumSize: Size(800, 500),
    center: true,
    backgroundColor: Color(0xFFF8FAFC),
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    title: 'Pantheon Forge',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Initialize storage (data on exe's drive, not C:)
  await StorageManager.instance.initialize();

  // Initialize SQLite database
  AppDatabase.instance.initialize();

  runApp(
    const ProviderScope(
      child: PantheonForgeApp(),
    ),
  );
}
