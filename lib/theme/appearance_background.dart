import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'table_style.dart';

/// 课表页最底下那层：预设底色 + 可选的自定义背景图。
///
/// 图片按「透明度 / 模糊 / 压暗」三档调，都是用户自己滑的：
/// 原图多半很花，直接铺上去课表就看不清了。
class AppearanceBackground extends StatelessWidget {
  const AppearanceBackground({
    super.key,
    required this.appearance,
    required this.dark,
  });

  final TableAppearance appearance;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final base =
        appearance.preset.backgroundOf(dark) ??
        Theme.of(context).scaffoldBackgroundColor;
    final background = appearance.background;
    if (!background.hasImage) return ColoredBox(color: base);

    final path = background.imagePath!;
    final image = Image.file(
      File(path),
      fit: BoxFit.cover,
      // 用户从系统相册选完又删掉原图之类的情况：当没设过背景
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    final blur = background.blur.clamp(0.0, 40.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        Opacity(
          opacity: background.opacity.clamp(0.0, 1.0),
          child: blur < 0.5
              ? image
              : ClipRect(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: blur,
                      sigmaY: blur,
                    ),
                    child: image,
                  ),
                ),
        ),
        // 压暗层让格子上的字在任何照片上都读得清
        if (background.dim > 0)
          ColoredBox(
            color: Colors.black.withValues(
              alpha: background.dim.clamp(0.0, 0.8),
            ),
          ),
      ],
    );
  }
}
