// lib/widgets/block_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'dart:io';

import '../models/message.dart';

/// 内容块 Widget - 渲染单个块
class BlockWidget extends StatefulWidget {
  final Message message;
  final String content;
  final int localIndex;
  final bool isFirst;
  final bool isLast;
  final bool isStreaming;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;

  const BlockWidget({
    super.key,
    required this.message,
    required this.content,
    required this.localIndex,
    required this.isFirst,
    required this.isLast,
    this.isStreaming = false,
    this.onRetry,
    this.onDelete,
    this.onRegenerate,
    this.onEdit,
  });

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget> {
  bool _thinkingExpanded = false;
  
  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: widget.isFirst ? 6 : 0,
          bottom: widget.isLast ? 6 : 0,
        ),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 消息头部（只在第一块显示）
            if (widget.isFirst && !isUser)
              _buildHeader(context),
            
            // 内容
            if (isUser && widget.content.isNotEmpty)
              _buildUserContent(context)
            else if (!isUser)
              _buildAIContent(context),
            
            // 附件（只在第一块显示）
            if (widget.isFirst && (widget.message.attachments.isNotEmpty || widget.message.embeddedFiles.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildAttachments(context),
              ),
            
            // 底部操作栏（只在最后一块显示）
            if (widget.isLast)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _buildFooter(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // 简化的头部，可以根据需要添加头像等
    return const SizedBox(height: 4);
  }

  Widget _buildUserContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        widget.content,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 15,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildAIContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (widget.content.isEmpty && widget.isStreaming) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.primary,
        ),
      );
    }
    
    // 流式时用纯文本，完成后用 Markdown
    if (widget.isStreaming) {
      return _buildPlainText(context);
    }
    
    return _buildRichContent(context);
  }

  Widget _buildPlainText(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SelectableText(
      widget.content,
      style: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 15,
        height: 1.6,
      ),
    );
  }

  Widget _buildRichContent(BuildContext context) {
    final content = widget.content;
    final blocks = _parseContent(content);
    
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.map((block) {
          switch (block.type) {
            case _BlockType.thinking:
              return _buildThinkingBlock(context, block.content);
            case _BlockType.code:
              return _buildCodeBlock(context, block.content, block.language);
            case _BlockType.markdown:
              return _buildMarkdownBlock(context, block.content);
          }
        }).toList(),
      ),
    );
  }

  List<_ParsedBlock> _parseContent(String content) {
    List<_ParsedBlock> blocks = [];
    String mainContent = content;
    
    // 提取思维链
    final thinkingPatterns = [
      RegExp(r'', caseSensitive: false),
      RegExp(r'', caseSensitive: false),
    ];
    
    for (var regex in thinkingPatterns) {
      final match = regex.firstMatch(mainContent);
      if (match != null) {
        final thinkingContent = match.group(1)?.trim();
        if (thinkingContent != null && thinkingContent.isNotEmpty) {
          blocks.add(_ParsedBlock(type: _BlockType.thinking, content: thinkingContent));
        }
        mainContent = mainContent.substring(0, match.start) + mainContent.substring(match.end);
        break;
      }
    }
    
    mainContent = mainContent.trim();
    if (mainContent.isEmpty) return blocks;
    
    // 提取代码块
    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    final matches = codeBlockRegex.allMatches(mainContent).toList();
    
    if (matches.isEmpty) {
      blocks.add(_ParsedBlock(type: _BlockType.markdown, content: mainContent));
      return blocks;
    }
    
    int lastEnd = 0;
    for (var match in matches) {
      if (match.start > lastEnd) {
        final textBefore = mainContent.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          blocks.add(_ParsedBlock(type: _BlockType.markdown, content: textBefore));
        }
      }
      blocks.add(_ParsedBlock(
        type: _BlockType.code,
        content: (match.group(2) ?? '').trim(),
        language: match.group(1),
      ));
      lastEnd = match.end;
    }
    
    if (lastEnd < mainContent.length) {
      final textAfter = mainContent.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        blocks.add(_ParsedBlock(type: _BlockType.markdown, content: textAfter));
      }
    }
    
    return blocks;
  }

  Widget _buildThinkingBlock(BuildContext context, String content) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () => setState(() => _thinkingExpanded = !_thinkingExpanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.blur_on,
                    size: 20,
                    color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '深度思考',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFFE3F2FD) : const Color(0xFF1565C0),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _thinkingExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF1976D2),
                  ),
                ],
              ),
            ),
            if (_thinkingExpanded)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1B2A) : const Color(0xFFF5F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFBBDEFB),
                  ),
                ),
                child: SelectableText(
                  content.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code, String? language) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1a1a1a) : const Color(0xFFF8F9FA);
    final dividerColor = isDark ? const Color(0xFF333333) : const Color(0xFFE1E4E8);
    final textColor = isDark ? const Color(0xFF888888) : const Color(0xFF57606A);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: dividerColor, width: 0.5)),
            ),
            child: Row(
              children: [
                if (language?.isNotEmpty == true)
                  Text(
                    language!,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textColor),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded, size: 14, color: textColor),
                      const SizedBox(width: 4),
                      Text('复制', style: TextStyle(fontSize: 12, color: textColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              code,
              language: _normalizeLanguage(language),
              theme: isDark ? atomOneDarkTheme : githubTheme,
              padding: const EdgeInsets.all(12),
              textStyle: const TextStyle(fontFamily: 'SarasaMono', fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeLanguage(String? language) {
    if (language == null || language.isEmpty) return 'plaintext';
    const aliases = {
      'js': 'javascript', 'ts': 'typescript', 'py': 'python',
      'rb': 'ruby', 'sh': 'bash', 'shell': 'bash', 'yml': 'yaml',
      'md': 'markdown', 'kt': 'kotlin', 'rs': 'rust', 'cs': 'csharp',
    };
    final lower = language.toLowerCase();
    return aliases[lower] ?? lower;
  }

  Widget _buildMarkdownBlock(BuildContext context, String content) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return MarkdownBody(
      data: content,
      selectable: false,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: colorScheme.onSurface, fontSize: 15, height: 1.6),
        h1: TextStyle(color: colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.bold),
        h2: TextStyle(color: colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
        h3: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
        code: TextStyle(fontFamily: 'monospace', fontSize: 13, color: colorScheme.outline),
        pPadding: const EdgeInsets.only(bottom: 8),
      ),
    );
  }

  Widget _buildAttachments(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = widget.message.role == MessageRole.user;
    
    // 简化的附件显示
    final attachmentCount = widget.message.attachments.length + widget.message.embeddedFiles.length;
    if (attachmentCount == 0) return const SizedBox();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text('$attachmentCount 个附件', style: TextStyle(fontSize: 12, color: colorScheme.onSurface)),
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
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        // Token 统计
        if (isAI && usage != null)
          Wrap(
            spacing: 12,
            children: [
              Text('↑${_formatNumber(usage.promptTokens)}', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.6))),
              Text('↓${_formatNumber(usage.completionTokens)}', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.6))),
              if (usage.tokensPerSecond > 0)
                Text('${usage.tokensPerSecond.toStringAsFixed(1)}/s', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.6))),
            ],
          ),
        Text(_formatTime(widget.message.timestamp), style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.5))),
        
        if (isSent) ...[
          const SizedBox(width: 12),
          if (widget.content.isNotEmpty)
            _buildActionButton(Icons.copy, () {
              Clipboard.setData(ClipboardData(text: widget.message.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
              );
            }, colorScheme),
          if (isUser && widget.onEdit != null)
            _buildActionButton(Icons.edit, widget.onEdit!, colorScheme),
          if (isAI && widget.onRegenerate != null)
            _buildActionButton(Icons.refresh, widget.onRegenerate!, colorScheme),
          if (widget.onDelete != null)
            _buildActionButton(Icons.delete_outline, () => _confirmDelete(context), colorScheme, isDestructive: true),
        ],
      ],
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap, ColorScheme colorScheme, {bool isDestructive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(
          icon,
          size: 18,
          color: isDestructive ? colorScheme.error.withOpacity(0.7) : colorScheme.outline.withOpacity(0.6),
        ),
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
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete?.call();
            },
            child: Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
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

class _ParsedBlock {
  final _BlockType type;
  final String content;
  final String? language;

  _ParsedBlock({required this.type, required this.content, this.language});
}