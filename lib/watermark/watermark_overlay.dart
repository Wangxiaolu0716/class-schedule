import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'watermark_settings.dart';

/// 全局水印层。
///
/// 挂在 `MaterialApp.builder` 上，因此所有页面、弹窗、对话框都会被它盖住，
/// 不需要每个页面单独加。它只是视觉装饰，绝不参与命中测试——水印再密也
/// 不会影响任何点击。
class AppWatermark extends StatelessWidget {
  const AppWatermark({super.key, required this.settings, required this.child});

  final WatermarkSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 深色背景上黑水印等于看不见，跟着主题翻成白色
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    return CustomPaint(
      // 用前景画笔：先画 child，再把水印叠在上面
      foregroundPainter: WatermarkPainter(settings, color: color),
      child: child,
    );
  }
}

/// 把水印按倾斜角度平铺满整块画布
class WatermarkPainter extends CustomPainter {
  const WatermarkPainter(this.settings, {required this.color});

  final WatermarkSettings settings;

  /// 水印本身的颜色。透明度仍由 [settings] 里的值决定，这里只管基色，
  /// 因为深色主题下黑水印是完全看不见的。
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final label = TextPainter(
      text: TextSpan(
        text: settings.text,
        style: TextStyle(
          fontSize: settings.fontSize,
          color: color.withValues(alpha: settings.opacity),
          fontWeight: FontWeight.w500,
          letterSpacing: 2,
        ),
      ),
      // 文本方向必须显式给出：水印层在 MaterialApp 的 builder 上，
      // 这里拿不到 Directionality，也不能依赖它
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    // 以画布中心为轴旋转，再按最长边向四周铺开，保证四个角也盖得到
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(settings.angle);
    final reach = math.max(size.width, size.height);
    for (var y = -reach; y <= reach; y += settings.verticalStep) {
      for (var x = -reach; x <= reach; x += settings.horizontalStep) {
        label.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  /// 前景绘制层默认不拦事件（返回 null 即视为 false），这里显式写成 false，
  /// 让「水印不吃点击」这件事靠代码本身成立，而不依赖框架默认值
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant WatermarkPainter oldDelegate) =>
      oldDelegate.settings != settings || oldDelegate.color != color;
}