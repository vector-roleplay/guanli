// lib/utils/message_detector.dart

class MessageDetector {
  // 检测【申请N级子界面】，返回级别数，没有则返回0
  int detectSubLevelRequest(String content) {
    // 匹配【申请一级子界面】【申请二级子界面】等
    final chineseNums = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    
    for (int i = 0; i < chineseNums.length; i++) {
      if (content.contains('【申请${chineseNums[i]}级子界面】')) {
        return i + 1;
      }
    }
    
    // 也支持阿拉伯数字：【申请1级子界面】
    final arabicRegex = RegExp(r'【申请(\d+)级子界面】');
    final match = arabicRegex.firstMatch(content);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? 0;
    }
    
    return 0;
  }

  // 检测【N级子界面提取结束，返回X】，返回当前级别，没有则返回0
  int detectReturnRequest(String content) {
    final chineseNums = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    
    for (int i = 0; i < chineseNums.length; i++) {
      if (content.contains('【${chineseNums[i]}级子界面提取结束，返回')) {
        return i + 1;
      }
    }
    
    // 也支持阿拉伯数字
    final arabicRegex = RegExp(r'【(\d+)级子界面提取结束，返回');
    final match = arabicRegex.firstMatch(content);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? 0;
    }
    
    return 0;
  }

  // 检测【请继续】
  bool hasContinue(String content) {
    return content.contains('【请继续】');
  }

  // 从内容中提取文件路径
  List<String> extractPaths(String content) {
    Set<String> paths = {};

    // 方法1：匹配反引号包裹的路径
    final backtickRegex = RegExp(r'`([^`]+\.[a-zA-Z0-9]+)`');
    for (var match in backtickRegex.allMatches(content)) {
      final path = match.group(1);
      if (path != null && path.contains('/')) {
        paths.add(path.trim());
      }
    }

    // 方法2：匹配数字列表中的路径
    final listRegex = RegExp(r'^\s*\d+[\.\)、]\s*(.+\.[a-zA-Z0-9]+)\s*$', multiLine: true);
    for (var match in listRegex.allMatches(content)) {
      var path = match.group(1);
      if (path != null) {
        path = path.replaceAll('`', '').trim();
        if (path.contains('/')) {
          paths.add(path);
        }
      }
    }

    // 方法3：匹配显式标记的路径
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
    final generalRegex = RegExp(
      r'([^\s\[\]【】\n][^\[\]【】\n]*?/[^\[\]【】\n]*?\.[a-zA-Z0-9]+)',
    );
    for (var match in generalRegex.allMatches(content)) {
      var path = match.group(1);
      if (path != null) {
        path = path.replaceAll('`', '').trim();
        if (!path.startsWith('http') && !path.startsWith('//')) {
          paths.add(path);
        }
      }
    }

    return paths.toList();
  }

  // 获取中文数字
  static String getChineseNumber(int num) {
    const chineseNums = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (num >= 1 && num <= 10) {
      return chineseNums[num - 1];
    }
    return num.toString();
  }
}
