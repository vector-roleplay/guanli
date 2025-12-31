// Lib/widgets/scroll_buttons.dart

import 'package:flutter/material.dart';

class ScrollButtons extends StatelessWidget {
  final VoidCallback onScrollToTop;
  final VoidCallback onScrollToBottom;
  final VoidCallback onPreviousMessage;
  final VoidCallback onNextMessage;

  const ScrollButtons({
    super.key,
    required this.onScrollToTop,
    required this.onScrollToBottom,
    required this.onPreviousMessage,
    required this.onNextMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 到顶部（双箭头向上）
        _buildButton(
          icon: Icons.keyboard_double_arrow_up,
          onTap: onScrollToTop,
          colorScheme: colorScheme,
          isDark: isDark,
        ),
        const SizedBox(height: 8),
        // 上一条消息（单箭头向上）
        _buildButton(
          icon: Icons.keyboard_arrow_up,
          onTap: onPreviousMessage,
          colorScheme: colorScheme,
          isDark: isDark,
        ),
        const SizedBox(height: 8),
        // 下一条消息（单箭头向下）
        _buildButton(
          icon: Icons.keyboard_arrow_down,
          onTap: onNextMessage,
          colorScheme: colorScheme,
          isDark: isDark,
        ),
        const SizedBox(height: 8),
        // 到底部（双箭头向下）
        _buildButton(
          icon: Icons.keyboard_double_arrow_down,
          onTap: onScrollToBottom,
          colorScheme: colorScheme,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark 
              ? Colors.black.withOpacity(0.6) 
              : Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 24,
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }
}
