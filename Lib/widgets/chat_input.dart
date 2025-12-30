// lib/widgets/chat_input.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/message.dart';
import 'package:mime/mime.dart';

class ChatInput extends StatefulWidget {
  final Function(String text, List<FileAttachment> attachments) onSend;
  final VoidCallback? onStop;
  final bool enabled;
  final bool isGenerating;

  const ChatInput({
    super.key,
    required this.onSend,
    this.onStop,
    this.enabled = true,
    this.isGenerating = false,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final List<FileAttachment> _attachments = [];
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    widget.onSend(text, List.from(_attachments));
    _controller.clear();
    setState(() => _attachments.clear());
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null) {
      for (var file in result.files) {
        if (file.path != null) {
          final fileInfo = File(file.path!);
          final mimeType = lookupMimeType(file.path!) ?? 'application/octet-stream';
          
          String? content;
          // 尝试读取更多类型的文本文件
          final textExtensions = [
            '.txt', '.md', '.json', '.xml', '.yaml', '.yml',
            '.dart', '.js', '.ts', '.jsx', '.tsx', '.py', '.java',
            '.c', '.cpp', '.h', '.hpp', '.cs', '.go', '.rs', '.rb',
            '.php', '.html', '.css', '.scss', '.less', '.vue', '.svelte',
            '.sh', '.bash', '.zsh', '.fish', '.ps1', '.bat', '.cmd',
            '.sql', '.graphql', '.proto', '.toml', '.ini', '.cfg', '.conf',
            '.env', '.gitignore', '.dockerfile', '.makefile',
          ];
          
          final ext = file.name.toLowerCase();
          final isTextFile = mimeType.startsWith('text/') || 
              mimeType.contains('json') || 
              mimeType.contains('xml') ||
              mimeType.contains('javascript') ||
              textExtensions.any((e) => ext.endsWith(e));
          
          if (isTextFile) {
            try {
              content = await fileInfo.readAsString();
            } catch (e) {
              // 无法读取为文本，可能是二进制文件
            }
          }

          setState(() {
            _attachments.add(FileAttachment(
              name: file.name,
              path: file.path!,
              mimeType: mimeType,
              size: file.size,
              content: content,
            ));
          });
        }
      }
    }
  }

  Future<void> _pickImage() async {

    final picker = ImagePicker();
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () async {
                Navigator.pop(context);
                final image = await picker.pickImage(source: ImageSource.camera);
                if (image != null) _addImage(image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () async {
                Navigator.pop(context);
                final images = await picker.pickMultiImage();
                for (var image in images) {
                  _addImage(image);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addImage(XFile image) {
    final file = File(image.path);
    final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
    
    setState(() {
      _attachments.add(FileAttachment(
        name: image.name,
        path: image.path,
        mimeType: mimeType,
        size: file.lengthSync(),
      ));
    });
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canSend = widget.enabled && (_controller.text.trim().isNotEmpty || _attachments.isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 附件预览区域（包含图片缩略图）
            if (_attachments.isNotEmpty)
              Container(
                height: 80,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    final attachment = _attachments[index];
                    final isImage = attachment.mimeType.startsWith('image/');
                    
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          if (isImage)
                            // 图片缩略图
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(attachment.path),
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.broken_image, color: colorScheme.primary),
                                ),
                              ),
                            )
                          else
                            // 普通文件
                            Container(
                              width: 64,
                              height: 64,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.insert_drive_file, size: 24, color: colorScheme.primary),
                                  const SizedBox(height: 4),
                                  Text(
                                    attachment.name,
                                    style: const TextStyle(fontSize: 9),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          // 删除按钮
                          Positioned(
                            top: -4,
                            right: -4,
                            child: GestureDetector(
                              onTap: () => _removeAttachment(index),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            
            // 输入框区域
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 输入框
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48, maxHeight: 150),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: widget.enabled,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: '输入消息...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 发送/暂停按钮
                  widget.isGenerating
                      ? IconButton.filled(
                          onPressed: widget.onStop,
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.error,
                          ),
                          icon: const Icon(Icons.stop, color: Colors.white),
                        )
                      : IconButton.filled(
                          onPressed: canSend ? _send : null,
                          icon: const Icon(Icons.send),
                        ),
                ],
              ),
            ),
            
            // 底部按钮区域
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  // 添加文件按钮
                  TextButton.icon(
                    onPressed: widget.enabled && !widget.isGenerating ? _pickFiles : null,
                    icon: Icon(Icons.attach_file, size: 20, color: colorScheme.primary),
                    label: Text('文件', style: TextStyle(color: colorScheme.primary)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 添加图片按钮
                  TextButton.icon(
                    onPressed: widget.enabled && !widget.isGenerating ? _pickImage : null,
                    icon: Icon(Icons.image, size: 20, color: colorScheme.primary),
                    label: Text('图片', style: TextStyle(color: colorScheme.primary)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}