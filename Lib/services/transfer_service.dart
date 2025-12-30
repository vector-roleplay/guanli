import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 中转站文件数据
class TransferFile {
  final String path;
  final String content;
  final DateTime uploadedAt;

  TransferFile({
    required this.path,
    required this.content,
    DateTime? uploadedAt,
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  String get fileName => path.split('/').last;
  
  int get size => content.length;

  Map<String, dynamic> toJson() => {
    'path': path,
    'content': content,
    'uploadedAt': uploadedAt.toIso8601String(),
  };

  factory TransferFile.fromJson(Map<String, dynamic> json) => TransferFile(
    path: json['path'] as String,
    content: json['content'] as String,
    uploadedAt: DateTime.parse(json['uploadedAt'] as String),
  );
}

/// 中转站服务 - 用于两个应用之间共享文件
class TransferService {
  static final TransferService instance = TransferService._internal();
  TransferService._internal();

  /// 获取中转站目录路径（与 AI Code Sync 相同）
  Future<String> get _transferDirPath async {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/AiCodeTransfer';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/AiCodeTransfer';
    }
  }

  /// 获取中转站文件路径
  Future<String> get _transferFilePath async {
    final dir = await _transferDirPath;
    return '$dir/transfer.json';
  }

  /// 读取中转站中的所有文件
  Future<List<TransferFile>> getFiles() async {
    try {
      final filePath = await _transferFilePath;
      final file = File(filePath);
      
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      if (content.isEmpty) {
        return [];
      }

      final data = jsonDecode(content) as Map<String, dynamic>;
      final files = data['files'] as List? ?? [];
      
      return files.map((f) => TransferFile.fromJson(f)).toList();
    } catch (e) {
      print('读取中转站失败: $e');
      return [];
    }
  }

  /// 获取中转站文件数量
  Future<int> getFileCount() async {
    final files = await getFiles();
    return files.length;
  }

  /// 从中转站删除指定文件
  Future<bool> removeFile(String path) async {
    try {
      final files = await getFiles();
      files.removeWhere((f) => f.path == path);
      
      final filePath = await _transferFilePath;
      final file = File(filePath);
      
      final data = {
        'files': files.map((f) => f.toJson()).toList(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      await file.writeAsString(jsonEncode(data), flush: true);
      return true;
    } catch (e) {
      print('从中转站删除失败: $e');
      return false;
    }
  }

  /// 清空中转站
  Future<bool> clear() async {
    try {
      final filePath = await _transferFilePath;
      final file = File(filePath);
      
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      print('清空中转站失败: $e');
      return false;
    }
  }
}