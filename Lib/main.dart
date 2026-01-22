// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:io';
import 'screens/main_chat_screen.dart';
import 'services/database_service.dart';
import 'services/conversation_service.dart';
import 'services/sub_conversation_service.dart';
import 'config/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await DatabaseService.instance.init();
  await AppConfig.instance.load();
  await ConversationService.instance.load();
  await SubConversationService.instance.load();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppConfig.instance,
      child: MaterialApp(
        title: 'AI Chat',
        debugShowCheckedModeBanner: false,
        // 添加中文本地化支持
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
            surface: Colors.black,
          ),
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          drawerTheme: const DrawerThemeData(
            backgroundColor: Colors.black,
          ),
          useMaterial3: true,
        ),

        themeMode: ThemeMode.system,
        home: const PermissionWrapper(),
      ),
    );
  }
}

class PermissionWrapper extends StatefulWidget {
  const PermissionWrapper({super.key});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  bool _isChecking = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) {
      setState(() {
        _isChecking = false;
        _hasPermission = true;
      });
      return;
    }

    final status = await Permission.manageExternalStorage.status;
    
    setState(() {
      _isChecking = false;
      _hasPermission = status.isGranted;
    });
  }

  Future<void> _requestPermission() async {
    final status = await Permission.manageExternalStorage.request();
    
    if (status.isGranted) {
      setState(() => _hasPermission = true);
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text('请在系统设置中允许"管理所有文件"权限，否则无法导入文件目录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
              await Future.delayed(const Duration(seconds: 1));
              _checkPermission();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                const Text(
                  '需要文件访问权限',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  '为了导入文件目录并读取其中的内容，需要您授予"管理所有文件"权限。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _requestPermission,
                  icon: const Icon(Icons.security),
                  label: const Text('授予权限'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _hasPermission = true),
                  child: const Text('暂时跳过（部分功能不可用）'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const MainChatScreen();
  }
}