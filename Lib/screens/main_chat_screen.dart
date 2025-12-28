// lib/screens/main_chat_screen.dart

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../models/sub_conversation.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/conversation_service.dart';
import '../services/sub_conversation_service.dart';
import '../services/file_service.dart';
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
  final MessageDetector _detector = MessageDetector();
  
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
    await SubConversationService.instance.load();
    
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
    Navigator.pop(context);
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

  Future<void> _deleteMessage(int index) async {
    if (_currentConversation == null) return;
    
    _currentConversation!.messages.removeAt(index);
    await ConversationService.instance.update(_currentConversation!);
    setState(() {});
  }

  Future<void> _sendMessage(String text, List<FileAttachment> attachments) async {
    if (text.isEmpty && attachments.isEmpty) return;
    if (_currentConversation == null) return;

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
  String fullContent = '';
  
  final result = await ApiService.streamToMainAIWithTokens(
    messages: _currentConversation!.messages
        .where((m) => m.status != MessageStatus.sending)
        .toList(),
    directoryTree: _directoryTree,
    onChunk: (chunk) {
      fullContent += chunk;
      final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
      if (msgIndex != -1) {
        _currentConversation!.messages[msgIndex] = Message(
          id: aiMessage.id,
          role: MessageRole.assistant,
          content: fullContent,
          timestamp: aiMessage.timestamp,
          status: MessageStatus.sending,
        );
        setState(() {});
        _scrollToBottom();
      }
    },
  );

  stopwatch.stop();

  final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
  if (msgIndex != -1) {
    _currentConversation!.messages[msgIndex] = Message(
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

  await ConversationService.instance.update(_currentConversation!);
  setState(() {});
  _scrollToBottom();

  await _checkAndNavigateToSub(result.content);
        

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
  final requestedLevel = _detector.detectSubLevelRequest(response);
  
  if (requestedLevel == 1 && _currentConversation != null) {
    final paths = _detector.extractPaths(response);
    
    final subConv = await SubConversationService.instance.create(
      parentId: _currentConversation!.id,
      rootConversationId: _currentConversation!.id,
      level: 1,
    );

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => SubChatScreen(
          subConversation: subConv,
          initialMessage: response,
          requestedPaths: paths,
          directoryTree: _directoryTree,
        ),
      ),
    );

    // 处理返回 - 自动发送给主界面AI
    if (result != null && result['message'] != null && result['message'].isNotEmpty) {
      final returnMessage = result['message'] as String;
      
      // 添加一条系统消息显示来自子界面的内容
      final infoMessage = Message(
        role: MessageRole.user,
        content: '【来自子界面的提取结果】\n$returnMessage',
        status: MessageStatus.sent,
      );
      _currentConversation!.messages.add(infoMessage);
      await ConversationService.instance.update(_currentConversation!);
      setState(() {});
      _scrollToBottom();
      
      // 自动发送给AI（不带文本，只是触发AI响应）
      await _sendMessageToAI();
    }
    
    setState(() {});
  }
}

// 新增：只发送给AI，不添加新的用户消息
Future<void> _sendMessageToAI() async {
  if (_currentConversation == null) return;

  final aiMessage = Message(
    role: MessageRole.assistant,
    content: '',
    status: MessageStatus.sending,
  );
  _currentConversation!.messages.add(aiMessage);
  setState(() {
    _isLoading = true;
  });
  _scrollToBottom();

  final stopwatch = Stopwatch()..start();

  try {
    String fullContent = '';
    
    final result = await ApiService.streamToMainAIWithTokens(
      messages: _currentConversation!.messages
          .where((m) => m.status != MessageStatus.sending)
          .toList(),
      directoryTree: _directoryTree,
      onChunk: (chunk) {
        fullContent += chunk;
        final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
        if (msgIndex != -1) {
          _currentConversation!.messages[msgIndex] = Message(
            id: aiMessage.id,
            role: MessageRole.assistant,
            content: fullContent,
            timestamp: aiMessage.timestamp,
            status: MessageStatus.sending,
          );
          setState(() {});
          _scrollToBottom();
        }
      },
    );

    stopwatch.stop();

    final msgIndex = _currentConversation!.messages.indexWhere((m) => m.id == aiMessage.id);
    if (msgIndex != -1) {
      _currentConversation!.messages[msgIndex] = Message(
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

    await ConversationService.instance.update(_currentConversation!);
    setState(() {});
    _scrollToBottom();

    await _checkAndNavigateToSub(result.content);

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
    });
  }
}

// 新增：重新生成AI回复
Future<void> _regenerateMessage(int aiMessageIndex) async {
  if (_currentConversation == null) return;
  
  // 删除当前AI消息
  _currentConversation!.messages.removeAt(aiMessageIndex);
  await ConversationService.instance.update(_currentConversation!);
  setState(() {});
  
  // 重新发送给AI
  await _sendMessageToAI();
}

  Future<void> _handleReturnMessage(String message) async {
    // 作为AI消息添加到主界面
    final returnMessage = Message(
      role: MessageRole.assistant,
      content: '【来自子界面的返回】\n$message',
      status: MessageStatus.sent,
    );
    _currentConversation!.messages.add(returnMessage);
    await ConversationService.instance.update(_currentConversation!);
    setState(() {});
    _scrollToBottom();
  }

  // 进入已存在的子会话
  Future<void> _enterSubConversation(SubConversation subConv) async {
    Navigator.pop(context);
    
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => SubChatScreen(
          subConversation: subConv,
          initialMessage: '',
          requestedPaths: [],
          directoryTree: _directoryTree,
          isResuming: true,
        ),
      ),
    );

    if (result != null && result['message'] != null && result['message'].isNotEmpty) {
      // 只有一级子界面返回的消息才发送给主界面
      if (subConv.level == 1) {
        await _handleReturnMessage(result['message']);
      }
    }
    setState(() {});
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
              await SubConversationService.instance.deleteByRootId(conversation.id);
              await ConversationService.instance.delete(conversation.id);
              Navigator.pop(context);
              
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
                        onDelete: () => _deleteMessage(index),
                        onRegenerate: message.role == MessageRole.assistant && message.status == MessageStatus.sent
                            ? () => _regenerateMessage(index)
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
    
    // 获取当前会话的所有子会话
    List<SubConversation> allSubConvs = [];
    if (_currentConversation != null) {
      allSubConvs = SubConversationService.instance.getByRootId(_currentConversation!.id);
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
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

            // 当前会话的子界面列表
            if (allSubConvs.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                alignment: Alignment.centerLeft,
                child: Text(
                  '子界面 (${allSubConvs.length}个)',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...allSubConvs.map((sub) => ListTile(
                leading: Icon(
                  Icons.subdirectory_arrow_right,
                  color: colorScheme.secondary,
                ),
                title: Text(
                  sub.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${sub.levelName} · ${sub.messages.length}条消息',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('删除子界面'),
                        content: Text('确定要删除「${sub.title}」吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text('删除', style: TextStyle(color: colorScheme.error)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await SubConversationService.instance.delete(sub.id);
                      setState(() {});
                    }
                  },
                ),
                onTap: () => _enterSubConversation(sub),
              )),
              const Divider(height: 1),
            ],

            // 主会话列表
            Expanded(
              child: ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  final isSelected = conv.id == _currentConversation?.id;
                  final subCount = SubConversationService.instance.getByRootId(conv.id).length;

                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: colorScheme.primaryContainer.withOpacity(0.3),
                    leading: Stack(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: isSelected ? colorScheme.primary : colorScheme.outline,
                        ),
                        if (subCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: colorScheme.secondary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$subCount',
                                style: const TextStyle(fontSize: 8, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                        if (value == 'rename') _renameConversation(conv);
                        else if (value == 'delete') _deleteConversation(conv);
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
