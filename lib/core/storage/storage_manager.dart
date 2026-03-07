import 'dart:io';
import 'package:path/path.dart' as p;

/// Manages the application data directory.
///
/// Data is stored on the same drive as the executable, NOT on C:.
/// Default location: `<exe_drive>:\.pantheon_forge\`
class StorageManager {
  StorageManager._();
  static StorageManager? _instance;
  static StorageManager get instance => _instance ??= StorageManager._();

  late final String _dataDir;
  bool _initialized = false;

  String get dataDir => _dataDir;
  String get dbPath => p.join(_dataDir, 'data.db');
  String get settingsPath => p.join(_dataDir, 'settings.json');
  String get configPath => p.join(_dataDir, 'config.json');
  String get agentsDir => p.join(_dataDir, 'agents');
  String get skillsDir => p.join(_dataDir, 'skills');

  Future<void> initialize() async {
    if (_initialized) return;

    // Store data in project root directory, relative to executable
    final exePath = Platform.resolvedExecutable;
    final exeDir = p.dirname(exePath);
    
    // Navigate up from build/windows/x64/runner/Debug to project root
    // In production: build/windows/runner -> project root
    // In debug: build/windows/x64/runner/Debug -> project root
    var projectRoot = exeDir;
    if (exeDir.contains('build${p.separator}windows')) {
      // Go up to project root
      projectRoot = p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(exeDir)))));
    }
    
    _dataDir = p.join(projectRoot, '.pantheon_forge');

    // Ensure directory exists
    final dir = Directory(_dataDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Ensure subdirectories
    for (final sub in [agentsDir, skillsDir]) {
      final subDir = Directory(sub);
      if (!subDir.existsSync()) {
        subDir.createSync(recursive: true);
      }
    }

    _initialized = true;
  }
}
