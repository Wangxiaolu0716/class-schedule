import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/import/school_picker.dart';

/// 学校选择弹窗的高度稳定性。
///
/// 曾经的 bug：弹窗高度跟着内容走，先显示「加载中」（矮）、数据到了换成列表
/// （高），高度在入场滑动动画还没播完时就跳了一截，看起来是「闪一下」。
/// 所以这里钉住「高度只由屏幕决定，与内容多少无关」。
Future<void> openPicker(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSchoolPicker(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

/// 当前弹窗的高度
double sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(BottomSheet)).height;

void main() {
  testWidgets('高度在打开后就不变：搜索把列表过滤到更少，高度也不动', (tester) async {
    await openPicker(tester);

    final full = sheetHeight(tester);
    expect(full, greaterThan(0));

    // 过滤到只剩一所，内容明显变少
    await tester.enterText(find.byType(TextField), '横店');
    await tester.pumpAndSettle();
    expect(find.text('浙江横店影视职业学院'), findsOneWidget);

    expect(sheetHeight(tester), full, reason: '内容变少不该让弹窗高度跟着缩');
  });

  testWidgets('搜索到空结果时高度仍然不变', (tester) async {
    await openPicker(tester);

    final full = sheetHeight(tester);

    await tester.enterText(find.byType(TextField), '不存在的学校名');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的学校'), findsOneWidget);

    expect(sheetHeight(tester), full, reason: '空结果不该让弹窗高度塌下去');
  });

  testWidgets('高度约为屏幕高度的 0.68，且是个固定值', (tester) async {
    await openPicker(tester);

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    expect(sheetHeight(tester), closeTo(screenHeight * 0.68, 1));
  });

  testWidgets('本校与「手动输入网址」两个入口始终可见，不因列表长短而消失', (tester) async {
    await openPicker(tester);

    expect(find.text('宁波城市职业技术学院'), findsOneWidget);
    expect(find.text('其它学校（手动输入网址）'), findsOneWidget);

    // 输入搜索词后，固定底栏仍然在（只是本校那一项隐藏）
    await tester.enterText(find.byType(TextField), '横店');
    await tester.pumpAndSettle();

    expect(find.text('其它学校（手动输入网址）'), findsOneWidget);
  });
}