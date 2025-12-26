// lib/services/conversation_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/message.dart';

class ConversationService {
  static final ConversationService instance = ConversationService._internal();
  ConversationService._internal();

  static const String _storageKey = 'conversations';
  List<Conversation> _conversations = [];

  List<Conversation> get conversations => List.unmodifiable(_conversations);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
    
    if (data != null) {
      try {
        final list = jsonDecode(data) as List;
        _conversations = list.map((e) => Conversation.fromJson(e)).toList();
        // 按更新时间排序，最新的在前
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (e) {
        _conversations = [];
      }
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_conversations.map((c) => c.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  Future<Conversation> create() async {
    final conversation = Conversation();
    _conversations.insert(0, conversation);
    await save();
    return conversation;
  }

  Future<void> update(Conversation conversation) async {
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index != -1) {
      conversation.updatedAt = DateTime.now();
      _conversations[index] = conversation;
      // 重新排序
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await save();
    }
  }

  Future<void> delete(String id) async {
    _conversations.removeWhere((c) => c.id == id);
    await save();
  }

  Future<void> rename(String id, String newTitle) async {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index != -1) {
      _conversations[index].title = newTitle;
      await save();
    }
  }

  Future<void> addMessage(String conversationId, Message message) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index].messages.add(message);
      _conversations[index].updatedAt = DateTime.now();
      
      // 如果是第一条用户消息，自动生成标题
      if (_conversations[index].messages.length <= 2) {
        _conversations[index].autoGenerateTitle();
      }
      
      await save();
    }
  }

  Future<void> updateMessage(String conversationId, String messageId, {
    String? content,
    MessageStatus? status,
    TokenUsage? tokenUsage,
  }) async {
    final convIndex = _conversations.indexWhere((c) => c.id == conversationId);
    if (convIndex != -1) {
      final msgIndex = _conversations[convIndex].messages.indexWhere((m) => m.id == messageId);
      if (msgIndex != -1) {
        final oldMsg = _conversations[convIndex].messages[msgIndex];
        _conversations[convIndex].messages[msgIndex] = Message(
          id: oldMsg.id,
          role: oldMsg.role,
          content: content ?? oldMsg.content,
          timestamp: oldMsg.timestamp,
          attachments: oldMsg.attachments,
          status: status ?? oldMsg.status,
          tokenUsage: tokenUsage ?? oldMsg.tokenUsage,
        );
        await save();
      }
    }
  }

  Conversation? getById(String id) {
    try {
      return _conversations.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }
}
