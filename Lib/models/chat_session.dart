// lib/models/chat_session.dart

import 'package:flutter/foundation.dart';
import 'message.dart';

class ChatSession extends ChangeNotifier {
  final List<Message> _messages = [];
  bool _isLoading = false;
  String? _error;

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  void addMessage(Message message) {
    _messages.add(message);
    notifyListeners();
  }

  void updateMessage(String id, {String? content, MessageStatus? status}) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      if (content != null) {
        _messages[index] = Message(
          id: _messages[index].id,
          role: _messages[index].role,
          content: content,
          timestamp: _messages[index].timestamp,
          attachments: _messages[index].attachments,
          status: status ?? _messages[index].status,
        );
      } else if (status != null) {
        _messages[index].status = status;
      }
      notifyListeners();
    }
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void clear() {
    _messages.clear();
    _error = null;
    notifyListeners();
  }

  // 获取最后一条AI消息
  Message? get lastAssistantMessage {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == MessageRole.assistant) {
        return _messages[i];
      }
    }
    return null;
  }
}
