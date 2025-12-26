// lib/models/conversation.dart

import 'package:uuid/uuid.dart';
import 'message.dart';

class Conversation {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<Message> messages;

  Conversation({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Message>? messages,
  })  : id = id ?? const Uuid().v4(),
        title = title ?? '新会话',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      messages: (json['messages'] as List?)
          ?.map((m) => Message.fromJson(m))
          .toList() ?? [],
    );
  }

  // 根据第一条用户消息自动生成标题
  void autoGenerateTitle() {
    for (var msg in messages) {
      if (msg.role == MessageRole.user && msg.content.isNotEmpty) {
        final content = msg.content;
        title = content.length > 20 ? '${content.substring(0, 20)}...' : content;
        break;
      }
    }
  }
}
