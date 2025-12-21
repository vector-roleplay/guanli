// lib/services/file_service.dart

import 'database_service.dart';

class FileContent {
  final String path;
  final String content;
  final int size;

  FileContent({
    required this.path,
    required this.content,
    required this.size,
  });
}

class FileService {
  static final FileService instance = FileService._internal();
  FileService._internal();

// 根据路径列表获取文件内容
  Future<List<FileContent>> getFilesContent(List<String> paths) async {
    List<FileContent> results = [];

    for (var path in paths) {
      final content = await DatabaseService.instance.getFileContent(path);
      if (content != null) {
        results.add(FileContent(
          path: path,
          content: content,
          size: content.length,
        ));
      }
    }

    return results;
  }

  // 分割大文件内容
  List<String> splitContent(String content, int maxSize) {
    List<String> chunks = [];
    
    if (content.length <= maxSize) {
      chunks.add(content);
      return chunks;
    }

    // 按行分割，尽量保持完整性
    final lines = content.split('\n');
    StringBuffer currentChunk = StringBuffer();
    
    for (var line in lines) {
      // 如果单行就超过限制，强制分割
      if (line.length > maxSize) {
        // 先保存当前chunk
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.toString());
          currentChunk.clear();
        }
        
        // 分割超长行
        for (int i = 0; i < line.length; i += maxSize) {
          final end = (i + maxSize > line.length) ? line.length : i + maxSize;
          chunks.add(line.substring(i, end));
        }
      } else if (currentChunk.length + line.length + 1 > maxSize) {
        // 当前chunk已满，保存并开始新chunk
        chunks.add(currentChunk.toString());
        currentChunk.clear();
        currentChunk.writeln(line);
      } else {
        currentChunk.writeln(line);
      }
    }

    // 保存最后的chunk
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString());
    }

    return chunks;
  }

  // 计算发送进度百分比
  int calculateProgress(int sent, int total) {
    if (total == 0) return 100;
    return ((sent / total) * 100).round();
  }

  // 检查文件是否需要分批发送
  bool needsChunking(List<FileContent> files, int maxSize) {
    int totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
    return totalSize > maxSize;
  }

  // 将文件分组，每组不超过maxSize
  List<List<FileContent>> groupFiles(List<FileContent> files, int maxSize) {
    List<List<FileContent>> groups = [];
    List<FileContent> currentGroup = [];
    int currentSize = 0;

    for (var file in files) {
      if (file.size > maxSize) {
        // 单个文件过大，单独处理
        if (currentGroup.isNotEmpty) {
          groups.add(currentGroup);
          currentGroup = [];
          currentSize = 0;
        }
        groups.add([file]);
      } else if (currentSize + file.size > maxSize) {
        // 当前组已满
        groups.add(currentGroup);
        currentGroup = [file];
        currentSize = file.size;
      } else {
        currentGroup.add(file);
        currentSize += file.size;
      }
    }

    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    return groups;
  }
}
