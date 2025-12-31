// Lib/screens/sub_chat_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';


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
  final MessageDetector _detector = MessageDetector();
  
  // scrollable_positioned_list 控制器
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  
  late SubConversation _subConversation;
  bool _isLoading = false;
  bool _stopRequested = false;
  
  bool _showScrollButtons = false;
  bool _isNearBottom = true;
  Timer? _hideButtonsTimer;
  
  // 流式消息专用
  final ValueNotifier<String> _streamingContent = ValueNotifier('');
  String? _streamingMessageId;
  
  DateTime _lastUIUpdate = DateTime.now();
  static const Duration _uiUpdateInterval = Duration(milliseconds: 200);


  @override
  void initState() {
    super.initState();
    _subConversation = widget.subConversation;
    _itemPositionsListener.itemPositions.addListener(_onPositionsChange);
    
    if (!widget.isResuming && widget.requestedPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeChat();
      });
    }
  }

  void _onPositionsChange() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    
    final lastIndex = _subConversation.messages.length - 1;
    final isLastVisible = positions.any((pos) => pos.index == lastIndex);
    
    if (isLastVisible != _isNearBottom) {
      setState(() => _isNearBottom = isLastVisible);
    }
    
    setState(() => _showScrollButtons = true);
    
    _hideButtonsTimer?.cancel();
    _hideButtonsTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showScrollButtons = false);
    });
  }

  @override
  void dispose() {
    _hideButtonsTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onPositionsChange);
    _streamingContent.dispose();
    super.dispose();
  }


  void _scrollToBottom() {
    if (!_isNearBottom) return;
    _performScrollToBottom();
  }

  void _performScrollToBottom() {
    if (_subConversation.messages.isEmpty) return;
    if (!_itemScrollController.isAttached) return;
    
    final lastIndex = _subConversation.messages.length - 1;
    _itemScrollController.jumpTo(index: lastIndex, alignment: 0.0);
  }

  void _ensureScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _forceScrollToBottom();
    });
  }

  void _scrollToTop() {
    if (!_itemScrollController.isAttached) return;
    _itemScrollController.jumpTo(index: 0, alignment: 0.0);
  }

  void _forceScrollToBottom() {
    if (_subConversation.messages.isEmpty) return;
    if (!_itemScrollController.isAttached) return;
    
    setState(() => _isNearBottom = true);
    final lastIndex = _subConversation.messages.length - 1;
    _itemScrollController.jumpTo(index: lastIndex, alignment: 0.0);
  }

  void _scrollToPreviousMessage() {
    if (_subConversation.messages.isEmpty) return;
    if (!_itemScrollController.isAttached) return;
    
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    
    final firstVisible = positions.reduce((a, b) => a.index < b.index ? a : b);
    final targetIndex = (firstVisible.index - 1).clamp(0, _subConversation.messages.length - 1);
    
    _itemScrollController.scrollTo(
      index: targetIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.0,
    );
  }

  void _scrollToNextMessage() {
    if (_subConversation.messages.isEmpty) return;
    if (!_itemScrollController.isAttached) return;
    
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    
    final lastVisible = positions.reduce((a, b) => a.index > b.index ? a : b);
    final targetIndex = (lastVisible.index + 1).clamp(0, _subConversation.messages.length - 1);
    
    _itemScrollController.scrollTo(
      index: targetIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.0,
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
    _scrollController.animateTo(targetOffset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
    
    // 不再添加目录附件，只后台打包发送
    List<EmbeddedFile> embeddedFiles = [];
    
    if (fileContents.isEmpty) {
      fullContent += '\n\n【注意】未找到请求的文件';

      await _sendSystemMessage(displayContent: displayContent, fullContent: fullContent, embeddedFiles: embeddedFiles);
    } else if (!exceedsLimit) {
      fullContent += '\n\n【文件内容】\n';
      for (var file in fileContents) {
        fullContent += '--- ${file.path} ---\n${file.content}\n\n';
        embeddedFiles.add(EmbeddedFile(path: file.path, content: file.content, size: file.size));
      }
      await _sendSystemMessage(displayContent: displayContent, fullContent: fullContent, embeddedFiles: embeddedFiles);
    } else {
      await _sendFilesInChunks(displayContent, fullContent, fileContents, warningText, embeddedFiles);
    }
  }

  Future<void> _sendFilesInChunks(String baseDisplayContent, String baseFullContent, List<FileContent> files, String warningText, List<EmbeddedFile> baseEmbeddedFiles) async {
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

  Future<void> _sendBatch(String baseDisplayContent, String baseFullContent, List<FileContent> batch, int sentTokens, int totalTokens, String warningText, List<EmbeddedFile> baseEmbeddedFiles) async {
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

    await _sendSystemMessage(displayContent: displayContent, fullContent: fullContent, embeddedFiles: embeddedFiles);
    if (percentage < 100) await _waitForContinue();
  }

  Future<void> _sendLargeFile(String baseDisplayContent, String baseFullContent, FileContent file, int sentTokens, int totalTokens, String warningText, List<EmbeddedFile> baseEmbeddedFiles) async {
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
      embeddedFiles.add(EmbeddedFile(path: '${file.path} (第$chunksSent/${chunks.length}部分)', content: chunk, size: chunk.length));

      await _sendSystemMessage(displayContent: displayContent, fullContent: fullContent, embeddedFiles: embeddedFiles);
      if (chunksSent < chunks.length) await _waitForContinue();
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
    if (currentChunk.isNotEmpty) chunks.add(currentChunk.toString());
    return chunks;
  }

  Future<void> _waitForContinue() async {
    int attempts = 0;
    while (attempts < 60) {
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
      if (_subConversation.messages.isNotEmpty) {
        final lastMessage = _subConversation.messages.last;
        if (lastMessage.role == MessageRole.assistant && lastMessage.status == MessageStatus.sent && lastMessage.content.contains('【请继续】')) {
          break;
        }
      }
    }
  }

  Future<void> _sendSystemMessage({required String displayContent, required String fullContent, List<EmbeddedFile>? embeddedFiles}) async {
    final systemMessage = Message(role: MessageRole.user, content: displayContent, fullContent: fullContent, embeddedFiles: embeddedFiles ?? [], status: MessageStatus.sent);
    _subConversation.messages.add(systemMessage);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    _scrollToBottom();
    await _requestAIResponse();
  }

  void _stopGeneration() {
    _stopRequested = true;
    ApiService.cancelRequest();
    _streamingMessageId = null;
    setState(() => _isLoading = false);
    
    // 更新最后一条消息状态
    if (_subConversation.messages.isNotEmpty) {
      final lastMsg = _subConversation.messages.last;
      if (lastMsg.role == MessageRole.assistant && lastMsg.status == MessageStatus.sending) {
        final content = _streamingContent.value;
        final msgIndex = _subConversation.messages.indexWhere((m) => m.id == lastMsg.id);
        if (msgIndex != -1) {
          if (content.isNotEmpty) {
            // 有内容，更新为已停止
            _subConversation.messages[msgIndex] = Message(
              id: lastMsg.id,
              role: MessageRole.assistant,
              content: '$content\n\n[已停止生成]',
              timestamp: lastMsg.timestamp,
              status: MessageStatus.sent,
            );
            SubConversationService.instance.update(_subConversation);
          } else {
            // 没有内容，直接删除这条消息
            _subConversation.messages.removeAt(msgIndex);
            SubConversationService.instance.update(_subConversation);
          }
        }
      }
    }
    setState(() {});
  }


  Future<void> _requestAIResponse() async {

    _stopRequested = false;
    final aiMessage = Message(role: MessageRole.assistant, content: '', status: MessageStatus.sending);
    _subConversation.messages.add(aiMessage);
    _streamingMessageId = aiMessage.id;
    _streamingContent.value = '';
    setState(() => _isLoading = true);
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();

    try {
      String fullResponseContent = '';
      
      final result = await ApiService.streamToSubAIWithTokens(
        messages: _subConversation.messages.where((m) => m.status != MessageStatus.sending).toList(),
        directoryTree: widget.directoryTree,
        level: _subConversation.level,
        onChunk: (chunk) {
          fullResponseContent += chunk;
          final now = DateTime.now();
          if (now.difference(_lastUIUpdate) >= _uiUpdateInterval) {
            _lastUIUpdate = now;
            _streamingContent.value = fullResponseContent;
            _scrollToBottom();
          }
        },
      );

      stopwatch.stop();
      _streamingMessageId = null;

      final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _subConversation.messages[msgIndex] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: result.content,
          timestamp: aiMessage.timestamp,
          status: MessageStatus.sent,
          tokenUsage: TokenUsage(
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            totalTokens: result.promptTokens + result.completionTokens,
            duration: stopwatch.elapsedMilliseconds / 1000,
          ),
        );
      }
      await SubConversationService.instance.update(_subConversation);

      setState(() {});
      _ensureScrollToBottom();  // 使用校正方法
      await _handleAIResponse(result.content);

    } catch (e) {
      // 如果是主动停止，不显示错误
      if (_stopRequested) {

        _streamingMessageId = null;
        setState(() {});
        return;
      }
      
      _streamingMessageId = null;
      final msgIndex = _subConversation.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _subConversation.messages[msgIndex] = Message(id: aiMessage.id, role: MessageRole.assistant, content: '发送失败: $e', timestamp: aiMessage.timestamp, status: MessageStatus.error);
      }
      await SubConversationService.instance.update(_subConversation);
      setState(() {});
    } finally {
      setState(() => _isLoading = false);
    }

  }

  Future<void> _handleAIResponse(String response) async {
    final returnLevel = _detector.detectReturnRequest(response);
    if (returnLevel == _subConversation.level) {
      if (mounted) Navigator.pop(context, {'message': response});
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
    final returnMessage = Message(role: MessageRole.assistant, content: message, status: MessageStatus.sent);
    _subConversation.messages.add(returnMessage);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    _scrollToBottom();
    await _handleAIResponse(message);
  }

  Future<void> _sendMessage(String text, List<FileAttachment> attachments) async {
    if (text.isEmpty && attachments.isEmpty) return;
    final userMessage = Message(role: MessageRole.user, content: text, attachments: attachments, status: MessageStatus.sent);
    _subConversation.messages.add(userMessage);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
    _scrollToBottom();
    await _requestAIResponse();
  }

  Future<void> _deleteMessage(int index) async {
    _subConversation.messages.removeAt(index);
    await SubConversationService.instance.update(_subConversation);
    setState(() {});
  }


  Future<void> _editMessage(int index) async {
    final message = _subConversation.messages[index];
    if (message.role != MessageRole.user) return;
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _SubEditMessageDialog(
        initialContent: message.content,
        attachments: List.from(message.attachments),
        embeddedFiles: List.from(message.embeddedFiles),
      ),
    );
    
    if (result != null) {
      final newContent = result['content'] as String;
      final newAttachments = result['attachments'] as List<FileAttachment>;
      final newEmbeddedFiles = result['embeddedFiles'] as List<EmbeddedFile>;
      final shouldResend = result['resend'] as bool;
      
      if (shouldResend) {
        // 删除该消息及之后的所有消息
        while (_subConversation.messages.length > index) {
          _subConversation.messages.removeLast();
        }

        
        // 添加编辑后的消息
        final editedMessage = Message(
          role: MessageRole.user,
          content: newContent,
          fullContent: message.fullContent,
          attachments: newAttachments,
          embeddedFiles: newEmbeddedFiles,
          status: MessageStatus.sent,
        );
        _subConversation.messages.add(editedMessage);
        await SubConversationService.instance.update(_subConversation);
        setState(() {});
        _scrollToBottom();
        await _requestAIResponse();
      } else {
        // 仅保存
        final msgIndex = _subConversation.messages.indexWhere((m) => m.id == message.id);
        if (msgIndex != -1) {
          _subConversation.messages[msgIndex] = Message(
            id: message.id,
            role: MessageRole.user,
            content: newContent,
            fullContent: message.fullContent,
            timestamp: message.timestamp,
            attachments: newAttachments,
            embeddedFiles: newEmbeddedFiles,
            status: MessageStatus.sent,
          );
          await SubConversationService.instance.update(_subConversation);
          setState(() {});
        }
      }
    }
  }


  Future<void> _regenerateMessage(int aiMessageIndex) async {
    _subConversation.messages.removeAt(aiMessageIndex);
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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context, null)),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Text(_subConversation.levelName, style: TextStyle(fontSize: 12, color: colorScheme.onSecondaryContainer)),
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
                            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history, size: 48, color: colorScheme.outline), const SizedBox(height: 16), Text('会话已恢复', style: TextStyle(color: colorScheme.outline))])
                            : const CircularProgressIndicator(),
                      )
                    : ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _itemPositionsListener,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          itemCount: _subConversation.messages.length,
                          itemBuilder: (context, index) {
                            final message = _subConversation.messages[index];
                            
                            if (message.id == _streamingMessageId) {
                              return ValueListenableBuilder<String>(
                                valueListenable: _streamingContent,
                                builder: (context, content, _) {
                                  final streamingMsg = Message(
                                    id: message.id,
                                    role: MessageRole.assistant,
                                    content: content,
                                    timestamp: message.timestamp,
                                    status: MessageStatus.sending,
                                  );
                                  return MessageBubble(message: streamingMsg);
                                },
                              );
                            }
                            
                            return MessageBubble(
                              message: message,
                              onRetry: message.status == MessageStatus.error ? () => _sendMessage(message.content, message.attachments) : null,
                              onDelete: () => _deleteMessage(index),
                              onRegenerate: message.role == MessageRole.assistant && message.status == MessageStatus.sent ? () => _regenerateMessage(index) : null,
                              onEdit: message.role == MessageRole.user && message.status == MessageStatus.sent ? () => _editMessage(index) : null,
                            );
                          },
                        ),

                          itemCount: _subConversation.messages.length,
                          itemBuilder: (context, index) {
                            _messageKeys[index] ??= GlobalKey();
                            final message = _subConversation.messages[index];
                            
                            if (message.id == _streamingMessageId) {
                              return Container(
                                key: _messageKeys[index],
                                child: ValueListenableBuilder<String>(
                                  valueListenable: _streamingContent,
                                  builder: (context, content, _) {
                                    final streamingMsg = Message(id: message.id, role: MessageRole.assistant, content: content, timestamp: message.timestamp, status: MessageStatus.sending);
                                    return MessageBubble(message: streamingMsg);
                                  },
                                ),
                              );
                            }
                            
                            return Container(
                              key: _messageKeys[index],
                              child: MessageBubble(
                                message: message,
                                onRetry: message.status == MessageStatus.error ? () => _sendMessage(message.content, message.attachments) : null,
                                onDelete: () => _deleteMessage(index),
                                onRegenerate: message.role == MessageRole.assistant && message.status == MessageStatus.sent ? () => _regenerateMessage(index) : null,
                                onEdit: message.role == MessageRole.user && message.status == MessageStatus.sent ? () => _editMessage(index) : null,
                              ),
                            );
                          },
                        ),
                      ),
              ),
              ChatInput(onSend: _sendMessage, enabled: !_isLoading, isGenerating: _isLoading, onStop: _stopGeneration),

            ],
          ),
          if (_showScrollButtons && hasMessages)
            Positioned(
              right: 12,
              top: 0,
              bottom: 80,
              child: Center(
                child: ScrollButtons(
                  onScrollToTop: _scrollToTop,
                  onScrollToBottom: _forceScrollToBottom,
                  onPreviousMessage: _scrollToPreviousMessage,
                  onNextMessage: _scrollToNextMessage,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 子界面编辑消息对话框

class _SubEditMessageDialog extends StatefulWidget {
  final String initialContent;
  final List<FileAttachment> attachments;
  final List<EmbeddedFile> embeddedFiles;

  const _SubEditMessageDialog({
    required this.initialContent,
    required this.attachments,
    required this.embeddedFiles,
  });

  @override
  State<_SubEditMessageDialog> createState() => _SubEditMessageDialogState();
}

class _SubEditMessageDialogState extends State<_SubEditMessageDialog> {
  late TextEditingController _controller;
  late List<FileAttachment> _attachments;
  late List<EmbeddedFile> _embeddedFiles;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _attachments = List.from(widget.attachments);
    _embeddedFiles = List.from(widget.embeddedFiles);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null) {
      for (var file in result.files) {
        if (file.path != null) {
          final fileInfo = File(file.path!);
          final mimeType = _getMimeType(file.name);
          
          String? content;
          if (_isTextFile(file.name, mimeType)) {
            try {
              content = await fileInfo.readAsString();
            } catch (e) {}
          }

          setState(() {
            _attachments.add(FileAttachment(
              name: file.name,
              path: file.path!,
              mimeType: mimeType,
              size: file.size,
              content: content,
            ));
          });
        }
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    
    for (var image in images) {
      final file = File(image.path);
      final mimeType = _getMimeType(image.name);
      
      setState(() {
        _attachments.add(FileAttachment(
          name: image.name,
          path: image.path,
          mimeType: mimeType,
          size: file.lengthSync(),
        ));
      });
    }
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    final mimeTypes = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
      'dart': 'text/x-dart', 'js': 'text/javascript', 'json': 'application/json',
      'xml': 'application/xml', 'yaml': 'text/yaml', 'yml': 'text/yaml',
      'md': 'text/markdown', 'txt': 'text/plain', 'html': 'text/html',
      'css': 'text/css', 'py': 'text/x-python', 'java': 'text/x-java',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }

  bool _isTextFile(String fileName, String mimeType) {
    if (mimeType.startsWith('text/') || mimeType.contains('json') || mimeType.contains('xml')) {
      return true;
    }
    final textExtensions = ['.dart', '.js', '.ts', '.py', '.java', '.c', '.cpp', '.h', '.go', '.rs', '.rb', '.php', '.sh', '.sql', '.md', '.txt', '.yaml', '.yml', '.json', '.xml', '.html', '.css'];
    return textExtensions.any((e) => fileName.toLowerCase().endsWith(e));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return AlertDialog(

      title: const Text('编辑消息'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                maxLines: null,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: '输入消息内容...',
                  border: OutlineInputBorder(),
                ),
              ),
              
              if (_attachments.any((a) => a.mimeType.startsWith('image/'))) ...[
                const SizedBox(height: 16),
                Text('图片', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _attachments
                      .where((a) => a.mimeType.startsWith('image/'))
                      .map((att) => _buildImageThumbnail(att))
                      .toList(),
                ),
              ],
              
              if (_attachments.any((a) => !a.mimeType.startsWith('image/'))) ...[
                const SizedBox(height: 16),
                Text('文件', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _attachments
                      .where((a) => !a.mimeType.startsWith('image/'))
                      .map((att) => _buildFileChip(att))
                      .toList(),
                ),
              ],
              
              if (_embeddedFiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('内嵌文件', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _embeddedFiles
                      .map((f) => _buildEmbeddedFileChip(f))
                      .toList(),
                ),
              ],
              
              // 添加附件按钮
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFiles,
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: const Text('添加文件'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image, size: 18),
                      label: const Text('添加图片'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context, {
              'content': _controller.text.trim(),
              'attachments': _attachments,
              'embeddedFiles': _embeddedFiles,
              'resend': false,
            });
          },
          child: const Text('仅保存'),
        ),

        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'content': _controller.text.trim(),
              'attachments': _attachments,
              'embeddedFiles': _embeddedFiles,
              'resend': true,
            });
          },
          child: const Text('保存并重发'),
        ),
      ],
    );
  }

  Widget _buildImageThumbnail(FileAttachment att) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(att.path),
            width: 60,
            height: 75,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, stack) => Container(
              width: 60,
              height: 75,
              color: Colors.grey[300],
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: () => setState(() => _attachments.remove(att)),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileChip(FileAttachment att) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              att.name,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _attachments.remove(att)),
            child: Icon(Icons.close, size: 16, color: colorScheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbeddedFileChip(EmbeddedFile file) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.code, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              file.fileName,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _embeddedFiles.remove(file)),
            child: Icon(Icons.close, size: 16, color: colorScheme.error),
          ),
        ],
      ),
    );
  }
}

