// lib/models/sub_conversation.dart

import 'package:uuid/uuid.dart';
import 'message.dart';

class SubConversation {
  final String id;
  final String parentConversationId;  // 所属主会话
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<Message> messages;
  bool isCompleted;  // 是否已完成（系统自动退出）

  SubConversation({
    String? id,
    required this.parentConversationId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Message>? messages,
    this.isCompleted = false,
  })  : id = id ?? const Uuid().v4(),
        title = title ?? '子会话',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentConversationId': parentConversationId,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'isCompleted': isCompleted,
    };
  }

  factory SubConversation.fromJson(Map<String, dynamic> json) {
    return SubConversation(
      id: json['id'],
      parentConversationId: json['parentConversationId'],
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      messages: (json['messages'] as List?)
          ?.map((m) => Message.fromJson(m))
          .toList() ?? [],
      isCompleted: json['isCompleted'] ?? false,
    );
  }
}
