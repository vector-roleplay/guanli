// Lib/widgets/message_bubble.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import 'file_attachment_view.dart';
import 'code_block.dart';

// 缓存解析结果
class _ParsedContent {
  final String? thinkingContent;
  final String mainContent;
  final List<_CodeBlockData> codeBlocks;
  final List<String> textParts;

  _ParsedContent({
    this.thinkingContent,
    required this.mainContent,
    required this.codeBlocks,
    required this.textParts,
  });
}

class _CodeBlockData {
  final String language;
  final String code;
  _CodeBlockData(this.language, this.code);
}

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
  bool _contentExpanded = false;
  _ParsedContent? _cachedParsed;
  String? _lastParsedContent;

  // 长消息阈值
  static const int _foldThreshold = 3000;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    final isSending = widget.message.status == MessageStatus.sending;

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(
                children: [
                  Text(isUser ? '你' : 'AI', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                  if (isSending) ...[
                    const SizedBox(width: 8),
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary)),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.message.attachments.isNotEmpty) ...[
                    _buildAttachments(context),
                    const SizedBox(height: 8),
                  ],
                  if (widget.message.content.isNotEmpty)
                    _buildContent(context),
                  if (widget.message.embeddedFiles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    FileAttachmentView(
                      files: widget.message.embeddedFiles
                          .map((f) => FileAttachmentData(path: f.path, content: f.content, size: f.size))
                          .toList(),
                    ),
                  ],
                  if (widget.message.status == MessageStatus.error)
                    _buildError(context),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
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
    final isSending = widget.message.status == MessageStatus.sending;
    final colorScheme = Theme.of(context).colorScheme;

    // 流式传输中：用纯文本，不解析
    if (isSending) {
      return SelectableText(
        content,
        style: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontSize: 15),
      );
    }

    // 完成后：解析并缓存
    if (_lastParsedContent != content) {
      _cachedParsed = _parseContent(content);
      _lastParsedContent = content;
    }

    final parsed = _cachedParsed!;
    final isLong = content.length > _foldThreshold;
    final shouldFold = isLong && !_contentExpanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 思维链
        if (parsed.thinkingContent != null && !isUser)
          _buildThinkingBlock(context, parsed.thinkingContent!),
        // 主内容
        if (shouldFold)
          _buildFoldedContent(context, parsed.mainContent)
        else
          _buildParsedContent(context, parsed),
        // 展开/收起按钮
        if (isLong)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => setState(() => _contentExpanded = !_contentExpanded),
              child: Text(
                _contentExpanded ? '收起' : '展开全部 (${(content.length / 1000).toStringAsFixed(1)}K字符)',
                style: TextStyle(color: colorScheme.primary, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  _ParsedContent _parseContent(String content) {
    String? thinkingContent;
    String mainContent = content;

    // 提取思维链
    final thinkingRegex = RegExp(r'<think(?:ing)?>([\s\S]*?)</think(?:ing)?>', caseSensitive: false);
    final thinkMatch = thinkingRegex.firstMatch(content);
    if (thinkMatch != null) {
      thinkingContent = thinkMatch.group(1)?.trim();
      mainContent = content.replaceAll(thinkingRegex, '').trim();
    }

    // 提取代码块
    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    final matches = codeBlockRegex.allMatches(mainContent).toList();
    
    List<_CodeBlockData> codeBlocks = [];
    List<String> textParts = [];
    int lastEnd = 0;

    for (var match in matches) {
      if (match.start > lastEnd) {
        textParts.add(mainContent.substring(lastEnd, match.start).trim());
      }
      codeBlocks.add(_CodeBlockData(match.group(1) ?? '', match.group(2)?.trim() ?? ''));
      textParts.add('__CODE_BLOCK_${codeBlocks.length - 1}__');
      lastEnd = match.end;
    }
    if (lastEnd < mainContent.length) {
      textParts.add(mainContent.substring(lastEnd).trim());
    }

    return _ParsedContent(
      thinkingContent: thinkingContent,
      mainContent: mainContent,
      codeBlocks: codeBlocks,
      textParts: textParts,
    );
  }

  Widget _buildThinkingBlock(BuildContext context, String thinking) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
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
                Icon(_thinkingExpanded ? Icons.expand_less : Icons.expand_more, size: 20, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text('💭 思考过程', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text(_thinkingExpanded ? '收起' : '展开', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
              ],
            ),
            if (_thinkingExpanded) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              SelectableText(thinking, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withOpacity(0.8), fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFoldedContent(BuildContext context, String content) {
    final colorScheme = Theme.of(context).colorScheme;
    final preview = content.length > 500 ? '${content.substring(0, 500)}...' : content;
    return SelectableText(preview, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15));
  }

  Widget _buildParsedContent(BuildContext context, _ParsedContent parsed) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;

    if (parsed.codeBlocks.isEmpty) {
      return _buildMarkdown(context, parsed.mainContent);
    }

    List<Widget> widgets = [];
    for (var part in parsed.textParts) {
      if (part.startsWith('__CODE_BLOCK_')) {
        final index = int.tryParse(part.replaceAll('__CODE_BLOCK_', '').replaceAll('__', ''));
        if (index != null && index < parsed.codeBlocks.length) {
          final block = parsed.codeBlocks[index];
          widgets.add(CodeBlock(code: block.code, language: block.language.isEmpty ? null : block.language));
        }
      } else if (part.isNotEmpty) {
        widgets.add(_buildMarkdown(context, part));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _buildMarkdown(BuildContext context, String content) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MarkdownBody(
      data: content,
      selectable: true,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontSize: 15),
        h1: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontSize: 22, fontWeight: FontWeight.bold),
        h2: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontSize: 20, fontWeight: FontWeight.bold),
        h3: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontSize: 18, fontWeight: FontWeight.bold),
        strong: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
        em: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
        tableHead: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
        tableBody: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant),
        tableBorder: TableBorder.all(color: colorScheme.outline.withOpacity(0.5), width: 1),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        code: TextStyle(backgroundColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8), fontFamily: 'monospace', fontSize: 13),
        listBullet: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant),
      ),
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
            GestureDetector(onTap: widget.onRetry, child: Text('重试', style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.bold))),
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
        Expanded(
          child: Wrap(
            spacing: 12,
            children: [
              if (isAI && usage != null) ...[
                Text('↑ ${_formatNumber(usage.promptTokens)}', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.7))),
                Text('↓ ${_formatNumber(usage.completionTokens)}', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.7))),
                if (usage.tokensPerSecond > 0) Text('⚡${usage.tokensPerSecond.toStringAsFixed(1)}/s', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.7))),
                if (usage.duration > 0) Text('⏱${usage.duration.toStringAsFixed(1)}s', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.7))),
              ],
              Text(_formatTime(widget.message.timestamp), style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.6))),
            ],
          ),
        ),
        if (isSent) ...[
          _buildActionButton(Icons.copy, () {
            Clipboard.setData(ClipboardData(text: widget.message.content));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
          }, colorScheme),
          if (isAI && widget.onRegenerate != null) _buildActionButton(Icons.refresh, widget.onRegenerate!, colorScheme),
          if (widget.onDelete != null) _buildActionButton(Icons.delete_outline, () => _confirmDelete(context), colorScheme, isDestructive: true),
        ],
      ],
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap, ColorScheme colorScheme, {bool isDestructive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(icon, size: 18, color: isDestructive ? colorScheme.error.withOpacity(0.7) : colorScheme.outline.withOpacity(0.7)),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除这条消息吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () { Navigator.pop(ctx); widget.onDelete?.call(); }, child: Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
  }

  String _formatNumber(int num) {
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toString();
  }

  Widget _buildAttachments(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.message.attachments.map((a) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.insert_drive_file, size: 18, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 6), Text(a.name, style: const TextStyle(fontSize: 13))]),
      )).toList(),
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