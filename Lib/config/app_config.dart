// lib/config/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig extends ChangeNotifier {
  static final AppConfig instance = AppConfig._internal();
  AppConfig._internal();

  // 主界面API配置
  String mainApiUrl = '';
  String mainApiKey = '';
  String mainModel = 'gpt-4';
  
  // 子界面API配置
  String subApiUrl = '';
  String subApiKey = '';
  String subModel = 'gpt-4';
  
  // 提示词
  String mainPrompt = '';      // 主界面提示词
  String subPrompt = '';       // 子界面提示词
  
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
    subPrompt = prefs.getString('subPrompt') ?? '';
    
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
    await prefs.setString('subPrompt', subPrompt);
    
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

  void updatePrompts({String? main, String? sub}) {
    if (main != null) mainPrompt = main;
    if (sub != null) subPrompt = sub;
    save();
  }
}
