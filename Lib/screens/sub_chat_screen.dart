// lib/screens/sub_chat_screen.dart

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/sub_conversation.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import '../services/sub_conversation_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../utils/message_detector.dart';
import '../config/app_config.dart';

class SubChatScreen extends StatefulWidget {
  final SubConversation subConversation;
  final String initialMessage;
  final List<String> requestedPaths;
  final String directoryTree;
  final bool isResuming;  // 是否是恢复已有会话

  const SubChatScreen({
    super.key,
    required this.subConversation,
    required this.initialMessage,
    required this.requestedPaths,
    required this.directoryTree,
    this.isResuming = false,
  });

  @override
  State<SubChatScreen> createState() => _SubChatScreenState();
}

class _SubChatScreenState extends State<SubChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final MessageDetector _detector = MessageDetector();
  
  late SubConversation _subConversation;
  bool _isLoading = false;
  String _streamingContent = '';

  @override
  void initState() {
    super.initState();
    _subConversation = widget.subConversation;
    
    // 如果不是恢复会话，初始化发送文件
    if (!widget.isResuming && widget.requestedPaths.isNotEmpty) {
      _initializeChat();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _initializeChat() async {
    await _sendFilesWithMessage(widget.initialMessage, widget.requestedPaths);
  }

  Future<void> _sendFilesWithMessage(String message, List<String> paths) async {
    final fileContents = await FileService.instance.getFilesContent(paths);
    final totalSize = fileContents.fold<int>(0, (sum, f) => sum + f.size);

    String content = '【请求说明书】\n$message\n\n【文件目录】\n${widget.directoryTree}';

    if (fileContents.isEmpty) {
      content += '\n\n【注意】未找到请求的文件内容';
      await _sendSystemMessage(content);
    } else if (totalSize <= AppConfig.maxChunkSize) {
      content += '\n\n【文件内容】\n';
      for (var file in fileContents) {
        content += '--- ${file.path} ---\n${file.content}\n\n';
      }
      await _sendSystemMessage(content);
    } else {
      await _sendFilesInChunks(content, fileContents);
    }
  }

  Future<void> _sendFilesInChunks(String baseContent, List<FileContent> files) async {
    int sentSize = 0;
    int totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
    List<FileContent> currentBatch = [];
    int currentBatchSize = 0;

    for (var file in files) {
      if (file.size > AppConfig.maxChunkSize) {
        await _sendLargeFile(baseContent, file, sentSize, totalSize);
        sentSize += file.size;
      } else if (currentBatchSize + file.size > AppConfig.maxChunkSize) {
        await _sendBatch(baseContent, currentBatch, sentSize, totalSize);
        sentSize += currentBatchSize;
        currentBatch = [file];
        currentBatchSize = file.size;
      } else {
        currentBatch.add(file);
        currentBatchSize += file.size;
      }
    }

    if (currentBatch.isNotEmpty) {
      await _sendBatch(baseContent, currentBatch, sentSize, totalSize);
    }
  }

  Future<void> _sendBatch(String baseContent, List<FileContent> batch, int sentSize, int totalSize) async {
    int batchSize = batch.fold<int>(0, (sum, f) => sum + f.size);
    int newSentSize = sentSize + batchSize;
    int percentage = ((newSentSize / totalSize) * 100).round();

    String content = '$baseContent\n\n【文件内容】\n';
    for (var file in batch) {
      content += '--- ${file.path} ---\n${file.content}\n\n';
    }
    content += '\n本次文件已发送$percentage%';

    await _sendSystemMessage(content);

    if (percentage < 100) {
      await _waitForContinue();
    }
  }

  Future<void> _sendLargeFile(String baseContent, FileContent file, int sentSize, int totalSize) async {
    final chunks = FileService.instance.splitContent(file.content, AppConfig.maxChunkSize);
    int chunksSent = 0;

    for (var chunk in chunks) {
      chunksSent++;
      int overallPercentage = (((sentSize + (file.size * chunksSent / chunks.length)) / totalSize) * 100).round();

      String content = '$baseContent\n\n【文件内容 - ${file.path} (第$chunksSent/${chunks.length}部分)】\n$chunk';
      content += '\n\n本次文件已发送$overallPercentage%';

      await _sendSystemMessage(content);

      if (chunksSent < chunks.length) {
        await _waitForContinue();
      }
    }
  }

  Future<void> _waitForContinue() async {
    int attempts = 0;
    while (attempts < 60) {  // 最多等30秒
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
      
      if (_subConversation.messages.isNotEmpty) {
        final lastMessage = _subConversation.messages.last;
        if (lastMessage.role == MessageRole.assistant && 
            lastMessage.status == MessageStatus.sent &&
            lastMessage.content.contains('【请继续】')) {
          break;
        }
      }
    }
  }

  Future<void> _sendSystemMessage(String content) async {
    final systemMessage = Message(
      role: MessageRole.user,
      content: content,
      status: MessageStatus.sent,
    );
    _subConversation.messages.add(systemMessage);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    _scrollToBottom();

    final aiMessage = Message(
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.sending,
    );
    _subConversation.messages.add(aiMessage);
    setState(() {
      _isLoading = true;
      _streamingContent = '';
    });
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();

    try {
      final stream = ApiService.streamToSubAI(
        messages: _subConversation.messages
            .where((m) => m.status != MessageStatus.sending)
            .toList(),
        directoryTree: widget.directoryTree,
      );

      await for (var chunk in stream) {
        _streamingContent += chunk;
        final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
        if (msgIndex != -1) {
          _subConversation.messages[msgIndex] = Message(
            id: aiMessage.id,
            role: MessageRole.assistant,
            content: _streamingContent,
            timestamp: aiMessage.timestamp,
            status: MessageStatus.sending,
          );
          setState(() {});
          _scrollToBottom();
        }
      }

      stopwatch.stop();

      final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _subConversation.messages[msgIndex] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: _streamingContent,
          timestamp: aiMessage.timestamp,
          status: MessageStatus.sent,
          tokenUsage: TokenUsage(
            promptTokens: 0,
            completionTokens: _streamingContent.length ~/ 4,
            totalTokens: _streamingContent.length ~/ 4,
            duration: stopwatch.elapsedMilliseconds / 1000,
          ),
        );
      }

      await SubConversationService.instance.update(_subConversation);
      setState(() {});
      _scrollToBottom();

      await _handleAIResponse(_streamingContent);

    } catch (e) {
      final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _subConversation.messages[msgIndex] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: '发送失败: $e',
          timestamp: aiMessage.timestamp,
          status: MessageStatus.error,
        );
      }
      await SubConversationService.instance.update(_subConversation);
      setState(() {});
    } finally {
      setState(() {
        _isLoading = false;
        _streamingContent = '';
      });
    }
  }

  Future<void> _handleAIResponse(String response) async {
    // 检测是否返回主界面
    if (_detector.hasReturnToMain(response)) {
      if (mounted) {
        Navigator.pop(context, {
          'completed': true,
          'message': response,
        });
      }
      return;
    }

    // 检测是否继续请求文件
    if (_detector.hasRequestDoc(response)) {
      final paths = _detector.extractPaths(response);
      if (paths.isNotEmpty) {
        await _sendFilesWithMessage(response, paths);
      }
    }
  }

  Future<void> _sendMessage(String text, List<FileAttachment> attachments) async {
    if (text.isEmpty && attachments.isEmpty) return;

    final userMessage = Message(
      role: MessageRole.user,
      content: text,
      attachments: attachments,
      status: MessageStatus.sent,
    );
    _subConversation.messages.add(userMessage);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    _scrollToBottom();

    final aiMessage = Message(
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.sending,
    );
    _subConversation.messages.add(aiMessage);
    setState(() {
      _isLoading = true;
      _streamingContent = '';
    });
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();

    try {
      final stream = ApiService.streamToSubAI(
        messages: _subConversation.messages
            .where((m) => m.status != MessageStatus.sending)
            .toList(),
        directoryTree: widget.directoryTree,
      );

      await for (var chunk in stream) {
        _streamingContent += chunk;
        final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
        if (msgIndex != -1) {
          _subConversation.messages[msgIndex] = Message(
            id: aiMessage.id,
            role: MessageRole.assistant,
            content: _streamingContent,
            timestamp: aiMessage.timestamp,
            status: MessageStatus.sending,
          );
          setState(() {});
          _scrollToBottom();
        }
      }

      stopwatch.stop();

      final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _subConversation.messages[msgIndex] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: _streamingContent,
          timestamp: aiMessage.timestamp,
          status: MessageStatus.sent,
          tokenUsage: TokenUsage(
            promptTokens: 0,
            completionTokens: _streamingContent.length ~/ 4,
            totalTokens: _streamingContent.length ~/ 4,
            duration: stopwatch.elapsedMilliseconds / 1000,
          ),
        );
      }

      await SubConversationService.instance.update(_subConversation);
      setState(() {});
      _scrollToBottom();

      await _handleAIResponse(_streamingContent);

    } catch (e) {
      final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _subConversation.messages[msgIndex] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: '发送失败: $e',
          timestamp: aiMessage.timestamp,
          status: MessageStatus.error,
        );
      }
      await SubConversationService.instance.update(_subConversation);
      setState(() {});
    } finally {
      setState(() {
        _isLoading = false;
        _streamingContent = '';
      });
    }
  }

  Future<void> _deleteMessage(int index) async {
    _subConversation.messages.removeAt(index);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_subConversation.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 用户手动退出，不标记为完成
            Navigator.pop(context, null);
          },
        ),
        actions: [
          // 手动标记完成并返回
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            tooltip: '完成并返回',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('完成子会话'),
                  content: const Text('确定要完成此子会话并返回主界面吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(this.context, {
                          'completed': true,
                          'message': '',
                        });
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _subConversation.messages.isEmpty
                ? Center(
                    child: widget.isResuming
                        ? const Text('会话已恢复，继续对话')
                        : const CircularProgressIndicator(),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _subConversation.messages.length,
                    itemBuilder: (context, index) {
                      final message = _subConversation.messages[index];
                      return MessageBubble(
                        message: message,
                        onRetry: message.status == MessageStatus.error
                            ? () => _sendMessage(message.content, message.attachments)
                            : null,
                        onDelete: () => _deleteMessage(index),
                      );
                    },
                  ),
          ),
          ChatInput(
            onSend: _sendMessage,
            enabled: !_isLoading,
          ),
        ],
      ),
    );
  }
}
