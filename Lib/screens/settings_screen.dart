// Lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _mainApiUrlController;
  late TextEditingController _mainApiKeyController;
  late TextEditingController _mainModelController;
  late TextEditingController _mainPromptController;

  late TextEditingController _subApiUrlController;
  late TextEditingController _subApiKeyController;
  late TextEditingController _subModelController;

  List<TextEditingController> _subPromptControllers = [];
  int _currentSubLevel = 1;

  bool _loadingMainModels = false;
  bool _loadingSubModels = false;

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
    _initSubPromptControllers();
  }

  void _initSubPromptControllers() {
    final config = AppConfig.instance;
    _subPromptControllers = [];
    for (int i = 0; i < config.subPromptLevels; i++) {
      _subPromptControllers.add(TextEditingController(text: config.subPrompts[i]));
    }
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
    for (var c in _subPromptControllers) c.dispose();
    super.dispose();
  }

  Future<void> _fetchMainModels() async {
    final url = _mainApiUrlController.text.trim();
    final key = _mainApiKeyController.text.trim();
    if (url.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写API地址和密钥')));
      return;
    }
    setState(() => _loadingMainModels = true);
    try {
      final models = await ApiService.getModels(url, key);
      setState(() => _loadingMainModels = false);
      if (models.isNotEmpty) _showModelPicker(models, _mainModelController);
    } catch (e) {
      setState(() => _loadingMainModels = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取模型失败: $e')));
    }
  }

  Future<void> _fetchSubModels() async {
    final url = _subApiUrlController.text.trim();
    final key = _subApiKeyController.text.trim();
    if (url.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写API地址和密钥')));
      return;
    }
    setState(() => _loadingSubModels = true);
    try {
      final models = await ApiService.getModels(url, key);
      setState(() => _loadingSubModels = false);
      if (models.isNotEmpty) _showModelPicker(models, _subModelController);
    } catch (e) {
      setState(() => _loadingSubModels = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取模型失败: $e')));
    }
  }

  void _showModelPicker(List<String> models, TextEditingController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.9, expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text('选择模型 (${models.length}个)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: models.length,
                itemBuilder: (ctx, index) {
                  final model = models[index];
                  final isSelected = controller.text == model;
                  return ListTile(
                    title: Text(model),
                    trailing: isSelected ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
                    onTap: () { controller.text = model; Navigator.pop(ctx); setState(() {}); },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveSettings() {
    final config = AppConfig.instance;
    config.updateMainApi(url: _mainApiUrlController.text.trim(), key: _mainApiKeyController.text.trim(), model: _mainModelController.text.trim());
    config.updateSubApi(url: _subApiUrlController.text.trim(), key: _subApiKeyController.text.trim(), model: _subModelController.text.trim());
    config.updateMainPrompt(_mainPromptController.text.trim());
    for (int i = 0; i < _subPromptControllers.length; i++) {
      config.setSubPrompt(i + 1, _subPromptControllers[i].text.trim());
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存'), duration: Duration(seconds: 1)));
  }

  void _addSubPromptLevel() {
    setState(() {
      _subPromptControllers.add(TextEditingController());
      _currentSubLevel = _subPromptControllers.length;
    });
    AppConfig.instance.addSubPromptLevel();
  }

  String _getLevelName(int level) {
    const chineseNums = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (level >= 1 && level <= 10) return '${chineseNums[level - 1]}级';
    return '$level级';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true, actions: [TextButton(onPressed: _saveSettings, child: const Text('保存'))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('主界面 API 设置', Icons.api, [
              _buildTextField(_mainApiUrlController, 'API地址', 'https://api.openai.com/v1'),
              const SizedBox(height: 12),
              _buildTextField(_mainApiKeyController, 'API密钥', 'sk-xxx', obscure: true),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _buildTextField(_mainModelController, '模型', 'gpt-4')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _loadingMainModels ? null : _fetchMainModels, child: _loadingMainModels ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('获取')),
              ]),
              const SizedBox(height: 12),
              _buildTextField(_mainPromptController, '主界面提示词', '输入主界面的系统提示词...', maxLines: 4),
            ]),
            const SizedBox(height: 24),
            _buildSection('子界面 API 设置', Icons.api, [
              _buildTextField(_subApiUrlController, 'API地址', 'https://api.openai.com/v1'),
              const SizedBox(height: 12),
              _buildTextField(_subApiKeyController, 'API密钥', 'sk-xxx', obscure: true),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _buildTextField(_subModelController, '模型', 'gpt-4')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _loadingSubModels ? null : _fetchSubModels, child: _loadingSubModels ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('获取')),
              ]),
            ]),
            const SizedBox(height: 24),
            _buildSection('子界面提示词设置', Icons.layers, [
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _subPromptControllers.length + 1,
                  itemBuilder: (ctx, index) {
                    if (index == _subPromptControllers.length) {
                      return Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('添加'), onPressed: _addSubPromptLevel));
                    }
                    final level = index + 1;
                    final isSelected = _currentSubLevel == level;
                    return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(_getLevelName(level)), selected: isSelected, onSelected: (s) { if (s) setState(() => _currentSubLevel = level); }));
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (_currentSubLevel > 0 && _currentSubLevel <= _subPromptControllers.length)
                _buildTextField(_subPromptControllers[_currentSubLevel - 1], '${_getLevelName(_currentSubLevel)}子界面提示词', '输入${_getLevelName(_currentSubLevel)}子界面的系统提示词...', maxLines: 4),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint, {bool obscure = false, int maxLines = 1}) {
    return TextField(controller: controller, obscureText: obscure, maxLines: maxLines, decoration: InputDecoration(labelText: label, hintText: hint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)));
  }
}