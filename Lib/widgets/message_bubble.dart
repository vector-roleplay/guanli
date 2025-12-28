// lib/widgets/message_bubble.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/message.dart';
import 'file_attachment_view.dart';

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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 50 : 12,
          right: isUser ? 12 : 50,
          top: 6,
          bottom: 6,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(
                isUser ? '你' : 'AI',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
            ),
            GestureDetector(
              onLongPress: () => _showOptions(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isUser
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
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
                    // 内嵌文件（折叠展示）
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
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: _buildFooter(context),
            ),
          ],
        ),
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
                      contextMenuBuilder: _buildChineseContextMenu,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (mainContent.isNotEmpty)
            _buildSelectableText(context, mainContent),
        ],
      );
    }

    return _buildSelectableText(context, content);
  }

  Widget _buildSelectableText(BuildContext context, String content) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;

    return SelectableText(
      content,
      style: TextStyle(
        color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
      ),
      contextMenuBuilder: _buildChineseContextMenu,
    );
  }

  Widget _buildChineseContextMenu(BuildContext context, EditableTextState editableTextState) {
    final List<ContextMenuButtonItem> buttonItems = [];

    if (editableTextState.copyEnabled) {
      buttonItems.add(ContextMenuButtonItem(
        label: '复制',
        onPressed: () => editableTextState.copySelection(SelectionChangedCause.toolbar),
      ));
    }

    if (editableTextState.selectAllEnabled) {
      buttonItems.add(ContextMenuButtonItem(
        label: '全选',
        onPressed: () => editableTextState.selectAll(SelectionChangedCause.toolbar),
      ));
    }

    buttonItems.add(ContextMenuButtonItem(
      label: '分享',
      onPressed: () {
        final text = editableTextState.textEditingValue.selection
            .textInside(editableTextState.textEditingValue.text);
        Clipboard.setData(ClipboardData(text: text));
        editableTextState.hideToolbar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
        );
      },
    ));

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
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
    
    return Wrap(
      spacing: 12,
      children: [
        if (widget.message.role == MessageRole.assistant && usage != null) ...[
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

  void _showOptions(BuildContext context) {
  final isAssistant = widget.message.role == MessageRole.assistant;
  
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制全部'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.message.content));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
              );
            },
          ),
          if (isAssistant && widget.onRegenerate != null)
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重新生成'),
              onTap: () {
                Navigator.pop(context);
                widget.onRegenerate?.call();
              },
            ),
          if (widget.onDelete != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text('删除此消息', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context);
              },
            ),
        ],
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (time.day == now.day && time.month == now.month && time.year == now.year) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
