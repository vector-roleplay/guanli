// lib/models/content_block.dart

/// 内容块 - 渲染的最小单位
class ContentBlock {
  final String messageId;      // 属于哪条消息
  final int partIndex;         // 这条消息的第几部分（0, 1, 2...）
  final String content;        // 这部分的内容
  
  ContentBlock({
    required this.messageId,
    required this.partIndex,
    required this.content,
  });
}

/// 流式分块构建器
class StreamingBlockBuilder {
  final String messageId;
  final List<String> completedBlocks = [];  // 已完成的块内容
  final StringBuffer _currentBlock = StringBuffer();  // 正在增长的块
  
  /// 每块的目标字符数（约 0.8 屏，留余量）
  static const int charsPerBlock = 1500;
  
  /// 切分时的搜索范围（在目标位置的 80% 处开始找换行符）
  static const double searchStartRatio = 0.8;
  
  StreamingBlockBuilder({required this.messageId});
  
  /// 追加新内容
  void append(String chunk) {
    _currentBlock.write(chunk);
    _trySplit();
  }
  
  /// 尝试切分
  void _trySplit() {
    while (_currentBlock.length > charsPerBlock) {
      String content = _currentBlock.toString();
      int cutPoint = _findCutPoint(content);
      
      completedBlocks.add(content.substring(0, cutPoint));
      
      // 重置当前块
      _currentBlock.clear();
      _currentBlock.write(content.substring(cutPoint));
    }
  }
  
  /// 找切分点（尽量在换行符处切）
  int _findCutPoint(String content) {
    int searchStart = (charsPerBlock * searchStartRatio).toInt();
    
    // 在目标位置附近找换行符
    int lastNewline = content.lastIndexOf('\n', charsPerBlock);
    
    if (lastNewline > searchStart) {
      return lastNewline + 1;  // 在换行符后切
    }
    
    // 找不到换行符，尝试找空格
    int lastSpace = content.lastIndexOf(' ', charsPerBlock);
    if (lastSpace > searchStart) {
      return lastSpace + 1;
    }
    
    // 都找不到，硬切
    return charsPerBlock;
  }
  
  /// 获取当前块的内容
  String get currentBlockContent => _currentBlock.toString();
  
  /// 总块数
  int get blockCount => completedBlocks.length + (_currentBlock.isNotEmpty ? 1 : 0);
  
  /// 获取指定块的内容
  String getBlockContent(int index) {
    if (index < completedBlocks.length) {
      return completedBlocks[index];
    } else if (index == completedBlocks.length && _currentBlock.isNotEmpty) {
      return _currentBlock.toString();
    }
    return '';
  }
  
  /// 是否是第一块
  bool isFirstBlock(int index) => index == 0;
  
  /// 是否是最后一块（正在增长的块）
  bool isLastBlock(int index) => index == blockCount - 1;
  
  /// 完成流式，获取所有块
  List<ContentBlock> finalize() {
    // 把当前块也加入已完成列表
    if (_currentBlock.isNotEmpty) {
      completedBlocks.add(_currentBlock.toString());
      _currentBlock.clear();
    }
    
    return List.generate(completedBlocks.length, (index) => ContentBlock(
      messageId: messageId,
      partIndex: index,
      content: completedBlocks[index],
    ));
  }
  
  /// 从完整内容创建块列表（用于非流式消息）
  static List<ContentBlock> fromContent(String messageId, String content) {
    if (content.isEmpty) {
      return [ContentBlock(messageId: messageId, partIndex: 0, content: '')];
    }
    
    final builder = StreamingBlockBuilder(messageId: messageId);
    builder.append(content);
    return builder.finalize();
  }
}