/// 课程表数据模型。
///
/// 这些模型只承载数据，不含解析逻辑，方便后续替换或新增数据源
/// （例如将来接入 AI 解析时，只要产出同样的模型即可）。
library;

/// 把周次列表压缩成便于阅读的区间串，如 `[5,6,7,8,10,11]` → `5-8,10-11`
String formatWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '—';
  final sorted = [...weeks]..sort();
  final parts = <String>[];
  var start = sorted.first;
  var previous = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    final week = sorted[i];
    if (week == previous + 1) {
      previous = week;
      continue;
    }
    parts.add(start == previous ? '$start' : '$start-$previous');
    start = week;
    previous = week;
  }
  parts.add(start == previous ? '$start' : '$start-$previous');
  return parts.join(',');
}

/// 一次排课记录：某门课在星期 [dayOfWeek] 的第 [periods] 节、
/// 于 [weeks] 这些周上课，地点是 [room]。
class CourseSession {
  CourseSession({
    required this.courseId,
    required this.name,
    required this.teacher,
    required this.room,
    required this.dayOfWeek,
    required List<int> periods,
    required List<int> weeks,
  })  : periods = List.unmodifiable(periods),
        weeks = List.unmodifiable(weeks);

  /// 课程序号，如 `031A13B07`
  final String courseId;

  /// 课程名称，如 `IT专业基本技能训练`
  final String name;

  /// 教师姓名，多位教师以 `,` 分隔
  final String teacher;

  /// 上课地点
  final String room;

  /// 星期，1=周一 … 7=周日
  final int dayOfWeek;

  /// 连续节次（1 起、升序），如 `[1, 2]` 表示第 1-2 节
  final List<int> periods;

  /// 上课周次（1 起、升序），如 `[5, 6, 7, 8, 10]`
  final List<int> weeks;

  /// 起始节次
  int get startPeriod => periods.first;

  /// 结束节次
  int get endPeriod => periods.last;

  /// 占用节数
  int get periodCount => periods.length;

  /// 第 [week] 周是否有课
  bool hasClassInWeek(int week) => weeks.contains(week);

  @override
  String toString() =>
      'CourseSession($name, 周$dayOfWeek 第$startPeriod-$endPeriod节, '
      '周次$weeks, $room, $teacher)';
}

/// 课程名单中的一门课（含未安排上课时间的课程）
class Course {
  const Course({
    required this.courseId,
    required this.code,
    required this.name,
    this.credits,
    this.teacher = '',
  });

  /// 课程序号，如 `031A13B07`
  final String courseId;

  /// 课程代码，如 `031A13B`
  final String code;

  /// 课程名称
  final String name;

  /// 学分
  final double? credits;

  /// 教师姓名
  final String teacher;
}

/// 一次课表解析的完整结果
class CourseTableData {
  const CourseTableData({
    required this.sessions,
    required this.courses,
    this.periodsPerDay,
    this.studentId,
    this.semesterId,
  });

  /// 所有排课记录
  final List<CourseSession> sessions;

  /// 课程名单（可用于展示未排课的课程）
  final List<Course> courses;

  /// 每天节数，取自课表页面的 `unitCount`
  final int? periodsPerDay;

  /// 学生 ID，取自课表页面的 `ids` 参数
  final String? studentId;

  /// 学期 ID，取自课表页面的 `semester.id` 参数
  final String? semesterId;
}