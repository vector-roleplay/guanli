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
    Set<String> paths = {};

    // 方法1：匹配反引号包裹的路径（最可靠）
    // 例如: `第二层1/第三层11/index (2).js`
    final backtickRegex = RegExp(r'`([^`]+\.[a-zA-Z0-9]+)`');
    for (var match in backtickRegex.allMatches(content)) {
      final path = match.group(1);
      if (path != null && path.contains('/')) {
        paths.add(path.trim());
      }
    }

    // 方法2：匹配数字列表中的路径
    // 例如: 1. 第二层1/第三层11/file.js
    //       2. folder/subfolder/test.txt
    final listRegex = RegExp(r'^\s*\d+[\.\)、]\s*(.+\.[a-zA-Z0-9]+)\s*$', multiLine: true);
    for (var match in listRegex.allMatches(content)) {
      var path = match.group(1);
      if (path != null) {
        // 去掉反引号如果有
        path = path.replaceAll('`', '').trim();
        if (path.contains('/')) {
          paths.add(path);
        }
      }
    }

    // 方法3：匹配显式标记的路径
    // 例如: 路径: xxx, path: xxx, 文件: xxx
    final explicitRegex = RegExp(
      r'(?:路径|path|文件|file)[：:\s]+[`]?([^`\n\[\]【】]+\.[a-zA-Z0-9]+)[`]?',
      caseSensitive: false,
    );
    for (var match in explicitRegex.allMatches(content)) {
      final path = match.group(1);
      if (path != null && path.contains('/')) {
        paths.add(path.trim());
      }
    }

    // 方法4：匹配常见路径格式（支持中文、空格、括号）
    // 例如: 第二层1/第三层11/server (1).js
    final generalRegex = RegExp(
      r'([^\s\[\]【】\n][^\[\]【】\n]*?/[^\[\]【】\n]*?\.[a-zA-Z0-9]+)',
    );
    for (var match in generalRegex.allMatches(content)) {
      var path = match.group(1);
      if (path != null) {
        path = path.replaceAll('`', '').trim();
        // 过滤掉URL
        if (!path.startsWith('http') && !path.startsWith('//')) {
          paths.add(path);
        }
      }
    }

    return paths.toList();
  }
}
