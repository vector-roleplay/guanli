// lib/widgets/chat_input.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/message.dart';
import 'package:mime/mime.dart';

class ChatInput extends StatefulWidget {
  final Function(String text, List<FileAttachment> attachments) onSend;
  final bool enabled;

  const ChatInput({
    super.key,
    required this.onSend,
    this.enabled = true,
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
          
          // 读取文件内容（仅文本文件）
          String? content;
          if (mimeType.startsWith('text/') || 
              mimeType.contains('json') || 
              mimeType.contains('xml')) {
            try {
              content = await fileInfo.readAsString();
            } catch (e) {
              // 无法读取为文本
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
            // 附件预览
            if (_attachments.isNotEmpty)
              Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    final attachment = _attachments[index];
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            attachment.mimeType.startsWith('image/')
                                ? Icons.image
                               : Icons.insert_drive_file,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Text(
                              attachment.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _removeAttachment(index),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            // 输入区域
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 添加文件按钮
                  IconButton(
                    onPressed: widget.enabled ? _pickFiles : null,
                    icon: const Icon(Icons.attach_file),
                    tooltip: '添加文件',
                  ),
                  // 添加图片按钮
                  IconButton(
                    onPressed: widget.enabled ? _pickImage : null,
                    icon: const Icon(Icons.image),
                    tooltip: '添加图片',
                  ),
                  // 输入框
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
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
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 发送按钮
                  IconButton.filled(
                    onPressed: widget.enabled &&
                            (_controller.text.trim().isNotEmpty ||
                                _attachments.isNotEmpty)
                        ? _send
                        : null,
                    icon: const Icon(Icons.send),
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
