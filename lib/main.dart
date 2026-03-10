import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pantheon_forge/core/storage/storage_manager.dart';
import 'package:pantheon_forge/core/database/database.dart';
import 'package:pantheon_forge/core/performance/performance_config.dart';
import 'package:pantheon_forge/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 性能优化：启用硬件加速和缓存
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  // 禁用不必要的系统 UI 叠加层
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  
  // 初始化性能配置
  PerformanceConfig.instance.initialize();
  
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

  // Initialize storage (data on exe's drive, not C:) - 异步初始化，不阻塞 UI
  StorageManager.instance.initialize().then((_) {
    // Initialize SQLite database after storage is ready
    AppDatabase.instance.initialize();
  }).catchError((error) {
    debugPrint('Storage initialization error: $error');
  });

  runApp(
    const ProviderScope(
      child: PantheonForgeApp(),
    ),
  );
}
