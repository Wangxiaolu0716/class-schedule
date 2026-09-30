import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/watermark/watermark_settings.dart';

void main() {
  test('默认值就是约定的那一套：15sp、稀疏、很淡', () {
    const settings = WatermarkSettings.defaults;

    expect(settings.text, '测试中 @王小路 制作');
    expect(settings.fontSize, 15);
    expect(settings.spacing, 260);
    expect(settings.opacity, 0.07);
  });

  test('纵向间距按比例跟着疏密走，避免两个方向各自为政', () {
    const settings = WatermarkSettings(spacing: 200);

    expect(settings.horizontalStep, 200);
    expect(settings.verticalStep, 200 * WatermarkSettings.verticalRatio);
  });

  test('序列化后能原样读回来', () {
    const settings = WatermarkSettings(
      fontSize: 22,
      spacing: 300,
      opacity: 0.15,
      angle: -0.5,
    );

    final restored = WatermarkSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );

    expect(restored, settings);
  });

  test('字段缺失时只回落到默认值，不会整个配置作废', () {
    final restored = WatermarkSettings.fromJson({'fontSize': 30});

    expect(restored.fontSize, 30);
    expect(restored.spacing, WatermarkSettings.defaults.spacing);
    expect(restored.text, WatermarkSettings.defaults.text);
  });

  test('改过和没改过的不相等，shouldRepaint 才判断得出来', () {
    const base = WatermarkSettings();

    expect(base, const WatermarkSettings());
    expect(base == base.copyWith(opacity: base.opacity + 0.01), isFalse);
  });
}