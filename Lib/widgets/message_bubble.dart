// Lib/widgets/message_bubble.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import 'file_attachment_view.dart';
import 'code_block.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onRegenerate;

  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onDelete,
    this.onRegenerate,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _thinkingExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 角色标签
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Text(
              isUser ? '你' : 'AI',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ),
          // 消息内容
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 普通附件
                if (widget.message.attachments.isNotEmpty) ...[
                  _buildAttachments(context),
                  const SizedBox(height: 8),
                ],
                // 消息内容
                if (widget.message.content.isNotEmpty)
                  _buildContent(context),
                // 内嵌文件
                if (widget.message.embeddedFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FileAttachmentView(
                    files: widget.message.embeddedFiles
                        .map((f) => FileAttachmentData(
                              path: f.path,
                              content: f.content,
                              size: f.size,
                            ))
                        .toList(),
                  ),
                ],
                // 发送中状态
                if (widget.message.status == MessageStatus.sending)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                // 错误状态
                if (widget.message.status == MessageStatus.error)
                  _buildError(context),
              ],
            ),
          ),
          // 底部信息栏 + 操作按钮
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
            child: _buildFooter(context),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final content = widget.message.content;
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;

    // 检查思维链
    final thinkingRegex = RegExp(r'<think(?:ing)?>([\s\S]*?)</think(?:ing)?>', caseSensitive: false);
    final match = thinkingRegex.firstMatch(content);

    if (match != null && !isUser) {
      final thinkingContent = match.group(1) ?? '';
      final mainContent = content.replaceAll(thinkingRegex, '').trim();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 思维链折叠
          GestureDetector(
            onTap: () => setState(() => _thinkingExpanded = !_thinkingExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _thinkingExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '💭 思考过程',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _thinkingExpanded ? '点击折叠' : '点击展开',
                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                      ),
                    ],
                  ),
                  if (_thinkingExpanded) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    SelectableText(
                      thinkingContent.trim(),
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (mainContent.isNotEmpty)
            _buildMarkdownContent(context, mainContent),
        ],
      );
    }

    return _buildMarkdownContent(context, content);
  }

  Widget _buildMarkdownContent(BuildContext context, String content) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 检查是否包含代码块
    if (content.contains('```')) {
      return _buildContentWithCodeBlocks(context, content);
    }

    // 使用 Markdown 渲染
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          fontSize: 15,
        ),
        h1: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        h2: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h3: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        strong: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
        em: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        tableHead: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
        tableBody: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        ),
        tableBorder: TableBorder.all(
          color: colorScheme.outline.withOpacity(0.5),
          width: 1,
        ),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        blockquote: TextStyle(
          color: colorScheme.outline,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        code: TextStyle(
          backgroundColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8),
          fontFamily: 'monospace',
          fontSize: 13,
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        listBullet: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildContentWithCodeBlocks(BuildContext context, String content) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;

    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    final matches = codeBlockRegex.allMatches(content).toList();

    if (matches.isEmpty) {
      return _buildMarkdownContent(context, content);
    }

    List<Widget> widgets = [];
    int lastEnd = 0;

    for (var match in matches) {
      if (match.start > lastEnd) {
        final textBefore = content.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          widgets.add(_buildMarkdownContent(context, textBefore));
        }
      }

      final language = match.group(1) ?? '';
      final code = match.group(2) ?? '';
      widgets.add(CodeBlock(code: code.trim(), language: language.isEmpty ? null : language));

      lastEnd = match.end;
    }

    if (lastEnd < content.length) {
      final textAfter = content.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        widgets.add(_buildMarkdownContent(context, textAfter));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 16, color: colorScheme.error),
          const SizedBox(width: 4),
          Text('发送失败', style: TextStyle(fontSize: 12, color: colorScheme.error)),
          if (widget.onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onRetry,
              child: Text(
                '重试',
                style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final usage = widget.message.tokenUsage;
    final isAI = widget.message.role == MessageRole.assistant;
    final isSent = widget.message.status == MessageStatus.sent;

    return Row(
      children: [
        // Token 信息
        Expanded(
          child: Wrap(
            spacing: 12,
            children: [
              if (isAI && usage != null) ...[
                _buildTokenChip('↑ ${_formatNumber(usage.promptTokens)}', colorScheme.outline.withOpacity(0.7)),
                _buildTokenChip('↓ ${_formatNumber(usage.completionTokens)}', colorScheme.outline.withOpacity(0.7)),
                if (usage.tokensPerSecond > 0)
                  _buildTokenChip('⚡${usage.tokensPerSecond.toStringAsFixed(1)}/s', colorScheme.outline.withOpacity(0.7)),
                if (usage.duration > 0)
                  _buildTokenChip('⏱${usage.duration.toStringAsFixed(1)}s', colorScheme.outline.withOpacity(0.7)),
              ],
              Text(
                _formatTime(widget.message.timestamp),
                style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.6)),
              ),
            ],
          ),
        ),
        // 操作按钮
        if (isSent) ...[
          _buildActionButton(
            icon: Icons.copy,
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.message.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
              );
            },
            colorScheme: colorScheme,
          ),
          if (isAI && widget.onRegenerate != null)
            _buildActionButton(
              icon: Icons.refresh,
              onTap: widget.onRegenerate!,
              colorScheme: colorScheme,
            ),
          if (widget.onDelete != null)
            _buildActionButton(
              icon: Icons.delete_outline,
              onTap: () => _confirmDelete(context),
              colorScheme: colorScheme,
              isDestructive: true,
            ),
        ],
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(
          icon,
          size: 18,
          color: isDestructive ? colorScheme.error.withOpacity(0.7) : colorScheme.outline.withOpacity(0.7),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除这条消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete?.call();
            },
            child: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenChip(String text, Color color) {
    return Text(text, style: TextStyle(fontSize: 10, color: color));
  }

  String _formatNumber(int num) {
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toString();
  }

  Widget _buildAttachments(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.message.attachments.map((attachment) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text(attachment.name, style: const TextStyle(fontSize: 13)),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (time.day == now.day && time.month == now.month && time.year == now.year) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}