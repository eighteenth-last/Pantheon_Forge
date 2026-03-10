import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 性能优化配置类
class PerformanceConfig {
  PerformanceConfig._();

  static final PerformanceConfig instance = PerformanceConfig._();

  /// 初始化性能优化配置
  void initialize() {
    // 启用性能叠加层（仅在调试模式）
    if (kDebugMode) {
      // 使用节流减少 FPS 监控的性能开销
      int frameCount = 0;
      SchedulerBinding.instance.addTimingsCallback((timings) {
        frameCount++;
        // 每 60 帧才检查一次，减少性能开销
        if (frameCount % 60 == 0) {
          for (final timing in timings) {
            final fps = 1000000 / timing.totalSpan.inMicroseconds;
            if (fps < 55) {
              debugPrint('⚠️ 性能警告: FPS = ${fps.toStringAsFixed(1)}');
            }
          }
        }
      });
    }

    // 设置默认的过渡动画时长
    _configureAnimations();
  }

  void _configureAnimations() {
    // 可以根据设备性能调整动画时长
    // 这里使用默认值，如果需要可以动态调整
  }

  /// 防抖函数 - 用于减少频繁的操作
  static void Function() debounce(
    void Function() action, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    DateTime? lastActionTime;
    return () {
      final now = DateTime.now();
      if (lastActionTime == null ||
          now.difference(lastActionTime!) > delay) {
        lastActionTime = now;
        action();
      }
    };
  }

  /// 节流函数 - 确保操作在指定时间内只执行一次
  static void Function() throttle(
    void Function() action, {
    Duration duration = const Duration(milliseconds: 300),
  }) {
    bool isThrottled = false;
    return () {
      if (!isThrottled) {
        isThrottled = true;
        action();
        Future.delayed(duration, () {
          isThrottled = false;
        });
      }
    };
  }

  /// 批量更新 - 将多个更新合并为一次
  static Future<void> batchUpdate(List<Future<void> Function()> updates) async {
    await Future.wait(updates.map((update) => update()));
  }
}
