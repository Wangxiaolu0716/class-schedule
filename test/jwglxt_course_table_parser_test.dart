import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/parsers/course_table_parser.dart';
import 'package:nbcc_schedule/parsers/jwglxt_course_table_parser.dart';

/// 用真实页面（另一所学校的正方新版 jwglxt 学生课表）验证解析规则。
///
/// 样本已脱敏：真实姓名与学号已替换，结构一字未动。
void main() {
  final html =
      File('test/fixtures/jwglxt_course_table.html').readAsStringSync();
  final data = const JwglxtCourseTableParser().parse(html);

  group('识别与总体结果', () {
    test('靠 kblist_table 认出是 jwglxt', () {
      expect(const JwglxtCourseTableParser().matches(html), isTrue);
      expect(const JwglxtCourseTableParser().matches('<html></html>'), isFalse);
    });

    test('EAMS 解析器不该抢着认领这份页面', () {
      expect(matchedParserNames(html), ['正方新版 jwglxt']);
    });

    test('按顺序试解析器时选中 jwglxt', () {
      final parsed = parseWithAny(html);

      expect(parsed, isNotNull);
      expect(parsed!.parserName, '正方新版 jwglxt');
      expect(parsed.data.sessions.length, 11);
    });

    test('一天节数取最晚的节次，学生与学期从标题栏取', () {
      expect(data.periodsPerDay, 13);
      expect(data.studentId, '2501100000');
      expect(data.semesterId, '2026-2027-1');
    });
  });

  group('排课内容', () {
    test('人工智能应用基础：周二第 1-2 节，第 4-17 周', () {
      final session = data.sessions.firstWhere((s) => s.name == '人工智能应用基础');

      expect(session.dayOfWeek, 2);
      expect(session.periods, [1, 2]);
      expect(session.weeks.first, 4);
      expect(session.weeks.last, 17);
      expect(session.room, '计算机机房（一）（制作楼-4层）');
      expect(session.teacher, '黄志远');
    });

    test('课名后的类型标记（★■◆☆）要被去掉', () {
      for (final session in data.sessions) {
        expect(session.name.contains('★'), isFalse, reason: session.name);
      }
    });

    test('跨多节的课按起止节次展开，如数字视频编辑占周五 6-8 节', () {
      final session = data.sessions.firstWhere((s) => s.name == '数字视频编辑');

      expect(session.dayOfWeek, 5);
      expect(session.periods, [6, 7, 8]);
      expect(session.room, '虚拟制片工坊（制作楼408）');
    });

    test('周数不是从第 1 周开始的课要按实际周次解析', () {
      final session = data.sessions.firstWhere((s) => s.name == '形势与政策(1)');

      expect(session.dayOfWeek, 2);
      expect(session.periods, [10, 11, 12, 13]);
      expect(session.weeks, [16, 17]);
    });

    test('周六没课也不该被当成有课', () {
      expect(data.sessions.any((s) => s.dayOfWeek == 6), isFalse);
    });

    test('周日第 1-2 节的大学英语要被解析出来', () {
      final session = data.sessions.firstWhere(
        (s) => s.dayOfWeek == 7 && s.periods.first == 1,
      );

      expect(session.name, '大学英语(1)');
    });
  });

  group('课程名单', () {
    test('按教学班去重：同一门课排两次只算一门', () {
      // 大学英语(1) 在周二和周日各有一段
      final english = data.sessions.where((s) => s.name == '大学英语(1)');
      expect(english.length, 2);
      expect(data.courses.where((c) => c.name == '大学英语(1)').length, 1);
    });

    test('课程序号用教学班，便于识别同一门课的不同班', () {
      final course = data.courses.firstWhere((c) => c.name == '大学英语(1)');
      expect(course.courseId, '大学英语(1)-0055');
      expect(course.teacher, '唐文清');
    });
  });

  group('冒号写法与字段缺失的兼容', () {
    /// 拼一段最小可用的列表式课表，正文按真实页面那种一堆 font/span 包着来写
    String pageWithInfo(String info) => '''
<table id="kblist_table"><tbody id="xq_1">
<tr><td id="jc_1-1-2" rowspan="1"><span class="festival">1-2</span></td>
<td><div class="timetable_con text-left">
<span class="title"><font color="blue">军事理论★</font></span><p>$info</p>
</div></td></tr></tbody></table>''';

    test('「教师 ：」中间带空格也要能读出来（湖州职业技术学院那种写法）', () {
      final html = pageWithInfo(
        '<span class="glyphicon glyphicon-user"></span> 教师 ：曹荣军'
        '<span class="glyphicon glyphicon-tower"></span> 上课地点：12204(大) '
        '<span class="glyphicon glyphicon-calendar"></span> 周数：3-10周',
      );
      final session = const JwglxtCourseTableParser().parse(html).sessions.single;

      expect(session.teacher, '曹荣军');
      expect(session.room, '12204(大)');
      expect(session.weeks, [3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('没有「教学班：」时用课名加教师兜底，别把所有课挤成一条', () {
      final html = pageWithInfo(
        '<span class="glyphicon glyphicon-user"></span> 教师 ：曹荣军'
        '<span class="glyphicon glyphicon-home"></span> 教学班组成：集成2632;集成2633',
      );
      final session = const JwglxtCourseTableParser().parse(html).sessions.single;

      expect(session.courseId, '军事理论-曹荣军');
    });
  });

  group('周数文本解析', () {
    test('连续区间展开成周次列表', () {
      expect(JwglxtCourseTableParser.parseWeeks('4-17周'), [
        4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
      ]);
    });

    test('单个周次和逗号分隔都支持', () {
      expect(JwglxtCourseTableParser.parseWeeks('16-17周'), [16, 17]);
      expect(JwglxtCourseTableParser.parseWeeks('1,3,5周'), [1, 3, 5]);
    });

    test('单双周按括号里的标记过滤', () {
      expect(JwglxtCourseTableParser.parseWeeks('4-10周(单)'), [5, 7, 9]);
      expect(JwglxtCourseTableParser.parseWeeks('4-10周(双)'), [4, 6, 8, 10]);
    });

    test('空文本不报错，返回空列表', () {
      expect(JwglxtCourseTableParser.parseWeeks(''), isEmpty);
      expect(JwglxtCourseTableParser.parseWeeks('   '), isEmpty);
    });
  });
}