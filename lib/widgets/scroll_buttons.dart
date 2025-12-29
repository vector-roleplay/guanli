// lib/widgets/scroll_buttons.dart

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

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 到顶部（双箭头）
          _buildButton(
            icon: Icons.keyboard_double_arrow_up,
            onTap: onScrollToTop,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 2),
          // 上一条消息（单箭头）
          _buildButton(
            icon: Icons.keyboard_arrow_up,
            onTap: onPreviousMessage,
            colorScheme: colorScheme,
            isInner: true,
          ),
          const SizedBox(height: 2),
          // 下一条消息（单箭头）
          _buildButton(
            icon: Icons.keyboard_arrow_down,
            onTap: onNextMessage,
            colorScheme: colorScheme,
            isInner: true,
          ),
          const SizedBox(height: 2),
          // 到底部（双箭头）
          _buildButton(
            icon: Icons.keyboard_double_arrow_down,
            onTap: onScrollToBottom,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isInner = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: isInner ? 22 : 26,
            color: isInner 
                ? colorScheme.onSurfaceVariant 
                : colorScheme.primary,
          ),
        ),
      ),
    );
  }
}