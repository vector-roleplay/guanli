// lib/screens/sub_chat_screen.dart

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../utils/message_detector.dart';
import '../config/app_config.dart';

class SubChatScreen extends StatefulWidget {
  final String initialMessage;
  final List<String> requestedPaths;
  final String directoryTree;

  const SubChatScreen({
    super.key,
    required this.initialMessage,
    required this.requestedPaths,
    required this.directoryTree,
  });

  @override
  State<SubChatScreen> createState() => _SubChatScreenState();
}

class _SubChatScreenState extends State<SubChatScreen> {
  final ChatSession _session = ChatSession();
  final ScrollController _scrollController = ScrollController();
  final MessageDetector _detector = MessageDetector();

  @override
  void initState() {
    super.initState();
    _initializeChat();
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

    if (totalSize <= AppConfig.maxChunkSize) {
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

  Future<void> _sendBatch(
    String baseContent,
    List<FileContent> batch,
    int sentSize,
    int totalSize,
  ) async {
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

  Future<void> _sendLargeFile(
    String baseContent,
    FileContent file,
    int sentSize,
    int totalSize,
  ) async {
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
    while (true) {
      await Future.delayed(const Duration(milliseconds: 500));
      final lastMessage = _session.lastAssistantMessage;
      if (lastMessage != null && lastMessage.content.contains('【请继续】')) {
        break;
      }
      if (lastMessage != null && lastMessage.status == MessageStatus.sent) {
        break;
      }
    }
  }

  Future<void> _sendSystemMessage(String content) async {
    final systemMessage = Message(
      role: MessageRole.user,
      content: content,
      status: MessageStatus.sent,
    );
    _session.addMessage(systemMessage);
    _scrollToBottom();

    final aiMessage = Message(
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.sending,
    );
    _session.addMessage(aiMessage);
    _session.setLoading(true);
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();

    try {
      final response = await ApiService.sendToSubAI(
        messages: _session.messages.where((m) => m.status != MessageStatus.sending).toList(),
        directoryTree: widget.directoryTree,
      );

      stopwatch.stop();

      _session.updateMessage(
        aiMessage.id,
        content: response.content,
        status: MessageStatus.sent,
        tokenUsage: TokenUsage(
          promptTokens: response.promptTokens,
          completionTokens: response.completionTokens,
          totalTokens: response.totalTokens,
          duration: stopwatch.elapsedMilliseconds / 1000,
        ),
      );
      _scrollToBottom();

      await _handleAIResponse(response.content);

    } catch (e) {
      _session.updateMessage(aiMessage.id, content: '发送失败: $e', status: MessageStatus.error);
    } finally {
      _session.setLoading(false);
    }
  }

  Future<void> _handleAIResponse(String response) async {
    if (_detector.hasReturnToMain(response)) {
      if (mounted) {
        Navigator.pop(context, response);
      }
      return;
    }

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
    _session.addMessage(userMessage);
    _scrollToBottom();

    final aiMessage = Message(
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.sending,
    );
    _session.addMessage(aiMessage);
    _session.setLoading(true);
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();

    try {
      final response = await ApiService.sendToSubAI(
        messages: _session.messages.where((m) => m.status != MessageStatus.sending).toList(),
        directoryTree: widget.directoryTree,
      );

      stopwatch.stop();

      _session.updateMessage(
        aiMessage.id,
        content: response.content,
        status: MessageStatus.sent,
        tokenUsage: TokenUsage(
          promptTokens: response.promptTokens,
          completionTokens: response.completionTokens,
          totalTokens: response.totalTokens,
          duration: stopwatch.elapsedMilliseconds / 1000,
        ),
      );
      _scrollToBottom();

      await _handleAIResponse(response.content);

    } catch (e) {
      _session.updateMessage(aiMessage.id, content: '发送失败: $e', status: MessageStatus.error);
    } finally {
      _session.setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('子界面 - 文件处理'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _session,
              builder: (context, _) {
                if (_session.messages.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: _session.messages.length,
                  itemBuilder: (context, index) {
                    return MessageBubble(message: _session.messages[index]);
                  },
                );
              },
            ),
          ),
          ListenableBuilder(
            listenable: _session,
            builder: (context, _) {
              return ChatInput(
                onSend: _sendMessage,
                enabled: !_session.isLoading,
              );
            },
          ),
        ],
      ),
    );
  }
}
