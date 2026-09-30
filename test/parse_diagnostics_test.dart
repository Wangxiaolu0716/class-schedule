import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/parsers/parse_diagnostics.dart';

/// 诊断报告要能区分三种情况：真课表页、入口页、无关页面。
/// 判断错了会让「验证别的学校」这件事直接失去意义，所以这里逐条钉死。
void main() {
  const diagnostics = ParseDiagnostics();
  final tableHtml =
      File('test/fixtures/nbcc_course_table.html').readAsStringSync();
  final entryHtml =
      File('test/fixtures/nbcc_course_table_entry.html').readAsStringSync();

  test('真实课表页：报告解析正常并给出关键计数', () {
    final report = diagnostics.report(tableHtml);

    expect(report, contains('解析正常'));
    expect(report, contains('使用的解析器：正方 EAMS'));
    expect(report, contains('一天节数：14'));
    expect(report, contains('排课段：17'));
    expect(report, contains('课程名单：15 门'));
    // 学生与学期 ID 是从页面参数里取的，取不到就说明入口参数识别退化
    expect(report, isNot(contains('学生 ID：未取到')));
    expect(report, isNot(contains('学期 ID：未取到')));
  });

  test('真实课表页：报告里带前几条排课，方便肉眼核对', () {
    final report = diagnostics.report(tableHtml);

    expect(report, contains('=== 前 5 条排课 ==='));
    expect(report, contains('周次'));
    // 节次、地点都要出现在预览里
    expect(report, contains('第3-4节'));
  });

  test('入口页：要认出来是入口页，而不是「不是课表页」', () {
    final report = diagnostics.report(entryHtml);

    expect(report, contains('这是「我的课表」入口页'));
    expect(report, contains('候选参数'));
    expect(report, isNot(contains('解析正常')));
  });

  test('无关页面：明确说这不是课表页，并给出该怎么做', () {
    final report = diagnostics.report('<html><body><p>hello</p></body></html>');

    expect(report, contains('既不是课表页，也不是「我的课表」入口页'));
    expect(report, contains('再点「导课」'));
  });

  test('有 TaskActivity 但解析不出排课：提示可能是非正方系统', () {
    const html = '<html><body><script>var a = new TaskActivity(1,2,3);'
        '</script></body></html>';
    final report = diagnostics.report(html);

    expect(report, contains('但没解析出任何排课'));
    expect(report, contains('不是标准的正方 EAMS 结构'));
  });

  test('空输入不会让工具自己崩掉', () {
    final report = diagnostics.report('');

    expect(report, contains('=== 输入 ==='));
    expect(report, contains('=== 结论 ==='));
    expect(report, contains('字符数：0'));
  });

  group('正方新版 jwglxt 页面', () {
    final jwglxtHtml =
        File('test/fixtures/jwglxt_course_table.html').readAsStringSync();

    test('报告要认得出是 jwglxt，且 EAMS 解析器不认识它', () {
      final report = diagnostics.report(jwglxtHtml);

      expect(report, contains('使用的解析器：正方新版 jwglxt'));
      expect(report, contains('· 正方 EAMS：未识别'));
      expect(report, contains('解析正常'));
    });

    test('识别出来的排课数与课程数要和解析器一致', () {
      final report = diagnostics.report(jwglxtHtml);

      expect(report, contains('排课段：11'));
      expect(report, contains('课程名单：10 门'));
      expect(report, contains('学生 ID：2501100000'));
      expect(report, contains('学期 ID：2026-2027-1'));
    });
  });
}