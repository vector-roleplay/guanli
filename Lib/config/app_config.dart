// lib/config/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
  
  // 文件大小限制 (bytes)
  static const int maxChunkSize = 900 * 1024; // 900KB

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
}
