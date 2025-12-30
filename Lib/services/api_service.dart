// lib/services/api_service.dart

import 'dart:convert';
import 'dart:async';
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

// 流式响应结果
class StreamResult {
  final String content;
  final int estimatedPromptTokens;
  final int estimatedCompletionTokens;

  StreamResult({
    required this.content,
    required this.estimatedPromptTokens,
    required this.estimatedCompletionTokens,
  });
}

class ApiService {
  // 用于取消请求的 client
  static http.Client? _activeClient;
  static bool _isCancelled = false;

  // 取消当前请求
  static void cancelRequest() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  // 重置取消状态
  static void _resetCancelState() {
    _isCancelled = false;
  }

  // 估算token数（1 token ≈ 4字符，中文约2字符）
  static int estimateTokens(String text) {
    return (text.length / 3).ceil();
  }

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

  // 流式发送到主界面AI，返回估算的token
  static Future<StreamResult> streamToMainAIWithTokens({
    required List<Message> messages,
    required String directoryTree,
    required Function(String) onChunk,
  }) async {
    final config = AppConfig.instance;
    return _streamRequestWithTokens(
      apiUrl: config.mainApiUrl,
      apiKey: config.mainApiKey,
      model: config.mainModel,
      messages: messages,
      systemPrompt: config.mainPrompt,
      directoryTree: directoryTree,
      onChunk: onChunk,
    );
  }

  // 流式发送到子界面AI，返回估算的token
  static Future<StreamResult> streamToSubAIWithTokens({
    required List<Message> messages,
    required String directoryTree,
    required int level,
    required Function(String) onChunk,
  }) async {
    final config = AppConfig.instance;
    return _streamRequestWithTokens(
      apiUrl: config.subApiUrl,
      apiKey: config.subApiKey,
      model: config.subModel,
      messages: messages,
      systemPrompt: config.getSubPrompt(level),
      directoryTree: directoryTree,
      onChunk: onChunk,
    );
  }

  static Future<StreamResult> _streamRequestWithTokens({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Message> messages,
    required String systemPrompt,
    required String directoryTree,
    required Function(String) onChunk,
  }) async {
    _resetCancelState();
    
    final url = Uri.parse('$apiUrl/chat/completions');

    List<Map<String, dynamic>> apiMessages = [];
    int totalInputLength = 0;
    bool hasImages = false;

    // 系统消息
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
      totalInputLength += systemContent.length;
    }

    // 对话消息（异步处理附件）
    for (var msg in messages) {
      // 检查是否有图片
      if (msg.attachments.any((a) => a.isImage)) {
        hasImages = true;
      }
      
      final apiFormat = await msg.toApiFormatAsync();
      apiMessages.add(apiFormat);
      
      // 估算长度
      if (apiFormat['content'] is String) {
        totalInputLength += (apiFormat['content'] as String).length;
      } else if (apiFormat['content'] is List) {
        for (var part in apiFormat['content']) {
          if (part['type'] == 'text') {
            totalInputLength += (part['text'] as String).length;
          } else if (part['type'] == 'image_url') {
            totalInputLength += 1000; // 图片估算
          }
        }
      }
    }

    // 估算输入token
    final estimatedPromptTokens = (totalInputLength / 3).ceil();

    // 创建可取消的 client
    _activeClient = http.Client();
    
    try {
      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.body = jsonEncode({
        'model': model,
        'messages': apiMessages,
        'max_tokens': 8192,
        'stream': true,
      });

      final response = await _activeClient!.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('API请求失败: ${response.statusCode} - $body');
      }

      StringBuffer fullContent = StringBuffer();

      await for (var chunk in response.stream.transform(utf8.decoder)) {
        // 检查是否已取消
        if (_isCancelled) {
          break;
        }
        
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (_isCancelled) break;
          
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              break;
            }
            if (data.isNotEmpty) {
              try {
                final json = jsonDecode(data);
                final delta = json['choices']?[0]?['delta'];
                if (delta != null) {
                  final content = delta['content'];
                  if (content != null && content.isNotEmpty) {
                    fullContent.write(content);
                    onChunk(content);
                  }
                }
              } catch (e) {
                // 解析错误，跳过
              }
            }
          }
        }
      }

      final outputContent = fullContent.toString();
      final estimatedCompletionTokens = estimateTokens(outputContent);

      return StreamResult(
        content: outputContent,
        estimatedPromptTokens: estimatedPromptTokens,
        estimatedCompletionTokens: estimatedCompletionTokens,
      );
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }

  // 保留原来的流式方法（兼容）
  static Stream<String> streamToMainAI({
    required List<Message> messages,
    required String directoryTree,
  }) {
    final config = AppConfig.instance;
    return _streamRequest(
      apiUrl: config.mainApiUrl,
      apiKey: config.mainApiKey,
      model: config.mainModel,
      messages: messages,
      systemPrompt: config.mainPrompt,
      directoryTree: directoryTree,
    );
  }

  static Stream<String> streamToSubAI({
    required List<Message> messages,
    required String directoryTree,
    required int level,
  }) {
    final config = AppConfig.instance;
    return _streamRequest(
      apiUrl: config.subApiUrl,
      apiKey: config.subApiKey,
      model: config.subModel,
      messages: messages,
      systemPrompt: config.getSubPrompt(level),
      directoryTree: directoryTree,
    );
  }

  static Stream<String> _streamRequest({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Message> messages,
    required String systemPrompt,
    required String directoryTree,
  }) async* {
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

    final request = http.Request('POST', url);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.body = jsonEncode({
      'model': model,
      'messages': apiMessages,
      'max_tokens': 8192,
      'stream': true,
    });

    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('API请求失败: ${response.statusCode} - $body');
    }

    await for (var chunk in response.stream.transform(utf8.decoder)) {
      final lines = chunk.split('\n');
      for (var line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            return;
          }
          if (data.isNotEmpty) {
            try {
              final json = jsonDecode(data);
              final delta = json['choices']?[0]?['delta'];
              if (delta != null) {
                final content = delta['content'];
                if (content != null && content.isNotEmpty) {
                  yield content;
                }
              }
            } catch (e) {}
          }
        }
      }
    }
  }

  // 非流式发送
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

  static Future<ApiResponse> sendToSubAI({
    required List<Message> messages,
    required String directoryTree,
    required int level,
  }) async {
    final config = AppConfig.instance;
    return _sendRequest(
      apiUrl: config.subApiUrl,
      apiKey: config.subApiKey,
      model: config.subModel,
      messages: messages,
      systemPrompt: config.getSubPrompt(level),
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
      final apiFormat = await msg.toApiFormatAsync();
      apiMessages.add(apiFormat);
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
        'max_tokens': 8192,
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
