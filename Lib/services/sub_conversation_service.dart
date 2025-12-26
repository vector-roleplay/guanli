// lib/services/sub_conversation_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sub_conversation.dart';
import '../models/message.dart';

class SubConversationService {
  static final SubConversationService instance = SubConversationService._internal();
  SubConversationService._internal();

  static const String _storageKey = 'sub_conversations';
  List<SubConversation> _subConversations = [];

  List<SubConversation> get subConversations => List.unmodifiable(_subConversations);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
    
    if (data != null) {
      try {
        final list = jsonDecode(data) as List;
        _subConversations = list.map((e) => SubConversation.fromJson(e)).toList();
      } catch (e) {
        _subConversations = [];
      }
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_subConversations.map((c) => c.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  // 创建子会话
  Future<SubConversation> create(String parentConversationId, String title) async {
    final sub = SubConversation(
      parentConversationId: parentConversationId,
      title: title.length > 20 ? '${title.substring(0, 20)}...' : title,
    );
    _subConversations.add(sub);
    await save();
    return sub;
  }

  // 获取某个主会话的所有未完成子会话
  List<SubConversation> getByParentId(String parentConversationId) {
    return _subConversations
        .where((s) => s.parentConversationId == parentConversationId && !s.isCompleted)
        .toList();
  }

  // 标记为已完成
  Future<void> markCompleted(String id) async {
    final index = _subConversations.indexWhere((s) => s.id == id);
    if (index != -1) {
      _subConversations[index].isCompleted = true;
      await save();
    }
  }

  // 删除子会话
  Future<void> delete(String id) async {
    _subConversations.removeWhere((s) => s.id == id);
    await save();
  }

  // 更新子会话
  Future<void> update(SubConversation sub) async {
    final index = _subConversations.indexWhere((s) => s.id == sub.id);
    if (index != -1) {
      sub.updatedAt = DateTime.now();
      _subConversations[index] = sub;
      await save();
    }
  }

  // 获取子会话
  SubConversation? getById(String id) {
    try {
      return _subConversations.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  // 添加消息
  Future<void> addMessage(String subId, Message message) async {
    final index = _subConversations.indexWhere((s) => s.id == subId);
    if (index != -1) {
      _subConversations[index].messages.add(message);
      _subConversations[index].updatedAt = DateTime.now();
      await save();
    }
  }

  // 删除某主会话的所有子会话
  Future<void> deleteByParentId(String parentConversationId) async {
    _subConversations.removeWhere((s) => s.parentConversationId == parentConversationId);
    await save();
  }
}
