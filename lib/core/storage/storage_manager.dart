import 'dart:io';
import 'package:path/path.dart' as p;

/// Manages the application data directory.
///
/// Data is stored in the application directory under Memory folder.
/// Location: `<app_dir>/Memory/`
/// This ensures data is NOT on C: drive root or disk root directory.
class StorageManager {
  StorageManager._();
  static StorageManager? _instance;
  static StorageManager get instance => _instance ??= StorageManager._();

  late final String _appDir;
  late final String _dataDir;
  bool _initialized = false;

  String get appDir => _appDir;
  String get dataDir => _dataDir;
  String get dbPath => p.join(_dataDir, 'data.db');
  String get settingsPath => p.join(_dataDir, 'settings.json');
  String get configPath => p.join(_dataDir, 'config.json');
  String get agentsDir => p.join(_dataDir, 'agents');
  String get skillsDir => p.join(_dataDir, 'skills');
  String get memoryDir => p.join(_dataDir, 'memory');

  Future<void> initialize() async {
    if (_initialized) return;

    // Get executable directory
    final exePath = Platform.resolvedExecutable;
    var appDir = p.dirname(exePath);
    
    // In debug mode, navigate up from build/windows/x64/runner/Debug to project root
    if (appDir.contains('build${p.separator}windows')) {
      // Go up to project root (pantheon_forge folder)
      appDir = p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(appDir)))));
    }
    
    _appDir = appDir;
    
    // Store data in Memory folder under application directory
    // This ensures data is NOT on C: drive root or disk root
    _dataDir = p.join(appDir, 'Memory');

    // Ensure directory exists
    final dir = Directory(_dataDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Ensure subdirectories
    for (final sub in [agentsDir, skillsDir, memoryDir]) {
      final subDir = Directory(sub);
      if (!subDir.existsSync()) {
        subDir.createSync(recursive: true);
      }
    }

    _initialized = true;
  }
  
  /// Get memory file path for a session
  String getMemoryPath(String sessionId) => p.join(memoryDir, '$sessionId.json');
  
  /// List all memory files
  List<String> listMemoryFiles() {
    final dir = Directory(memoryDir);
    if (!dir.existsSync()) return [];
    return dir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => p.basenameWithoutExtension(f.path))
        .toList();
  }
}
