import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 32,
        color: colorScheme.surface,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Image.asset('assets/logo.png', width: 18, height: 18),
            const SizedBox(width: 8),
            Text('Pantheon Forge',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
            const Spacer(),
            _WindowButton(
              icon: Icons.minimize,
              onPressed: () => windowManager.minimize(),
              colorScheme: colorScheme,
            ),
            _WindowButton(
              icon: Icons.crop_square,
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              colorScheme: colorScheme,
            ),
            _WindowButton(
              icon: Icons.close,
              onPressed: () => windowManager.close(),
              isClose: true,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;
  final ColorScheme colorScheme;

  const _WindowButton({
    required this.icon, required this.onPressed,
    this.isClose = false, required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46, height: 32,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: isClose
              ? Colors.red.withValues(alpha: 0.9)
              : colorScheme.onSurface.withValues(alpha: 0.08),
          child: Center(
            child: Icon(icon, size: 16,
              color: colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }
}
