import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/schedule_screen.dart';
import 'screens/watermark_settings_screen.dart';
import 'watermark/three_finger_tap.dart';
import 'watermark/watermark_overlay.dart';
import 'watermark/watermark_settings.dart';

void main() {
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

  WatermarkSettings _watermark = WatermarkSettings.defaults;

  @override
  void initState() {
    super.initState();
    _loadWatermark();
  }

  Future<void> _loadWatermark() async {
    final settings = await _watermarkStore.load();
    if (!mounted) return;
    setState(() => _watermark = settings);
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
    return MaterialApp(
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
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
    );
  }
}