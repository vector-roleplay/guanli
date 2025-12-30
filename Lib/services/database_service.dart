// lib/services/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _database;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ai_chat.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            parent_path TEXT,
            is_directory INTEGER DEFAULT 0,
            size INTEGER DEFAULT 0,
            content TEXT,
            mime_type TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        ''');

        await db.execute('CREATE INDEX idx_files_path ON files(path)');
        await db.execute('CREATE INDEX idx_files_parent ON files(parent_path)');
        await db.execute('CREATE INDEX idx_files_name ON files(name)');
      },
    );
  }

  Database get db {
    if (_database == null) {
      throw Exception('Database not initialized');
    }
    return _database!;
  }

  // 导入文件夹
  Future<int> importDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw Exception('目录不存在: $dirPath');
    }

    int fileCount = 0;
    await _importRecursive(dir, '', (count) => fileCount += count);
    return fileCount;
  }

  Future<void> _importRecursive(Directory dir, String parentPath, Function(int) onCount) async {
    try {
      final entities = await dir.list(followLinks: false).toList();

      for (var entity in entities) {
        final name = entity.path.split('/').last;
        if (name.startsWith('.')) continue;
        
        final relativePath = parentPath.isEmpty ? name : '$parentPath/$name';

        if (entity is Directory) {
          await db.insert(
            'files',
            {
              'name': name,
              'path': relativePath,
              'parent_path': parentPath.isEmpty ? null : parentPath,
              'is_directory': 1,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          await _importRecursive(entity, relativePath, onCount);
        } else if (entity is File) {
          String? content;
          int size = 0;
          
          try {
            size = await entity.length();
          } catch (e) {}

          if (size > 0 && size < 5 * 1024 * 1024) {
            try {
              content = await entity.readAsString();
            } catch (e) {}
          }

          await db.insert(
            'files',
            {
              'name': name,
              'path': relativePath,
              'parent_path': parentPath.isEmpty ? null : parentPath,
              'is_directory': 0,
              'size': size,
              'content': content,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          
          onCount(1);
        }
      }
    } catch (e) {
      print('遍历目录出错: $e');
    }
  }

  // 导入单个文件
  Future<void> importFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final name = filePath.split('/').last;
    int size = 0;
    
    try {
      size = await file.length();
    } catch (e) {}

    String? content;
    if (size > 0 && size < 5 * 1024 * 1024) {
      try {
        content = await file.readAsString();
      } catch (e) {}
    }

    await db.insert(
      'files',
      {
        'name': name,
        'path': name,
        'parent_path': null,
        'is_directory': 0,
        'size': size,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 获取目录树（只查必要字段，不查content）
  Future<String> getDirectoryTree() async {
    final files = await db.query(
      'files',
      columns: ['path', 'name', 'is_directory'],  // 只查这3个字段
      orderBy: 'path',
    );

    if (files.isEmpty) return '(暂无文件)';

    StringBuffer tree = StringBuffer();
    
    for (var file in files) {
      final path = file['path'] as String;
      final name = file['name'] as String;
      final isDir = file['is_directory'] == 1;
      
      final depth = path.split('/').length - 1;
      final prefix = '  ' * depth;
      final icon = isDir ? '📁' : '📄';
      
      tree.writeln('$prefix$icon $name');
    }

    return tree.toString();
  }

  // 根据路径获取文件内容（单独查询，不会爆内存）
  Future<String?> getFileContent(String path) async {
    // 精确匹配
    var results = await db.query(
      'files',
      columns: ['content'],
      where: 'path = ? AND is_directory = 0',
      whereArgs: [path],
    );

    if (results.isNotEmpty && results.first['content'] != null) {
      return results.first['content'] as String?;
    }

    // 文件名匹配
    final fileName = path.split('/').last;
    results = await db.query(
      'files',
      columns: ['content'],
      where: 'name = ? AND is_directory = 0',
      whereArgs: [fileName],
    );

    if (results.isNotEmpty && results.first['content'] != null) {
      return results.first['content'] as String?;
    }

    // 模糊匹配路径末尾
    results = await db.query(
      'files',
      columns: ['content'],
      where: 'path LIKE ? AND is_directory = 0',
      whereArgs: ['%/$fileName'],
    );

    if (results.isNotEmpty && results.first['content'] != null) {
      return results.first['content'] as String?;
    }

    return null;
  }

  // 获取所有文件路径（不含content）
  Future<List<Map<String, dynamic>>> getAllFiles() async {
    return await db.query(
      'files',
      columns: ['id', 'name', 'path', 'parent_path', 'size'],
      where: 'is_directory = 0',
    );
  }

  Future<void> clearAll() async {
    await db.delete('files');
  }

  Future<void> deleteFile(String path) async {
    await db.delete('files', where: 'path = ? OR parent_path LIKE ?', whereArgs: [path, '$path%']);
  }// 获取所有文件内容（用于一键发送）
  Future<List<Map<String, dynamic>>> getAllFilesWithContent() async {
    return await db.query(
      'files',
      columns: ['path', 'name', 'content', 'size'],
      where: 'is_directory = 0 AND content IS NOT NULL',
      orderBy: 'path',
    );
  }

  // 获取所有根目录（仓库）
  Future<List<String>> getRootDirectories() async {
    final results = await db.query(
      'files',
      columns: ['path'],
      where: 'parent_path IS NULL AND is_directory = 1',
      orderBy: 'name',
    );
    return results.map((r) => r['path'] as String).toList();
  }

  // 获取指定目录下的所有文件（包含内容）
  Future<List<Map<String, dynamic>>> getFilesByDirectory(String dirPath) async {
    return await db.query(
      'files',
      columns: ['path', 'name', 'content', 'size'],
      where: '(path LIKE ? OR path = ?) AND is_directory = 0 AND content IS NOT NULL',
      whereArgs: ['$dirPath/%', dirPath],
      orderBy: 'path',
    );
  }

  // 获取单个文件信息（包含内容）
  Future<Map<String, dynamic>?> getFileByPath(String path) async {
    final results = await db.query(
      'files',
      columns: ['path', 'name', 'content', 'size'],
      where: 'path = ? AND is_directory = 0',
      whereArgs: [path],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // 获取所有文件列表（不含内容，用于选择器）
  Future<List<Map<String, dynamic>>> getAllFilesList() async {
    return await db.query(
      'files',
      columns: ['path', 'name', 'size', 'is_directory', 'parent_path'],
      orderBy: 'path',
    );
  }


  // 从 GitHub 导入文件
  Future<void> importGitHubFile(String path, String content) async {
    final name = path.split('/').last;
    final parentPath = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : null;

    // 确保父目录存在
    if (parentPath != null) {
      await _ensureDirectoryExists(parentPath);
    }

    await db.insert(
      'files',
      {
        'name': name,
        'path': path,
        'parent_path': parentPath,
        'is_directory': 0,
        'size': content.length,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _ensureDirectoryExists(String dirPath) async {
    final parts = dirPath.split('/');
    String currentPath = '';

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final parentPath = currentPath.isEmpty ? null : currentPath;
      currentPath = currentPath.isEmpty ? part : '$currentPath/$part';

      final existing = await db.query('files', where: 'path = ?', whereArgs: [currentPath]);
      if (existing.isEmpty) {
        await db.insert(
          'files',
          {
            'name': part,
            'path': currentPath,
            'parent_path': parentPath,
            'is_directory': 1,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

}
