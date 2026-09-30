import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/theme/theme_mode.dart';

void main() {
  test('三种模式都有名字，且互不相同', () {
    final labels = ThemeMode.values.map(ThemeModeStore.label).toSet();

    expect(labels.length, ThemeMode.values.length);
    expect(labels.contains('白天模式'), isTrue);
    expect(labels.contains('夜晚模式'), isTrue);
    expect(labels.contains('跟随系统'), isTrue);
  });

  test('弹窗里的三种模式一个不少、也一个不多', () {
    // 以后 Flutter 加了新模式，这里会先失败，提醒把入口补上
    expect(ThemeModeStore.pickOrder.toSet(), ThemeMode.values.toSet());
    expect(ThemeModeStore.pickOrder.length, ThemeMode.values.length);
  });

  test('默认是跟随系统，不是写死白天', () {
    expect(appThemeMode.value, ThemeMode.system);
  });
}
