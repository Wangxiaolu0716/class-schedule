import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/models/custom_entry.dart';
import 'package:nbcc_schedule/models/table_config.dart';

/// 开学日默认定在周一（2026-09-07），方便直接按日期推周次
TableConfig _config({DateTime? startDate, int totalWeeks = 20}) => TableConfig(
      startDate: startDate ?? DateTime(2026, 9, 7),
      totalWeeks: totalWeeks,
      periodTimes: TableConfig.defaultPeriodTimes,
    );

void main() {
  group('自建课程序列化', () {
    final course = CustomCourse(
      id: 'abc',
      name: '高等数学',
      color: 0xFF90CAF9,
      credits: 3,
      slots: [
        CustomSlot(
          weeks: [1, 2, 3],
          dayOfWeek: 1,
          periods: [1, 2],
          room: 'A101',
          teacher: '张老师',
          note: '带教材',
        ),
        CustomSlot(
          weeks: [5, 6],
          dayOfWeek: 3,
          periods: [5, 6],
          useCustomTime: true,
          startTime: '13:30',
          endTime: '15:00',
        ),
      ],
    );

    test('往返序列化后字段不变', () {
      final restored = CustomCourse.fromJson(course.toJson())!;
      expect(restored.id, 'abc');
      expect(restored.name, '高等数学');
      expect(restored.color, 0xFF90CAF9);
      expect(restored.credits, 3);
      expect(restored.slots.length, 2);

      final first = restored.slots.first;
      expect(first.weeks, [1, 2, 3]);
      expect(first.dayOfWeek, 1);
      expect(first.periods, [1, 2]);
      expect(first.room, 'A101');
      expect(first.teacher, '张老师');
      expect(first.note, '带教材');
      expect(first.customTimeRange, isNull);

      final second = restored.slots[1];
      expect(second.useCustomTime, isTrue);
      expect(second.customTimeRange, '13:30 - 15:00');
    });

    test('缺少必需字段时返回 null', () {
      expect(CustomCourse.fromJson(const {'name': '只有名字'}), isNull);
      expect(CustomCourse.fromJson(const {'id': 'x'}), isNull);
      expect(CustomCourse.fromJson(const <String, dynamic>{}), isNull);
    });

    test('换算成排课记录：周次与节次原样带过去', () {
      final sessions = customCourseSessions(course);
      expect(sessions.length, 2);
      expect(sessions.first.courseId, '${customCourseIdPrefix}abc');
      expect(sessions.first.name, '高等数学');
      expect(sessions.first.dayOfWeek, 1);
      expect(sessions.first.periods, [1, 2]);
      expect(sessions.first.weeks, [1, 2, 3]);
      expect(sessions.first.room, 'A101');
      expect(sessions.first.teacher, '张老师');
    });

    test('没有周次或节次的时段不参与排课', () {
      final empty = CustomCourse(
        id: 'x',
        name: '空课',
        color: 0xFF90CAF9,
        slots: [
          CustomSlot(weeks: const [], dayOfWeek: 1, periods: const [1]),
          CustomSlot(weeks: const [1], dayOfWeek: 1, periods: const []),
        ],
      );
      expect(customCourseSessions(empty), isEmpty);
    });
  });

  group('自建日程序列化', () {
    final schedule = CustomSchedule(
      id: 's1',
      title: '期末考试',
      location: '教学楼',
      start: DateTime(2026, 9, 30, 8, 15),
      end: DateTime(2026, 9, 30, 9, 50),
      repeat: ScheduleRepeat.weekly,
      tag: '考试',
      note: '带学生证',
    );

    test('往返序列化后字段不变', () {
      final restored = CustomSchedule.fromJson(schedule.toJson())!;
      expect(restored.id, 's1');
      expect(restored.title, '期末考试');
      expect(restored.location, '教学楼');
      expect(restored.allDay, isFalse);
      expect(restored.start, schedule.start);
      expect(restored.end, schedule.end);
      expect(restored.repeat, ScheduleRepeat.weekly);
      expect(restored.tag, '考试');
      expect(restored.note, '带学生证');
    });

    test('缺少必需字段或日期非法时返回 null', () {
      expect(CustomSchedule.fromJson(const {'id': 'x', 'title': '只有标题'}), isNull);
      expect(
        CustomSchedule.fromJson(const {
          'id': 'x',
          'title': 't',
          'start': '不是日期',
          'end': '也不是',
        }),
        isNull,
      );
    });

    test('未知的重复方式回落到「永不」，缺标签时用「其他」', () {
      final restored = CustomSchedule.fromJson(const {
        'id': 'x',
        'title': 't',
        'start': '2026-09-30T08:15:00.000',
        'end': '2026-09-30T09:50:00.000',
        'repeat': 'yearly',
      })!;
      expect(restored.repeat, ScheduleRepeat.never);
      expect(restored.tag, '其他');
    });

    test('标签颜色：已知取配置值，未知回落到「其他」', () {
      expect(tagColorOf('考试'), 0xFFE53935);
      expect(tagColorOf('其他'), scheduleTags.last.color);
      expect(tagColorOf('不存在的标签'), scheduleTags.last.color);
    });
  });

  group('日程 → 周次 / 节次换算', () {
    test('钟点落在第 1-2 节上', () {
      final periods = periodsForTimeRange(
        DateTime(2026, 9, 30, 8, 15),
        DateTime(2026, 9, 30, 9, 50),
        _config(),
      );
      expect(periods, [1, 2]);
    });

    test('钟点对不上节次时就近吸附', () {
      // 08:05 落在第 1 节（08:15）之前，距第 1 节最近
      expect(
        periodsForTimeRange(
          DateTime(2026, 9, 30, 8, 5),
          DateTime(2026, 9, 30, 8, 40),
          _config(),
        ),
        [1],
      );
    });

    test('没有配置节次时间时无法换算', () {
      expect(
        periodsForTimeRange(
          DateTime(2026, 9, 30, 8, 15),
          DateTime(2026, 9, 30, 9, 50),
          const TableConfig(),
        ),
        isEmpty,
      );
    });

    test('「永不」只落在当天那一周', () {
      final sessions = customScheduleSessions(
        CustomSchedule(
          id: 'n',
          title: '讲座',
          start: DateTime(2026, 9, 30, 8, 15),
          end: DateTime(2026, 9, 30, 9, 50),
        ),
        _config(),
      );
      expect(sessions.length, 1);
      // 2026-09-30 是第 4 周（开学 09-07 为第 1 周）的周三
      expect(sessions.single.weeks, [4]);
      expect(sessions.single.dayOfWeek, DateTime.wednesday);
      expect(sessions.single.periods, [1, 2]);
      expect(sessions.single.name, '讲座');
    });

    test('「每周」从当周铺到学期末', () {
      final sessions = customScheduleSessions(
        CustomSchedule(
          id: 'w',
          title: '早自习',
          start: DateTime(2026, 9, 30, 8, 15),
          end: DateTime(2026, 9, 30, 8, 50),
          repeat: ScheduleRepeat.weekly,
        ),
        _config(),
      );
      expect(sessions.length, 1);
      expect(sessions.single.weeks.first, 4);
      expect(sessions.single.weeks.last, 20);
      expect(sessions.single.dayOfWeek, DateTime.wednesday);
    });

    test('「每天」铺满一周七天', () {
      final sessions = customScheduleSessions(
        CustomSchedule(
          id: 'd',
          title: '晨跑',
          start: DateTime(2026, 9, 30, 8, 15),
          end: DateTime(2026, 9, 30, 8, 50),
          repeat: ScheduleRepeat.daily,
        ),
        _config(),
      );
      expect(sessions.map((s) => s.dayOfWeek).toList(), [1, 2, 3, 4, 5, 6, 7]);
      expect(sessions.every((s) => s.weeks.first == 4), isTrue);
    });

    test('全天日程不落网格（改由日期条展示）', () {
      final sessions = customScheduleSessions(
        CustomSchedule(
          id: 'a',
          title: '运动会',
          allDay: true,
          start: DateTime(2026, 9, 30),
          end: DateTime(2026, 9, 30, 23, 59),
        ),
        _config(),
      );
      expect(sessions, isEmpty);
    });

    test('没设置开学时间时不落网格', () {
      final sessions = customScheduleSessions(
        CustomSchedule(
          id: 'x',
          title: '讲座',
          start: DateTime(2026, 9, 30, 8, 15),
          end: DateTime(2026, 9, 30, 9, 50),
        ),
        const TableConfig(periodTimes: TableConfig.defaultPeriodTimes),
      );
      expect(sessions, isEmpty);
    });

    test('超出学期范围的日程不落网格', () {
      final sessions = customScheduleSessions(
        CustomSchedule(
          id: 'late',
          title: '下学期的事',
          start: DateTime(2027, 6, 1, 8, 15),
          end: DateTime(2027, 6, 1, 9, 50),
        ),
        _config(),
      );
      expect(sessions, isEmpty);
    });
  });
}
