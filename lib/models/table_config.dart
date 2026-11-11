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

/// 调休规则：某个具体日期按另一天的课表上课。
///
/// 国内学校的调休（国庆/中秋等假期前后）本质就是「周末那天上周几的课」。
/// 课表本身是按周铺开的，所以这里记的是「哪一天」而不是「周次」：
/// 用户改了开学时间导致周次错位时，按日期匹配的规则依然落在正确的日子上。
class DaySwap {
  const DaySwap({required this.date, required this.sourceWeekday});

  /// 调休那天（只用到年月日）
  final DateTime date;

  /// 那天按周几的课表上课，1=周一 … 7=周日
  final int sourceWeekday;

  /// 是否落在 [day] 这一天（只看年月日）
  bool isOn(DateTime day) =>
      date.year == day.year && date.month == day.month && date.day == day.day;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'sourceWeekday': sourceWeekday,
  };

  static DaySwap? fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    final weekday = json['sourceWeekday'];
    if (date == null || weekday is! num) return null;
    return DaySwap(date: date, sourceWeekday: weekday.toInt().clamp(1, 7));
  }
}

/// 课表配置
class TableConfig {
  /// 课表默认名称，也是「用户还没改过名字」的判定依据
  static const String defaultName = '我的课表';

  const TableConfig({
    this.name = defaultName,
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
    this.reservedPeriods = 0,
    this.easterEggUnlocked = false,
    this.singleDayOnly = false,
    this.daySwaps = const [],
    this.autoRefresh = false,
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

  /// 课表底部额外预留的空档节数。
  ///
  /// 教务系统只给到「第几节有课」，晚自习这类时段根本不在数据里，
  /// 导入后课表就画到最晚有课的那一节为止，晚上一片空白无处落笔。
  /// 预留若干节空档后，底部会多出几行没有课的行，用户可直接在上面
  /// 加晚自习、午休一类的自建课程；0 表示不预留，界面与原来完全一致。
  final int reservedPeriods;

  /// 课件实际画出来的节数：正常作息 + 底部预留的空档
  int get totalPeriods => periodsPerDay + reservedPeriods;

  /// 彩蛋是否已解锁（在设置页连点 7 次「当前版本」）。
  ///
  /// 解锁后「仅显示单日程」开关才会出现在设置里；再连点 7 次即重新隐藏。
  final bool easterEggUnlocked;

  /// 彩蛋功能：课表只显示一天，而不是一整周
  final bool singleDayOnly;

  /// 调休规则：某些具体日期按别的星期上课
  final List<DaySwap> daySwaps;

  /// 打开课表时静默从教务重新拉一次。
  ///
  /// 默认关：只有上次是从「能自动导课」的学校导进来的才有意义，
  /// 别校走的是手动翻页面，静默刷新无从下手。
  final bool autoRefresh;

  /// [day] 这一天有没有调休规则；没有则返回 null
  DaySwap? swapOn(DateTime day) {
    for (final swap in daySwaps) {
      if (swap.isOn(day)) return swap;
    }
    return null;
  }

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
    int? reservedPeriods,
    bool? easterEggUnlocked,
    bool? singleDayOnly,
    List<DaySwap>? daySwaps,
    bool? autoRefresh,
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
      reservedPeriods: reservedPeriods ?? this.reservedPeriods,
      easterEggUnlocked: easterEggUnlocked ?? this.easterEggUnlocked,
      singleDayOnly: singleDayOnly ?? this.singleDayOnly,
      daySwaps: daySwaps ?? this.daySwaps,
      autoRefresh: autoRefresh ?? this.autoRefresh,
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
    'reservedPeriods': reservedPeriods,
    'easterEggUnlocked': easterEggUnlocked,
    'singleDayOnly': singleDayOnly,
    'daySwaps': daySwaps.map((s) => s.toJson()).toList(),
    'autoRefresh': autoRefresh,
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
      reservedPeriods: json['reservedPeriods'] as int? ?? 0,
      easterEggUnlocked: json['easterEggUnlocked'] as bool? ?? false,
      singleDayOnly: json['singleDayOnly'] as bool? ?? false,
      autoRefresh: json['autoRefresh'] as bool? ?? false,
      daySwaps: [
        for (final item in json['daySwaps'] as List<dynamic>? ?? const [])
          if (item is Map<String, dynamic>) ?DaySwap.fromJson(item),
      ],
    );
  }

  /// 把节次钟点补齐到第 [through] 节，已有的不动
  static List<PeriodTime> extendPeriodTimes(
    List<PeriodTime> times,
    int through,
  ) {
    final byPeriod = {for (final t in times) t.period: t};
    for (final t in defaultPeriodTimes) {
      if (t.period <= through) byPeriod.putIfAbsent(t.period, () => t);
    }
    final periods = byPeriod.keys.toList()..sort();
    return [for (final p in periods) byPeriod[p]!];
  }

  /// 重新导入课表时用：以新数据生成基础配置，但保留用户已经调过的项。
  ///
  /// 这里要解决的问题是「重新导一次课表，之前手动调好的节次钟点又变回去了」：
  /// [fresh] 是从新数据算出来的配置（含默认作息），[previous] 是导入前的配置。
  /// 用户的钟点、开学时间、外观这些都不是教务数据能覆盖的，一律沿用旧的，
  /// 只有节数/周数/课表名这类确实随数据变化的部分才用新的。
  ///
  /// [previous] 为 null（首次导入）时直接返回 [fresh]。
  static TableConfig mergeImport({
    required TableConfig fresh,
    required TableConfig? previous,
  }) {
    if (previous == null) return fresh;
    return fresh.copyWith(
      // 用户改过名字就留着，没改过就用学校名
      name: previous.name == defaultName ? fresh.name : previous.name,
      startDate: previous.startDate ?? fresh.startDate,
      periodTimes: previous.periodTimes.isEmpty
          ? fresh.periodTimes
          : extendPeriodTimes(previous.periodTimes, fresh.periodsPerDay),
      weekStartDay: previous.weekStartDay,
      showSaturday: previous.showSaturday,
      showSunday: previous.showSunday,
      showOtherWeeks: previous.showOtherWeeks,
      cellHeight: previous.cellHeight,
      cellRadius: previous.cellRadius,
      reservedPeriods: previous.reservedPeriods,
      easterEggUnlocked: previous.easterEggUnlocked,
      singleDayOnly: previous.singleDayOnly,
      daySwaps: previous.daySwaps,
      autoRefresh: previous.autoRefresh,
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
      periodTimes: defaultPeriodTimes
          .where((t) => t.period <= periods)
          .toList(),
    );
  }
}
