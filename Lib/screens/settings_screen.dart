// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 主界面API控制器
  late TextEditingController _mainApiUrlController;
  late TextEditingController _mainApiKeyController;
  late TextEditingController _mainModelController;
  late TextEditingController _mainPromptController;

  // 子界面API控制器
  late TextEditingController _subApiUrlController;
  late TextEditingController _subApiKeyController;
  late TextEditingController _subModelController;
  late TextEditingController _subPromptController;

  String _directoryTree = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = AppConfig.instance;

    _mainApiUrlController = TextEditingController(text: config.mainApiUrl);
    _mainApiKeyController = TextEditingController(text: config.mainApiKey);
    _mainModelController = TextEditingController(text: config.mainModel);
    _mainPromptController = TextEditingController(text: config.mainPrompt);

    _subApiUrlController = TextEditingController(text: config.subApiUrl);
    _subApiKeyController = TextEditingController(text: config.subApiKey);
    _subModelController = TextEditingController(text: config.subModel);
    _subPromptController = TextEditingController(text: config.subPrompt);

    _loadDirectoryTree();
  }

  @override
  void dispose() {
    _mainApiUrlController.dispose();
    _mainApiKeyController.dispose();
    _mainModelController.dispose();
    _mainPromptController.dispose();
    _subApiUrlController.dispose();
    _subApiKeyController.dispose();
    _subModelController.dispose();
    _subPromptController.dispose();
    super.dispose();
  }

  Future<void> _loadDirectoryTree() async {
    final tree = await DatabaseService.instance.getDirectoryTree();
    setState(() => _directoryTree = tree);
  }

  void _saveSettings() {
    final config = AppConfig.instance;

    config.updateMainApi(
      url: _mainApiUrlController.text.trim(),
      key: _mainApiKeyController.text.trim(),
      model: _mainModelController.text.trim(),
    );

    config.updateSubApi(
      url: _subApiUrlController.text.trim(),
      key: _subApiKeyController.text.trim(),
      model: _subModelController.text.trim(),
    );

    config.updatePrompts(
      main: _mainPromptController.text.trim(),
      sub: _subPromptController.text.trim(),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _importFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null) {
      setState(() => _isLoading = true);

      for (var file in result.files) {
        if (file.path != null) {
          await DatabaseService.instance.importFile(file.path!);
        }
      }

      await _loadDirectoryTree();
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${result.files.length} 个文件')),
        );
      }
    }
  }

  Future<void> _importDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null) {
      setState(() => _isLoading = true);

      await DatabaseService.instance.importDirectory(result);
      await _loadDirectoryTree();

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('目录导入完成')),
        );
      }
    }
  }

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空数据库'),
        content: const Text('确定要清空所有已导入的文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '清空',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.clearAll();
      await _loadDirectoryTree();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据库已清空')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ============ 主界面API设置 ============
                  _buildSectionTitle('主界面 API 设置', Icons.api),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _mainApiUrlController,
                    label: 'API地址',
                    hint: 'https://api.openai.com/v1',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _mainApiKeyController,
                    label: 'API密钥',
                    hint: 'sk-xxx',
                    obscure: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _mainModelController,
                    label: '模型',
                    hint: 'gpt-4',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _mainPromptController,
                    label: '主界面提示词',
                    hint: '输入主界面的系统提示词...',
                    maxLines: 4,
                  ),

                  const SizedBox(height: 32),

                  // ============ 子界面API设置 ============
                  _buildSectionTitle('子界面 API 设置', Icons.api),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _subApiUrlController,
                    label: 'API地址',
                    hint: 'https://api.openai.com/v1',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _subApiKeyController,
                    label: 'API密钥',
                    hint: 'sk-xxx',
                    obscure: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _subModelController,
                    label: '模型',
                    hint: 'gpt-4',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _subPromptController,
                    label: '子界面提示词',
                    hint: '输入子界面的系统提示词...',
                    maxLines: 4,
                  ),

                  const SizedBox(height: 32),

                  // ============ 文件数据库 ============
                  _buildSectionTitle('文件数据库', Icons.folder),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importFiles,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('导入文件'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importDirectory,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('导入目录'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: _clearDatabase,
                    icon: Icon(Icons.delete_outline, color: colorScheme.error),
                    label: Text('清空数据库', style: TextStyle(color: colorScheme.error)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colorScheme.error),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 目录树预览
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前文件目录:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _directoryTree.isEmpty ? '(暂无文件)' : _directoryTree,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}
