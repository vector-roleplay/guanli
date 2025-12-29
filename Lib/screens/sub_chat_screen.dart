// Lib/screens/sub_chat_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/sub_conversation.dart';
import '../services/api_service.dart';
import '../services/file_service.dart';
import '../services/sub_conversation_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/scroll_buttons.dart';
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
  
  bool _userScrolling = false;
  bool _showScrollButtons = false;
  bool _isNearBottom = true;
  Timer? _hideButtonsTimer;
  
  final Map<int, GlobalKey> _messageKeys = {};
  
  // 节流控制
  DateTime _lastUIUpdate = DateTime.now();
  static const Duration _uiUpdateInterval = Duration(milliseconds: 100);
  String _pendingContent = '';

  @override
  void initState() {
    super.initState();
    _subConversation = widget.subConversation;
    _scrollController.addListener(_onScroll);
    
    if (!widget.isResuming && widget.requestedPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeChat();
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final nearBottom = (maxScroll - currentScroll) < 50;
    
    if (nearBottom != _isNearBottom) {
      setState(() {
        _isNearBottom = nearBottom;
      });
    }
    
    setState(() {
      _showScrollButtons = true;
    });
    
    _hideButtonsTimer?.cancel();
    _hideButtonsTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showScrollButtons = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _hideButtonsTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_userScrolling || !_isNearBottom) return;
    
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

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _forceScrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      setState(() {
        _isNearBottom = true;
      });
    }
  }

  void _scrollToPreviousMessage() {
    if (!_scrollController.hasClients) return;
    
    final currentOffset = _scrollController.offset;
    double targetOffset = 0;
    
    for (int i = _subConversation.messages.length - 1; i >= 0; i--) {
      final key = _messageKeys[i];
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final scrollPosition = _scrollController.offset + position.dy - 100;
          if (scrollPosition < currentOffset - 10) {
            targetOffset = scrollPosition.clamp(0.0, _scrollController.position.maxScrollExtent);
            break;
          }
        }
      }
    }
    
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollToNextMessage() {
    if (!_scrollController.hasClients) return;
    
    final currentOffset = _scrollController.offset;
    double targetOffset = _scrollController.position.maxScrollExtent;
    
    for (int i = 0; i < _subConversation.messages.length; i++) {
      final key = _messageKeys[i];
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final scrollPosition = _scrollController.offset + position.dy - 100;
          if (scrollPosition > currentOffset + 10) {
            targetOffset = scrollPosition.clamp(0.0, _scrollController.position.maxScrollExtent);
            break;
          }
        }
      }
    }
    
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _initializeChat() async {
    await _sendFilesWithMessage(widget.initialMessage, widget.requestedPaths);
  }

  Future<void> _sendFilesWithMessage(String message, List<String> paths) async {
    final fileContents = await FileService.instance.getFilesContent(paths);
    
    int totalTokens = 0;
    for (var file in fileContents) {
      totalTokens += ApiService.estimateTokens(file.content);
    }
    totalTokens += ApiService.estimateTokens(message);
    totalTokens += ApiService.estimateTokens(widget.directoryTree);

    bool exceedsLimit = totalTokens > AppConfig.maxTokens;
    String warningText = exceedsLimit ? '\n\n【已超过900K】' : '';
    
    String displayContent = '【申请${_subConversation.levelName}子界面】\n$message$warningText';
    String fullContent = '【申请${_subConversation.levelName}子界面】\n$message\n\n【文件目录】\n${widget.directoryTree}$warningText';
    
    List<EmbeddedFile> embeddedFiles = [];
    
    embeddedFiles.add(EmbeddedFile(
      path: '📁 文件目录.txt',
      content: widget.directoryTree,
      size: widget.directoryTree.length,
    ));
    
    if (fileContents.isEmpty) {
      fullContent += '\n\n【注意】未找到请求的文件';
      await _sendSystemMessage(
        displayContent: displayContent,
        fullContent: fullContent,
        embeddedFiles: embeddedFiles,
      );
    } else if (!exceedsLimit) {
      fullContent += '\n\n【文件内容】\n';
      for (var file in fileContents) {
        fullContent += '--- ${file.path} ---\n${file.content}\n\n';
        embeddedFiles.add(EmbeddedFile(path: file.path, content: file.content, size: file.size));
      }

      await _sendSystemMessage(
        displayContent: displayContent,
        fullContent: fullContent,
        embeddedFiles: embeddedFiles,
      );
    } else {
      await _sendFilesInChunks(displayContent, fullContent, fileContents, warningText, embeddedFiles);
    }
  }

  Future<void> _sendFilesInChunks(
    String baseDisplayContent,
    String baseFullContent,
    List<FileContent> files,
    String warningText,
    List<EmbeddedFile> baseEmbeddedFiles,
  ) async {
    int sentTokens = 0;
    int totalTokens = files.fold<int>(0, (sum, f) => sum + ApiService.estimateTokens(f.content));
    
    List<FileContent> currentBatch = [];
    int currentBatchTokens = 0;

    for (var file in files) {
      int fileTokens = ApiService.estimateTokens(file.content);
      
      if (fileTokens > AppConfig.maxTokens) {
        if (currentBatch.isNotEmpty) {
          await _sendBatch(baseDisplayContent, baseFullContent, currentBatch, sentTokens, totalTokens, warningText, baseEmbeddedFiles);
          sentTokens += currentBatchTokens;
          currentBatch = [];
          currentBatchTokens = 0;
        }
        await _sendLargeFile(baseDisplayContent, baseFullContent, file, sentTokens, totalTokens, warningText, baseEmbeddedFiles);
        sentTokens += fileTokens;
      } else if (currentBatchTokens + fileTokens > AppConfig.maxTokens) {
        await _sendBatch(baseDisplayContent, baseFullContent, currentBatch, sentTokens, totalTokens, warningText, baseEmbeddedFiles);
        sentTokens += currentBatchTokens;
        currentBatch = [file];
        currentBatchTokens = fileTokens;
      } else {
        currentBatch.add(file);
        currentBatchTokens += fileTokens;
      }
    }

    if (currentBatch.isNotEmpty) {
      await _sendBatch(baseDisplayContent, baseFullContent, currentBatch, sentTokens, totalTokens, warningText, baseEmbeddedFiles);
    }
  }

  Future<void> _sendBatch(
    String baseDisplayContent,
    String baseFullContent,
    List<FileContent> batch,
    int sentTokens,
    int totalTokens,
    String warningText,
    List<EmbeddedFile> baseEmbeddedFiles,
  ) async {
    int batchTokens = batch.fold<int>(0, (sum, f) => sum + ApiService.estimateTokens(f.content));
    int newSentTokens = sentTokens + batchTokens;
    int percentage = ((newSentTokens / totalTokens) * 100).round();

    String displayContent = '$baseDisplayContent\n\n本次发送 $percentage%';
    String fullContent = '$baseFullContent\n\n【文件内容】\n';
    for (var file in batch) {
      fullContent += '--- ${file.path} ---\n${file.content}\n\n';
    }
    fullContent += '\n本次文件已发送$percentage%$warningText';

    List<EmbeddedFile> embeddedFiles = List.from(baseEmbeddedFiles);
    for (var file in batch) {
      embeddedFiles.add(EmbeddedFile(path: file.path, content: file.content, size: file.size));
    }

    await _sendSystemMessage(
      displayContent: displayContent,
      fullContent: fullContent,
      embeddedFiles: embeddedFiles,
    );

    if (percentage < 100) {
      await _waitForContinue();
    }
  }

  Future<void> _sendLargeFile(
    String baseDisplayContent,
    String baseFullContent,
    FileContent file,
    int sentTokens,
    int totalTokens,
    String warningText,
    List<EmbeddedFile> baseEmbeddedFiles,
  ) async {
    final chunks = _splitContentByTokens(file.content, AppConfig.maxTokens);
    int chunksSent = 0;
    int fileTokens = ApiService.estimateTokens(file.content);

    for (var chunk in chunks) {
      chunksSent++;
      int overallPercentage = (((sentTokens + (fileTokens * chunksSent / chunks.length)) / totalTokens) * 100).round();

      String displayContent = '$baseDisplayContent\n\n${file.path} (第$chunksSent/${chunks.length}部分) $overallPercentage%';
      String fullContent = '$baseFullContent\n\n【文件内容 - ${file.path} (第$chunksSent/${chunks.length}部分)】\n$chunk';
      fullContent += '\n\n本次文件已发送$overallPercentage%$warningText';

      List<EmbeddedFile> embeddedFiles = List.from(baseEmbeddedFiles);
      embeddedFiles.add(EmbeddedFile(
        path: '${file.path} (第$chunksSent/${chunks.length}部分)',
        content: chunk,
        size: chunk.length,
      ));

      await _sendSystemMessage(
        displayContent: displayContent,
        fullContent: fullContent,
        embeddedFiles: embeddedFiles,
      );

      if (chunksSent < chunks.length) {
        await _waitForContinue();
      }
    }
  }

  List<String> _splitContentByTokens(String content, int maxTokens) {
    List<String> chunks = [];
    final lines = content.split('\n');
    StringBuffer currentChunk = StringBuffer();
    int currentTokens = 0;

    for (var line in lines) {
      int lineTokens = ApiService.estimateTokens(line);
      
      if (lineTokens > maxTokens) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.toString());
          currentChunk.clear();
          currentTokens = 0;
        }
        
        int charsPerChunk = maxTokens * 3;
        for (int i = 0; i < line.length; i += charsPerChunk) {
          final end = (i + charsPerChunk > line.length) ? line.length : i + charsPerChunk;
          chunks.add(line.substring(i, end));
        }
      } else if (currentTokens + lineTokens > maxTokens) {
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

  Future<void> _waitForContinue() async {
    int attempts = 0;
    while (attempts < 60) {
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

    await _requestAIResponse();
  }

  Future<void> _requestAIResponse() async {
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
          _pendingContent = fullResponseContent;
          
          // 节流：100ms 更新一次 UI
          final now = DateTime.now();
          if (now.difference(_lastUIUpdate) >= _uiUpdateInterval) {
            _lastUIUpdate = now;
            final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
            if (msgIndex != -1) {
              _subConversation.messages[msgIndex] = Message(
                id: aiMessage.id,
                role: MessageRole.assistant,
                content: _pendingContent,
                timestamp: aiMessage.timestamp,
                status: MessageStatus.sending,
              );
              setState(() {});
              _scrollToBottom();
            }
          }
        },
      );
      
      // 确保最后一次更新
      final msgIndexFinal = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndexFinal != -1 && _pendingContent.isNotEmpty) {
        _subConversation.messages[msgIndexFinal] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: _pendingContent,
          timestamp: aiMessage.timestamp,
          status: MessageStatus.sending,
        );
      }
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
    final returnLevel = _detector.detectReturnRequest(response);
    if (returnLevel == _subConversation.level) {
      if (mounted) {
        Navigator.pop(context, {'message': response});
      }
      return;
    }

    final requestedLevel = _detector.detectSubLevelRequest(response);
    if (requestedLevel == _subConversation.level + 1) {
      final paths = _detector.extractPaths(response);
      await _navigateToNextLevel(response, paths);
    }
  }

  Future<void> _navigateToNextLevel(String message, List<String> paths) async {
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

    if (result != null && result['message'] != null && result['message'].isNotEmpty) {
      await _handleReturnFromChild(result['message']);
    }
    
    setState(() {});
  }

  Future<void> _handleReturnFromChild(String message) async {
    final returnMessage = Message(
      role: MessageRole.assistant,
      content: message,
      status: MessageStatus.sent,
    );
    _subConversation.messages.add(returnMessage);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    _scrollToBottom();

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

    await _requestAIResponse();
  }

  Future<void> _deleteMessage(int index) async {
    _subConversation.messages.removeAt(index);
    _messageKeys.remove(index);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
  }

  Future<void> _regenerateMessage(int aiMessageIndex) async {
    _subConversation.messages.removeAt(aiMessageIndex);
    _messageKeys.remove(aiMessageIndex);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    await _requestAIResponse();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMessages = _subConversation.messages.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_subConversation.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, null),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _subConversation.levelName,
              style: TextStyle(fontSize: 12, color: colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: !hasMessages
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
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollStartNotification) {
                            _userScrolling = true;
                          } else if (notification is ScrollEndNotification) {
                            _userScrolling = false;
                            if (_scrollController.hasClients) {
                              final maxScroll = _scrollController.position.maxScrollExtent;
                              final currentScroll = _scrollController.offset;
                              if ((maxScroll - currentScroll) < 50) {
                                setState(() {
                                  _isNearBottom = true;
                                });
                              }
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          itemCount: _subConversation.messages.length,
                          itemBuilder: (context, index) {
                            _messageKeys[index] ??= GlobalKey();
                            final message = _subConversation.messages[index];
                            return Container(
                              key: _messageKeys[index],
                              child: MessageBubble(
                                message: message,
                                onRetry: message.status == MessageStatus.error
                                    ? () => _sendMessage(message.content, message.attachments)
                                    : null,
                                onDelete: () => _deleteMessage(index),
                                onRegenerate: message.role == MessageRole.assistant && message.status == MessageStatus.sent
                                    ? () => _regenerateMessage(index)
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
              ),
              ChatInput(
                onSend: _sendMessage,
                enabled: !_isLoading,
              ),
            ],
          ),
          if (_showScrollButtons && hasMessages)
            Positioned(
              right: 12,
              bottom: 80,
              child: ScrollButtons(
                onScrollToTop: _scrollToTop,
                onScrollToBottom: _forceScrollToBottom,
                onPreviousMessage: _scrollToPreviousMessage,
                onNextMessage: _scrollToNextMessage,
              ),
            ),
        ],
      ),
    );
  }
}
