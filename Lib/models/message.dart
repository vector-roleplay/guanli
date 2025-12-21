// lib/models/message.dart

import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant, system }

enum MessageStatus { sending, sent, error }

class Message {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<FileAttachment> attachments;
  MessageStatus status;

  Message({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    List<FileAttachment>? attachments,
    this.status = MessageStatus.sent,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now(),
        attachments = attachments ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'status': status.name,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      role: MessageRole.values.byName(json['role']),
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      attachments: (json['attachments'] as List?)
          ?.map((a) => FileAttachment.fromJson(a))
          .toList(),
      status: MessageStatus.values.byName(json['status'] ?? 'sent'),
    );
  }

  // 转换为API请求格式
  Map<String, dynamic> toApiFormat() {
    return {
      'role': role.name,
      'content': content,
    };
  }
}

class FileAttachment {
  final String id;
  final String name;
  final String path;
  final String mimeType;
  final int size;
  final String? content; // 文件内容（文本文件）

  FileAttachment({
    String? id,
    required this.name,
    required this.path,
    required this.mimeType,
    required this.size,
    this.content,
  }) : id = id ?? const Uuid().v4();

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
