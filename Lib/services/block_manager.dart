// lib/services/block_manager.dart

import '../models/message.dart';
import '../models/content_block.dart';

/// 块管理器 - 管理消息和块之间的映射关系
class BlockManager {
  List<Message> _messages = [];
  
  // 流式消息的块构建器
  final Map<String, StreamingBlockBuilder> _streamingBuilders = {};
  
  /// 设置消息列表
  void setMessages(List<Message> messages) {
    _messages = messages;
    _rebuildBlockIndices();
  }
  
  /// 重建块索引
  void _rebuildBlockIndices() {
    int currentIndex = 0;
    for (var msg in _messages) {
      msg.blockStartIndex = currentIndex;
      
      // 如果消息没有块，初始化
      if (msg.blocks.isEmpty && msg.status != MessageStatus.sending) {
        msg.initBlocks();
      }
      
      currentIndex += msg.blockCount;
    }
  }
  
  /// 获取总块数
  int get totalBlockCount {
    if (_messages.isEmpty) return 0;
    
    int count = 0;
    for (var msg in _messages) {
      // 流式消息使用 builder 的块数
      if (_streamingBuilders.containsKey(msg.id)) {
        count += _streamingBuilders[msg.id]!.blockCount;
      } else {
        count += msg.blockCount;
      }
    }
    return count;
  }
  
  /// 根据全局块索引定位消息和局部块索引
  (Message, int)? locateBlock(int globalBlockIndex) {
    int currentIndex = 0;
    
    for (var msg in _messages) {
      int blockCount;
      if (_streamingBuilders.containsKey(msg.id)) {
        blockCount = _streamingBuilders[msg.id]!.blockCount;
      } else {
        blockCount = msg.blockCount;
      }
      
      if (globalBlockIndex < currentIndex + blockCount) {
        return (msg, globalBlockIndex - currentIndex);
      }
      currentIndex += blockCount;
    }
    return null;
  }
  
  /// 获取指定块的内容
  String getBlockContent(int globalBlockIndex) {
    final located = locateBlock(globalBlockIndex);
    if (located == null) return '';
    
    final (message, localIndex) = located;
    
    // 检查是否是流式消息
    if (_streamingBuilders.containsKey(message.id)) {
      return _streamingBuilders[message.id]!.getBlockContent(localIndex);
    }
    
    // 普通消息
    if (localIndex < message.blocks.length) {
      return message.blocks[localIndex].content;
    }
    
    // 没有块数据，返回整个消息内容（兼容旧数据）
    return message.content;
  }
  
  /// 是否是消息的第一块
  bool isFirstBlock(int globalBlockIndex) {
    final located = locateBlock(globalBlockIndex);
    if (located == null) return false;
    return located.$2 == 0;
  }
  
  /// 是否是消息的最后一块
  bool isLastBlock(int globalBlockIndex) {
    final located = locateBlock(globalBlockIndex);
    if (located == null) return false;
    
    final (message, localIndex) = located;
    
    if (_streamingBuilders.containsKey(message.id)) {
      return _streamingBuilders[message.id]!.isLastBlock(localIndex);
    }
    
    return localIndex == message.blockCount - 1;
  }
  
  /// 获取消息的起始块索引
  int getBlockIndexForMessage(String messageId) {
    for (var msg in _messages) {
      if (msg.id == messageId) {
        return msg.blockStartIndex;
      }
    }
    return 0;
  }
  /// 获取消息索引对应的块索引
  int getBlockIndexForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _messages.length) return -1;
    return _messages[messageIndex].blockStartIndex;
  }
  
  /// 获取最后一个块的索引（返回 -1 表示没有块）
  int get lastBlockIndex => totalBlockCount > 0 ? totalBlockCount - 1 : -1;
  
  /// 是否有块
  bool get hasBlocks => totalBlockCount > 0;

  
  // ========== 流式支持 ==========
  
  /// 开始流式消息
  void startStreaming(String messageId) {
    _streamingBuilders[messageId] = StreamingBlockBuilder(messageId: messageId);
  }
  
  /// 追加流式内容
  void appendStreamingContent(String messageId, String chunk) {
    _streamingBuilders[messageId]?.append(chunk);
  }
  
  /// 获取流式消息的当前块数
  int getStreamingBlockCount(String messageId) {
    return _streamingBuilders[messageId]?.blockCount ?? 1;
  }
  
  /// 完成流式消息
  List<ContentBlock> finishStreaming(String messageId) {
    final builder = _streamingBuilders.remove(messageId);
    if (builder != null) {
      return builder.finalize();
    }
    return [];
  }
  
  /// 是否正在流式
  bool isStreaming(String messageId) {
    return _streamingBuilders.containsKey(messageId);
  }
  
  /// 获取流式块内容
  String getStreamingBlockContent(String messageId, int localIndex) {
    return _streamingBuilders[messageId]?.getBlockContent(localIndex) ?? '';
  }
}