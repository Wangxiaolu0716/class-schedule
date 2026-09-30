import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/parsers/eams_course_table_parser.dart';

/// 用真实课表页面（宁波城市职业技术学院，宁波城市职业技术学院教务系统
/// 2026 学年第一学期）验证解析规则，样本见 test/fixtures/。
void main() {
  final html =
      File('test/fixtures/nbcc_course_table.html').readAsStringSync();
  final data = const EamsCourseTableParser().parse(html);

  test('每天节数取自 unitCount', () {
    expect(data.periodsPerDay, 14);
  });

  test('能从页面参数里取出学生 ID 与学期 ID', () {
    expect(data.studentId, isNotNull);
    expect(data.semesterId, isNotNull);
    expect(RegExp(r'^\d+$').hasMatch(data.studentId!), isTrue);
    expect(RegExp(r'^\d+$').hasMatch(data.semesterId!), isTrue);
  });

  test('课程名单解析出 15 门课', () {
    expect(data.courses.length, 15);
  });

  test('体育健康1：周四第 3-4 节，周次 5-8 与 10-17', () {
    final session = data.sessions.firstWhere(
      (s) => s.name == '体育健康1' && s.startPeriod == 3,
    );
    expect(session.dayOfWeek, 4);
    expect(session.periods, [3, 4]);
    expect(session.weeks, [5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17]);
    expect(session.room, '鄞州5-201乒乓球馆(鄞州校区)');
    expect(session.teacher, '周子安');
  });

  test('军事理论：周一第 10-11 节，双周 6-16', () {
    final session = data.sessions.firstWhere((s) => s.name == '军事理论');
    expect(session.dayOfWeek, 1);
    expect(session.periods, [10, 11]);
    expect(session.weeks, [6, 8, 10, 12, 14, 16]);
  });

  test('同一门课的多段排课全部保留（C语言程序设计有 3 段）', () {
    final sessions =
        data.sessions.where((s) => s.name == 'C语言程序设计').toList();
    expect(sessions.length, 3);
    for (final session in sessions) {
      expect(session.weeks, isNotEmpty);
      expect(session.room, isNotEmpty);
    }
  });

  test('未排课时间的课程仍出现在课程名单里', () {
    final names = data.courses.map((c) => c.name).toSet();
    expect(names, contains('军事技能训练'));
    expect(names, contains('劳动教育1（三年制）'));

    // 它们没有排课记录
    final sessionNames = data.sessions.map((s) => s.name).toSet();
    expect(sessionNames, isNot(contains('军事技能训练')));
  });

  test('HTML 里每个排课块都被解析出来，不丢课', () {
    final blockCount =
        RegExp(r'new\s+TaskActivity\s*\(').allMatches(html).length;
    expect(data.sessions.length, blockCount);
    expect(blockCount, 17);
  });

  test('课程名单里凡有排课时间的课程，都出现在课表中', () {
    final scheduled = data.sessions.map((s) => s.name).toSet();
    // 这几门课在教务系统里本就没有排课时间，不会出现在网格里
    const withoutSchedule = {
      '国家安全教育',
      '军事技能训练',
      '职业素质日常养成1（三年制）',
      '劳动教育1（三年制）',
      '心理健康教育实践1(三年制）',
    };
    for (final course in data.courses) {
      if (withoutSchedule.contains(course.name)) continue;
      expect(
        scheduled,
        contains(course.name),
        reason: '${course.name} 有排课时间却未出现在课表中',
      );
    }
  });

  group('从「我的课表」入口页提取接口参数', () {
    final entryHtml =
        File('test/fixtures/nbcc_course_table_entry.html').readAsStringSync();

    test('提取出学生 ID 与学期 ID', () {
      final candidates =
          EamsCourseTableParser.buildCourseTableParamsCandidates(entryHtml);
      expect(candidates, isNotEmpty);

      final first = candidates.first;
      expect(first, contains('ids=123456'));
      expect(first, contains('semester.id=279'));
      expect(first, contains('setting.kind=std'));
      expect(first, contains('ignoreHead=1'));
    });

    test('页面结构不符时返回空列表，而不是拼出错的参数', () {
      expect(
        EamsCourseTableParser.buildCourseTableParamsCandidates('<html></html>'),
        isEmpty,
      );
    });

    test('多框架时只在课表表单所在的框架取参数，不取到别的表单的学号', () {
      // 第一个框架放一个诱饵表单（例如成绩查询），学号是 999999。
      // 若按整段文本取第一个匹配就会取到它，请求必然失败。
      final page = [
        '${EamsCourseTableParser.frameMarker}0-->',
        '<html><body><script>',
        'bg.form.addInput(form,"ids","999999");',
        '</script></body></html>',
        '${EamsCourseTableParser.frameMarker}1-->',
        '<html><body>',
        '<form id="courseTableForm" action="/eams/courseTableForStd.action" '
            'method="post"></form>',
        '<script>var form = document.courseTableForm;',
        'function searchTable(){ bg.form.addInput(form,"ids","123456"); }',
        'semesterCalendar({empty:"false",onChange:"",value:"279"},'
            '"searchTable()");',
        '</script><div id="contentDiv"></div></body></html>',
      ].join('\n');

      final candidates =
          EamsCourseTableParser.buildCourseTableParamsCandidates(page);

      expect(candidates, isNotEmpty);
      expect(candidates.first, contains('ids=123456'));
      for (final candidate in candidates) {
        expect(candidate, isNot(contains('999999')));
      }
    });

    test('表单里的 project.id 会被带进候选参数', () {
      final page = [
        '${EamsCourseTableParser.frameMarker}0-->',
        '<html><body>',
        '<form id="courseTableForm" action="/eams/courseTableForStd.action">',
        '<input type="hidden" name="project.id" value="7">',
        '</form>',
        '<script>var form = document.courseTableForm;',
        'function searchTable(){ bg.form.addInput(form,"ids","123456"); }',
        'semesterCalendar({empty:"false",onChange:"",value:"279"},'
            '"searchTable()");',
        '</script></body></html>',
      ].join('\n');

      final candidates =
          EamsCourseTableParser.buildCourseTableParamsCandidates(page);

      expect(candidates, isNotEmpty);
      expect(candidates.first, contains('project.id=7'));
    });
  });
}