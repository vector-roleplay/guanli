// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../config/app_config.dart';

class ApiResponse {
  final String content;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  ApiResponse({
    required this.content,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });
}

class ApiService {
  // 获取模型列表
  static Future<List<String>> getModels(String apiUrl, String apiKey) async {
    try {
      final url = Uri.parse('$apiUrl/models');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final models = data['data'] as List;
        return models.map((m) => m['id'].toString()).toList();
      } else {
        throw Exception('获取模型失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('获取模型失败: $e');
    }
  }

  // 发送消息到主界面AI
  static Future<ApiResponse> sendToMainAI({
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
  static Future<ApiResponse> sendToSubAI({
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

  static Future<ApiResponse> _sendRequest({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Message> messages,
    required String systemPrompt,
    required String directoryTree,
  }) async {
    final url = Uri.parse('$apiUrl/chat/completions');

    List<Map<String, dynamic>> apiMessages = [];

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

    for (var msg in messages) {
      apiMessages.add(msg.toApiFormat());
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
      final content = data['choices'][0]['message']['content'];
      final usage = data['usage'] ?? {};
      
      return ApiResponse(
        content: content,
        promptTokens: usage['prompt_tokens'] ?? 0,
        completionTokens: usage['completion_tokens'] ?? 0,
        totalTokens: usage['total_tokens'] ?? 0,
      );
    } else {
      throw Exception('API请求失败: ${response.statusCode} - ${response.body}');
    }
  }
}
