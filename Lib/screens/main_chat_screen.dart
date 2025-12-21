// lib/screens/main_chat_screen.dart

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
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
  final ChatSession _session = ChatSession();
  final ScrollController _scrollController = ScrollController();
  String _directoryTree = '';

  @override
  void initState() {
    super.initState();
    _loadDirectoryTree();
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
      final response = await ApiService.sendToMainAI(
        messages: _session.messages.where((m) => m.status != MessageStatus.sending).toList(),
        directoryTree: _directoryTree,
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

      await _checkAndNavigateToSub(response.content);

    } catch (e) {
      _session.updateMessage(aiMessage.id, content: '发送失败: $e', status: MessageStatus.error);
    } finally {
      _session.setLoading(false);
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

  void _clearChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('确定要清空所有对话记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _session.clear();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 对话'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _clearChat,
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
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _session,
              builder: (context, _) {
                if (_session.messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '开始新对话',
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: _session.messages.length,
                  itemBuilder: (context, index) {
                    final message = _session.messages[index];
                    return MessageBubble(
                      message: message,
                      onRetry: message.status == MessageStatus.error
                          ? () => _sendMessage(message.content, message.attachments)
                          : null,
                    );
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
