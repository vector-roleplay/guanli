// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../config/app_config.dart';

class ApiService {
  // 发送消息到主界面AI
  static Future<String> sendToMainAI({
    required List<Message> messages,
    required String directoryTree,
  }) async {
    final config = AppConfig.instance;
    return _sendRequest(
      apiUrl: config.mainApiUrl,
      apiKey: config.mainApiKey,
      model: config.mainModel,
      messages: messages,
      systemPrompt: config.mainPrompt,
      directoryTree: directoryTree,
    );
  }

  // 发送消息到子界面AI
  static Future<String> sendToSubAI({
    required List<Message> messages,
    required String directoryTree,
  }) async {
    final config = AppConfig.instance;
    return _sendRequest(
      apiUrl: config.subApiUrl,
      apiKey: config.subApiKey,
      model: config.subModel,
      messages: messages,
      systemPrompt: config.subPrompt,
      directoryTree: directoryTree,
    );
  }

  static Future<String> _sendRequest({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Message> messages,
    required String systemPrompt,
    required String directoryTree,
  }) async {
    final url = Uri.parse('$apiUrl/chat/completions');

    // 构建消息列表
    List<Map<String, dynamic>> apiMessages = [];

    // 添加系统消息（如果有）
    if (systemPrompt.isNotEmpty || directoryTree.isNotEmpty) {
      String systemContent = '';
      if (directoryTree.isNotEmpty) {
        systemContent += '【文件目录】\n$directoryTree\n\n';
      }
      if (systemPrompt.isNotEmpty) {
        systemContent += systemPrompt;
      }
      apiMessages.add({
        'role': 'system',
        'content': systemContent.trim(),
      });
    }

    // 添加对话消息
    for (var msg in messages) {
      apiMessages.add(msg.toApiFormat());
    }

    // 处理最后一条用户消息，附加提示词
    if (apiMessages.isNotEmpty && 
        apiMessages.last['role'] == 'user' && 
        systemPrompt.isNotEmpty) {
      // 提示词已在system消息中，这里不重复添加
      // 如果需要在用户消息尾部也加，可以取消下面的注释
      // apiMessages.last['content'] += '\n\n$systemPrompt';
    }

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': apiMessages,
        'max_tokens': 4096,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['choices'][0]['message']['content'];
    } else {
      throw Exception('API请求失败: ${response.statusCode} - ${response.body}');
    }
  }
}
