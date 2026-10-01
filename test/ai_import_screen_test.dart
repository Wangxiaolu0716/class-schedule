import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/import/ai_import_screen.dart';
import 'package:nbcc_schedule/models/course.dart';

/// 界面 pop 回来的课表数据，测试里读它来断言导入结果
CourseTableData? imported;

/// 被写进剪贴板的内容，用来验证「复制提示词」抄走的到底是什么
final List<String> clipboard = [];

/// 把界面推起来
Future<void> _open(WidgetTester tester, {String? url}) async {
  imported = null;

  // 默认 800×600 的测试窗口装不下整页，ListView 又只构建可见部分，
  // 断言上方的卡片就会落空。把窗口开高些，让整页都真实存在。
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            imported = await Navigator.of(context).push<CourseTableData>(
              MaterialPageRoute(
                builder: (_) => AiImportScreen(lastManualUrl: url),
              ),
            );
          },
          child: const Text('打开'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

/// 界面比测试窗口高，按钮常常在屏幕外，点之前得先滚到可见位置
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  const json = '[{"name":"高等数学","teacher":"张三","classRoom":"综合楼313",'
      '"weekday":"星期一","fixWeeks":"1-4周","courseNumbers":"1-2节"}]';

  setUp(() {
    clipboard.clear();
    // 剪贴板走的是平台通道，测试环境里得自己接住
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  testWidgets('粘进 JSON 点识别，出预览并确认导入', (tester) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField), json);
    await _tap(tester, find.text('识别'));

    expect(find.text('识别结果：1 条'), findsOneWidget);
    expect(find.textContaining('导入这 1 门课'), findsOneWidget);
    // 预览里逐条列出课程，方便用户核对
    expect(find.textContaining('周一 第1-2节'), findsOneWidget);

    await _tap(tester, find.textContaining('导入这 1 门课'));

    expect(imported, isNotNull);
    expect(imported!.sessions.single.name, '高等数学');
  });

  testWidgets('粘进看不出来的内容时报错，且不出现导入按钮', (tester) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField), '抱歉，我看不清这张图片。');
    await _tap(tester, find.text('识别'));

    expect(find.textContaining('没找到 JSON'), findsOneWidget);
    expect(find.textContaining('导入这'), findsNothing);
  });

  testWidgets('内容为空时提示先粘贴，不会崩', (tester) async {
    await _open(tester);

    await _tap(tester, find.text('识别'));

    expect(find.text('请先把 AI 返回的内容粘进来'), findsOneWidget);
  });

  testWidgets('带上次填过的教务网址时直接显示，不用再填一次', (tester) async {
    await _open(tester, url: 'https://jw.example.edu.cn');

    expect(find.text('https://jw.example.edu.cn'), findsOneWidget);
    expect(find.text('打开学校教务系统'), findsOneWidget);
  });

  testWidgets('没填过网址时不提前显示「换地址」，避免点了个没用的按钮', (tester) async {
    await _open(tester);

    expect(find.text('换地址'), findsNothing);
    expect(find.text('打开学校教务系统'), findsOneWidget);
  });

  testWidgets('复制的提示词里带着解析器认的字段名', (tester) async {
    await _open(tester);

    await _tap(tester, find.text('复制提示词'));

    // 提示词与解析器的字段名必须一致，否则用户照做的结果是导不进来
    expect(clipboard, hasLength(1));
    for (final field in ['name', 'teacher', 'classRoom', 'weekday', 'fixWeeks', 'courseNumbers']) {
      expect(clipboard.single, contains(field));
    }
    expect(find.textContaining('已复制'), findsOneWidget);
  });
}
