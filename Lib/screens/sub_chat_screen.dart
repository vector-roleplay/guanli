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
  final bool isResuming;

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
    
    if (!widget.isResuming && widget.requestedPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeChat();
      });
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
  // 获取文件内容
  final fileContents = await FileService.instance.getFilesContent(paths);
  
  // 计算总token数
  int totalTokens = 0;
  for (var file in fileContents) {
    totalTokens += ApiService.estimateTokens(file.content);
  }
  totalTokens += ApiService.estimateTokens(message);
  totalTokens += ApiService.estimateTokens(widget.directoryTree);

  // 检查是否超过90万token
  bool exceedsLimit = totalTokens > AppConfig.maxTokens;
  String warningText = exceedsLimit ? '\n\n【已超过900K】' : '';
  
  // 构建显示内容（简短版）
  String displayContent = '【申请${_subConversation.levelName}子界面】\n$message\n\n【文件目录】\n${widget.directoryTree}$warningText';
  
  if (fileContents.isEmpty) {
    // 没有找到文件
    String fullContent = '$displayContent\n\n【注意】未找到请求的文件';
    await _sendSystemMessage(
      displayContent: displayContent,
      fullContent: fullContent,
      embeddedFiles: [],
    );
  } else if (!exceedsLimit) {
    // 未超过限制，一次性发送所有文件
    String fullContent = displayContent + '\n\n【文件内容】\n';
    for (var file in fileContents) {
      fullContent += '--- ${file.path} ---\n${file.content}\n\n';
    }
    
    List<EmbeddedFile> embeddedFiles = fileContents
        .map((f) => EmbeddedFile(path: f.path, content: f.content, size: f.size))
        .toList();

    await _sendSystemMessage(
      displayContent: displayContent,
      fullContent: fullContent,
      embeddedFiles: embeddedFiles,
    );
  } else {
    // 超过限制，需要分批发送
    await _sendFilesInChunks(displayContent, fileContents, warningText);
  }
}

Future<void> _sendFilesInChunks(String baseContent, List<FileContent> files, String warningText) async {
  int sentTokens = 0;
  int totalTokens = files.fold<int>(0, (sum, f) => sum + ApiService.estimateTokens(f.content));
  
  List<FileContent> currentBatch = [];
  int currentBatchTokens = 0;

  for (var file in files) {
    int fileTokens = ApiService.estimateTokens(file.content);
    
    if (fileTokens > AppConfig.maxTokens) {
      // 单个文件过大，需要分割
      if (currentBatch.isNotEmpty) {
        await _sendBatch(baseContent, currentBatch, sentTokens, totalTokens, warningText);
        sentTokens += currentBatchTokens;
        currentBatch = [];
        currentBatchTokens = 0;
      }
      await _sendLargeFile(baseContent, file, sentTokens, totalTokens, warningText);
      sentTokens += fileTokens;
    } else if (currentBatchTokens + fileTokens > AppConfig.maxTokens) {
      // 当前批次已满，发送
      await _sendBatch(baseContent, currentBatch, sentTokens, totalTokens, warningText);
      sentTokens += currentBatchTokens;
      currentBatch = [file];
      currentBatchTokens = fileTokens;
    } else {
      currentBatch.add(file);
      currentBatchTokens += fileTokens;
    }
  }

  // 发送剩余的
  if (currentBatch.isNotEmpty) {
    await _sendBatch(baseContent, currentBatch, sentTokens, totalTokens, warningText);
  }
}

Future<void> _sendBatch(String baseContent, List<FileContent> batch, int sentTokens, int totalTokens, String warningText) async {
  int batchTokens = batch.fold<int>(0, (sum, f) => sum + ApiService.estimateTokens(f.content));
  int newSentTokens = sentTokens + batchTokens;
  int percentage = ((newSentTokens / totalTokens) * 100).round();

  String displayContent = '$baseContent\n\n本次发送 $percentage%$warningText';
  String fullContent = '$baseContent\n\n【文件内容】\n';
  for (var file in batch) {
    fullContent += '--- ${file.path} ---\n${file.content}\n\n';
  }
  fullContent += '\n本次文件已发送$percentage%$warningText';

  List<EmbeddedFile> embeddedFiles = batch
      .map((f) => EmbeddedFile(path: f.path, content: f.content, size: f.size))
      .toList();

  await _sendSystemMessage(
    displayContent: displayContent,
    fullContent: fullContent,
    embeddedFiles: embeddedFiles,
  );

  if (percentage < 100) {
    await _waitForContinue();
  }
}

Future<void> _sendLargeFile(String baseContent, FileContent file, int sentTokens, int totalTokens, String warningText) async {
  // 按token限制分割文件内容
  final chunks = _splitContentByTokens(file.content, AppConfig.maxTokens);
  int chunksSent = 0;
  int fileTokens = ApiService.estimateTokens(file.content);

  for (var chunk in chunks) {
    chunksSent++;
    int chunkTokens = ApiService.estimateTokens(chunk);
    int overallPercentage = (((sentTokens + (fileTokens * chunksSent / chunks.length)) / totalTokens) * 100).round();

    String displayContent = '$baseContent\n\n${file.path} (第$chunksSent/${chunks.length}部分) $overallPercentage%$warningText';
    String fullContent = '$baseContent\n\n【文件内容 - ${file.path} (第$chunksSent/${chunks.length}部分)】\n$chunk';
    fullContent += '\n\n本次文件已发送$overallPercentage%$warningText';

    await _sendSystemMessage(
      displayContent: displayContent,
      fullContent: fullContent,
      embeddedFiles: [EmbeddedFile(path: '${file.path} (第$chunksSent/${chunks.length}部分)', content: chunk, size: chunk.length)],
    );

    if (chunksSent < chunks.length) {
      await _waitForContinue();
    }
  }
}

// 按token限制分割内容
List<String> _splitContentByTokens(String content, int maxTokens) {
  List<String> chunks = [];
  final lines = content.split('\n');
  StringBuffer currentChunk = StringBuffer();
  int currentTokens = 0;

  for (var line in lines) {
    int lineTokens = ApiService.estimateTokens(line);
    
    if (lineTokens > maxTokens) {
      // 单行过长，强制分割
      if (currentChunk.isNotEmpty) {
        chunks.add(currentChunk.toString());
        currentChunk.clear();
        currentTokens = 0;
      }
      
      // 按字符分割长行
      int charsPerChunk = maxTokens * 3; // 约3字符/token
      for (int i = 0; i < line.length; i += charsPerChunk) {
        final end = (i + charsPerChunk > line.length) ? line.length : i + charsPerChunk;
        chunks.add(line.substring(i, end));
      }
    } else if (currentTokens + lineTokens > maxTokens) {
      // 当前chunk已满
      chunks.add(currentChunk.toString());
      currentChunk.clear();
      currentChunk.writeln(line);
      currentTokens = lineTokens;
    } else {
      currentChunk.writeln(line);
      currentTokens += lineTokens;
    }
  }

  if (currentChunk.isNotEmpty) {
    chunks.add(currentChunk.toString());
  }

  return chunks;
}

  Future<void> _sendSystemMessage({
  required String displayContent,
  required String fullContent,
  List<EmbeddedFile>? embeddedFiles,
}) async {
  final systemMessage = Message(
    role: MessageRole.user,
    content: displayContent,
    fullContent: fullContent,
    embeddedFiles: embeddedFiles ?? [],
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
  });
  _scrollToBottom();

  final stopwatch = Stopwatch()..start();

  try {
    String fullResponseContent = '';
    
    final result = await ApiService.streamToSubAIWithTokens(
      messages: _subConversation.messages
          .where((m) => m.status != MessageStatus.sending)
          .toList(),
      directoryTree: widget.directoryTree,
      level: _subConversation.level,
      onChunk: (chunk) {
        fullResponseContent += chunk;
        final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
        if (msgIndex != -1) {
          _subConversation.messages[msgIndex] = Message(
            id: aiMessage.id,
            role: MessageRole.assistant,
            content: fullResponseContent,
            timestamp: aiMessage.timestamp,
            status: MessageStatus.sending,
          );
          setState(() {});
          _scrollToBottom();
        }
      },
    );

    stopwatch.stop();

    final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
    if (msgIndex != -1) {
      _subConversation.messages[msgIndex] = Message(
        id: aiMessage.id,
        role: MessageRole.assistant,
        content: result.content,
        timestamp: aiMessage.timestamp,
        status: MessageStatus.sent,
        tokenUsage: TokenUsage(
          promptTokens: result.estimatedPromptTokens,
          completionTokens: result.estimatedCompletionTokens,
          totalTokens: result.estimatedPromptTokens + result.estimatedCompletionTokens,
          duration: stopwatch.elapsedMilliseconds / 1000,
        ),
      );
    }

    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    _scrollToBottom();

    await _handleAIResponse(result.content);

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
    });
  }
  }

  Future<void> _handleAIResponse(String response) async {
    // 检测是否返回上一级
    final returnLevel = _detector.detectReturnRequest(response);
    if (returnLevel == _subConversation.level) {
      // 返回上一级
      if (mounted) {
        Navigator.pop(context, {
          'message': response,
        });
      }
      return;
    }

    // 检测是否申请下一级子界面
    final requestedLevel = _detector.detectSubLevelRequest(response);
    if (requestedLevel == _subConversation.level + 1) {
      final paths = _detector.extractPaths(response);
      await _navigateToNextLevel(response, paths);
    }
  }

  Future<void> _navigateToNextLevel(String message, List<String> paths) async {
    // 创建下一级子会话
    final nextSubConv = await SubConversationService.instance.create(
      parentId: _subConversation.id,
      rootConversationId: _subConversation.rootConversationId,
      level: _subConversation.level + 1,
    );

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => SubChatScreen(
          subConversation: nextSubConv,
          initialMessage: message,
          requestedPaths: paths,
          directoryTree: widget.directoryTree,
        ),
      ),
    );

    // 处理下级返回的消息
    if (result != null && result['message'] != null && result['message'].isNotEmpty) {
      await _handleReturnFromChild(result['message']);
    }
    
    setState(() {});
  }

  Future<void> _handleReturnFromChild(String message) async {
    // 作为AI消息添加
    final returnMessage = Message(
      role: MessageRole.assistant,
      content: message,
      status: MessageStatus.sent,
    );
    _subConversation.messages.add(returnMessage);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    _scrollToBottom();

    // 继续检测这条消息
    await _handleAIResponse(message);
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
        level: _subConversation.level,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_subConversation.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, null),
        ),
        actions: [
          // 显示当前级别
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _subConversation.levelName,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _subConversation.messages.isEmpty
                ? Center(
                    child: widget.isResuming
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 48, color: colorScheme.outline),
                              const SizedBox(height: 16),
                              Text('会话已恢复', style: TextStyle(color: colorScheme.outline)),
                            ],
                          )
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
