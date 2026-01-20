// lib/models/message.dart

import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant, system }

enum MessageStatus { sending, sent, error }

class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final double duration;
  final bool isRealUsage;  // 是否是API返回的真实数据
  
  TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.duration = 0,
    this.isRealUsage = false,
  });


  double get tokensPerSecond {
    if (duration <= 0) return 0;
    return completionTokens / duration;
  }

  Map<String, dynamic> toJson() => {
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'totalTokens': totalTokens,
    'duration': duration,
    'isRealUsage': isRealUsage,
  };

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
    promptTokens: json['promptTokens'] ?? 0,
    completionTokens: json['completionTokens'] ?? 0,
    totalTokens: json['totalTokens'] ?? 0,
    duration: (json['duration'] ?? 0).toDouble(),
    isRealUsage: json['isRealUsage'] ?? false,
  );

}

// 内嵌文件数据（用于显示，不发送给API）
class EmbeddedFile {
  final String path;
  final String content;
  final int size;

  EmbeddedFile({
    required this.path,
    required this.content,
    required this.size,
  });

  String get fileName => path.split('/').last;

  Map<String, dynamic> toJson() => {
    'path': path,
    'content': content,
    'size': size,
  };

  factory EmbeddedFile.fromJson(Map<String, dynamic> json) => EmbeddedFile(
    path: json['path'] ?? '',
    content: json['content'] ?? '',
    size: json['size'] ?? 0,
  );
}

class Message {
  final String id;
  final MessageRole role;
  final String content;  // 显示用的简短内容
  final String? fullContent;  // 完整内容（发送给API）
  final DateTime timestamp;
  final List<FileAttachment> attachments;
  final List<EmbeddedFile> embeddedFiles;  // 内嵌文件
  MessageStatus status;
  TokenUsage? tokenUsage;

  Message({
    String? id,
    required this.role,
    required this.content,
    this.fullContent,
    DateTime? timestamp,
    List<FileAttachment>? attachments,
    List<EmbeddedFile>? embeddedFiles,
    this.status = MessageStatus.sent,
    this.tokenUsage,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now(),
        attachments = attachments ?? [],
        embeddedFiles = embeddedFiles ?? [];

  // 获取发送给API的内容
  String get apiContent => fullContent ?? content;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'fullContent': fullContent,
      'timestamp': timestamp.toIso8601String(),
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'embeddedFiles': embeddedFiles.map((f) => f.toJson()).toList(),
      'status': status.name,
      'tokenUsage': tokenUsage?.toJson(),
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      role: MessageRole.values.byName(json['role']),
      content: json['content'],
      fullContent: json['fullContent'],
      timestamp: DateTime.parse(json['timestamp']),
      attachments: (json['attachments'] as List?)
          ?.map((a) => FileAttachment.fromJson(a))
          .toList(),
      embeddedFiles: (json['embeddedFiles'] as List?)
          ?.map((f) => EmbeddedFile.fromJson(f))
          .toList(),
      status: MessageStatus.values.byName(json['status'] ?? 'sent'),
      tokenUsage: json['tokenUsage'] != null 
          ? TokenUsage.fromJson(json['tokenUsage']) 
          : null,
    );
  }

  // 转换为API格式（支持多模态）
  Future<Map<String, dynamic>> toApiFormatAsync() async {
    // 分离图片和文本文件
    final imageAttachments = attachments.where((a) => a.mimeType.startsWith('image/')).toList();
    final textAttachments = attachments.where((a) => !a.mimeType.startsWith('image/')).toList();
    
    // 构建文本内容
    String textContent = apiContent;
    
    // 添加文本文件内容
    if (textAttachments.isNotEmpty) {
      textContent += '\n\n【附件内容】\n';
      for (var att in textAttachments) {
        if (att.content != null && att.content!.isNotEmpty) {
          textContent += '--- ${att.name} ---\n${att.content}\n\n';
        } else {
          // 尝试读取文件
          try {
            final file = File(att.path);
            if (await file.exists()) {
              final content = await file.readAsString();
              textContent += '--- ${att.name} ---\n$content\n\n';
            }
          } catch (e) {
            textContent += '--- ${att.name} ---\n[无法读取文件内容]\n\n';
          }
        }
      }
    }
    
    // 如果没有图片，返回简单格式
    if (imageAttachments.isEmpty) {
      return {
        'role': role.name,
        'content': textContent,
      };
    }
    
    // 有图片，使用多模态格式
    List<Map<String, dynamic>> contentParts = [];
    
    // 先添加文本
    if (textContent.isNotEmpty) {
      contentParts.add({
        'type': 'text',
        'text': textContent,
      });
    }
    
    // 添加图片
    for (var img in imageAttachments) {
      try {
        final file = File(img.path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64Data = base64Encode(bytes);
          final mimeType = img.mimeType.isNotEmpty ? img.mimeType : 'image/jpeg';
          
          contentParts.add({
            'type': 'image_url',
            'image_url': {
              'url': 'data:$mimeType;base64,$base64Data',
            },
          });
        }
      } catch (e) {
        // 图片读取失败，跳过
      }
    }
    
    return {
      'role': role.name,
      'content': contentParts,
    };
  }

  // 同步版本（兼容旧代码，不处理图片）
  Map<String, dynamic> toApiFormat() {
    String textContent = apiContent;
    
    // 添加文本文件内容
    final textAttachments = attachments.where((a) => !a.mimeType.startsWith('image/')).toList();
    if (textAttachments.isNotEmpty) {
      textContent += '\n\n【附件内容】\n';
      for (var att in textAttachments) {
        if (att.content != null && att.content!.isNotEmpty) {
          textContent += '--- ${att.name} ---\n${att.content}\n\n';
        }
      }
    }
    
    return {
      'role': role.name,
      'content': textContent,
    };
  }
}

class FileAttachment {
  final String id;
  final String name;
  final String path;
  final String mimeType;
  final int size;
  final String? content;

  FileAttachment({
    String? id,
    required this.name,
    required this.path,
    required this.mimeType,
    required this.size,
    this.content,
  }) : id = id ?? const Uuid().v4();

  bool get isImage => mimeType.startsWith('image/');

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'mimeType': mimeType,
      'size': size,
      'content': content,
    };
  }

  factory FileAttachment.fromJson(Map<String, dynamic> json) {
    return FileAttachment(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      mimeType: json['mimeType'],
      size: json['size'],
      content: json['content'],
    );
  }
}
