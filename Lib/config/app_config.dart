// lib/config/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// API配置项（用于保存历史记录）
class ApiConfig {
  final String url;
  final String key;
  final String model;
  final DateTime lastUsed;

  ApiConfig({
    required this.url,
    required this.key,
    required this.model,
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  /// 生成唯一标识（用于去重）
  String get uniqueId => '$url|$key';

  Map<String, dynamic> toJson() => {
    'url': url,
    'key': key,
    'model': model,
    'lastUsed': lastUsed.toIso8601String(),
  };

  factory ApiConfig.fromJson(Map<String, dynamic> json) => ApiConfig(
    url: json['url'] ?? '',
    key: json['key'] ?? '',
    model: json['model'] ?? '',
    lastUsed: json['lastUsed'] != null ? DateTime.parse(json['lastUsed']) : DateTime.now(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiConfig && runtimeType == other.runtimeType && uniqueId == other.uniqueId;

  @override
  int get hashCode => uniqueId.hashCode;
}

class AppConfig extends ChangeNotifier {
  static final AppConfig instance = AppConfig._internal();
  AppConfig._internal();

  // 主界面API配置
  String mainApiUrl = '';
  String mainApiKey = '';
  String mainModel = 'gpt-4';
  
  // 子界面API配置（所有级别共用）
  String subApiUrl = '';
  String subApiKey = '';
  String subModel = 'gpt-4';
  
  // 主界面提示词
  String mainPrompt = '';
  
  // 多级子界面提示词 (索引0=一级, 1=二级, ...)
  List<String> subPrompts = ['', '', '', '', ''];  // 预设5级
  
  // API配置历史记录
  List<ApiConfig> _mainApiHistory = [];
  List<ApiConfig> _subApiHistory = [];
  
  List<ApiConfig> get mainApiHistory => List.unmodifiable(_mainApiHistory);
  List<ApiConfig> get subApiHistory => List.unmodifiable(_subApiHistory);

  // 文件大小限制（按token估算，1 token ≈ 4字符）
  static const int maxTokens = 900000; // 90万token
  static const int maxChunkSize = maxTokens * 4; // 约360万字符

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    
    mainApiUrl = prefs.getString('mainApiUrl') ?? 'https://api.openai.com/v1';
    mainApiKey = prefs.getString('mainApiKey') ?? '';
    mainModel = prefs.getString('mainModel') ?? 'gpt-4';
    
    subApiUrl = prefs.getString('subApiUrl') ?? 'https://api.openai.com/v1';
    subApiKey = prefs.getString('subApiKey') ?? '';
    subModel = prefs.getString('subModel') ?? 'gpt-4';
    
    mainPrompt = prefs.getString('mainPrompt') ?? '';
    
    // 加载多级提示词
    final subPromptsJson = prefs.getString('subPrompts');
    if (subPromptsJson != null) {
      try {
        final list = jsonDecode(subPromptsJson) as List;
        subPrompts = list.map((e) => e.toString()).toList();
        // 确保至少5级
        while (subPrompts.length < 5) {
          subPrompts.add('');
        }
      } catch (e) {
        subPrompts = ['', '', '', '', ''];
      }
    }
    
    // 加载API历史记录
    final mainHistoryJson = prefs.getString('mainApiHistory');
    if (mainHistoryJson != null) {
      try {
        final list = jsonDecode(mainHistoryJson) as List;
        _mainApiHistory = list.map((e) => ApiConfig.fromJson(e)).toList();
        // 按最近使用时间排序
        _mainApiHistory.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      } catch (e) {
        _mainApiHistory = [];
      }
    }
    
    final subHistoryJson = prefs.getString('subApiHistory');
    if (subHistoryJson != null) {
      try {
        final list = jsonDecode(subHistoryJson) as List;
        _subApiHistory = list.map((e) => ApiConfig.fromJson(e)).toList();
        _subApiHistory.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      } catch (e) {
        _subApiHistory = [];
      }
    }
    
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString('mainApiUrl', mainApiUrl);
    await prefs.setString('mainApiKey', mainApiKey);
    await prefs.setString('mainModel', mainModel);
    
    await prefs.setString('subApiUrl', subApiUrl);
    await prefs.setString('subApiKey', subApiKey);
    await prefs.setString('subModel', subModel);
    
    await prefs.setString('mainPrompt', mainPrompt);
    await prefs.setString('subPrompts', jsonEncode(subPrompts));
    
    // 保存API历史记录
    await prefs.setString('mainApiHistory', jsonEncode(_mainApiHistory.map((e) => e.toJson()).toList()));
    await prefs.setString('subApiHistory', jsonEncode(_subApiHistory.map((e) => e.toJson()).toList()));
    
    notifyListeners();
  }

  void updateMainApi({String? url, String? key, String? model}) {
    if (url != null) mainApiUrl = url;
    if (key != null) mainApiKey = key;
    if (model != null) mainModel = model;
    save();
  }

  void updateSubApi({String? url, String? key, String? model}) {
    if (url != null) subApiUrl = url;
    if (key != null) subApiKey = key;
    if (model != null) subModel = model;
    save();
  }

  void updateMainPrompt(String prompt) {
    mainPrompt = prompt;
    save();
  }

  // 获取某一级的提示词
  String getSubPrompt(int level) {
    if (level < 1 || level > subPrompts.length) return '';
    return subPrompts[level - 1];
  }

  // 设置某一级的提示词
  void setSubPrompt(int level, String prompt) {
    if (level < 1) return;
    // 自动扩展列表
    while (subPrompts.length < level) {
      subPrompts.add('');
    }
    subPrompts[level - 1] = prompt;
    save();
  }

  // 添加新级别
  void addSubPromptLevel() {
    subPrompts.add('');
    save();
  }

  // 获取总级别数
  int get subPromptLevels => subPrompts.length;

  /// 记录成功使用的主界面API配置
  void recordMainApiSuccess() {
    if (mainApiUrl.isEmpty || mainApiKey.isEmpty) return;
    
    final config = ApiConfig(
      url: mainApiUrl,
      key: mainApiKey,
      model: mainModel,
    );
    
    // 移除已存在的相同配置
    _mainApiHistory.removeWhere((c) => c.uniqueId == config.uniqueId);
    // 添加到开头
    _mainApiHistory.insert(0, config);
    // 最多保留10条
    if (_mainApiHistory.length > 10) {
      _mainApiHistory = _mainApiHistory.sublist(0, 10);
    }
    save();
  }

  /// 记录成功使用的子界面API配置
  void recordSubApiSuccess() {
    if (subApiUrl.isEmpty || subApiKey.isEmpty) return;
    
    final config = ApiConfig(
      url: subApiUrl,
      key: subApiKey,
      model: subModel,
    );
    
    _subApiHistory.removeWhere((c) => c.uniqueId == config.uniqueId);
    _subApiHistory.insert(0, config);
    if (_subApiHistory.length > 10) {
      _subApiHistory = _subApiHistory.sublist(0, 10);
    }
    save();
  }

  /// 切换到指定的主界面API配置
  void switchMainApi(ApiConfig config) {
    mainApiUrl = config.url;
    mainApiKey = config.key;
    mainModel = config.model;
    
    // 更新使用时间
    _mainApiHistory.removeWhere((c) => c.uniqueId == config.uniqueId);
    _mainApiHistory.insert(0, ApiConfig(
      url: config.url,
      key: config.key,
      model: config.model,
    ));
    
    save();
  }

  /// 切换到指定的子界面API配置
  void switchSubApi(ApiConfig config) {
    subApiUrl = config.url;
    subApiKey = config.key;
    subModel = config.model;
    
    _subApiHistory.removeWhere((c) => c.uniqueId == config.uniqueId);
    _subApiHistory.insert(0, ApiConfig(
      url: config.url,
      key: config.key,
      model: config.model,
    ));
    
    save();
  }

  /// 删除主界面API历史记录
  void deleteMainApiHistory(ApiConfig config) {
    _mainApiHistory.removeWhere((c) => c.uniqueId == config.uniqueId);
    save();
  }

  /// 删除子界面API历史记录
  void deleteSubApiHistory(ApiConfig config) {
    _subApiHistory.removeWhere((c) => c.uniqueId == config.uniqueId);
    save();
  }
}
