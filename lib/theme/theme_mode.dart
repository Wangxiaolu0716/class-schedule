import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 全局主题模式：白天 / 夜晚 / 跟随系统。
///
/// 单独做成全局 notifier，是因为改它的在设置页（`MaterialApp.home` 之下好几层），
/// 而用它的是根部的 `MaterialApp`，一路传回调不划算。
final ValueNotifier<ThemeMode> appThemeMode =
    ValueNotifier<ThemeMode>(ThemeMode.system);

/// 主题模式的本地存储。
///
/// 与其它设置一样放在应用私有目录，不随课表导入被覆盖。
class ThemeModeStore {
  const ThemeModeStore();

  static const String _fileName = 'theme_mode.txt';

  /// 弹窗里的显示顺序：按用户直觉从「白天」到「自动」
  static const List<ThemeMode> pickOrder = [
    ThemeMode.light,
    ThemeMode.dark,
    ThemeMode.system,
  ];

  static String label(ThemeMode mode) {
    if (mode == ThemeMode.light) return '白天模式';
    if (mode == ThemeMode.dark) return '夜晚模式';
    return '跟随系统';
  }

  Future<ThemeMode> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    if (!await file.exists()) return ThemeMode.system;
    return _fromName((await file.readAsString()).trim());
  }

  Future<void> save(ThemeMode mode) async {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/$_fileName').writeAsString(_name(mode));
  }

  /// 存的是名字而不是枚举下标：以后枚举顺序变了也不会读串。
  static String _name(ThemeMode mode) {
    if (mode == ThemeMode.light) return 'light';
    if (mode == ThemeMode.dark) return 'dark';
    return 'system';
  }

  static ThemeMode _fromName(String name) {
    if (name == 'light') return ThemeMode.light;
    if (name == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }
}
