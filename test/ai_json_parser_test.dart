import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/parsers/ai_json_parser.dart';

/// 造一条 AI 返回的记录
String _item({
  String name = '高等数学',
  String teacher = '张三',
  String room = '综合楼313',
  String weekday = '星期一',
  String weeks = '1-16周',
  String periods = '1-2节',
}) =>
    '{"name":"$name","teacher":"$teacher","classRoom":"$room",'
    '"weekday":"$weekday","fixWeeks":"$weeks","courseNumbers":"$periods"}';

void main() {
  const parser = AiCourseJsonParser();

  group('外层包装', () {
    test('识别标准 JSON 数组', () {
      final result = parser.parse('[${_item()}]');
      expect(result.data.sessions, hasLength(1));
      expect(result.data.sessions.first.name, '高等数学');
    });

    test('带 ```json 代码块与前后说明文字也能认', () {
      final raw = '好的，这是识别结果：\n```json\n[${_item()}]\n```\n希望有帮助。';
      expect(parser.parse(raw).data.sessions, hasLength(1));
    });

    test('只返回单个对象时按一条处理', () {
      expect(parser.parse(_item()).data.sessions, hasLength(1));
    });

    test('被包了一层 {"courses": [...]} 也能认', () {
      expect(parser.parse('{"courses":[${_item()}]}').data.sessions, hasLength(1));
    });

    test('完全不是 JSON 时给出可读的提示', () {
      expect(
        () => parser.parse('抱歉，我看不清这张图片。'),
        throwsA(isA<AiImportException>()),
      );
    });
  });

  group('周次', () {
    List<int> weeksOf(String raw) =>
        parser.parse('[${_item(weeks: raw)}]').data.sessions.first.weeks;

    test('区间 1-4 周', () {
      expect(weeksOf('1-4周'), [1, 2, 3, 4]);
    });

    test('单周', () {
      expect(weeksOf('3-8单周'), [3, 5, 7]);
    });

    test('双周', () {
      expect(weeksOf('2-8双周'), [2, 4, 6, 8]);
    });

    test('逗号分隔与不连续区间', () {
      expect(weeksOf('1-2,5,7-8周'), [1, 2, 5, 7, 8]);
    });

    test('带「第」与全角顿号', () {
      expect(weeksOf('第1、3、5周'), [1, 3, 5]);
    });

    test('「至」当作区间连接号', () {
      expect(weeksOf('1至3周'), [1, 2, 3]);
    });

    test('没有周次信息时按整学期兜底，并留下说明', () {
      final result = parser.parse('[${_item(weeks: "")}]');
      expect(result.data.sessions.first.weeks, hasLength(AiCourseJsonParser.defaultWeekCount));
      expect(result.notes, isNotEmpty);
    });
  });

  group('节次', () {
    List<int> periodsOf(String raw) =>
        parser.parse('[${_item(periods: raw)}]').data.sessions.first.periods;

    test('1-2 节', () {
      expect(periodsOf('1-2节'), [1, 2]);
    });

    test('跨三节的 3-5 节', () {
      expect(periodsOf('3-5节'), [3, 4, 5]);
    });

    test('单节', () {
      expect(periodsOf('第6节'), [6]);
    });

    test('逗号分隔', () {
      expect(periodsOf('1,3,5节'), [1, 3, 5]);
    });
  });

  group('星期', () {
    int? dayOf(String raw) =>
        parser.parse('[${_item(weekday: raw)}]').data.sessions.firstOrNull?.dayOfWeek;

    test('中文写法', () {
      expect(dayOf('星期一'), 1);
      expect(dayOf('星期日'), 7);
      expect(dayOf('星期天'), 7);
      expect(dayOf('周三'), 3);
    });

    test('数字与英文写法', () {
      expect(dayOf('5'), 5);
      expect(dayOf('Monday'), 1);
    });

    test('认不出星期几时跳过该条，并在说明里指出原因', () {
      final result = parser.parse('[${_item(weekday: "")},${_item(name: "大学物理")}]');
      expect(result.data.sessions, hasLength(1));
      expect(result.data.sessions.single.name, '大学物理');
      expect(result.skipped.single, contains('星期几'));
    });

    test('全都认不出时，报错里带上第一条原因', () {
      expect(
        () => parser.parse('[${_item(weekday: "")}]'),
        throwsA(
          isA<AiImportException>().having((e) => e.message, 'message', contains('星期几')),
        ),
      );
    });
  });

  group('字段兼容', () {
    test('字段名中英文混用也能认', () {
      final raw = '[{"课程名称":"大学英语","教师":"李四","上课地点":"文科楼201",'
          '"星期":"星期二","周次":"2-4周","节次":"3-4节"}]';
      final session = parser.parse(raw).data.sessions.single;
      expect(session.name, '大学英语');
      expect(session.teacher, '李四');
      expect(session.room, '文科楼201');
      expect(session.dayOfWeek, 2);
      expect(session.weeks, [2, 3, 4]);
      expect(session.periods, [3, 4]);
    });

    test('教师给成数组时拼成逗号分隔', () {
      final raw = '[{"name":"体育","teacher":["王五","赵六"],"weekday":"星期五",'
          '"fixWeeks":"1-2周","courseNumbers":"1-2节"}]';
      expect(parser.parse(raw).data.sessions.single.teacher, '王五,赵六');
    });
  });

  group('整体', () {
    test('缺课名的条目被跳过，其余照常导入', () {
      final raw = '[{"weekday":"星期一","fixWeeks":"1-2周","courseNumbers":"1-2节"},'
          '${_item(name: '线性代数')}]';
      final result = parser.parse(raw);
      expect(result.data.sessions, hasLength(1));
      expect(result.data.sessions.single.name, '线性代数');
      expect(result.skipped, hasLength(1));
    });

    test('课表按课名去重进课程名单', () {
      final raw = '[${_item()},${_item(weekday: "星期三")}]';
      final result = parser.parse(raw);
      expect(result.data.sessions, hasLength(2));
      expect(result.data.courses, hasLength(1));
    });

    test('认不出任何一门课时报错', () {
      expect(
        () => parser.parse('[]'),
        throwsA(isA<AiImportException>()),
      );
    });

    test('periodsPerDay 取最大结束节次', () {
      final raw = '[${_item(periods: "1-2节")},${_item(periods: "9-10节", weekday: "星期三")}]';
      expect(parser.parse(raw).data.periodsPerDay, 10);
    });
  });
}
