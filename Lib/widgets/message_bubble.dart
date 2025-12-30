// Lib/widgets/message_bubble.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:io';
import '../models/message.dart';
import 'file_attachment_view.dart';
import 'code_block.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;

  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onDelete,
    this.onRegenerate,
    this.onEdit,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with AutomaticKeepAliveClientMixin {
  bool _thinkingExpanded = false;
  
  String? _cachedContent;
  List<_ContentBlock>? _cachedBlocks;

  @override
  bool get wantKeepAlive => true;

  bool get _isUserStopped {
    final content = widget.message.content;
    return content.endsWith('[已停止生成]') || content.contains('\n\n[已停止生成]');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
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
              child: Text(
                isUser ? '你' : 'AI',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
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
                  if (widget.message.attachments.any((a) => a.mimeType.startsWith('image/'))) ...[
                    _buildImageAttachments(context),
                    const SizedBox(height: 8),
                  ],
                  if (widget.message.attachments.any((a) => !a.mimeType.startsWith('image/'))) ...[
                    _buildFileAttachments(context),
                    const SizedBox(height: 8),
                  ],
                  if (widget.message.content.isNotEmpty)
                    isSending 
                        ? _buildStreamingContent(context)
                        : _buildCachedContent(context),
                  if (widget.message.embeddedFiles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    FileAttachmentView(
                      files: widget.message.embeddedFiles.map((f) => FileAttachmentData(path: f.path, content: f.content, size: f.size)).toList(),
                    ),
                  ],
                  if (isSending)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary)),
                    ),
                  if (widget.message.status == MessageStatus.error && !_isUserStopped) _buildError(context),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.only(top: 6, left: 4, right: 4), child: _buildFooter(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingContent(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    
    return SelectableText(
      widget.message.content,
      style: TextStyle(
        color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        fontSize: 15,
        height: 1.6,
      ),
    );
  }

  Widget _buildCachedContent(BuildContext context) {
    final content = widget.message.content;
    
    if (_cachedContent != content) {
      _cachedContent = content;
      _cachedBlocks = _parseContent(content);
    }
    
    return SelectionArea(child: _buildParsedContent(context, _cachedBlocks!));
  }

  List<_ContentBlock> _parseContent(String content) {
    List<_ContentBlock> blocks = [];
    
    final thinkingRegex = RegExp(r'<think(?:ing)?>([\s\S]*?)</think(?:ing)?>', caseSensitive: false);
    final thinkMatch = thinkingRegex.firstMatch(content);
    
    String mainContent = content;
    if (thinkMatch != null && widget.message.role != MessageRole.user) {
      blocks.add(_ContentBlock(type: _BlockType.thinking, content: thinkMatch.group(1) ?? ''));
      mainContent = content.replaceAll(thinkingRegex, '').trim();
    }
    
    if (mainContent.isEmpty) return blocks;
    
    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    final matches = codeBlockRegex.allMatches(mainContent).toList();
    
    if (matches.isEmpty) {
      blocks.add(_ContentBlock(type: _BlockType.markdown, content: mainContent));
      return blocks;
    }
    
    int lastEnd = 0;
    for (var match in matches) {
      if (match.start > lastEnd) {
        final textBefore = mainContent.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          blocks.add(_ContentBlock(type: _BlockType.markdown, content: textBefore));
        }
      }
      blocks.add(_ContentBlock(
        type: _BlockType.code,
        content: (match.group(2) ?? '').trim(),
        language: match.group(1),
      ));
      lastEnd = match.end;
    }
    
    if (lastEnd < mainContent.length) {
      final textAfter = mainContent.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        blocks.add(_ContentBlock(type: _BlockType.markdown, content: textAfter));
      }
    }
    
    return blocks;
  }

  Widget _buildParsedContent(BuildContext context, List<_ContentBlock> blocks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) {
        switch (block.type) {
          case _BlockType.thinking:
            return _buildThinkingBlock(context, block.content);
          case _BlockType.code:
            return CodeBlock(code: block.content, language: block.language);
          case _BlockType.markdown:
            return _buildMarkdownBlock(context, block.content);
        }
      }).toList(),
    );
  }

  Widget _buildThinkingBlock(BuildContext context, String content) {
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
                Text(_thinkingExpanded ? '点击折叠' : '点击展开', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
              ],
            ),
            if (_thinkingExpanded) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(content.trim(), style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withOpacity(0.8), fontStyle: FontStyle.italic, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMarkdownBlock(BuildContext context, String content) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MarkdownBody(
      data: content,
      selectable: false,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, 
          fontSize: 15,
          height: 1.6,
        ),
        h1: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
        h2: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
        h3: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4),
        strong: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
        em: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
        blockquote: TextStyle(color: colorScheme.outline, fontStyle: FontStyle.italic, height: 1.5),
        blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: colorScheme.primary, width: 3))),
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
        codeblockPadding: const EdgeInsets.all(12),
        listBullet: TextStyle(color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, height: 1.5),
        listIndent: 20,
        tableBorder: TableBorder.all(color: colorScheme.outline.withOpacity(0.5), width: 1),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        pPadding: const EdgeInsets.only(bottom: 8),
      ),
    );
  }

  Widget _buildImageAttachments(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final images = widget.message.attachments.where((a) => a.mimeType.startsWith('image/')).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: images.map((att) {
        return GestureDetector(
          onTap: () => _showFullImage(context, att.path),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(att.path),
              width: 120,
              height: 120,
              fit: BoxFit.cover,
              cacheWidth: 240,
              errorBuilder: (ctx, err, stack) => Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.broken_image, color: colorScheme.outline),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showFullImage(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: InteractiveViewer(
                child: Center(
                  child: Image.file(File(path), fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileAttachments(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final files = widget.message.attachments.where((a) => !a.mimeType.startsWith('image/')).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: files.map((att) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file, size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(att.name, style: const TextStyle(fontSize: 13)),
            ],
          ),
        );
      }).toList(),
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
          if (widget.onDelete != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline, size: 14, color: colorScheme.error),
                    const SizedBox(width: 4),
                    Text('删除', style: TextStyle(fontSize: 12, color: colorScheme.error, fontWeight: FontWeight.bold)),
                  ],
                ),
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
    final isUser = widget.message.role == MessageRole.user;
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
          _buildActionButton(icon: Icons.copy, onTap: () {
            Clipboard.setData(ClipboardData(text: widget.message.content));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
          }, colorScheme: colorScheme),
          // 用户消息显示编辑按钮
          if (isUser && widget.onEdit != null) _buildActionButton(icon: Icons.edit, onTap: widget.onEdit!, colorScheme: colorScheme),
          // AI消息显示重新生成按钮
          if (isAI && widget.onRegenerate != null) _buildActionButton(icon: Icons.refresh, onTap: widget.onRegenerate!, colorScheme: colorScheme),
          if (widget.onDelete != null) _buildActionButton(icon: Icons.delete_outline, onTap: () => _confirmDelete(context), colorScheme: colorScheme, isDestructive: true),
        ],
      ],
    );
  }

  Widget _buildActionButton({required IconData icon, required VoidCallback onTap, required ColorScheme colorScheme, bool isDestructive = false}) {
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (time.day == now.day && time.month == now.month && time.year == now.year) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

enum _BlockType { thinking, code, markdown }

class _ContentBlock {
  final _BlockType type;
  final String content;
  final String? language;

  _ContentBlock({required this.type, required this.content, this.language});
}
