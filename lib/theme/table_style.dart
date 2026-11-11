/// 课表外观：样式预设 + 自定义背景。
///
/// 单独存一份 `appearance.json`，与课表配置分开：重新导入课表只会覆盖
/// `table_config.json`，外观是用户自己挑的，不该跟着教务数据一起被冲掉。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 一套配色预设。
///
/// 不给每门课写死颜色，只给一组「色相」+ 浅色/深色两套明度饱和度：
/// 同一门课按课名哈希稳定地落到某个色相上，换预设时整屏一起变，
/// 新增预设也只是加一条数据。
class TableStylePreset {
  const TableStylePreset({
    required this.id,
    required this.name,
    required this.description,
    this.hues = const [],
    required this.lightSaturation,
    required this.lightLightness,
    required this.darkSaturation,
    required this.darkLightness,
    required this.seed,
    this.lightBackground,
    this.darkBackground,
    this.outlined = false,
    this.cardAlpha = 1,
  });

  /// 存进 json 的稳定标识，改名不影响已保存的选择
  final String id;

  /// 显示名
  final String name;

  /// 一句话说明它长什么样
  final String description;

  /// 课程色的候选色相。空表示按课名哈希取任意色相（经典款）
  final List<int> hues;

  final double lightSaturation;
  final double lightLightness;
  final double darkSaturation;
  final double darkLightness;

  /// 主题种子色：按钮、开关、选中态跟着它走
  final int seed;

  /// 页面底色；null 表示跟随 Material 主题默认底色（经典款）
  final int? lightBackground;
  final int? darkBackground;

  /// 卡片用描边代替实底（纸感、水墨这类）
  final bool outlined;

  /// 卡片不透明度上限。玻璃感这类需要透出背景，取 < 1
  final double cardAlpha;

  Color? backgroundOf(bool dark) {
    final value = dark ? darkBackground : lightBackground;
    return value == null ? null : Color(value);
  }

  static const List<TableStylePreset> all = [
    TableStylePreset(
      id: 'classic',
      name: '经典',
      description: '跟随深浅色主题，颜色按课名自动分配',
      lightSaturation: 0.45,
      lightLightness: 0.89,
      darkSaturation: 0.38,
      darkLightness: 0.32,
      seed: 0xFF3F51B5,
    ),
    TableStylePreset(
      id: 'paper',
      name: '纸感',
      description: '米色纸底配暖色描边，像贴在手账上的课表',
      hues: [34, 12, 6, 190, 120, 268, 42, 320],
      lightSaturation: 0.32,
      lightLightness: 0.84,
      darkSaturation: 0.30,
      darkLightness: 0.26,
      seed: 0xFF8A6A47,
      lightBackground: 0xFFF6F0E4,
      darkBackground: 0xFF1C1A16,
      outlined: true,
      cardAlpha: 0.9,
    ),
    TableStylePreset(
      id: 'morandi',
      name: '莫兰迪',
      description: '灰调低饱和，整屏很安静，久看不累',
      hues: [12, 36, 88, 150, 196, 240, 300, 330],
      lightSaturation: 0.20,
      lightLightness: 0.82,
      darkSaturation: 0.24,
      darkLightness: 0.30,
      seed: 0xFF8C8578,
      lightBackground: 0xFFEDEBE7,
      darkBackground: 0xFF1A1A1A,
    ),
    TableStylePreset(
      id: 'ink',
      name: '水墨',
      description: '近乎无彩色，只靠明度分层，留白很多',
      hues: [210, 205, 215, 200, 220, 195, 225, 212],
      lightSaturation: 0.06,
      lightLightness: 0.86,
      darkSaturation: 0.08,
      darkLightness: 0.24,
      seed: 0xFF30343B,
      lightBackground: 0xFFF7F6F3,
      darkBackground: 0xFF121212,
      outlined: true,
    ),
    TableStylePreset(
      id: 'glass',
      name: '玻璃感',
      description: '半透明卡片配柔光，最适合搭一张背景图',
      hues: [200, 170, 220, 250, 190, 280, 160, 230],
      lightSaturation: 0.40,
      lightLightness: 0.88,
      darkSaturation: 0.35,
      darkLightness: 0.34,
      seed: 0xFF4C6FFF,
      lightBackground: 0xFFEDF1F7,
      darkBackground: 0xFF0F1319,
      cardAlpha: 0.62,
    ),
    TableStylePreset(
      id: 'candy',
      name: '糖果',
      description: '明亮高饱和，一眼就能分清哪门课是哪门',
      hues: [345, 150, 45, 265, 200, 10, 320, 95],
      lightSaturation: 0.62,
      lightLightness: 0.87,
      darkSaturation: 0.50,
      darkLightness: 0.40,
      seed: 0xFFFF5C8A,
      lightBackground: 0xFFFDF7FB,
      darkBackground: 0xFF17121C,
    ),
    TableStylePreset(
      id: 'midnight',
      name: '午夜',
      description: '深蓝底配冷色，夜里打开不刺眼',
      hues: [205, 190, 225, 250, 175, 265, 215, 235],
      lightSaturation: 0.30,
      lightLightness: 0.86,
      darkSaturation: 0.45,
      darkLightness: 0.30,
      seed: 0xFF2A3A5A,
      lightBackground: 0xFFEEF2F8,
      darkBackground: 0xFF0A0E16,
    ),
  ];

  static TableStylePreset byId(String? id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return all.first;
  }
}

/// 自定义背景图与它的三个可调数值。
class TableBackground {
  const TableBackground({
    this.imagePath,
    this.opacity = 0.35,
    this.blur = 0,
    this.dim = 0.15,
  });

  /// 复制进应用私有目录后的图片路径；null 表示不用背景图
  final String? imagePath;

  /// 图片本身的不透明度
  final double opacity;

  /// 高斯模糊半径，压掉细节让课表更清楚
  final double blur;

  /// 盖在图片上的压暗层，深色文字压在白底图上更清楚
  final double dim;

  bool get hasImage => (imagePath ?? '').isNotEmpty;

  TableBackground copyWith({
    String? imagePath,
    bool clearImage = false,
    double? opacity,
    double? blur,
    double? dim,
  }) {
    return TableBackground(
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      opacity: opacity ?? this.opacity,
      blur: blur ?? this.blur,
      dim: dim ?? this.dim,
    );
  }

  Map<String, dynamic> toJson() => {
    'imagePath': imagePath,
    'opacity': opacity,
    'blur': blur,
    'dim': dim,
  };

  static TableBackground fromJson(Map<String, dynamic> json) {
    const defaults = TableBackground();
    return TableBackground(
      imagePath: json['imagePath'] as String?,
      opacity: (json['opacity'] as num?)?.toDouble() ?? defaults.opacity,
      blur: (json['blur'] as num?)?.toDouble() ?? defaults.blur,
      dim: (json['dim'] as num?)?.toDouble() ?? defaults.dim,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TableBackground &&
      other.imagePath == imagePath &&
      other.opacity == opacity &&
      other.blur == blur &&
      other.dim == dim;

  @override
  int get hashCode => Object.hash(imagePath, opacity, blur, dim);
}

/// 整套外观设置
class TableAppearance {
  const TableAppearance({
    this.presetId = 'classic',
    this.background = const TableBackground(),
    this.cardAlpha = 1,
  });

  final String presetId;
  final TableBackground background;

  /// 卡片不透明度。与预设自带的 [TableStylePreset.cardAlpha] 取小值
  final double cardAlpha;

  TableStylePreset get preset => TableStylePreset.byId(presetId);

  /// 卡片最终不透明度：预设与用户滑杆都限制，别让格子彻底看不见
  double get effectiveCardAlpha =>
      (cardAlpha * preset.cardAlpha).clamp(0.25, 1.0).toDouble();

  TableAppearance copyWith({
    String? presetId,
    TableBackground? background,
    double? cardAlpha,
  }) {
    return TableAppearance(
      presetId: presetId ?? this.presetId,
      background: background ?? this.background,
      cardAlpha: cardAlpha ?? this.cardAlpha,
    );
  }

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'background': background.toJson(),
    'cardAlpha': cardAlpha,
  };

  static TableAppearance fromJson(Map<String, dynamic> json) {
    const defaults = TableAppearance();
    final rawBackground = json['background'];
    return TableAppearance(
      presetId: json['presetId'] as String? ?? defaults.presetId,
      background: rawBackground is Map<String, dynamic>
          ? TableBackground.fromJson(rawBackground)
          : defaults.background,
      cardAlpha: (json['cardAlpha'] as num?)?.toDouble() ?? defaults.cardAlpha,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TableAppearance &&
      other.presetId == presetId &&
      other.background == background &&
      other.cardAlpha == cardAlpha;

  @override
  int get hashCode => Object.hash(presetId, background, cardAlpha);
}

/// 当前外观。与主题模式、字体一样做成全局 notifier：
/// 改它在设置页，用它的是课表页与根部 `MaterialApp`。
final ValueNotifier<TableAppearance> appAppearance =
    ValueNotifier<TableAppearance>(const TableAppearance());

/// 把一套预设 + 深浅色解析成具体颜色。
///
/// 课表页只跟这个类打交道，换预设不用改页面代码。
class TablePalette {
  const TablePalette(this.appearance, {required this.dark});

  final TableAppearance appearance;
  final bool dark;

  TableStylePreset get preset => appearance.preset;

  /// 页面底色；经典款返回 null 表示跟随主题
  Color? get background => preset.backgroundOf(dark);

  /// 主题种子色
  Color get seed => Color(preset.seed);

  /// 卡片不透明度
  double get cardAlpha => appearance.effectiveCardAlpha;

  /// 网格线：描边风格重一点，否则淡一点
  Color get gridLine => dark
      ? Colors.white.withValues(alpha: preset.outlined ? 0.18 : 0.08)
      : Colors.black.withValues(alpha: preset.outlined ? 0.16 : 0.06);

  /// 左侧节次数字
  Color get labelColor => dark
      ? Colors.white.withValues(alpha: 0.72)
      : Colors.black.withValues(alpha: 0.66);

  /// 左侧节次钟点
  Color get labelSubColor => dark
      ? Colors.white.withValues(alpha: 0.42)
      : Colors.black.withValues(alpha: 0.38);

  /// 某门课的卡片颜色。[key] 用课名或自建条目的稳定 id。
  Color cardColor(String key, {required bool faded}) {
    final hue = _hueOf(key);
    final saturation = dark ? preset.darkSaturation : preset.lightSaturation;
    final lightness = dark ? preset.darkLightness : preset.lightLightness;
    if (faded) {
      return HSLColor.fromAHSL(
        1,
        hue,
        saturation * (dark ? 0.45 : 0.22),
        dark ? lightness * 0.62 : 0.96,
      ).toColor();
    }
    return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
  }

  /// 描边风格用的边框色：比填充色深一档，否则边框和底色都是同一个浅色，
  /// 在纸感/水墨这类预设下等于没有边框
  Color borderOn(Color card) {
    final hsl = HSLColor.fromColor(card);
    final lightness = dark
        ? (hsl.lightness + 0.18).clamp(0.0, 1.0)
        : (hsl.lightness - 0.22).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor().withValues(alpha: 0.9);
  }

  /// 卡片上的文字：浅底配深字，深底配浅字，由卡片自身亮度决定，
  /// 换预设或换成深色底都不用另配一套文字色
  Color textColorOn(Color card, {required bool secondary}) {
    final light = card.computeLuminance() > 0.42;
    if (secondary) {
      return light
          ? Colors.black.withValues(alpha: 0.55)
          : Colors.white.withValues(alpha: 0.72);
    }
    return light
        ? Colors.black.withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.95);
  }

  double _hueOf(String key) {
    if (preset.hues.isEmpty) return (_hashOf(key) % 360).toDouble();
    return preset.hues[_hashOf(key) % preset.hues.length].toDouble();
  }

  /// 与 Dart `String.hashCode` 不同，这里必须跨进程稳定：同一个课名
  /// 每次启动、每台设备都要落到同一个颜色上。
  static int _hashOf(String text) {
    var hash = 0;
    for (final unit in text.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

/// 外观设置的本地存储
class AppearanceStore {
  const AppearanceStore();

  static const String _fileName = 'appearance.json';
  static const String _dirName = 'background';
  static const String _prefix = 'bg.';

  Future<TableAppearance> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return const TableAppearance();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return TableAppearance.fromJson(decoded);
      }
    } catch (_) {
      // 外观只是装饰，读坏了就用默认的，不该影响启动
    }
    return const TableAppearance();
  }

  Future<void> save(TableAppearance appearance) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/$_fileName')
          .writeAsString(jsonEncode(appearance.toJson()));
    } catch (_) {
      // 存不下来只影响下次启动
    }
  }

  /// 把用户选的背景图复制进私有目录，返回新路径。
  ///
  /// name 里带上扩展名：`Image.file` 不解码猜格式，扩展名不对在某些机型上
  /// 会直接解不出来。
  Future<String> importBackground(File source) async {
    final dir = await _dir();
    // 一张背景图就够，换图时把旧的删掉，免得越占越多
    for (final entity in await dir.list().toList()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith(_prefix)) {
        await entity.delete();
      }
    }
    final lower = source.path.toLowerCase();
    final ext = [
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
    ].firstWhere(lower.endsWith, orElse: () => '.jpg');
    final target = File('${dir.path}/$_prefix$ext');
    await target.writeAsBytes(await source.readAsBytes(), flush: true);
    return target.path;
  }

  Future<void> clearBackground() async {
    final dir = await _dir();
    for (final entity in await dir.list().toList()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith(_prefix)) {
        await entity.delete();
      }
    }
  }

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
