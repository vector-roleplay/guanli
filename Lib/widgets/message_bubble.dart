// Lib/widgets/message_bubble.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:io';
import '../models/message.dart';
import 'file_attachment_view.dart';

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
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 消息内容（用户消息为空时不显示气泡）
            if (isUser && widget.message.content.isNotEmpty)
              _buildUserMessage(context)
            else if (!isUser)
              _buildAIMessage(context),
            
            // 附件区域（放在气泡外面下方）
            if (widget.message.attachments.isNotEmpty || widget.message.embeddedFiles.isNotEmpty)

              Padding(
                padding: EdgeInsets.only(top: 8, left: isUser ? 40 : 0, right: isUser ? 0 : 40),
                child: _buildAttachmentsSection(context),
              ),
            
            // 底部操作栏
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _buildFooter(context),
            ),
          ],
        ),
      ),
    );
  }

  // 用户消息 - 右对齐，黑灰色背景，短消息短气泡
  Widget _buildUserMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
        widget.message.content,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 15,
          height: 1.4,
        ),
      ),
    );
  }

  // AI消息 - 左对齐，透明背景
  Widget _buildAIMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSending = widget.message.status == MessageStatus.sending;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message.content.isNotEmpty)
          isSending 
              ? _buildStreamingContent(context)
              : _buildCachedContent(context),
        if (isSending)
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
        if (widget.message.status == MessageStatus.error && !_isUserStopped) 
          _buildError(context),
      ],
    );
  }

  // 附件区域
  Widget _buildAttachmentsSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = widget.message.role == MessageRole.user;
    
    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // 图片附件
        if (widget.message.attachments.any((a) => a.mimeType.startsWith('image/')))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildImageAttachments(context),
          ),
        
        // 文件附件
        if (widget.message.attachments.any((a) => !a.mimeType.startsWith('image/')))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildFileAttachments(context),
          ),
        
        // 内嵌文件
        if (widget.message.embeddedFiles.isNotEmpty)
          FileAttachmentView(
            files: widget.message.embeddedFiles
                .map((f) => FileAttachmentData(path: f.path, content: f.content, size: f.size))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildStreamingContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SelectableText(
      widget.message.content,
      style: TextStyle(
        color: colorScheme.onSurface,
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
    
    // 提取思维链
    final thinkingRegex = RegExp(r'<think(?:ing)?>([\s\S]*?)</think(?:ing)?>', caseSensitive: false);
    final thinkMatch = thinkingRegex.firstMatch(content);
    
    String mainContent = content;
    if (thinkMatch != null && widget.message.role != MessageRole.user) {
      blocks.add(_ContentBlock(type: _BlockType.thinking, content: thinkMatch.group(1) ?? ''));
      mainContent = content.replaceAll(thinkingRegex, '').trim();
    }
    
    if (mainContent.isEmpty) return blocks;
    
    // 提取代码块
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
            return _buildCodeBlock(context, block.content, block.language);
          case _BlockType.markdown:
            return _buildMarkdownBlock(context, block.content);
        }
      }).toList(),
    );
  }

  // 思维链 - 圆角按钮样式
  Widget _buildThinkingBlock(BuildContext context, String content) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () => setState(() => _thinkingExpanded = !_thinkingExpanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 折叠按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '深度思考',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _thinkingExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            // 展开内容
            if (_thinkingExpanded)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Text(
                  content.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 代码块 - 整体化样式
  Widget _buildCodeBlock(BuildContext context, String code, String? language) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 代码块背景色
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF6F8FA);
    // 顶部栏背景色（略深一点）
    final headerBgColor = isDark ? const Color(0xFF252526) : const Color(0xFFEEF1F4);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE1E4E8),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部栏 - 无边框分隔，通过背景色区分
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: headerBgColor,
            child: Row(
              children: [
                if (language?.isNotEmpty == true)
                  Text(
                    language!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
                    ),
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
                      Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '复制',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 代码内容 - 无额外装饰
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF24292F),
                height: 1.5,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownBlock(BuildContext context, String content) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MarkdownBody(
      data: content,

      selectable: false,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 15,
          height: 1.6,
        ),
        h1: TextStyle(color: colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
        h2: TextStyle(color: colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
        h3: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4),
        strong: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
        em: TextStyle(color: colorScheme.onSurface, fontStyle: FontStyle.italic),
        blockquote: TextStyle(color: colorScheme.outline, fontStyle: FontStyle.italic, height: 1.5),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: colorScheme.primary, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        code: TextStyle(
          backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE8E8E8),
          fontFamily: 'monospace',
          fontSize: 13,
          color: colorScheme.onSurface,
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE1E4E8),
            width: 1,
          ),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        listBullet: TextStyle(color: colorScheme.onSurface, height: 1.5),

        listIndent: 20,
        tableBorder: TableBorder.all(color: colorScheme.outline.withOpacity(0.5), width: 1),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        pPadding: const EdgeInsets.only(bottom: 8),
      ),
    );
  }

  // 图片附件 - 手机比例缩略图
  Widget _buildImageAttachments(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final images = widget.message.attachments.where((a) => a.mimeType.startsWith('image/')).toList();
    final isUser = widget.message.role == MessageRole.user;
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
      children: images.map((att) {
        return GestureDetector(
          onTap: () => _showFullImage(context, att.path),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(att.path),
                width: 80,
                height: 100,  // 手机比例 4:5
                fit: BoxFit.cover,
                cacheWidth: 160,
                errorBuilder: (ctx, err, stack) => Container(
                  width: 80,
                  height: 100,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.broken_image, color: colorScheme.outline),
                ),
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

  // 文件附件
  Widget _buildFileAttachments(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final files = widget.message.attachments.where((a) => !a.mimeType.startsWith('image/')).toList();
    final isUser = widget.message.role == MessageRole.user;
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
      children: files.map((att) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  att.name,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
            GestureDetector(
              onTap: widget.onRetry,
              child: Text('重试', style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  // 获取不含思维链的内容（用于复制）
  String _getContentWithoutThinking(String content) {
    final thinkingRegex = RegExp(r'<think(?:ing)?>([\s\S]*?)</think(?:ing)?>', caseSensitive: false);
    return content.replaceAll(thinkingRegex, '').trim();
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
        // Token 统计和时间
        Wrap(
          spacing: 12,
          children: [
            if (isAI && usage != null) ...[
              Text('↑${_formatNumber(usage.promptTokens)}', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.6))),
              Text('↓${_formatNumber(usage.completionTokens)}', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.6))),
              if (usage.tokensPerSecond > 0) 
                Text('${usage.tokensPerSecond.toStringAsFixed(1)}/s', style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.6))),
            ],
            Text(_formatTime(widget.message.timestamp), style: TextStyle(fontSize: 10, color: colorScheme.outline.withOpacity(0.5))),
          ],
        ),
        if (isSent) ...[
          const SizedBox(width: 12),
          // 复制按钮
          _buildActionButton(
            icon: Icons.copy,
            onTap: () {
              // AI消息复制时去除思维链
              final contentToCopy = isAI 
                  ? _getContentWithoutThinking(widget.message.content)
                  : widget.message.content;
              Clipboard.setData(ClipboardData(text: contentToCopy));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
              );
            },
            colorScheme: colorScheme,
          ),
          // 用户消息：编辑按钮
          if (isUser && widget.onEdit != null)
            _buildActionButton(icon: Icons.edit, onTap: widget.onEdit!, colorScheme: colorScheme),

          // AI消息：重新生成按钮
          if (isAI && widget.onRegenerate != null)
            _buildActionButton(icon: Icons.refresh, onTap: widget.onRegenerate!, colorScheme: colorScheme),
          // 删除按钮
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
          color: isDestructive 
              ? colorScheme.error.withOpacity(0.7) 
              : colorScheme.outline.withOpacity(0.6),
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

class _ContentBlock {
  final _BlockType type;
  final String content;
  final String? language;

  _ContentBlock({required this.type, required this.content, this.language});
}
