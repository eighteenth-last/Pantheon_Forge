import 'dart:convert';
import 'package:flutter/material.dart';

class AnsiParser {
  static final _ansiRegex = RegExp(
    r'\x1b\[[0-9;?]*[a-zA-Z]|'  // CSI 序列
    r'\x1b\].*?\x07|'           // OSC 序列
    r'\x1b[=<>]|'               // 特殊模式
    r'\x08',                    // 退格
    multiLine: true,
  );

  static final _colorCodeRegex = RegExp(r'\x1b\[([0-9;]*)m');

  /// 移除所有 ANSI 转义序列
  static String stripAnsi(String input) {
    return input.replaceAll(_ansiRegex, '');
  }

  /// 解析 ANSI 颜色并返回带格式的 TextSpan
  static List<TextSpan> parseAnsi(String input, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    final lines = input.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      
      final tokens = _tokenize(line);
      TextStyle currentStyle = baseStyle;
      StringBuffer currentText = StringBuffer();
      
      for (final token in tokens) {
        if (token is AnsiColorCode) {
          // 保存当前文本
          if (currentText.isNotEmpty) {
            spans.add(TextSpan(text: currentText.toString(), style: currentStyle));
            currentText.clear();
          }
          // 更新样式
          currentStyle = _applyColor(currentStyle, token, baseStyle);
        } else if (token is String) {
          currentText.write(token);
        }
      }
      
      // 添加最后的文本
      if (currentText.isNotEmpty) {
        spans.add(TextSpan(text: currentText.toString(), style: currentStyle));
      }
    }
    
    return spans;
  }

  static List<dynamic> _tokenize(String input) {
    final List<dynamic> tokens = [];
    final matches = _colorCodeRegex.allMatches(input);
    
    int lastEnd = 0;
    for (final match in matches) {
      // 添加普通文本
      if (match.start > lastEnd) {
        tokens.add(input.substring(lastEnd, match.start));
      }
      // 添加颜色代码
      tokens.add(AnsiColorCode(match.group(1) ?? ''));
      lastEnd = match.end;
    }
    
    // 添加剩余文本
    if (lastEnd < input.length) {
      tokens.add(input.substring(lastEnd));
    }
    
    return tokens;
  }

  static TextStyle _applyColor(TextStyle currentStyle, AnsiColorCode colorCode, TextStyle baseStyle) {
    final codes = colorCode.codes.split(';');
    
    for (final code in codes) {
      final c = int.tryParse(code) ?? 0;
      
      if (c == 0) {
        // 重置
        return baseStyle;
      } else if (c == 1) {
        // 粗体
        currentStyle = currentStyle.copyWith(fontWeight: FontWeight.bold);
      } else if (c >= 30 && c <= 37) {
        // 前景色
        currentStyle = currentStyle.copyWith(color: _getForegroundColor(c));
      } else if (c >= 40 && c <= 47) {
        // 背景色
        currentStyle = currentStyle.copyWith(backgroundColor: _getBackgroundColor(c - 40));
      } else if (c >= 90 && c <= 97) {
        // 亮前景色
        currentStyle = currentStyle.copyWith(color: _getBrightForegroundColor(c));
      }
    }
    
    return currentStyle;
  }

  static Color _getForegroundColor(int code) {
    const colors = [
      Color(0xFF000000), // 30 - 黑色
      Color(0xFFCD3131), // 31 - 红色
      Color(0xFF0DBC79), // 32 - 绿色
      Color(0xFFE5E510), // 33 - 黄色
      Color(0xFF2472C8), // 34 - 蓝色
      Color(0xFFBC3FBC), // 35 - 紫色
      Color(0xFF11A8CD), // 36 - 青色
      Color(0xFFCCCCCC), // 37 - 白色
    ];
    return colors[code - 30];
  }

  static Color _getBrightForegroundColor(int code) {
    const colors = [
      Color(0xFF666666), // 90 - 亮黑
      Color(0xFFF14C4C), // 91 - 亮红
      Color(0xFF23D18B), // 92 - 亮绿
      Color(0xFFF5F543), // 93 - 亮黄
      Color(0xFF3B8EEA), // 94 - 亮蓝
      Color(0xFFD670FF), // 95 - 亮紫
      Color(0xFF29B8DB), // 96 - 亮青
      Color(0xFFFFFFFF), // 97 - 亮白
    ];
    return colors[code - 90];
  }

  static Color _getBackgroundColor(int code) {
    const colors = [
      Color(0xFF000000), // 40 - 黑
      Color(0xFFCD3131), // 41 - 红
      Color(0xFF0DBC79), // 42 - 绿
      Color(0xFFE5E510), // 43 - 黄
      Color(0xFF2472C8), // 44 - 蓝
      Color(0xFFBC3FBC), // 45 - 紫
      Color(0xFF11A8CD), // 46 - 青
      Color(0xFFCCCCCC), // 47 - 白
    ];
    return colors[code];
  }
}

class AnsiColorCode {
  final String codes;
  AnsiColorCode(this.codes);
}
