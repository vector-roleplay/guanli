// lib/models/sub_conversation.dart

import 'package:uuid/uuid.dart';
import 'message.dart';

class SubConversation {
  final String id;
  final String parentId;  // 父级ID（可以是主会话ID或上级子会话ID）
  final String rootConversationId;  // 根主会话ID
  final int level;  // 级别：1=一级, 2=二级, ...
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<Message> messages;

  SubConversation({
    String? id,
    required this.parentId,
    required this.rootConversationId,
    required this.level,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Message>? messages,
  })  : id = id ?? const Uuid().v4(),
        title = title ?? '${_getLevelName(level)}子界面',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  static String _getLevelName(int level) {
    const chineseNums = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (level >= 1 && level <= 10) {
      return chineseNums[level - 1] + '级';
    }
    return '$level级';
  }

  String get levelName => _getLevelName(level);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'rootConversationId': rootConversationId,
      'level': level,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }

  factory SubConversation.fromJson(Map<String, dynamic> json) {
    return SubConversation(
      id: json['id'],
      parentId: json['parentId'],
      rootConversationId: json['rootConversationId'],
      level: json['level'] ?? 1,
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      messages: (json['messages'] as List?)
          ?.map((m) => Message.fromJson(m))
          .toList() ?? [],
    );
  }
}
