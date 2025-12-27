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
    
    // 构建显示内容（简短版）
    String displayContent = '【申请${_subConversation.levelName}子界面】\n$message\n\n【文件目录】\n${widget.directoryTree}';
    
    // 构建完整内容（发送给API）
    String fullContent = displayContent;
    if (fileContents.isNotEmpty) {
      fullContent += '\n\n【文件内容】\n';
      for (var file in fileContents) {
        fullContent += '--- ${file.path} ---\n${file.content}\n\n';
      }
    } else {
      fullContent += '\n\n【注意】未找到请求的文件';
    }

    // 创建内嵌文件列表
    List<EmbeddedFile> embeddedFiles = fileContents
        .map((f) => EmbeddedFile(path: f.path, content: f.content, size: f.size))
        .toList();

    await _sendSystemMessage(
      displayContent: displayContent,
      fullContent: fullContent,
      embeddedFiles: embeddedFiles,
    );
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
