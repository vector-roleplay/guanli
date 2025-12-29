// Lib/screens/database_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/database_service.dart';
import '../services/github_service.dart';

class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  String _directoryTree = '';
  bool _isLoading = false;
  bool _isGitHubLoggedIn = false;
  String _githubUsername = '';

  final TextEditingController _tokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await GitHubService.instance.load();
    final tree = await DatabaseService.instance.getDirectoryTree();
    setState(() {
      _directoryTree = tree;
      _isGitHubLoggedIn = GitHubService.instance.isLoggedIn;
      _githubUsername = GitHubService.instance.username;
    });
  }

  Future<void> _importFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
    if (result != null) {
      setState(() => _isLoading = true);
      for (var file in result.files) {
        if (file.path != null) {
          await DatabaseService.instance.importFile(file.path!);
        }
      }
      await _loadData();
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${result.files.length} 个文件')));
    }
  }

  Future<void> _importDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() => _isLoading = true);
      try {
        final count = await DatabaseService.instance.importDirectory(result);
        await _loadData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入完成，共 $count 个文件')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空数据库'),
        content: const Text('确定要清空所有已导入的文件吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('清空', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.instance.clearAll();
      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数据库已清空')));
    }
  }

  Future<void> _loginGitHub() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入Token')));
      return;
    }
    setState(() => _isLoading = true);
    final success = await GitHubService.instance.login(token);
    setState(() => _isLoading = false);
    if (success) {
      _tokenController.clear();
      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GitHub 登录成功')));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录失败，请检查Token')));
    }
  }

  Future<void> _logoutGitHub() async {
    await GitHubService.instance.logout();
    await _loadData();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已退出 GitHub')));
  }

  Future<void> _importFromGitHub() async {
    if (!_isGitHubLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录 GitHub')));
      return;
    }

    setState(() => _isLoading = true);
    final repos = await GitHubService.instance.getRepos();
    setState(() => _isLoading = false);

    if (repos.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到仓库')));
      return;
    }

    if (!mounted) return;

    final selectedRepo = await showModalBottomSheet<GitHubRepo>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('选择仓库 (${repos.length}个)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: repos.length,
                itemBuilder: (ctx, index) {
                  final repo = repos[index];
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(repo.name),
                    subtitle: Text(repo.fullName),
                    onTap: () => Navigator.pop(ctx, repo),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedRepo == null) return;

    await _browseGitHubRepo(selectedRepo);
  }

  Future<void> _browseGitHubRepo(GitHubRepo repo, [String path = '']) async {
    setState(() => _isLoading = true);
    final contents = await GitHubService.instance.getContents(repo.fullName, path);
    setState(() => _isLoading = false);

    if (!mounted) return;

    final selected = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (path.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(ctx, 'back'),
                    ),
                  Expanded(
                    child: Text(
                      path.isEmpty ? repo.name : path.split('/').last,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'import_all'),
                    child: const Text('导入全部'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: contents.length,
                itemBuilder: (ctx, index) {
                  final item = contents[index];
                  return ListTile(
                    leading: Icon(item.type == 'dir' ? Icons.folder : Icons.insert_drive_file),
                    title: Text(item.name),
                    subtitle: item.type == 'file' ? Text('${(item.size / 1024).toStringAsFixed(1)} KB') : null,
                    trailing: item.type == 'file' ? IconButton(icon: const Icon(Icons.download), onPressed: () => Navigator.pop(ctx, item)) : null,
                    onTap: () {
                      if (item.type == 'dir') {
                        Navigator.pop(ctx, item);
                      } else {
                        Navigator.pop(ctx, item);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;

    if (selected == 'back') {
      final parentPath = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
      await _browseGitHubRepo(repo, parentPath);
    } else if (selected == 'import_all') {
      await _importGitHubDirectory(repo.fullName, path);
    } else if (selected is GitHubFile) {
      if (selected.type == 'dir') {
        await _browseGitHubRepo(repo, selected.path);
      } else {
        await _importGitHubFile(repo.fullName, selected);
      }
    }
  }

  Future<void> _importGitHubFile(String repo, GitHubFile file) async {
    setState(() => _isLoading = true);
    final content = await GitHubService.instance.getFileContent(repo, file.path);
    if (content != null) {
      await DatabaseService.instance.importGitHubFile(file.path, content);
      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${file.name}')));
    }
    setState(() => _isLoading = false);
  }

  Future<void> _importGitHubDirectory(String repo, String path) async {
    setState(() => _isLoading = true);
    try {
      final files = await GitHubService.instance.getDirectoryContents(repo, path);
      for (var entry in files.entries) {
        await DatabaseService.instance.importGitHubFile(entry.key, entry.value);
      }
      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${files.length} 个文件')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件数据库'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // GitHub 登录区域
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.code, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            const Text('GitHub 导入', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            if (_isGitHubLoggedIn)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle, size: 14, color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text('已登录', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_isGitHubLoggedIn) ...[
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: colorScheme.primary,
                                child: Text(_githubUsername.isNotEmpty ? _githubUsername[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_githubUsername, style: const TextStyle(fontSize: 16))),
                              TextButton(onPressed: _logoutGitHub, child: const Text('退出')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _importFromGitHub,
                              icon: const Icon(Icons.cloud_download),
                              label: const Text('从仓库导入'),
                            ),
                          ),
                        ] else ...[
                          TextField(
                            controller: _tokenController,
                            decoration: InputDecoration(
                              labelText: 'GitHub Token',
                              hintText: 'ghp_xxxx...',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.key),
                            ),
                            obscureText: true,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _loginGitHub,
                              icon: const Icon(Icons.login),
                              label: const Text('登录 GitHub'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 本地导入区域
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.folder, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            const Text('本地导入', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _importFiles,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('导入文件'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _importDirectory,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('导入目录'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _clearDatabase,
                            icon: Icon(Icons.delete_outline, color: colorScheme.error),
                            label: Text('清空数据库', style: TextStyle(color: colorScheme.error)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: colorScheme.error),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 文件目录展示
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_tree, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            const Text('当前文件目录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 300),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              _directoryTree.isEmpty ? '(暂无文件)' : _directoryTree,
                              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }
}