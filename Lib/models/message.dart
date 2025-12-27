// lib/models/message.dart

import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant, system }

enum MessageStatus { sending, sent, error }

class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final double duration;
  
  TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.duration = 0,
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
  };

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
    promptTokens: json['promptTokens'] ?? 0,
    completionTokens: json['completionTokens'] ?? 0,
    totalTokens: json['totalTokens'] ?? 0,
    duration: (json['duration'] ?? 0).toDouble(),
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

  Map<String, dynamic> toApiFormat() {
    return {
      'role': role.name,
      'content': apiContent,
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
