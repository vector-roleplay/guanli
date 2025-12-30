// Lib/services/github_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GitHubFile {
  final String name;
  final String path;
  final String type; // 'file' or 'dir'
  final int size;
  final String? downloadUrl;

  GitHubFile({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    this.downloadUrl,
  });

  factory GitHubFile.fromJson(Map<String, dynamic> json) {
    return GitHubFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      type: json['type'] ?? 'file',
      size: json['size'] ?? 0,
      downloadUrl: json['download_url'],
    );
  }
}

class GitHubRepo {
  final String name;
  final String fullName;
  final String defaultBranch;

  GitHubRepo({
    required this.name,
    required this.fullName,
    required this.defaultBranch,
  });

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    return GitHubRepo(
      name: json['name'] ?? '',
      fullName: json['full_name'] ?? '',
      defaultBranch: json['default_branch'] ?? 'main',
    );
  }
}

class GitHubService {
  static final GitHubService instance = GitHubService._internal();
  GitHubService._internal();

  String _token = '';
  String _username = '';
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;
  String get username => _username;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('github_token') ?? '';
    _username = prefs.getString('github_username') ?? '';
    _isLoggedIn = _token.isNotEmpty && _username.isNotEmpty;
  }

  Future<bool> login(String token) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _username = data['login'] ?? '';
        _token = token;
        _isLoggedIn = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('github_token', token);
        await prefs.setString('github_username', _username);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    _token = '';
    _username = '';
    _isLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('github_token');
    await prefs.remove('github_username');
  }

  Future<List<GitHubRepo>> getRepos() async {
    if (!_isLoggedIn) return [];

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user/repos?per_page=100&sort=updated'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => GitHubRepo.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<GitHubFile>> getContents(String repo, String path) async {
    if (!_isLoggedIn) return [];

    try {
      final url = path.isEmpty
          ? 'https://api.github.com/repos/$repo/contents'
          : 'https://api.github.com/repos/$repo/contents/$path';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data.map((e) => GitHubFile.fromJson(e)).toList();
        }
        return [GitHubFile.fromJson(data)];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<String?> getFileContent(String repo, String path) async {
    if (!_isLoggedIn) return null;

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/contents/$path'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['content'] != null) {
          final content = data['content'] as String;
          final decoded = utf8.decode(base64Decode(content.replaceAll('\n', '')));
          return decoded;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 并行获取目录内容（大幅提升下载速度）
  Future<Map<String, String>> getDirectoryContents(String repo, String path) async {
    Map<String, String> files = {};
    
    // 先收集所有文件路径
    List<GitHubFile> allFiles = [];
    await _collectAllFiles(repo, path, allFiles);
    
    // 并行下载所有文件（限制并发数为10）
    const int maxConcurrent = 10;
    for (int i = 0; i < allFiles.length; i += maxConcurrent) {
      final batch = allFiles.skip(i).take(maxConcurrent).toList();
      final results = await Future.wait(
        batch.map((file) async {
          final content = await getFileContent(repo, file.path);
          return MapEntry(file.path, content);
        }),
      );
      
      for (var entry in results) {
        if (entry.value != null) {
          files[entry.key] = entry.value!;
        }
      }
    }
    
    return files;
  }

  // 递归收集所有文件（只收集路径，不下载内容）
  Future<void> _collectAllFiles(String repo, String path, List<GitHubFile> allFiles) async {
    final contents = await getContents(repo, path);
    
    // 分离文件和目录
    final fileItems = contents.where((item) => item.type == 'file').toList();
    final dirItems = contents.where((item) => item.type == 'dir').toList();
    
    // 添加文件
    allFiles.addAll(fileItems);
    
    // 并行处理子目录
    if (dirItems.isNotEmpty) {
      await Future.wait(
        dirItems.map((dir) => _collectAllFiles(repo, dir.path, allFiles)),
      );
    }
  }
}
