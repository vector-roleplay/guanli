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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 到顶部（双箭头向上）
        _buildButton(
          icon: Icons.keyboard_double_arrow_up,
          onTap: onScrollToTop,
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 4),
        // 上一条消息（单箭头向上）
        _buildButton(
          icon: Icons.keyboard_arrow_up,
          onTap: onPreviousMessage,
          colorScheme: colorScheme,
          isSmall: true,
        ),
        const SizedBox(height: 4),
        // 下一条消息（单箭头向下）
        _buildButton(
          icon: Icons.keyboard_arrow_down,
          onTap: onNextMessage,
          colorScheme: colorScheme,
          isSmall: true,
        ),
        const SizedBox(height: 4),
        // 到底部（双箭头向下）
        _buildButton(
          icon: Icons.keyboard_double_arrow_down,
          onTap: onScrollToBottom,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isSmall = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isSmall ? 36 : 40,
        height: isSmall ? 36 : 40,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
        ),
        child: Icon(
          icon,
          size: isSmall ? 20 : 24,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}