import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/models/table_config.dart';

/// 「按今天是第几周反推开学日期」的正确性。
///
/// 这是别校用户的唯一入口——他们的课表页不给日期，只能靠这个推算，
/// 算错会直接导致整张课表的日期条错位，所以逐条钉死。
void main() {
  // 2026-09-29 是星期二（2026-09-28 为周一）
  final today = DateTime(2026, 9, 29);

  group('按「今天是第几周」反推开学日期', () {
    test('说是第 1 周，开学日期就是本周第一天', () {
      expect(
        TableConfig.deriveStartDate(
          currentWeek: 1,
          today: today,
          weekStartDay: DateTime.monday,
        ),
        DateTime(2026, 9, 28),
      );
    });

    test('说是第 5 周，就往前推 4 周', () {
      expect(
        TableConfig.deriveStartDate(
          currentWeek: 5,
          today: today,
          weekStartDay: DateTime.monday,
        ),
        DateTime(2026, 8, 31),
      );
    });

    test('今天正好是本周第一天时，不会多减一周', () {
      expect(
        TableConfig.deriveStartDate(
          currentWeek: 3,
          today: DateTime(2026, 9, 28),
          weekStartDay: DateTime.monday,
        ),
        DateTime(2026, 9, 14),
      );
    });

    test('每周起始日不是周一时，推算结果随之平移', () {
      // 以周日为每周第一天：本周第一天是 2026-09-27
      expect(
        TableConfig.deriveStartDate(
          currentWeek: 1,
          today: today,
          weekStartDay: DateTime.sunday,
        ),
        DateTime(2026, 9, 27),
      );
    });

    test('与 currentWeek 往返一致：推算出来的日期能还原出同一周', () {
      // 本校真实的开学日期，反推一次应当原样回来
      final realStart = DateTime(2026, 9, 7);
      final config = TableConfig(startDate: realStart);

      final week = config.currentWeek(today);
      expect(week, 4);

      final derived = TableConfig.deriveStartDate(
        currentWeek: week!,
        today: today,
        weekStartDay: DateTime.monday,
      );
      expect(derived, realStart);
    });

    test('推算结果的第一天，与原配置的 firstDayOfWeek 对齐', () {
      final derived = TableConfig.deriveStartDate(
        currentWeek: 4,
        today: today,
        weekStartDay: DateTime.monday,
      );
      final config = TableConfig(startDate: derived);

      // 第 4 周的第一天应当就是 2026-09-28（今天所在的这一周）
      expect(config.firstDayOfWeek(4), DateTime(2026, 9, 28));
    });
  });
}