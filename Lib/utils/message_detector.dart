// lib/utils/message_detector.dart

class MessageDetector {
  // 检测【请求说明书】
  bool hasRequestDoc(String content) {
    return content.contains('【请求说明书】');
  }

  // 检测【本次提取结束，请返回主界面】
  bool hasReturnToMain(String content) {
    return content.contains('【本次提取结束，请返回主界面】');
  }

  // 检测【请继续】
  bool hasContinue(String content) {
    return content.contains('【请继续】');
  }

  // 从内容中提取文件路径
  List<String> extractPaths(String content) {
    List<String> paths = [];

    // 匹配常见路径格式
    // 例如: /folder/file.txt, ./src/main.dart, folder/subfolder/file.py
    final pathRegex = RegExp(
      r'(?:^|[\s\[\]（）()【】])([./]?(?:[\w\-]+/)+[\w\-]+\.[\w]+)',
      multiLine: true,
    );

    final matches = pathRegex.allMatches(content);
    for (var match in matches) {
      final path = match.group(1);
      if (path != null && !paths.contains(path)) {
        paths.add(path);
      }
    }

    // 也匹配显式标记的路径
    // 例如: 路径: xxx, path: xxx, 文件: xxx
    final explicitPathRegex = RegExp(
      r'(?:路径|path|文件|file)[：:\s]+([^\s\n\[\]【】]+)',
      caseSensitive: false,
    );

    final explicitMatches = explicitPathRegex.allMatches(content);
    for (var match in explicitMatches) {
      final path = match.group(1);
      if (path != null && !paths.contains(path)) {
        paths.add(path);
      }
    }

    return paths;
  }
}
