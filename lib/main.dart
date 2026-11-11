import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'reminder/class_reminder.dart';
import 'screens/schedule_screen.dart';
import 'screens/watermark_settings_screen.dart';
import 'theme/app_font.dart';
import 'theme/table_style.dart';
import 'theme/theme_mode.dart';
import 'watermark/three_finger_tap.dart';
import 'watermark/watermark_overlay.dart';
import 'watermark/watermark_settings.dart';

void main() async {
  // 字体注册必须放在 runApp 之前：第一帧就用自定义字体渲染，
  // 否则开屏会先闪一下系统字体再切过来。
  WidgetsFlutterBinding.ensureInitialized();
  appFont.value = await const AppFontStore().load();
  // 课前通知的插件与时区提前初始化好：课表页一读出来就能立刻重排提醒
  await const ClassReminderService().init();
  runApp(const NbccScheduleApp());
}

class NbccScheduleApp extends StatefulWidget {
  const NbccScheduleApp({super.key});

  @override
  State<NbccScheduleApp> createState() => _NbccScheduleAppState();
}

class _NbccScheduleAppState extends State<NbccScheduleApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final WatermarkStore _watermarkStore = const WatermarkStore();
  final ThemeModeStore _themeStore = const ThemeModeStore();
  final AppearanceStore _appearanceStore = const AppearanceStore();

  WatermarkSettings _watermark = WatermarkSettings.defaults;

  @override
  void initState() {
    super.initState();
    _loadWatermark();
    _loadThemeMode();
    _loadAppearance();
  }

  Future<void> _loadWatermark() async {
    final settings = await _watermarkStore.load();
    if (!mounted) return;
    setState(() => _watermark = settings);
  }

  /// 主题模式读盘后写进全局 notifier，`MaterialApp` 跟着重建。
  ///
  /// 读出来之前先用默认的「跟随系统」，避免开屏闪一下白。
  Future<void> _loadThemeMode() async {
    appThemeMode.value = await _themeStore.load();
  }

  /// 外观（样式预设 + 背景）读盘后写进全局 notifier。
  ///
  /// 读出来之前先用默认预设，避免开屏先按别的配色画一帧再跳。
  Future<void> _loadAppearance() async {
    appAppearance.value = await _appearanceStore.load();
  }

  /// 主题配色，外加用户自己导入的字体包。
  ///
  /// 没导入字体时一个 fontFamily 都不设，用系统自带字体（安卓是思源黑体、
  /// iOS 是苹方），安装包里也就不带任何字体文件。
  ThemeData _buildTheme(Brightness brightness) {
    // 选中的样式预设决定种子色与页面底色，整套界面（含设置页、弹窗）跟着走
    final preset = appAppearance.value.preset;
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Color(preset.seed),
        brightness: brightness,
      ),
    );
    final background = preset.backgroundOf(brightness == Brightness.dark);
    final themed = base.copyWith(
      scaffoldBackgroundColor: background ?? base.scaffoldBackgroundColor,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: background ?? base.colorScheme.surface,
        // Material 3 默认给 AppBar 加一层随内容变化的着色，换背景后会很脏
        surfaceTintColor: Colors.transparent,
      ),
    );
    if (appFont.value == null) return themed;
    return themed.copyWith(
      textTheme: themed.textTheme.apply(fontFamily: AppFontStore.familyName),
      primaryTextTheme: themed.primaryTextTheme.apply(
        fontFamily: AppFontStore.familyName,
      ),
    );
  }

  /// 彩蛋入口：三指轻敲三次打开水印的隐藏设置页。
  ///
  /// 隐藏页在 `MaterialApp.builder` 之上，拿不到 Navigator，所以走 navigatorKey。
  Future<void> _openWatermarkSettings() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => WatermarkSettingsScreen(
          initial: _watermark,
          // 边调边看：整屏水印立刻跟着变
          onChanged: (settings) => setState(() => _watermark = settings),
        ),
      ),
    );
    // 拖动过程中不写盘，退出隐藏页时存一次就够
    await _watermarkStore.save(_watermark);
  }

  @override
  Widget build(BuildContext context) {
    // 主题模式与自定义字体都在设置页里改，这里一并监听，跟着换配色和字体
    return AnimatedBuilder(
      // 配色、字体、外观任何一项变了，MaterialApp 都要跟着重建
      animation: Listenable.merge([appThemeMode, appFont, appAppearance]),
      builder: (context, _) => MaterialApp(
        title: '课表',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        // 让日期选择器等系统控件显示中文
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: appThemeMode.value,
        // 这两层都挂在 builder 上，全局所有页面与弹窗都盖得住：
        // 外面是彩蛋手势，里面是水印。页面里不用重复加。
        builder: (context, child) => ThreeFingerTapDetector(
          onTrigger: _openWatermarkSettings,
          child: AppWatermark(
            settings: _watermark,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: const ScheduleScreen(),
      ),
    );
  }
}
