import 'course.dart';

/// 一个课程格子在网格中的位置。
class GridSlot {
  const GridSlot({
    required this.session,
    required this.column,
    required this.columns,
  });

  final CourseSession session;

  /// 所在列（0 起），同一时间段内互不重叠
  final int column;

  /// 所处重叠组的总列数，用来等分格宽
  final int columns;
}

/// 把同一天的课程按时间重叠情况分组。
///
/// 先按开始节次排序，再把时间上首尾相接/重叠的课程划为一组：
/// 上一门结束于第 2 节、下一门始于第 3 节，属于相邻而非重叠，会分到不同的组。
List<List<CourseSession>> _groupByOverlap(List<CourseSession> daySessions) {
  final sorted = [...daySessions]
    ..sort((a, b) {
      final byStart = a.startPeriod.compareTo(b.startPeriod);
      return byStart != 0 ? byStart : a.endPeriod.compareTo(b.endPeriod);
    });

  final groups = <List<CourseSession>>[];
  var current = <CourseSession>[];
  var currentEnd = -1;

  for (final session in sorted) {
    if (current.isEmpty) {
      current.add(session);
      currentEnd = session.endPeriod;
      continue;
    }
    if (session.startPeriod <= currentEnd) {
      current.add(session);
      if (session.endPeriod > currentEnd) currentEnd = session.endPeriod;
    } else {
      groups.add(current);
      current = [session];
      currentEnd = session.endPeriod;
    }
  }
  if (current.isNotEmpty) groups.add(current);
  return groups;
}

/// 两门课是否会在同一周同时出现
bool _sharesWeek(CourseSession a, CourseSession b) {
  final weeks = a.weeks.toSet();
  for (final week in b.weeks) {
    if (weeks.contains(week)) return true;
  }
  return false;
}

/// 把同一时段内「二选一」的课程合并成只显示一门。
///
/// 有些课程互斥地占用同一时段：例如军事理论在双周（6,8,…,16）、
/// 形势与政策1 在第 7、11 周，两门同占周一 10-11 节，但任何一周至多上
/// 其中一门。若把它们并排分列，每门只剩半宽，文字被挤得看不清；
/// 此时只显示当前周实际要上的那门，由它占满整个格子，
/// 当前周都没有课时则显示组内第一门。
///
/// 若两门课真的会在同一周同时出现（真正的冲突），保持分列显示，
/// 不做隐藏，避免漏掉课程。
List<CourseSession> resolveAlternatives(
  List<CourseSession> daySessions,
  int week,
) {
  if (daySessions.length < 2) return daySessions;

  final kept = <CourseSession>[];
  for (final group in _groupByOverlap(daySessions)) {
    if (group.length == 1) {
      kept.add(group.first);
      continue;
    }

    var allExclusive = true;
    for (var i = 0; i < group.length && allExclusive; i++) {
      for (var j = i + 1; j < group.length; j++) {
        if (_sharesWeek(group[i], group[j])) {
          allExclusive = false;
          break;
        }
      }
    }

    if (!allExclusive) {
      kept.addAll(group);
      continue;
    }

    CourseSession? active;
    for (final session in group) {
      if (session.hasClassInWeek(week)) {
        active = session;
        break;
      }
    }
    kept.add(active ?? group.first);
  }
  return kept;
}

/// 把同一天的课程按时间重叠情况分列，避免重叠的格子互相盖住。
///
/// 组内用贪心分配列号，组的列数决定该组内格子的宽度。
List<GridSlot> layoutDay(List<CourseSession> daySessions) {
  final slots = <GridSlot>[];
  for (final group in _groupByOverlap(daySessions)) {
    final columnEnd = <int>[];
    final assigned = <int>[];
    for (final session in group) {
      var column = -1;
      for (var c = 0; c < columnEnd.length; c++) {
        if (columnEnd[c] < session.startPeriod) {
          column = c;
          break;
        }
      }
      if (column < 0) {
        columnEnd.add(session.endPeriod);
        column = columnEnd.length - 1;
      } else {
        columnEnd[column] = session.endPeriod;
      }
      assigned.add(column);
    }
    for (var i = 0; i < group.length; i++) {
      slots.add(GridSlot(
        session: group[i],
        column: assigned[i],
        columns: columnEnd.length,
      ));
    }
  }
  return slots;
}
