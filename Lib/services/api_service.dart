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
  final int promptTokens;
  final int completionTokens;
  final bool isRealUsage;  // 是否是API返回的真实数据

  StreamResult({
    required this.content,
    required this.promptTokens,
    required this.completionTokens,
    this.isRealUsage = false,
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

  // 最后一次错误信息，用于调试显示
  static String? lastError;

  // 获取模型列表
  static Future<List<String>> getModels(String apiUrl, String apiKey) async {
    try {
      // 处理URL末尾斜杠
      final baseUrl = apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl;
      final url = Uri.parse('$baseUrl/models');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final models = data['data'] as List;
        return models.map((m) => m['id'].toString()).toList();
      } else {
        lastError = 'getModels失败: ${response.statusCode}\n${response.body}';
        throw Exception(lastError);
      }
    } catch (e) {
      lastError = '获取模型失败: $e';
      throw Exception(lastError);
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

    List<Map<String, dynamic>> apiMessages = [];

    int totalInputLength = 0;

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
      final apiFormat = await msg.toApiFormatAsync();
      apiMessages.add(apiFormat);
      
      // 估算长度（用于降级）
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

    // 估算值（用于降级）
    final fallbackPromptTokens = (totalInputLength / 3).ceil();

    // 创建可取消的 client
    _activeClient = http.Client();
    
    // 思维链状态追踪
    bool reasoningStarted = false;
    bool reasoningEnded = false;

    try {
      // 处理URL末尾斜杠
      final baseUrl = apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl;
      final requestUrl = Uri.parse('$baseUrl/chat/completions');
      
      final request = http.Request('POST', requestUrl);
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.headers['Accept'] = 'text/event-stream';
      request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      request.headers['Cache-Control'] = 'no-cache';
      request.headers['Connection'] = 'keep-alive';
      
      // 构建请求体
      final requestBody = <String, dynamic>{
        'model': model,
        'messages': apiMessages,
        'stream': true,
      };
      
      // 不发送 thinking 参数，让反代使用它自己的设置
      requestBody['max_tokens'] = 32000;
      
      request.body = jsonEncode(requestBody);



      final response = await _activeClient!.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        lastError = 'Stream请求失败: ${response.statusCode}\nURL: $requestUrl\nBody: $body';
        throw Exception(lastError);
      }


      StringBuffer fullContent = StringBuffer();
      int? realPromptTokens;
      int? realCompletionTokens;

      await for (var chunk in response.stream.transform(utf8.decoder)) {
        if (_isCancelled) break;
        
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (_isCancelled) break;
          
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') break;
            if (data.isEmpty) continue;
            
            try {
              final json = jsonDecode(data);
              
              // 解析 usage（在最后一个 chunk 中，与 finish_reason 一起返回）
              if (json['usage'] != null) {
                final usage = json['usage'] as Map<String, dynamic>;
                realPromptTokens = usage['prompt_tokens'] as int? ?? 
                                   usage['promptTokens'] as int?;  // 兼容不同格式
                realCompletionTokens = usage['completion_tokens'] as int? ?? 
                                       usage['completionTokens'] as int?;
                // 调试：打印收到的真实 token 数据
                print('📊 收到真实Token: prompt=$realPromptTokens, completion=$realCompletionTokens');
              }
              
              // 解析内容
              final choices = json['choices'] as List?;

              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'];
                if (delta != null) {
                  // 先处理思维链 (reasoning_content)
                  final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
                  if (reasoning != null && reasoning.isNotEmpty) {
                    if (!reasoningStarted) {
                      // 第一次收到思维链，添加开始标签
                      fullContent.write('<think>');
                      onChunk('<think>');
                      reasoningStarted = true;
                    }
                    fullContent.write(reasoning);
                    onChunk(reasoning);
                  }
                  
                  // 再处理正文内容
                  final content = delta['content'];
                  if (content != null && content.isNotEmpty) {
                    // 如果之前有思维链且未结束，先添加结束标签
                    if (reasoningStarted && !reasoningEnded) {
                      fullContent.write('</think>\n\n');
                      onChunk('</think>\n\n');
                      reasoningEnded = true;
                    }
                    fullContent.write(content);
                    onChunk(content);
                  }
                }
              }
            } catch (e) {
              // 解析错误，跳过
            }
          }
        }
      }
      
      // 流结束时，如果思维链未闭合，补上结束标签
      if (reasoningStarted && !reasoningEnded) {
        fullContent.write('</think>\n\n');
      }


      final outputContent = fullContent.toString();
      
      // 优先使用真实数据，否则降级使用估算值
      final hasRealUsage = realPromptTokens != null && realCompletionTokens != null;
      
      // 记录成功的API配置
      if (outputContent.isNotEmpty) {
        // 判断是主界面还是子界面API
        final config = AppConfig.instance;
        if (apiUrl == config.mainApiUrl && apiKey == config.mainApiKey) {
          config.recordMainApiSuccess();
        } else if (apiUrl == config.subApiUrl && apiKey == config.subApiKey) {
          config.recordSubApiSuccess();
        }
      }
      
      return StreamResult(
        content: outputContent,
        promptTokens: realPromptTokens ?? fallbackPromptTokens,
        completionTokens: realCompletionTokens ?? estimateTokens(outputContent),
        isRealUsage: hasRealUsage,
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
    // 处理URL末尾斜杠
    final baseUrl = apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl;
    final url = Uri.parse('$baseUrl/chat/completions');


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
    request.headers['Content-Type'] = 'application/json; charset=utf-8';
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.headers['Accept'] = 'text/event-stream';
    request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    request.headers['Cache-Control'] = 'no-cache';
    request.headers['Connection'] = 'keep-alive';
    
    // 构建请求体
    final requestBody = <String, dynamic>{
      'model': model,
      'messages': apiMessages,
      'stream': true,
    };
    
    // 不发送 thinking 参数，让反代使用它自己的设置
    requestBody['max_tokens'] = 32000;
    
    request.body = jsonEncode(requestBody);

    bool reasoningStarted = false;

    bool reasoningEnded = false;

    final client = http.Client();

    try {
      final response = await client.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        lastError = 'Stream请求失败: ${response.statusCode}\nBody: $body';
        throw Exception(lastError);
      }

      await for (var chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              // 流结束时，如果思维链未闭合，补上结束标签
              if (reasoningStarted && !reasoningEnded) {
                yield '</think>\n\n';
              }
              return;
            }
            if (data.isNotEmpty) {
              try {
                final json = jsonDecode(data);
                final delta = json['choices']?[0]?['delta'];
                if (delta != null) {
                  // 先处理思维链
                  final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
                  if (reasoning != null && reasoning.isNotEmpty) {
                    if (!reasoningStarted) {
                      yield '<think>';
                      reasoningStarted = true;
                    }
                    yield reasoning;
                  }
                  
                  // 再处理正文
                  final content = delta['content'];
                  if (content != null && content.isNotEmpty) {
                    if (reasoningStarted && !reasoningEnded) {
                      yield '</think>\n\n';
                      reasoningEnded = true;
                    }
                    yield content;
                  }
                }
              } catch (e) {}
            }
          }
        }
      }
      
      // 循环结束后，如果思维链未闭合
      if (reasoningStarted && !reasoningEnded) {
        yield '</think>\n\n';
      }
    } finally {
      client.close();
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

    // 构建请求体
    final requestBody = <String, dynamic>{
      'model': model,
      'messages': apiMessages,
    };
    
    // 不发送 thinking 参数，让反代使用它自己的设置
    requestBody['max_tokens'] = 32000;
    
    final response = await http.post(

      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(requestBody),
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
