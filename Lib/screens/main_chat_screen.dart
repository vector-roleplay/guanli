// Lib/screens/main_chat_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/message.dart';

import '../models/conversation.dart';
import '../models/sub_conversation.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/conversation_service.dart';
import '../services/sub_conversation_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/scroll_buttons.dart';
import '../utils/message_detector.dart';
import 'settings_screen.dart';
import 'database_screen.dart';
import 'sub_chat_screen.dart';

class MainChatScreen extends StatefulWidget {
  const MainChatScreen({super.key});

  @override
  State<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends State<MainChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MessageDetector _detector = MessageDetector();
  
  String _directoryTree = '';
  Conversation? _currentConversation;
  bool _isLoading = false;
  bool _stopRequested = false;
  
  bool _userScrolling = false;
  bool _showScrollButtons = false;
  bool _isNearBottom = true;
  Timer? _hideButtonsTimer;
  final Map<int, GlobalKey> _messageKeys = {};
  
  // 流式消息专用 - 避免整个列表重建
  final ValueNotifier<String> _streamingContent = ValueNotifier('');
  String? _streamingMessageId;
  
  DateTime _lastUIUpdate = DateTime.now();
  static const Duration _uiUpdateInterval = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final nearBottom = (maxScroll - currentScroll) < 50;
    if (nearBottom != _isNearBottom) setState(() => _isNearBottom = nearBottom);
    setState(() => _showScrollButtons = true);
    _hideButtonsTimer?.cancel();
    _hideButtonsTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showScrollButtons = false);
    });
  }

  Future<void> _init() async {
    await _loadDirectoryTree();
    await ConversationService.instance.load();
    await SubConversationService.instance.load();
    if (ConversationService.instance.conversations.isEmpty) {
      await _createNewConversation();
    } else {
      setState(() => _currentConversation = ConversationService.instance.conversations.first);
    }
  }

  @override
  void dispose() {
    _hideButtonsTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _streamingContent.dispose();
    super.dispose();
  }

  Future<void> _loadDirectoryTree() async {
    final tree = await DatabaseService.instance.getDirectoryTree();
    setState(() => _directoryTree = tree);
  }

  Future<void> _createNewConversation() async {
    final conversation = await ConversationService.instance.create();
    setState(() {
      _currentConversation = conversation;
      _messageKeys.clear();
    });
  }

  void _switchConversation(Conversation conversation) {
    setState(() {
      _currentConversation = conversation;
      _messageKeys.clear();
    });
    Navigator.pop(context);
  }

  void _scrollToBottom() {
    if (_userScrolling || !_isNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _forceScrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      setState(() => _isNearBottom = true);
    }
  }

  void _scrollToPreviousMessage() {
    if (!_scrollController.hasClients || _currentConversation == null) return;
    final currentOffset = _scrollController.offset;
    double targetOffset = 0;
    for (int i = _currentConversation!.messages.length - 1; i >= 0; i--) {
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
    _scrollController.animateTo(targetOffset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _scrollToNextMessage() {
    if (!_scrollController.hasClients || _currentConversation == null) return;
    final currentOffset = _scrollController.offset;
    double targetOffset = _scrollController.position.maxScrollExtent;
    for (int i = 0; i < _currentConversation!.messages.length; i++) {
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

  Future<void> _deleteMessage(int index) async {
    if (_currentConversation == null) return;
    _currentConversation!.messages.removeAt(index);
    _messageKeys.remove(index);
    await ConversationService.instance.update(_currentConversation!);
    setState(() {});
  }

  Future<void> _editMessage(int index) async {
    if (_currentConversation == null) return;
    final message = _currentConversation!.messages[index];
    if (message.role != MessageRole.user) return;
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EditMessageDialog(
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
        // 删除该消息及之后的所有消息，重新发送
        while (_currentConversation!.messages.length > index) {
          _currentConversation!.messages.removeLast();
        }
        _messageKeys.clear();
        
        // 添加编辑后的消息
        final editedMessage = Message(
          role: MessageRole.user,
          content: newContent,
          fullContent: message.fullContent,
          attachments: newAttachments,
          embeddedFiles: newEmbeddedFiles,
          status: MessageStatus.sent,
        );
        _currentConversation!.messages.add(editedMessage);
        await ConversationService.instance.update(_currentConversation!);
        setState(() {});
        _scrollToBottom();
        await _sendMessageToAI();
      } else {
        // 仅保存，不重发，不删除后续消息
        final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == message.id);
        if (msgIndex != -1) {
          _currentConversation!.messages[msgIndex] = Message(
            id: message.id,
            role: MessageRole.user,
            content: newContent,
            fullContent: message.fullContent,
            timestamp: message.timestamp,
            attachments: newAttachments,
            embeddedFiles: newEmbeddedFiles,
            status: MessageStatus.sent,
          );
          await ConversationService.instance.update(_currentConversation!);
          setState(() {});
        }
      }
    }
  }


  Future<void> _regenerateMessage(int aiMessageIndex) async {
    if (_currentConversation == null) return;
    _currentConversation!.messages.removeAt(aiMessageIndex);
    _messageKeys.remove(aiMessageIndex);
    await ConversationService.instance.update(_currentConversation!);
    setState(() {});
    await _sendMessageToAI();
  }

  Future<void> _sendAllFiles() async {

    if (_currentConversation == null) return;
    
    // 获取所有根目录（仓库）
    final rootDirs = await DatabaseService.instance.getRootDirectories();
    final allFiles = await DatabaseService.instance.getAllFilesList();
    
    if (allFiles.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数据库中没有文件')));
      return;
    }

    // 显示选择对话框
    final selectedFiles = await _showFileSelectionDialog(rootDirs, allFiles);
    if (selectedFiles == null || selectedFiles.isEmpty) return;

    // 获取选中文件的内容
    List<Map<String, dynamic>> filesToSend = [];
    for (var path in selectedFiles) {
      final file = await DatabaseService.instance.getFileByPath(path);
      if (file != null) {
        filesToSend.add(file);
      }
    }

    if (filesToSend.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('选中的文件没有内容')));
      return;
    }

    // 显示内容只显示文件数量，不重复显示目录（目录在附件中）
    String displayContent = '【发送文件】共 ${filesToSend.length} 个文件';
    // 完整内容包含目录和文件
    String fullContent = '【发送文件】共 ${filesToSend.length} 个文件\n\n【文件目录】\n$_directoryTree\n\n【文件内容】\n';
    List<EmbeddedFile> embeddedFiles = [];
    // 目录作为附件
    embeddedFiles.add(EmbeddedFile(path: '📁 文件目录.txt', content: _directoryTree, size: _directoryTree.length));
    for (var file in filesToSend) {
      final path = file['path'] as String;
      final content = file['content'] as String? ?? '';
      final size = file['size'] as int? ?? content.length;
      fullContent += '--- $path ---\n$content\n\n';
      embeddedFiles.add(EmbeddedFile(path: path, content: content, size: size));
    }
    int totalTokens = ApiService.estimateTokens(fullContent);
    if (totalTokens > AppConfig.maxTokens) {
      displayContent += '\n\n【已超过900K】';
      fullContent += '\n\n【已超过900K】';
    }
    final userMessage = Message(role: MessageRole.user, content: displayContent, fullContent: fullContent, embeddedFiles: embeddedFiles, status: MessageStatus.sent);

    _currentConversation!.messages.add(userMessage);
    await ConversationService.instance.update(_currentConversation!);
    setState(() {});
    _scrollToBottom();
    await _sendMessageToAI();
  }

  Future<List<String>?> _showFileSelectionDialog(List<String> rootDirs, List<Map<String, dynamic>> allFiles) async {
    // 按目录分组文件
    Map<String, List<Map<String, dynamic>>> groupedFiles = {};
    List<Map<String, dynamic>> rootFiles = [];
    
    for (var file in allFiles) {
      if (file['is_directory'] == 1) continue;
      final path = file['path'] as String;
      final parentPath = file['parent_path'] as String?;
      
      if (parentPath == null) {
        rootFiles.add(file);
      } else {
        // 找到根目录
        String rootDir = path.split('/').first;
        groupedFiles.putIfAbsent(rootDir, () => []);
        groupedFiles[rootDir]!.add(file);
      }
    }

    // 选中状态
    Set<String> selectedPaths = {};
    Set<String> selectedDirs = {};

    return await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          // 计算每个目录的文件数
          int getTotalFilesInDir(String dir) {
            return groupedFiles[dir]?.length ?? 0;
          }

          // 检查目录是否全选
          bool isDirFullySelected(String dir) {
            final files = groupedFiles[dir] ?? [];
            if (files.isEmpty) return false;
            return files.every((f) => selectedPaths.contains(f['path']));
          }

          // 检查目录是否部分选中
          bool isDirPartiallySelected(String dir) {
            final files = groupedFiles[dir] ?? [];
            if (files.isEmpty) return false;
            final selectedCount = files.where((f) => selectedPaths.contains(f['path'])).length;
            return selectedCount > 0 && selectedCount < files.length;
          }

          // 切换目录选择
          void toggleDir(String dir) {
            final files = groupedFiles[dir] ?? [];
            if (isDirFullySelected(dir)) {
              for (var f in files) {
                selectedPaths.remove(f['path']);
              }
              selectedDirs.remove(dir);
            } else {
              for (var f in files) {
                selectedPaths.add(f['path'] as String);
              }
              selectedDirs.add(dir);
            }
            setModalState(() {});
          }

          // 全选/全不选
          void toggleAll() {
            if (selectedPaths.length == allFiles.where((f) => f['is_directory'] != 1).length) {
              selectedPaths.clear();
              selectedDirs.clear();
            } else {
              for (var f in allFiles) {
                if (f['is_directory'] != 1) {
                  selectedPaths.add(f['path'] as String);
                }
              }
              selectedDirs.addAll(groupedFiles.keys);
            }
            setModalState(() {});
          }

          final colorScheme = Theme.of(ctx).colorScheme;
          final totalFiles = allFiles.where((f) => f['is_directory'] != 1).length;

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scrollController) => Column(
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
                  ),
                  child: Row(
                    children: [
                      const Text('选择要发送的文件', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: toggleAll,
                        child: Text(selectedPaths.length == totalFiles ? '取消全选' : '全选'),
                      ),
                    ],
                  ),
                ),
                // 选中统计
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('已选择 ${selectedPaths.length} / $totalFiles 个文件', style: TextStyle(color: colorScheme.primary)),
                    ],
                  ),
                ),
                // 文件列表
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // 根目录文件
                      if (rootFiles.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text('根目录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        ...rootFiles.map((file) => CheckboxListTile(
                          value: selectedPaths.contains(file['path']),
                          onChanged: (v) {
                            setModalState(() {
                              if (v == true) {
                                selectedPaths.add(file['path'] as String);
                              } else {
                                selectedPaths.remove(file['path']);
                              }
                            });
                          },
                          title: Text(file['name'] as String, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(_formatSize(file['size'] as int? ?? 0), style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        )),
                      ],
                      // 按仓库分组
                      ...groupedFiles.entries.map((entry) {
                        final dir = entry.key;
                        final files = entry.value;
                        final isExpanded = selectedDirs.contains(dir) || isDirPartiallySelected(dir);
                        
                        return ExpansionTile(
                          leading: Checkbox(
                            value: isDirFullySelected(dir) ? true : (isDirPartiallySelected(dir) ? null : false),
                            tristate: true,
                            onChanged: (_) => toggleDir(dir),
                          ),
                          title: Row(
                            children: [
                              Icon(Icons.folder, size: 20, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(dir, style: const TextStyle(fontWeight: FontWeight.w500))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('${files.length}', style: TextStyle(fontSize: 12, color: colorScheme.onSecondaryContainer)),
                              ),
                            ],
                          ),
                          initiallyExpanded: isExpanded,
                          children: files.map((file) => CheckboxListTile(
                            value: selectedPaths.contains(file['path']),
                            onChanged: (v) {
                              setModalState(() {
                                if (v == true) {
                                  selectedPaths.add(file['path'] as String);
                                } else {
                                  selectedPaths.remove(file['path']);
                                }
                              });
                            },
                            title: Text(file['name'] as String, style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              '${file['path']}\n${_formatSize(file['size'] as int? ?? 0)}',
                              style: TextStyle(fontSize: 11, color: colorScheme.outline),
                            ),
                            isThreeLine: true,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                          )).toList(),
                        );
                      }),
                    ],
                  ),
                ),
                // 底部按钮
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: selectedPaths.isEmpty ? null : () => Navigator.pop(ctx, selectedPaths.toList()),
                          child: Text('发送 (${selectedPaths.length})'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }


  Future<void> _sendMessage(String text, List<FileAttachment> attachments) async {
    if (text.isEmpty && attachments.isEmpty) return;
    if (_currentConversation == null) return;
    final userMessage = Message(role: MessageRole.user, content: text, attachments: attachments, status: MessageStatus.sent);
    _currentConversation!.messages.add(userMessage);
    await ConversationService.instance.update(_currentConversation!);
    setState(() {});
    _scrollToBottom();
    await _sendMessageToAI();
  }

  void _stopGeneration() {
    _stopRequested = true;
    ApiService.cancelRequest();
    _streamingMessageId = null;
    setState(() => _isLoading = false);
    
    // 更新最后一条消息状态
    if (_currentConversation != null && _currentConversation!.messages.isNotEmpty) {
      final lastMsg = _currentConversation!.messages.last;
      if (lastMsg.role == MessageRole.assistant && lastMsg.status == MessageStatus.sending) {
        final content = _streamingContent.value;
        if (content.isNotEmpty) {
          final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == lastMsg.id);
          if (msgIndex != -1) {
            _currentConversation!.messages[msgIndex] = Message(
              id: lastMsg.id,
              role: MessageRole.assistant,
              content: '$content\n\n[已停止生成]',
              timestamp: lastMsg.timestamp,
              status: MessageStatus.sent,
            );
            ConversationService.instance.update(_currentConversation!);
          }
        }
      }
    }
  }

  Future<void> _sendMessageToAI() async {

    if (_currentConversation == null) return;
    _stopRequested = false;
    final aiMessage = Message(role: MessageRole.assistant, content: '', status: MessageStatus.sending);
    _currentConversation!.messages.add(aiMessage);
    _streamingMessageId = aiMessage.id;
    _streamingContent.value = '';
    setState(() => _isLoading = true);
    _scrollToBottom();
    final stopwatch = Stopwatch()..start();
    
    try {
      String fullContent = '';
      
      final result = await ApiService.streamToMainAIWithTokens(
        messages: _currentConversation!.messages.where((m) => m.status != MessageStatus.sending).toList(),
        directoryTree: _directoryTree,
        onChunk: (chunk) {
          fullContent += chunk;
          final now = DateTime.now();
          if (now.difference(_lastUIUpdate) >= _uiUpdateInterval) {
            _lastUIUpdate = now;
            // 使用 ValueNotifier 局部更新，不触发整个列表重建
            _streamingContent.value = fullContent;
            _scrollToBottom();
          }
        },
      );
      
      stopwatch.stop();
      _streamingMessageId = null;
      
      final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _currentConversation!.messages[msgIndex] = Message(
          id: aiMessage.id, role: MessageRole.assistant, content: result.content, timestamp: aiMessage.timestamp, status: MessageStatus.sent,
          tokenUsage: TokenUsage(promptTokens: result.estimatedPromptTokens, completionTokens: result.estimatedCompletionTokens, totalTokens: result.estimatedPromptTokens + result.estimatedCompletionTokens, duration: stopwatch.elapsedMilliseconds / 1000),
        );
      }
      await ConversationService.instance.update(_currentConversation!);
      setState(() {});
      _scrollToBottom();
      await _checkAndNavigateToSub(result.content);
    } catch (e) {
      _streamingMessageId = null;
      final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _currentConversation!.messages[msgIndex] = Message(id: aiMessage.id, role: MessageRole.assistant, content: '发送失败: $e', timestamp: aiMessage.timestamp, status: MessageStatus.error);
      }
      await ConversationService.instance.update(_currentConversation!);
      setState(() {});
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkAndNavigateToSub(String response) async {
    final requestedLevel = _detector.detectSubLevelRequest(response);
    if (requestedLevel == 1 && _currentConversation != null) {
      final paths = _detector.extractPaths(response);
      final subConv = await SubConversationService.instance.create(parentId: _currentConversation!.id, rootConversationId: _currentConversation!.id, level: 1);
      final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (context) => SubChatScreen(subConversation: subConv, initialMessage: response, requestedPaths: paths, directoryTree: _directoryTree)));
      if (result != null && result['message'] != null && result['message'].isNotEmpty) {
        final returnMessage = result['message'] as String;
        final infoMessage = Message(role: MessageRole.user, content: '【来自子界面的提取结果】\n$returnMessage', status: MessageStatus.sent);
        _currentConversation!.messages.add(infoMessage);
        await ConversationService.instance.update(_currentConversation!);
        setState(() {});
        _scrollToBottom();
        await _sendMessageToAI();
      }
      setState(() {});
    }
  }

  Future<void> _enterSubConversation(SubConversation subConv) async {
    Navigator.pop(context);
    final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (context) => SubChatScreen(subConversation: subConv, initialMessage: '', requestedPaths: [], directoryTree: _directoryTree, isResuming: true)));
    if (result != null && result['message'] != null && result['message'].isNotEmpty && subConv.level == 1) {
      final returnMessage = result['message'] as String;
      final infoMessage = Message(role: MessageRole.user, content: '【来自子界面的提取结果】\n$returnMessage', status: MessageStatus.sent);
      _currentConversation!.messages.add(infoMessage);
      await ConversationService.instance.update(_currentConversation!);
      setState(() {});
      _scrollToBottom();
      await _sendMessageToAI();
    }
    setState(() {});
  }

  void _clearCurrentChat() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('清空对话'), content: const Text('确定要清空当前对话记录吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async {
          _currentConversation?.messages.clear();
          _messageKeys.clear();
          await ConversationService.instance.update(_currentConversation!);
          Navigator.pop(ctx);
          setState(() {});
        }, child: const Text('确定')),
      ],
    ));
  }

  void _deleteConversation(Conversation conversation) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除会话'), content: Text('确定要删除「${conversation.title}」吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async {
          await SubConversationService.instance.deleteByRootId(conversation.id);
          await ConversationService.instance.delete(conversation.id);
          Navigator.pop(ctx);
          if (_currentConversation?.id == conversation.id) {
            if (ConversationService.instance.conversations.isNotEmpty) {
              _currentConversation = ConversationService.instance.conversations.first;
            } else {
              await _createNewConversation();
            }
          }
          setState(() {});
        }, child: Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
      ],
    ));
  }

  void _renameConversation(Conversation conversation) {
    final controller = TextEditingController(text: conversation.title);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('重命名'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '输入新名称')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async {
          await ConversationService.instance.rename(conversation.id, controller.text.trim());
          Navigator.pop(ctx);
          setState(() {});
        }, child: const Text('确定')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMessages = _currentConversation != null && _currentConversation!.messages.isNotEmpty;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
        title: Text(_currentConversation?.title ?? 'AI 对话'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (context) => const DatabaseScreen())); _loadDirectoryTree(); }, icon: const Icon(Icons.folder_outlined), tooltip: '文件数据库'),
          IconButton(onPressed: _sendAllFiles, icon: const Icon(Icons.upload_file), tooltip: '发送所有文件'),
          IconButton(onPressed: _clearCurrentChat, icon: const Icon(Icons.delete_outline), tooltip: '清空对话'),
        ],
      ),
      drawer: _buildDrawer(context),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: !hasMessages
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 64, color: colorScheme.outline),
                            const SizedBox(height: 16),
                            Text('开始新对话', style: TextStyle(fontSize: 18, color: colorScheme.outline)),
                          ],
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollStartNotification) _userScrolling = true;
                          else if (notification is ScrollEndNotification) {
                            _userScrolling = false;
                            if (_scrollController.hasClients) {
                              final maxScroll = _scrollController.position.maxScrollExtent;
                              final currentScroll = _scrollController.offset;
                              if ((maxScroll - currentScroll) < 50) setState(() => _isNearBottom = true);
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          itemCount: _currentConversation!.messages.length,
                          itemBuilder: (context, index) {
                            _messageKeys[index] ??= GlobalKey();
                            final message = _currentConversation!.messages[index];
                            
                            // 如果是正在流式生成的消息，使用 ValueListenableBuilder 局部更新
                            if (message.id == _streamingMessageId) {
                              return Container(
                                key: _messageKeys[index],
                                child: ValueListenableBuilder<String>(
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
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: ScrollButtons(onScrollToTop: _scrollToTop, onScrollToBottom: _forceScrollToBottom, onPreviousMessage: _scrollToPreviousMessage, onNextMessage: _scrollToNextMessage),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final conversations = ConversationService.instance.conversations;
    List<SubConversation> allSubConvs = [];
    if (_currentConversation != null) allSubConvs = SubConversationService.instance.getByRootId(_currentConversation!.id);
    
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Row(children: [Icon(Icons.chat_bubble_outline, color: colorScheme.primary, size: 28), const SizedBox(width: 12), const Expanded(child: Text('会话列表', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: InkWell(
                onTap: () async { await _createNewConversation(); Navigator.pop(context); },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(border: Border.all(color: colorScheme.outline.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [Icon(Icons.add, color: colorScheme.primary), const SizedBox(width: 12), const Text('新建会话', style: TextStyle(fontSize: 16))]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (allSubConvs.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [Text('子界面', style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Text('${allSubConvs.length}', style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer)))])),
              ...allSubConvs.map((sub) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: InkWell(
                  onTap: () => _enterSubConversation(sub),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: colorScheme.secondaryContainer.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.subdirectory_arrow_right, size: 20, color: colorScheme.secondary),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(sub.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)), Text('${sub.levelName} · ${sub.messages.length}条', style: TextStyle(fontSize: 12, color: colorScheme.outline))])),
                      IconButton(icon: Icon(Icons.close, size: 18, color: colorScheme.outline), onPressed: () async { await SubConversationService.instance.delete(sub.id); setState(() {}); }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                    ]),
                  ),
                ),
              )),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  final isSelected = conv.id == _currentConversation?.id;
                  final subCount = SubConversationService.instance.getByRootId(conv.id).length;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: InkWell(
                      onTap: () => _switchConversation(conv),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: isSelected ? colorScheme.primaryContainer.withOpacity(0.5) : Colors.transparent, borderRadius: BorderRadius.circular(12), border: isSelected ? Border.all(color: colorScheme.primary.withOpacity(0.5)) : null),
                        child: Row(children: [
                          Stack(children: [Icon(Icons.chat_bubble_outline, size: 22, color: isSelected ? colorScheme.primary : colorScheme.outline), if (subCount > 0) Positioned(right: -2, top: -2, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: colorScheme.secondary, shape: BoxShape.circle), child: Text('$subCount', style: const TextStyle(fontSize: 8, color: Colors.white))))]),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)), Text('${conv.messages.length} 条消息', style: TextStyle(fontSize: 12, color: colorScheme.outline))])),
                          PopupMenuButton(icon: Icon(Icons.more_vert, size: 20, color: colorScheme.outline), padding: EdgeInsets.zero, itemBuilder: (context) => [const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('重命名')])), PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))]))], onSelected: (value) { if (value == 'rename') _renameConversation(conv); else if (value == 'delete') _deleteConversation(conv); }),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: InkWell(
                onTap: () async { Navigator.pop(context); await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())); _loadDirectoryTree(); },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [Icon(Icons.settings, color: colorScheme.onSurfaceVariant), const SizedBox(width: 12), const Text('设置', style: TextStyle(fontSize: 16)), const Spacer(), Icon(Icons.chevron_right, color: colorScheme.outline)]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}// 编辑消息对话框
class _EditMessageDialog extends StatefulWidget {
  final String initialContent;
  final List<FileAttachment> attachments;
  final List<EmbeddedFile> embeddedFiles;

  const _EditMessageDialog({
    required this.initialContent,
    required this.attachments,
    required this.embeddedFiles,
  });

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
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
              // 消息内容
              TextField(
                controller: _controller,
                maxLines: null,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: '输入消息内容...',
                  border: OutlineInputBorder(),
                ),
              ),
              
              // 图片附件
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
              
              // 文件附件
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
              
              // 内嵌文件
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

