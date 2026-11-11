import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/theme/table_style.dart';

void main() {
  group('样式预设', () {
    test('未知 id 回落到第一个预设，不抛异常', () {
      expect(TableStylePreset.byId('不存在的预设').id, 'classic');
      expect(TableStylePreset.byId(null).id, 'classic');
    });

    test('每个预设的 id 唯一，否则存盘读回来会串', () {
      final ids = TableStylePreset.all.map((p) => p.id).toSet();
      expect(ids.length, TableStylePreset.all.length);
    });

    test('同一门课的颜色跨调用稳定：换周、重进都还是那个色', () {
      const palette = TablePalette(TableAppearance(), dark: false);
      expect(
        palette.cardColor('高等数学', faded: false),
        palette.cardColor('高等数学', faded: false),
      );
      // 不同课名要能区分开，否则整屏一个颜色
      expect(
        palette.cardColor('高等数学', faded: false),
        isNot(palette.cardColor('大学英语', faded: false)),
      );
    });

    test('非本周的格子比本周更淡，浅色下明度更高', () {
      const palette = TablePalette(TableAppearance(), dark: false);
      final now = palette.cardColor('高等数学', faded: false);
      final faded = palette.cardColor('高等数学', faded: true);

      expect(faded.computeLuminance(), greaterThan(now.computeLuminance()));
    });

    test('文字颜色跟着卡片亮度走：浅底配深字', () {
      const palette = TablePalette(TableAppearance(), dark: false);
      final light = palette.cardColor('高等数学', faded: false);
      final text = palette.textColorOn(light, secondary: false);

      expect(text.computeLuminance(), lessThan(light.computeLuminance()));
    });

    test('描边预设能认出来，玻璃感的不透明度上限低于 1', () {
      final paper = TableStylePreset.byId('paper');
      final glass = TableStylePreset.byId('glass');

      expect(paper.outlined, isTrue);
      expect(glass.outlined, isFalse);
      expect(glass.cardAlpha, lessThan(1));
    });
  });

  group('外观设置', () {
    test('序列化后能原样读回来', () {
      const appearance = TableAppearance(
        presetId: 'glass',
        cardAlpha: 0.8,
        background: TableBackground(
          imagePath: '/tmp/bg.jpg',
          opacity: 0.5,
          blur: 6,
          dim: 0.2,
        ),
      );

      final restored = TableAppearance.fromJson(
        jsonDecode(jsonEncode(appearance.toJson())) as Map<String, dynamic>,
      );

      expect(restored, appearance);
    });

    test('字段缺失时逐项回落默认值，不让整份设置作废', () {
      final restored = TableAppearance.fromJson({'presetId': 'paper'});

      expect(restored.presetId, 'paper');
      expect(restored.cardAlpha, 1);
      expect(restored.background.hasImage, isFalse);
    });

    test('卡片不透明度与预设取小值，并卡在能看清的下限', () {
      const glass = TableAppearance(presetId: 'glass', cardAlpha: 1);
      expect(
        glass.effectiveCardAlpha,
        TableStylePreset.byId('glass').cardAlpha,
      );

      const faint = TableAppearance(presetId: 'classic', cardAlpha: 0.1);
      expect(faint.effectiveCardAlpha, 0.25);
    });

    test('去掉背景图只清路径，滑杆上的数值留着', () {
      const background = TableBackground(
        imagePath: '/tmp/bg.jpg',
        opacity: 0.4,
        blur: 8,
      );

      final cleared = background.copyWith(clearImage: true);

      expect(cleared.hasImage, isFalse);
      expect(cleared.opacity, 0.4);
      expect(cleared.blur, 8);
    });

    test('预设给了底色就按它来，经典款留空表示跟随主题', () {
      expect(
        TableStylePreset.byId('paper').backgroundOf(false),
        const Color(0xFFF6F0E4),
      );
      expect(TableStylePreset.byId('classic').backgroundOf(false), isNull);
    });
  });
}
