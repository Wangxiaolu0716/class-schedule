/// 用户自建的课程 / 日程：数据模型与「换算成课表格子」的逻辑。
///
/// 自建条目与教务导入的课表彼此独立：导入的原始 HTML 只当数据源缓存，
/// 自建条目另存 JSON，重新导入课表不会把它们冲掉。
///
/// 自建条目最终都换算成 [CourseSession] 再进网格，这样分列、「二选一」
/// 合并、本周/非本周淡显这些布局逻辑都能直接复用，不必为自建条目另写一套。
library;

import 'course.dart';
import 'table_config.dart';

/// 自建课程的 courseId 前缀，用来跟教务导入的课程序号区分开
const String customCourseIdPrefix = 'custom:';

/// 自建日程的 courseId 前缀
const String customScheduleIdPrefix = 'schedule:';

/// 自建课程的备选颜色（ARGB），取自课表常用的几种浅色
const List<int> customCourseColors = [
  0xFF90CAF9,
  0xFFA5D6A7,
  0xFFFFCC80,
  0xFFCE93D8,
  0xFFF48FB1,
  0xFF80DEEA,
  0xFFFFAB91,
  0xFF9FA8DA,
  0xFFE6EE9C,
  0xFF80CBC4,
  0xFFBCAAA4,
  0xFFB0BEC5,
];

/// 日程标签及其配色，界面里显示成「名称 + 色点」
class ScheduleTag {
  const ScheduleTag(this.name, this.color);

  final String name;
  final int color;
}

/// 可选的日程标签
const List<ScheduleTag> scheduleTags = [
  ScheduleTag('考试', 0xFFE53935),
  ScheduleTag('活动', 0xFF1E88E5),
  ScheduleTag('会议', 0xFF8E24AA),
  ScheduleTag('自习', 0xFF43A047),
  ScheduleTag('其他', 0xFF3949AB),
];

/// 标签名对应的颜色；未收录的名称回落到「其他」的颜色
int tagColorOf(String name) {
  for (final tag in scheduleTags) {
    if (tag.name == name) return tag.color;
  }
  return scheduleTags.last.color;
}

/// 日程重复方式。
///
/// 课表是按周铺开的，所以只提供这三种能直接落到周课表上的选项，
/// 「每月」「每年」这类在周视图里没有稳定的落点。
enum ScheduleRepeat {
  never('永不'),
  daily('每天'),
  weekly('每周');

  const ScheduleRepeat(this.label);

  final String label;

  static ScheduleRepeat fromName(String? name) {
    for (final value in ScheduleRepeat.values) {
      if (value.name == name) return value;
    }
    return ScheduleRepeat.never;
  }
}

/// 自建课程的一个上课时段（一周上两次就是两个时段）
class CustomSlot {
  CustomSlot({
    required List<int> weeks,
    required this.dayOfWeek,
    required List<int> periods,
    this.useCustomTime = false,
    this.startTime = '',
    this.endTime = '',
    this.room = '',
    this.teacher = '',
    this.note = '',
  })  : weeks = List.unmodifiable(weeks),
        periods = List.unmodifiable(periods);

  /// 上课周次（1 起、升序）
  final List<int> weeks;

  /// 星期，1=周一 … 7=周日
  final int dayOfWeek;

  /// 连续节次（1 起、升序）
  final List<int> periods;

  /// 是否用自定义钟点代替课表设置里的节次时间
  final bool useCustomTime;

  /// 自定义起始钟点（`HH:mm`），仅 [useCustomTime] 为 true 时有意义
  final String startTime;

  /// 自定义结束钟点（`HH:mm`）
  final String endTime;

  final String room;
  final String teacher;
  final String note;

  /// 自定义钟点区间；未启用时返回 null
  String? get customTimeRange =>
      useCustomTime && startTime.isNotEmpty && endTime.isNotEmpty
          ? '$startTime - $endTime'
          : null;

  /// 起始节次
  int get startPeriod => periods.first;

  /// 结束节次
  int get endPeriod => periods.last;

  Map<String, dynamic> toJson() => {
        'weeks': weeks,
        'dayOfWeek': dayOfWeek,
        'periods': periods,
        'useCustomTime': useCustomTime,
        'startTime': startTime,
        'endTime': endTime,
        'room': room,
        'teacher': teacher,
        'note': note,
      };

  static CustomSlot fromJson(Map<String, dynamic> json) => CustomSlot(
        weeks: intList(json['weeks']),
        dayOfWeek: intOr(json['dayOfWeek'], 1).clamp(1, 7),
        periods: intList(json['periods']),
        useCustomTime: json['useCustomTime'] as bool? ?? false,
        startTime: text(json['startTime']),
        endTime: text(json['endTime']),
        room: text(json['room']),
        teacher: text(json['teacher']),
        note: text(json['note']),
      );
}

/// 一门自建课程
class CustomCourse {
  CustomCourse({
    required this.id,
    required this.name,
    required this.color,
    this.credits,
    required List<CustomSlot> slots,
  }) : slots = List.unmodifiable(slots);

  /// 本地唯一标识
  final String id;

  final String name;

  /// 格子颜色（ARGB）
  final int color;

  /// 学分（选填）
  final double? credits;

  final List<CustomSlot> slots;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'credits': credits,
        'slots': slots.map((slot) => slot.toJson()).toList(),
      };

  /// 解析一条记录；缺少必需字段时返回 null，由调用方跳过
  static CustomCourse? fromJson(Map<String, dynamic> json) {
    final id = text(json['id']);
    final name = text(json['name']);
    if (id.isEmpty || name.isEmpty) return null;
    return CustomCourse(
      id: id,
      name: name,
      color: intOr(json['color'], customCourseColors.first),
      credits: (json['credits'] as num?)?.toDouble(),
      slots: [
        for (final item in json['slots'] as List<dynamic>? ?? const [])
          if (item is Map<String, dynamic>) CustomSlot.fromJson(item),
      ],
    );
  }
}

/// 一条自建日程（考试、活动、会议、自习……）
class CustomSchedule {
  CustomSchedule({
    required this.id,
    required this.title,
    this.location = '',
    this.allDay = false,
    required this.start,
    required this.end,
    this.repeat = ScheduleRepeat.never,
    this.tag = '其他',
    this.note = '',
  });

  final String id;

  final String title;

  /// 地点（选填）
  final String location;

  /// 全天日程没有钟点，只能落在日期条上
  final bool allDay;

  final DateTime start;
  final DateTime end;

  final ScheduleRepeat repeat;

  /// 标签名，颜色由 [tagColorOf] 决定
  final String tag;

  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'location': location,
        'allDay': allDay,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'repeat': repeat.name,
        'tag': tag,
        'note': note,
      };

  /// 解析一条记录；缺少必需字段时返回 null，由调用方跳过
  static CustomSchedule? fromJson(Map<String, dynamic> json) {
    final id = text(json['id']);
    final title = text(json['title']);
    final start = DateTime.tryParse(text(json['start']));
    final end = DateTime.tryParse(text(json['end']));
    if (id.isEmpty || title.isEmpty || start == null || end == null) {
      return null;
    }
    return CustomSchedule(
      id: id,
      title: title,
      location: text(json['location']),
      allDay: json['allDay'] as bool? ?? false,
      start: start,
      end: end,
      repeat: ScheduleRepeat.fromName(json['repeat'] as String?),
      tag: text(json['tag']).isEmpty ? '其他' : text(json['tag']),
      note: text(json['note']),
    );
  }
}

/// 把一门自建课程的所有时段换算成排课记录
List<CourseSession> customCourseSessions(CustomCourse course) {
  final id = '$customCourseIdPrefix${course.id}';
  return [
    for (final slot in course.slots)
      if (slot.weeks.isNotEmpty && slot.periods.isNotEmpty)
        CourseSession(
          courseId: id,
          name: course.name,
          teacher: slot.teacher,
          room: slot.room,
          dayOfWeek: slot.dayOfWeek,
          periods: slot.periods,
          weeks: slot.weeks,
        ),
  ];
}

/// 把一条日程换算成排课记录。
///
/// 三种情况无法定位到格子，直接返回空：
/// - 全天日程没有钟点，改由日期条展示
/// - 没设置开学时间，算不出周次
/// - 开学时间早于日程所在周之外（超出学期范围）
List<CourseSession> customScheduleSessions(
  CustomSchedule schedule,
  TableConfig config,
) {
  if (schedule.allDay || config.startDate == null) return const [];

  final periods = periodsForTimeRange(schedule.start, schedule.end, config);
  if (periods.isEmpty) return const [];

  final startWeek = config.currentWeek(schedule.start) ?? 1;
  if (startWeek > config.totalWeeks) return const [];

  // 「每天」铺满一周七天，「每周」和「永不」只占起始那天
  final weekdays = schedule.repeat == ScheduleRepeat.daily
      ? const [1, 2, 3, 4, 5, 6, 7]
      : [schedule.start.weekday];
  final weeks = schedule.repeat == ScheduleRepeat.never
      ? [startWeek]
      : [for (var week = startWeek; week <= config.totalWeeks; week++) week];

  final id = '$customScheduleIdPrefix${schedule.id}';
  return [
    for (final weekday in weekdays)
      CourseSession(
        courseId: id,
        name: schedule.title,
        teacher: '',
        room: schedule.location,
        dayOfWeek: weekday,
        periods: periods,
        weeks: weeks,
      ),
  ];
}

/// 按起止钟点匹配节次区间；匹配不到任何节次时返回空。
///
/// 起止各自找「覆盖该时刻的节次」，再取两者之间的一段：
/// 例如 08:15-09:50 落在第 1、2 节上，就得到 `[1, 2]`。
List<int> periodsForTimeRange(
  DateTime start,
  DateTime end,
  TableConfig config,
) {
  final first = _nearestPeriod(start, config);
  final last = _nearestPeriod(end, config);
  if (first == null || last == null) return const [];
  final low = first <= last ? first : last;
  final high = first <= last ? last : first;
  return [for (var period = low; period <= high; period++) period];
}

/// 时刻 [time] 落在哪一节；不落在任何节次内时取钟点最接近的一节。
///
/// 教务系统和用户都不一定填得精确到分钟（例如 08:00 对 08:15 的第 1 节），
/// 因此这里做一次「就近吸附」而不是直接判定失败。
int? _nearestPeriod(DateTime time, TableConfig config) {
  final minutes = time.hour * 60 + time.minute;
  int? nearest;
  var nearestGap = 1 << 30;
  for (final item in config.periodTimes) {
    final from = _minutesOf(item.start);
    if (from == null) continue;
    final to = _minutesOf(item.end);
    if (to != null && minutes >= from && minutes <= to) return item.period;
    final gap = (minutes - from).abs();
    if (gap < nearestGap) {
      nearestGap = gap;
      nearest = item.period;
    }
  }
  return nearest;
}

int? _minutesOf(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

List<int> intList(dynamic value) {
  if (value is! List) return const [];
  final result = <int>[];
  for (final item in value) {
    if (item is num) result.add(item.toInt());
  }
  result.sort();
  return result;
}

int intOr(dynamic value, int fallback) => value is num ? value.toInt() : fallback;

String text(dynamic value) => value is String ? value : '';
