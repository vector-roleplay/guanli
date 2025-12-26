// lib/screens/main_chat_screen.dart

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/conversation_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../utils/message_detector.dart';
import 'settings_screen.dart';
import 'sub_chat_screen.dart';

class MainChatScreen extends StatefulWidget {
  const MainChatScreen({super.key});

  @override
  State<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends State<MainChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  String _directoryTree = '';
  Conversation? _currentConversation;
  bool _isLoading = false;
  String _streamingContent = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadDirectoryTree();
    await ConversationService.instance.load();
    
    // 如果没有会话，创建一个
    if (ConversationService.instance.conversations.isEmpty) {
      await _createNewConversation();
    } else {
      setState(() {
        _currentConversation = ConversationService.instance.conversations.first;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
    });
  }

  void _switchConversation(Conversation conversation) {
    setState(() {
      _currentConversation = conversation;
    });
    Navigator.pop(context); // 关闭抽屉
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

  Future<void> _sendMessage(String text, List<FileAttachment> attachments) async {
    if (text.isEmpty && attachments.isEmpty) return;
    if (_currentConversation == null) return;

    // 添加用户消息
    final userMessage = Message(
      role: MessageRole.user,
      content: text,
      attachments: attachments,
      status: MessageStatus.sent,
    );
    _currentConversation!.messages.add(userMessage);
    await ConversationService.instance.update(_currentConversation!);
    setState(() {});
    _scrollToBottom();

    // 添加AI消息占位
    final aiMessage = Message(
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.sending,
    );
    _currentConversation!.messages.add(aiMessage);
    setState(() {
      _isLoading = true;
      _streamingContent = '';
    });
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();

    try {
      // 流式接收
      final stream = ApiService.streamToMainAI(
        messages: _currentConversation!.messages
            .where((m) => m.status != MessageStatus.sending)
            .toList(),
        directoryTree: _directoryTree,
      );

      await for (var chunk in stream) {
        _streamingContent += chunk;
        // 更新界面
        final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
        if (msgIndex != -1) {
          _currentConversation!.messages[msgIndex] = Message(
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

      // 完成，更新状态
      final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _currentConversation!.messages[msgIndex] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: _streamingContent,
          timestamp: aiMessage.timestamp,
          status: MessageStatus.sent,
          tokenUsage: TokenUsage(
            promptTokens: 0, // 流式模式无法获取准确token
            completionTokens: _streamingContent.length ~/ 4, // 估算
            totalTokens: _streamingContent.length ~/ 4,
            duration: stopwatch.elapsedMilliseconds / 1000,
          ),
        );
      }

      await ConversationService.instance.update(_currentConversation!);
      setState(() {});
      _scrollToBottom();

      // 检查是否需要跳转子界面
      await _checkAndNavigateToSub(_streamingContent);

    } catch (e) {
      final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _currentConversation!.messages[msgIndex] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: '发送失败: $e',
          timestamp: aiMessage.timestamp,
          status: MessageStatus.error,
        );
      }
      await ConversationService.instance.update(_currentConversation!);
      setState(() {});
    } finally {
      setState(() {
        _isLoading = false;
        _streamingContent = '';
      });
    }
  }

  Future<void> _checkAndNavigateToSub(String response) async {
    final detector = MessageDetector();
    
    if (detector.hasRequestDoc(response)) {
      final paths = detector.extractPaths(response);
      
      if (paths.isNotEmpty) {
        final result = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) => SubChatScreen(
              initialMessage: response,
              requestedPaths: paths,
              directoryTree: _directoryTree,
            ),
          ),
        );

        if (result != null && result.isNotEmpty) {
          await _sendMessage(result, []);
        }
      }
    }
  }

  void _clearCurrentChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('确定要清空当前对话记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              _currentConversation?.messages.clear();
              await ConversationService.instance.update(_currentConversation!);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _deleteConversation(Conversation conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定要删除「${conversation.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await ConversationService.instance.delete(conversation.id);
              Navigator.pop(context);
              
              // 如果删的是当前会话，切换到别的
              if (_currentConversation?.id == conversation.id) {
                if (ConversationService.instance.conversations.isNotEmpty) {
                  _currentConversation = ConversationService.instance.conversations.first;
                } else {
                  await _createNewConversation();
                }
              }
              setState(() {});
            },
            child: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _renameConversation(Conversation conversation) {
    final controller = TextEditingController(text: conversation.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await ConversationService.instance.rename(conversation.id, controller.text.trim());
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(_currentConversation?.title ?? 'AI 对话'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _clearCurrentChat,
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空对话',
          ),
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              _loadDirectoryTree();
            },
            icon: const Icon(Icons.settings),
            tooltip: '设置',
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: Column(
        children: [
          Expanded(
            child: _currentConversation == null || _currentConversation!.messages.isEmpty
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
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _currentConversation!.messages.length,
                    itemBuilder: (context, index) {
                      final message = _currentConversation!.messages[index];
                      return MessageBubble(
                        message: message,
                        onRetry: message.status == MessageStatus.error
                            ? () => _sendMessage(message.content, message.attachments)
                            : null,
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

  Widget _buildDrawer(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final conversations = ConversationService.instance.conversations;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // 头部
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.chat, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text('会话列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(height: 1),
            
            // 新建会话按钮
            ListTile(
              leading: Icon(Icons.add, color: colorScheme.primary),
              title: const Text('新建会话'),
              onTap: () async {
                await _createNewConversation();
                Navigator.pop(context);
                setState(() {});
              },
            ),
            const Divider(height: 1),

            // 会话列表
            Expanded(
              child: ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  final isSelected = conv.id == _currentConversation?.id;

                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: colorScheme.primaryContainer.withOpacity(0.3),
                    leading: Icon(
                      Icons.chat_bubble_outline,
                      color: isSelected ? colorScheme.primary : colorScheme.outline,
                    ),
                    title: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${conv.messages.length} 条消息',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                    trailing: PopupMenuButton(
                      icon: Icon(Icons.more_vert, color: colorScheme.outline),
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'rename', child: Text('重命名')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                      onSelected: (value) {
                        if (value == 'rename') {
                          _renameConversation(conv);
                        } else if (value == 'delete') {
                          _deleteConversation(conv);
                        }
                      },
                    ),
                    onTap: () => _switchConversation(conv),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
