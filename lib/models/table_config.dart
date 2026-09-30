/// 课表配置：与学校、学期相关的可调项。
///
/// 教务系统页面对外只提供「第几节有课」，不含节次的具体钟点，
/// 也不含开学日期，因此这些必须由用户配置（WakeUp 的做法也是如此）。
library;

/// 某一节的起止时间
class PeriodTime {
  const PeriodTime({
    required this.period,
    required this.start,
    required this.end,
  });

  /// 第几节，1 起
  final int period;

  /// 起始时间，如 `08:15`
  final String start;

  /// 结束时间，如 `08:50`
  final String end;

  Map<String, dynamic> toJson() => {
        'period': period,
        'start': start,
        'end': end,
      };

  static PeriodTime fromJson(Map<String, dynamic> json) => PeriodTime(
        period: json['period'] as int,
        start: json['start'] as String,
        end: json['end'] as String,
      );
}

/// 课表配置
class TableConfig {
  const TableConfig({
    this.name = '我的课表',
    this.startDate,
    this.periodsPerDay = 14,
    this.totalWeeks = 20,
    this.weekStartDay = DateTime.monday,
    this.periodTimes = const [],
    this.showSaturday = true,
    this.showSunday = true,
    this.showOtherWeeks = true,
    this.cellHeight = 58,
    this.cellRadius = 6,
  });

  /// 课表名称
  final String name;

  /// 开学时间（第一周的周一）。为 null 时无法推算「当前周」。
  final DateTime? startDate;

  /// 一天课程节数
  final int periodsPerDay;

  /// 学期周数
  final int totalWeeks;

  /// 每周起始日，1=周一 … 7=周日
  final int weekStartDay;

  /// 各节次的起止时间
  final List<PeriodTime> periodTimes;

  /// 是否显示周六 / 周日
  final bool showSaturday;
  final bool showSunday;

  /// 是否显示非本周课程
  final bool showOtherWeeks;

  /// 课程格子高度（dp）
  final double cellHeight;

  /// 格子圆角半径（dp）
  final double cellRadius;

  /// 第 [period] 节的时间；未配置时返回 null
  PeriodTime? timeOf(int period) {
    for (final t in periodTimes) {
      if (t.period == period) return t;
    }
    return null;
  }

  /// 根据开学时间推算 [now] 所在的周次；无法推算时返回 null。
  int? currentWeek(DateTime now) {
    final start = startDate;
    if (start == null) return null;
    final from = DateTime(start.year, start.month, start.day);
    final to = DateTime(now.year, now.month, now.day);
    final days = to.difference(from).inDays;
    if (days < 0) return 1;
    return days ~/ 7 + 1;
  }

  /// 某周第一天的日期；无开学时间时返回 null
  DateTime? firstDayOfWeek(int week) {
    final start = startDate;
    if (start == null) return null;
    final from = DateTime(start.year, start.month, start.day);
    return from.add(Duration(days: (week - 1) * 7));
  }

  /// 用「今天是第几周」反推开学日期。
  ///
  /// 各校课表页基本都不给日期（本校 EAMS 和别校 jwglxt 都一样），用户也未必
  /// 记得确切的开学日，但大多知道「现在是第几周」。按本周第一天往前推
  /// (currentWeek - 1) 周即可，得到的开学日期和直接填日期完全等价。
  ///
  /// 注意：返回的是「第 1 周的第一天」，也就是 [firstDayOfWeek] 的第 1 周，
  /// 而不是某个月份的周一，因此与 [weekStartDay] 保持一致。
  static DateTime deriveStartDate({
    required int currentWeek,
    required DateTime today,
    required int weekStartDay,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    // 今天距离本周第一天过了几天
    final daysSinceWeekStart = (day.weekday - weekStartDay + 7) % 7;
    final firstDayOfThisWeek = day.subtract(Duration(days: daysSinceWeekStart));
    return firstDayOfThisWeek.subtract(Duration(days: (currentWeek - 1) * 7));
  }

  TableConfig copyWith({
    String? name,
    DateTime? startDate,
    int? periodsPerDay,
    int? totalWeeks,
    int? weekStartDay,
    List<PeriodTime>? periodTimes,
    bool? showSaturday,
    bool? showSunday,
    bool? showOtherWeeks,
    double? cellHeight,
    double? cellRadius,
  }) {
    return TableConfig(
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      periodsPerDay: periodsPerDay ?? this.periodsPerDay,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      periodTimes: periodTimes ?? this.periodTimes,
      showSaturday: showSaturday ?? this.showSaturday,
      showSunday: showSunday ?? this.showSunday,
      showOtherWeeks: showOtherWeeks ?? this.showOtherWeeks,
      cellHeight: cellHeight ?? this.cellHeight,
      cellRadius: cellRadius ?? this.cellRadius,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'startDate': startDate?.toIso8601String(),
        'periodsPerDay': periodsPerDay,
        'totalWeeks': totalWeeks,
        'weekStartDay': weekStartDay,
        'periodTimes': periodTimes.map((t) => t.toJson()).toList(),
        'showSaturday': showSaturday,
        'showSunday': showSunday,
        'showOtherWeeks': showOtherWeeks,
        'cellHeight': cellHeight,
        'cellRadius': cellRadius,
      };

  static TableConfig fromJson(Map<String, dynamic> json) {
    final rawStart = json['startDate'] as String?;
    return TableConfig(
      name: json['name'] as String? ?? '我的课表',
      startDate: rawStart == null ? null : DateTime.tryParse(rawStart),
      periodsPerDay: json['periodsPerDay'] as int? ?? 14,
      totalWeeks: json['totalWeeks'] as int? ?? 20,
      weekStartDay: json['weekStartDay'] as int? ?? DateTime.monday,
      periodTimes: (json['periodTimes'] as List<dynamic>? ?? [])
          .map((e) => PeriodTime.fromJson(e as Map<String, dynamic>))
          .toList(),
      showSaturday: json['showSaturday'] as bool? ?? true,
      showSunday: json['showSunday'] as bool? ?? true,
      showOtherWeeks: json['showOtherWeeks'] as bool? ?? true,
      cellHeight: (json['cellHeight'] as num?)?.toDouble() ?? 58,
      cellRadius: (json['cellRadius'] as num?)?.toDouble() ?? 6,
    );
  }

  /// 默认节次时间。
  ///
  /// 教务系统不提供钟点，这里给一份常见的作息作为起点，用户可在设置里改。
  static const List<PeriodTime> defaultPeriodTimes = [
    PeriodTime(period: 1, start: '08:15', end: '08:50'),
    PeriodTime(period: 2, start: '09:00', end: '09:50'),
    PeriodTime(period: 3, start: '10:05', end: '11:00'),
    PeriodTime(period: 4, start: '11:10', end: '11:40'),
    PeriodTime(period: 5, start: '13:30', end: '14:20'),
    PeriodTime(period: 6, start: '14:30', end: '15:05'),
    PeriodTime(period: 7, start: '15:20', end: '16:30'),
    PeriodTime(period: 8, start: '16:40', end: '17:30'),
    PeriodTime(period: 9, start: '18:30', end: '19:20'),
    PeriodTime(period: 10, start: '19:30', end: '20:20'),
    PeriodTime(period: 11, start: '20:30', end: '21:20'),
    PeriodTime(period: 12, start: '21:30', end: '22:20'),
  ];

  /// 导入完成后按实际数据生成的初始配置
  static TableConfig initialFor({
    required String name,
    required int maxPeriod,
    required int maxWeek,
    DateTime? startDate,
  }) {
    final periods = maxPeriod <= 0 ? 12 : maxPeriod;
    return TableConfig(
      name: name,
      startDate: startDate,
      periodsPerDay: periods,
      totalWeeks: maxWeek <= 0 ? 20 : maxWeek,
      periodTimes:
          defaultPeriodTimes.where((t) => t.period <= periods).toList(),
    );
  }
}
