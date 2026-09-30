import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/models/course.dart';
import 'package:nbcc_schedule/models/grid_layout.dart';
import 'package:nbcc_schedule/models/table_config.dart';

CourseSession _session(String name, int day, int start, int end) => CourseSession(
      courseId: 'x',
      name: name,
      teacher: '',
      room: '',
      dayOfWeek: day,
      periods: [for (var p = start; p <= end; p++) p],
      weeks: const [1],
    );

CourseSession _sessionWeeks(
  String name,
  int day,
  int start,
  int end,
  List<int> weeks,
) =>
    CourseSession(
      courseId: 'x',
      name: name,
      teacher: '',
      room: '',
      dayOfWeek: day,
      periods: [for (var p = start; p <= end; p++) p],
      weeks: weeks,
    );

void main() {
  group('课表网格分列', () {
    test('互不重叠的课程各占整宽', () {
      final slots = layoutDay([_session('A', 1, 1, 2), _session('B', 1, 5, 6)]);
      expect(slots.length, 2);
      for (final slot in slots) {
        expect(slot.column, 0);
        expect(slot.columns, 1);
      }
    });

    test('真正冲突（同周并存）的课程并排分列，各占半宽', () {
      final slots = layoutDay([
        _sessionWeeks('篮球选修', 1, 10, 11, [5, 6]),
        _sessionWeeks('足球选修', 1, 10, 11, [6, 7]),
      ]);
      expect(slots.length, 2);
      expect(slots.map((s) => s.column).toSet(), {0, 1});
      expect(slots.every((s) => s.columns == 2), isTrue);
    });

    test('重叠只影响同一组，之后的课程恢复整宽', () {
      final slots = layoutDay([
        _session('A', 1, 1, 2),
        _session('B', 1, 1, 2),
        _session('C', 1, 6, 7),
      ]);
      final c = slots.firstWhere((s) => s.session.name == 'C');
      expect(c.columns, 1);
      expect(c.column, 0);
    });
  });

  group('课表配置', () {
    test('由开学时间推算当前周', () {
      // 与 WakeUp 设置页一致：开学 2026-09-07，2026-09-28 为第 4 周
      final config = TableConfig(startDate: DateTime(2026, 9, 7));
      expect(config.currentWeek(DateTime(2026, 9, 7)), 1);
      expect(config.currentWeek(DateTime(2026, 9, 13)), 1);
      expect(config.currentWeek(DateTime(2026, 9, 14)), 2);
      expect(config.currentWeek(DateTime(2026, 9, 28)), 4);
      expect(config.currentWeek(DateTime(2026, 10, 5)), 5);
    });

    test('未设置开学时间时无法推算当前周', () {
      expect(const TableConfig().currentWeek(DateTime(2026, 9, 28)), isNull);
    });

    test('配置可序列化并原样还原', () {
      final config = TableConfig(
        name: '宁波城市职业技术学院',
        startDate: DateTime(2026, 9, 7),
        periodsPerDay: 11,
        totalWeeks: 20,
        periodTimes: const [
          PeriodTime(period: 1, start: '08:15', end: '08:50'),
        ],
        showSunday: false,
        cellHeight: 62,
        cellRadius: 8,
      );
      final restored = TableConfig.fromJson(config.toJson());
      expect(restored.name, config.name);
      expect(restored.startDate, config.startDate);
      expect(restored.periodsPerDay, 11);
      expect(restored.showSunday, isFalse);
      expect(restored.cellHeight, 62);
      expect(restored.cellRadius, 8);
      expect(restored.timeOf(1)?.start, '08:15');
      expect(restored.timeOf(2), isNull);
    });
  });

  group('周次格式化（详情弹窗用）', () {
    test('连续周次合并成区间', () {
      expect(formatWeeks([1, 2, 3]), '1-3');
      // 与样本里「体育健康1」的真实周次一致
      expect(
        formatWeeks([5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17]),
        '5-8,10-17',
      );
    });

    test('单周不写区间，双周逐周列出', () {
      expect(formatWeeks([6]), '6');
      expect(formatWeeks([6, 8, 10, 12, 14, 16]), '6,8,10,12,14,16');
    });

    test('乱序输入先排序', () {
      expect(formatWeeks([3, 1, 2]), '1-3');
    });

    test('空列表返回占位符', () {
      expect(formatWeeks([]), '—');
    });
  });

  group('同一时段「二选一」的课程', () {
    // 真实数据：军事理论（双周 6..16）与形势与政策1（第 7、11 周）
    // 同占周一第 10-11 节，任何一周至多上其中一门
    final military = _sessionWeeks('军事理论', 1, 10, 11, [6, 8, 10, 12, 14, 16]);
    final policy = _sessionWeeks('形势与政策1（三年制）', 1, 10, 11, [7, 11]);

    test('只保留本周实际要上的那一门，让它占满整宽', () {
      final week7 = resolveAlternatives([military, policy], 7);
      expect(week7.length, 1);
      expect(week7.single.name, '形势与政策1（三年制）');

      final week6 = resolveAlternatives([military, policy], 6);
      expect(week6.length, 1);
      expect(week6.single.name, '军事理论');
    });

    test('本周两门都没课时仍只显示一门，不留半宽空位', () {
      // 第 9 周军事理论（双周）与形势与政策1 都不上课
      final week9 = resolveAlternatives([military, policy], 9);
      expect(week9.length, 1);
    });

    test('真的会在同一周并存的课程仍然分列，不做隐藏', () {
      final a = _sessionWeeks('A', 1, 1, 2, [5, 6, 7]);
      final b = _sessionWeeks('B', 1, 1, 2, [6, 7, 8]);
      expect(resolveAlternatives([a, b], 6).length, 2);
    });

    test('时段不重叠的课程不受影响', () {
      final a = _sessionWeeks('A', 1, 1, 2, [5]);
      final b = _sessionWeeks('B', 1, 5, 6, [5]);
      expect(resolveAlternatives([a, b], 5).length, 2);
    });

    test('合并后的格子确实占满整宽（列数为 1）', () {
      final slots = layoutDay(resolveAlternatives([military, policy], 6));
      expect(slots.length, 1);
      expect(slots.single.columns, 1);
      expect(slots.single.column, 0);
    });
  });
}
