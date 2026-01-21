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

  /// 显示API历史记录选择器
  void _showApiHistoryPicker({required bool isMain}) {
    final config = AppConfig.instance;
    final history = isMain ? config.mainApiHistory : config.subApiHistory;
    
    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无历史记录，成功调用API后会自动保存')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) {
          final colorScheme = Theme.of(ctx).colorScheme;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.history, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '${isMain ? '主界面' : '子界面'} API 历史 (${history.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: history.length,
                  itemBuilder: (ctx, index) {
                    final item = history[index];
                    final isCurrentlyUsed = isMain
                        ? (item.url == _mainApiUrlController.text && item.key == _mainApiKeyController.text)
                        : (item.url == _subApiUrlController.text && item.key == _subApiKeyController.text);
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrentlyUsed ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.api,
                          color: isCurrentlyUsed ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        item.model,
                        style: TextStyle(
                          fontWeight: isCurrentlyUsed ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.url,
                            style: TextStyle(fontSize: 11, color: colorScheme.outline),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '密钥: ${_maskApiKey(item.key)}',
                            style: TextStyle(fontSize: 11, color: colorScheme.outline),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrentlyUsed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '当前',
                                style: TextStyle(fontSize: 10, color: colorScheme.onPrimaryContainer),
                              ),
                            ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
                            onPressed: () {
                              if (isMain) {
                                config.deleteMainApiHistory(item);
                              } else {
                                config.deleteSubApiHistory(item);
                              }
                              Navigator.pop(ctx);
                              _showApiHistoryPicker(isMain: isMain);
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        if (isMain) {
                          config.switchMainApi(item);
                          _mainApiUrlController.text = item.url;
                          _mainApiKeyController.text = item.key;
                          _mainModelController.text = item.model;
                        } else {
                          config.switchSubApi(item);
                          _subApiUrlController.text = item.url;
                          _subApiKeyController.text = item.key;
                          _subModelController.text = item.model;
                        }
                        Navigator.pop(ctx);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已切换到: ${item.model}')),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 遮盖API密钥
  String _maskApiKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }

  /// 打开全屏编辑器
  Future<void> _openFullscreenEditor({
    required String title,
    required String initialContent,
    required Function(String) onSave,
  }) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => _FullscreenEditorScreen(
          title: title,
          initialContent: initialContent,
        ),
      ),
    );
    
    if (result != null) {
      onSave(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final config = AppConfig.instance;
    
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true, actions: [TextButton(onPressed: _saveSettings, child: const Text('保存'))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 主界面 API 设置
            _buildSection('主界面 API 设置', Icons.api, [
              // API历史切换按钮
              if (config.mainApiHistory.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => _showApiHistoryPicker(isMain: true),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: Text('切换API配置 (${config.mainApiHistory.length})'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                ),
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
              // 主界面提示词 - 带全屏按钮
              Row(
                children: [
                  Expanded(
                    child: Text('主界面提示词', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.fullscreen, size: 20),
                    tooltip: '全屏编辑',
                    onPressed: () => _openFullscreenEditor(
                      title: '主界面提示词',
                      initialContent: _mainPromptController.text,
                      onSave: (content) {
                        _mainPromptController.text = content;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _buildTextField(_mainPromptController, '', '输入主界面的系统提示词...', maxLines: 4, showLabel: false),
            ]),
            const SizedBox(height: 24),
            
            // 子界面 API 设置
            _buildSection('子界面 API 设置', Icons.api, [
              // API历史切换按钮
              if (config.subApiHistory.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => _showApiHistoryPicker(isMain: false),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: Text('切换API配置 (${config.subApiHistory.length})'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                ),
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
            
            // 子界面提示词设置
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
              if (_currentSubLevel > 0 && _currentSubLevel <= _subPromptControllers.length) ...[
                // 子界面提示词 - 带全屏按钮
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_getLevelName(_currentSubLevel)}子界面提示词',
                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen, size: 20),
                      tooltip: '全屏编辑',
                      onPressed: () => _openFullscreenEditor(
                        title: '${_getLevelName(_currentSubLevel)}子界面提示词',
                        initialContent: _subPromptControllers[_currentSubLevel - 1].text,
                        onSave: (content) {
                          _subPromptControllers[_currentSubLevel - 1].text = content;
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildTextField(
                  _subPromptControllers[_currentSubLevel - 1],
                  '',
                  '输入${_getLevelName(_currentSubLevel)}子界面的系统提示词...',
                  maxLines: 4,
                  showLabel: false,
                ),
              ],
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

  Widget _buildTextField(TextEditingController controller, String label, String hint, {bool obscure = false, int maxLines = 1, bool showLabel = true}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: showLabel && label.isNotEmpty ? label : null,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}

/// 全屏编辑器
class _FullscreenEditorScreen extends StatefulWidget {
  final String title;
  final String initialContent;

  const _FullscreenEditorScreen({
    required this.title,
    required this.initialContent,
  });

  @override
  State<_FullscreenEditorScreen> createState() => _FullscreenEditorScreenState();
}

class _FullscreenEditorScreenState extends State<_FullscreenEditorScreen> {
  late TextEditingController _controller;
  bool _hasChanges = false;
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _charCount = widget.initialContent.length;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final newHasChanges = _controller.text != widget.initialContent;
    final newCharCount = _controller.text.length;
    
    if (newHasChanges != _hasChanges || newCharCount != _charCount) {
      setState(() {
        _hasChanges = newHasChanges;
        _charCount = newCharCount;
      });
    }
  }


  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {

    if (!_hasChanges) return true;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃更改？'),
        content: const Text('您有未保存的更改，确定要放弃吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (_hasChanges) {
                final shouldPop = await _onWillPop();
                if (shouldPop && context.mounted) {
                  Navigator.pop(context);
                }
              } else {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context, _controller.text);
              },
              icon: const Icon(Icons.check),
              label: const Text('保存'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: '输入提示词内容...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: colorScheme.outline),
              const SizedBox(width: 8),
              Text(
                '字数: $_charCount',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),

              const Spacer(),
              if (_hasChanges)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '有未保存的更改',
                    style: TextStyle(fontSize: 11, color: colorScheme.onPrimaryContainer),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
