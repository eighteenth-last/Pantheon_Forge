import 'dart:async';

import 'package:flutter/material.dart';

enum AppMessageType { info, success, error }

class AppMessage {
  AppMessage._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    _show(
      context,
      message: message,
      duration: duration,
      type: AppMessageType.info,
    );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    _show(
      context,
      message: message,
      duration: duration,
      type: AppMessageType.success,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      message: message,
      duration: duration,
      type: AppMessageType.error,
    );
  }

  static void fromSnackBar(
    BuildContext context,
    SnackBar snackBar, {
    AppMessageType? type,
  }) {
    final text = _extractMessage(snackBar.content);
    if (text == null || text.trim().isEmpty) return;
    final resolvedType = type ?? _resolveTypeFromSnackBar(snackBar, context);
    _show(
      context,
      message: text.trim(),
      duration: snackBar.duration,
      type: resolvedType,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Duration duration,
    required AppMessageType type,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _timer?.cancel();
    _entry?.remove();
    _entry = null;

    final scheme = Theme.of(context).colorScheme;
    final style = _resolveStyle(type, scheme);

    _entry = OverlayEntry(
      builder: (overlayContext) {
        final width = MediaQuery.sizeOf(overlayContext).width;
        return IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: width > 680 ? 520 : width - 24,
                ),
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: style.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(style.icon, size: 16, color: style.foreground),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: style.foreground,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_entry!);
    _timer = Timer(duration, () {
      _entry?.remove();
      _entry = null;
    });
  }

  static _MessageStyle _resolveStyle(AppMessageType type, ColorScheme scheme) {
    switch (type) {
      case AppMessageType.success:
        return _MessageStyle(
          icon: Icons.check_circle_outline,
          foreground: scheme.onTertiaryContainer,
          background: scheme.tertiaryContainer.withValues(alpha: 0.96),
          border: scheme.tertiary.withValues(alpha: 0.4),
        );
      case AppMessageType.error:
        return _MessageStyle(
          icon: Icons.error_outline,
          foreground: scheme.onErrorContainer,
          background: scheme.errorContainer.withValues(alpha: 0.96),
          border: scheme.error.withValues(alpha: 0.4),
        );
      case AppMessageType.info:
        return _MessageStyle(
          icon: Icons.info_outline,
          foreground: scheme.onSecondaryContainer,
          background: scheme.secondaryContainer.withValues(alpha: 0.96),
          border: scheme.secondary.withValues(alpha: 0.4),
        );
    }
  }

  static String? _extractMessage(Widget content) {
    if (content is Text) {
      return content.data ?? content.textSpan?.toPlainText();
    }
    return null;
  }

  static AppMessageType _resolveTypeFromSnackBar(
    SnackBar snackBar,
    BuildContext context,
  ) {
    final bg = snackBar.backgroundColor;
    if (bg == null) return AppMessageType.info;
    final scheme = Theme.of(context).colorScheme;
    if (bg == scheme.error || bg == scheme.errorContainer) {
      return AppMessageType.error;
    }
    return AppMessageType.info;
  }
}

class _MessageStyle {
  const _MessageStyle({
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;
}
