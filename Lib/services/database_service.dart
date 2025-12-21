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

        await db.execute('''
          CREATE INDEX idx_files_path ON files(path)
        ''');

        await db.execute('''
          CREATE INDEX idx_files_parent ON files(parent_path)
        ''');
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
  Future<void> importDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    await _importRecursive(dir, '');
  }

  Future<void> _importRecursive(Directory dir, String parentPath) async {
    final entities = await dir.list().toList();

    for (var entity in entities) {
      final name = entity.path.split('/').last;
      final relativePath = parentPath.isEmpty ? name : '$parentPath/$name';

      if (entity is Directory) {
        // 保存目录
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

        // 递归处理子目录
        await _importRecursive(entity, relativePath);
      } else if (entity is File) {
        // 读取文件内容（仅文本文件）
        String? content;
        final size = await entity.length();

        if (size < 1024 * 1024) {
          // 小于1MB才读取内容
          try {
            content = await entity.readAsString();
          } catch (e) {
            // 非文本文件
          }
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
      }
    }
  }

  // 导入单个文件
  Future<void> importFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final name = filePath.split('/').last;
    final size = await file.length();

    String? content;
    if (size < 1024 * 1024) {
      try {
        content = await file.readAsString();
      } catch (e) {
        // 非文本文件
      }
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

  // 获取目录树
  Future<String> getDirectoryTree() async {
    final files = await db.query('files', orderBy: 'path');

    if (files.isEmpty) return '(暂无文件)';

    StringBuffer tree = StringBuffer();
    Map<String, int> indentMap = {};

    for (var file in files) {
      final path = file['path'] as String;
      final name = file['name'] as String;
      final isDir = file['is_directory'] == 1;
      final parentPath = file['parent_path'] as String?;

      int indent = 0;
      if (parentPath != null) {
        indent = (indentMap[parentPath] ?? 0) + 1;
      }
      indentMap[path] = indent;

      final prefix = '  ' * indent;
      final icon = isDir ? '📁' : '📄';
      tree.writeln('$prefix$icon $name');
    }

    return tree.toString();
  }

  // 根据路径获取文件内容
  Future<String?> getFileContent(String path) async {
    final results = await db.query(
      'files',
      where: 'path = ?',
      whereArgs: [path],
    );

    if (results.isNotEmpty) {
      return results.first['content'] as String?;
    }
    return null;
  }

  // 获取所有文件
  Future<List<Map<String, dynamic>>> getAllFiles() async {
    return await db.query('files', where: 'is_directory = 0');
  }

  // 清空数据库
  Future<void> clearAll() async {
    await db.delete('files');
  }

  // 删除文件
  Future<void> deleteFile(String path) async {
    await db.delete('files', where: 'path = ? OR parent_path LIKE ?', whereArgs: [path, '$path%']);
  }
}
