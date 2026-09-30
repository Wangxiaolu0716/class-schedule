import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/watermark/three_finger_tap.dart';

/// 三根手指同时按下、再依次抬起，算一次「三指敲击」
Future<void> threeFingerTap(WidgetTester tester) async {
  final first = await tester.startGesture(const Offset(100, 300));
  final second = await tester.startGesture(const Offset(180, 300));
  final third = await tester.startGesture(const Offset(260, 300));
  await first.up();
  await second.up();
  await third.up();
}

Future<void> pumpDetector(WidgetTester tester, VoidCallback onTrigger) {
  return tester.pumpWidget(
    MaterialApp(
      home: ThreeFingerTapDetector(
        onTrigger: onTrigger,
        child: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  );
}

void main() {
  testWidgets('三指敲击三下触发彩蛋入口', (tester) async {
    var triggered = 0;
    await pumpDetector(tester, () => triggered++);

    for (var i = 0; i < 3; i++) {
      await threeFingerTap(tester);
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(triggered, 1);
  });

  testWidgets('只敲两下不触发', (tester) async {
    var triggered = 0;
    await pumpDetector(tester, () => triggered++);

    for (var i = 0; i < 2; i++) {
      await threeFingerTap(tester);
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(triggered, 0);
    // 把计数定时器跑完，避免测试结束时还有未完成的定时器
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('单指连点三下不算数', (tester) async {
    var triggered = 0;
    await pumpDetector(tester, () => triggered++);

    for (var i = 0; i < 3; i++) {
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(triggered, 0);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('三指敲击间隔太长会重新计数', (tester) async {
    var triggered = 0;
    await pumpDetector(tester, () => triggered++);

    await threeFingerTap(tester);
    // 超过两下之间允许的最大间隔
    await tester.pump(ThreeFingerTapDetector.betweenTaps * 2);
    await threeFingerTap(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await threeFingerTap(tester);

    expect(triggered, 0);
    await tester.pump(const Duration(seconds: 2));
  });
}