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
  Future<SubConversation> create({
    required String parentId,
    required String rootConversationId,
    required int level,
  }) async {
    final sub = SubConversation(
      parentId: parentId,
      rootConversationId: rootConversationId,
      level: level,
    );
    _subConversations.add(sub);
    await save();
    return sub;
  }

  // 获取某个父级下的所有子会话
  List<SubConversation> getByParentId(String parentId) {
    return _subConversations.where((s) => s.parentId == parentId).toList();
  }

  // 获取某个根主会话的所有子会话
  List<SubConversation> getByRootId(String rootConversationId) {
    return _subConversations.where((s) => s.rootConversationId == rootConversationId).toList();
  }

  // 获取某个根主会话下某一级别的子会话
  List<SubConversation> getByRootIdAndLevel(String rootConversationId, int level) {
    return _subConversations
        .where((s) => s.rootConversationId == rootConversationId && s.level == level)
        .toList();
  }

  // 删除子会话（同时删除其下级子会话）
  Future<void> delete(String id) async {
    // 递归删除下级
    final children = _subConversations.where((s) => s.parentId == id).toList();
    for (var child in children) {
      await delete(child.id);
    }
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

  // 删除某主会话的所有子会话
  Future<void> deleteByRootId(String rootConversationId) async {
    _subConversations.removeWhere((s) => s.rootConversationId == rootConversationId);
    await save();
  }
}
