import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 全局水印的可调参数。
///
/// 默认值是按「看得见但不碍事」定的：字号偏小、间距偏大、透明度很低。
/// 三指轻敲屏幕三次可以进入隐藏页自行调整，调完落在本地。
class WatermarkSettings {
  const WatermarkSettings({
    this.text = '测试中 @王小路 制作',
    this.fontSize = 15,
    this.spacing = 260,
    this.opacity = 0.07,
    this.angle = -0.32,
  });

  /// 水印文案
  final String text;

  /// 字号
  final double fontSize;

  /// 疏密：相邻两个水印的横向间距，越大越稀
  final double spacing;

  /// 透明度，0 为完全透明
  final double opacity;

  /// 倾斜角度（弧度）。负值是从左上往右下斜，约 -18°
  final double angle;

  /// 纵向间距与横向间距的比例。压扁一点更像常见的斜水印排版
  static const double verticalRatio = 0.85;

  double get horizontalStep => spacing;

  double get verticalStep => spacing * verticalRatio;

  /// 出厂默认值
  static const WatermarkSettings defaults = WatermarkSettings();

  WatermarkSettings copyWith({
    String? text,
    double? fontSize,
    double? spacing,
    double? opacity,
    double? angle,
  }) {
    return WatermarkSettings(
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      spacing: spacing ?? this.spacing,
      opacity: opacity ?? this.opacity,
      angle: angle ?? this.angle,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'fontSize': fontSize,
        'spacing': spacing,
        'opacity': opacity,
        'angle': angle,
      };

  static WatermarkSettings fromJson(Map<String, dynamic> json) {
    final defaults = WatermarkSettings.defaults;
    return WatermarkSettings(
      text: json['text'] as String? ?? defaults.text,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? defaults.fontSize,
      spacing: (json['spacing'] as num?)?.toDouble() ?? defaults.spacing,
      opacity: (json['opacity'] as num?)?.toDouble() ?? defaults.opacity,
      angle: (json['angle'] as num?)?.toDouble() ?? defaults.angle,
    );
  }

  /// 供 `CustomPainter.shouldRepaint` 比较用
  @override
  bool operator ==(Object other) =>
      other is WatermarkSettings &&
      other.text == text &&
      other.fontSize == fontSize &&
      other.spacing == spacing &&
      other.opacity == opacity &&
      other.angle == angle;

  @override
  int get hashCode => Object.hash(text, fontSize, spacing, opacity, angle);
}

/// 水印参数的本地存储
class WatermarkStore {
  const WatermarkStore();

  static const String _fileName = 'watermark.json';

  /// 读取水印参数；没存过或文件损坏时返回默认值。
  ///
  /// 水印只是装饰，任何异常都不该影响应用启动，所以这里吞掉所有错误。
  Future<WatermarkSettings> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return WatermarkSettings.defaults;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return WatermarkSettings.fromJson(decoded);
      }
    } catch (_) {
      // 按默认值处理
    }
    return WatermarkSettings.defaults;
  }

  Future<void> save(WatermarkSettings settings) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/$_fileName')
          .writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // 保存失败只影响下次启动，不影响当前使用
    }
  }
}