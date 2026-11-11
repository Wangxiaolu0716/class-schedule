import 'dart:convert';

import '../models/course.dart';
import '../models/school_periods.dart';
import '../models/table_config.dart';

/// 交给 AI 的提示词。
///
/// 字段名与 [AiCourseJsonParser] 认的字段一一对应，改这里就要同步改那边。
/// 给的是「图片或网页内容」两种说法：用户既可以截图，也可以把课表页的
/// 文字/HTML 粘给 AI，两条路最终都回同一套 JSON。
const String aiImportPrompt = '''
你是课程表识别助手。请识别我提供的课表图片或网页内容，并严格按下述要求输出：

1) 识别规则
- 表格最左侧为课程节数（第几节）
- 表格最上方为星期几
- 每个课程格子可能包含：课程名称、上课周数、上课地点、上课教师
- 课程可能跨多节课，请合并为连续节次（如 1-3节）
- 如果同名课程在不同教室上课，不要合并周数，必须拆分为多条课程
- 请从星期角度依次解析：周一 -> 周二 -> 周三 -> 周四 -> 周五 -> 周六 -> 周日，避免漏课

2) 输出要求
- 只输出 JSON 数组，不要任何解释文本
- 使用如下字段：name, teacher, classRoom, weekday, fixWeeks, courseNumbers
- weekday 使用"星期一~星期日"
- fixWeeks 示例："1-16周"、"3-18单周"、"2-16双周"
- courseNumbers 示例："1-2节"、"3-4节"
- 最终结果请使用 ```json 代码块包裹，便于复制

3) 输出示例
[
  {
    "name": "通信工程专业导论",
    "teacher": "赵月",
    "classRoom": "综合楼313",
    "weekday": "星期一",
    "fixWeeks": "6-7周",
    "courseNumbers": "1-2节"
  }
]''';

/// 作息时间表版提示词：让 AI 把作息图读成 [AiPeriodsParser] 认的 JSON。
///
/// 字段名同样与解析器一一对应，改这里就要同步改那边。
const String aiPeriodPrompt = '''
你是作息时间表识别助手。我会给你一张学校的作息时间表（上课时间表）图片，请严格按下述要求输出：

1) 识别规则
- 只要「上课时间」，也就是第几节从几点上到几点
- 不要理会上下班时间、教师签到时间、假期与考试周的安排
- 每个数字都照抄图上写的，不要推算、不要凑整、不要按常见作息「修正」
- 图里若分成两栏（如夏令时 / 冬令时），或按校区各有一份，每份单独输出

2) 输出要求
- 只输出 JSON 数组，不要任何解释文本
- 每份作息一个对象，字段：label（这份叫做什么，如「夏令时间」）、times（各节次数组）
- times 里每条字段：period（第几节，整数）、start（开始时间）、end（结束时间）
- 时间统一写成 HH:mm，例如 08:15
- 最终结果请使用 ```json 代码块包裹，便于复制

3) 输出示例
[
  {
    "label": "夏令时间",
    "times": [
      {"period": 1, "start": "08:15", "end": "09:00"},
      {"period": 2, "start": "09:05", "end": "09:50"}
    ]
  }
]''';

/// AI 返回的内容没法用（不是 JSON、认不出课程等）
class AiImportException implements Exception {
  const AiImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次 AI 导课的解析结果。
class AiParseResult {
  const AiParseResult({
    required this.data,
    this.skipped = const [],
    this.notes = const [],
  });

  final CourseTableData data;

  /// 认不出来、被跳过的条目及原因（如「某课：没认出星期几」）
  final List<String> skipped;

  /// 需要让用户知道的处理说明（如「有 3 条没有周次，按 1-20 周处理」）
  final List<String> notes;
}

/// 把大模型返回的课表 JSON 转成课表数据。
///
/// 这条路的定位是「这所学校没有内置解析器时的兜底」：用户把课表截图（或课表页
/// 内容）连同 [aiImportPrompt] 交给任意一个 AI，拿回 JSON 再粘进 App。
/// 好处是不必为每所学校单独适配，也不需要 App 联网、不花钱。
///
/// 代价是大模型的输出不会百分百规矩，所以这里的解析一律「能救就救」：
/// 前后多余的说明文字、```json 代码块、单条对象而不是数组、字段名中英文混用、
/// 教师给成数组，都尽量认；实在认不出的单条跳过，把原因交给界面显示。
class AiCourseJsonParser {
  const AiCourseJsonParser();

  /// 没有周次信息时的兜底周数，按常见的一学期长度取
  static const int defaultWeekCount = 20;

  /// 周次、节次的合法上限，防止 AI 写出 `1-9999` 把内存撑爆
  static const int _maxValue = 40;

  AiParseResult parse(String raw) {
    final items = _extractItems(raw);
    if (items.isEmpty) {
      throw const AiImportException('AI 返回的课表是空的，请让它重新识别一次');
    }

    final sessions = <CourseSession>[];
    final teachers = <String, String>{};
    final skipped = <String>[];
    final notes = <String>[];
    var missingWeeks = 0;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) {
        skipped.add('第 ${i + 1} 条不是课程对象，已跳过');
        continue;
      }

      final name = _text(item, const ['name', 'courseName', '课程名称', '课程名', '课程']);
      if (name.isEmpty) {
        skipped.add('第 ${i + 1} 条没有课程名，已跳过');
        continue;
      }

      final day = _parseWeekday(_text(item, const ['weekday', 'dayOfWeek', '星期', '周几']));
      if (day == null) {
        skipped.add('$name：没认出是星期几，已跳过');
        continue;
      }

      final weekText =
          _text(item, const ['fixWeeks', 'weeks', 'weekRange', '上课周数', '周次', '周数']);
      var weeks = _expandRanges(weekText, parity: _parityOf(weekText));
      if (weeks.isEmpty) {
        // 没给周次多半是「整学期都上」，直接丢掉这门课反而更糟
        weeks = List.generate(defaultWeekCount, (i) => i + 1);
        missingWeeks++;
      }

      final periods = _expandRanges(
        _text(item, const ['courseNumbers', 'periods', 'sections', '节次', '上课节次']),
      );
      if (periods.isEmpty) {
        skipped.add('$name：没认出是第几节，已跳过');
        continue;
      }

      final teacher =
          _text(item, const ['teacher', 'teachers', '教师', '上课教师', '授课教师']);
      teachers[name] = teacher;

      sessions.add(
        CourseSession(
          courseId: 'ai-${i + 1}-$name',
          name: name,
          teacher: teacher,
          room: _text(item, const ['classRoom', 'classroom', 'room', 'location', '教室', '上课地点', '地点']),
          dayOfWeek: day,
          periods: periods,
          weeks: weeks,
        ),
      );
    }

    if (sessions.isEmpty) {
      // 一条都没成时，把第一条原因带出来——「没认出是星期几」这种提示，
      // 比笼统的「没读出课程」有用得多，用户知道该让 AI 补什么
      throw AiImportException(
        skipped.isEmpty
            ? '这些内容里没读出任何一门课，请换一次识别结果再试'
            : '这些内容里没读出课程：${skipped.first}',
      );
    }

    if (missingWeeks > 0) {
      notes.add('有 $missingWeeks 条没有周次信息，已按第 1-$defaultWeekCount 周处理');
    }

    return AiParseResult(
      data: CourseTableData(
        sessions: sessions,
        // 课程名单按课名去重，用于「无排课时间的课程」等处
        courses: [
          for (final entry in teachers.entries)
            Course(courseId: 'ai-${entry.key}', code: '', name: entry.key, teacher: entry.value),
        ],
        periodsPerDay: sessions.map((s) => s.endPeriod).reduce((a, b) => a > b ? a : b),
      ),
      skipped: skipped,
      notes: notes,
    );
  }

  /// 从可能夹着说明文字、代码块的回复里抠出课程数组。
  static List<Object?> _extractItems(String raw) {
    // 去掉 ``` 与 ```json 这类围栏，留下纯文本再定位括号
    final text = raw.replaceAll('```', ' ');

    final arrayStart = text.indexOf('[');
    final arrayEnd = text.lastIndexOf(']');
    if (arrayStart >= 0 && arrayEnd > arrayStart) {
      final decoded = _decode(text.substring(arrayStart, arrayEnd + 1));
      if (decoded is List) return decoded;
    }

    final objectStart = text.indexOf('{');
    final objectEnd = text.lastIndexOf('}');
    if (objectStart >= 0 && objectEnd > objectStart) {
      final decoded = _decode(text.substring(objectStart, objectEnd + 1));
      if (decoded is Map) {
        // 可能是 {"courses": [...]} 这种被包了一层
        for (final value in decoded.values) {
          if (value is List) return value;
        }
        return [decoded];
      }
    }

    throw const AiImportException('没找到 JSON，请把 AI 返回的内容整段粘进来');
  }

  static Object? _decode(String source) {
    try {
      return jsonDecode(source);
    } catch (_) {
      throw const AiImportException('这段内容不是合法的 JSON，看看是不是没复制完整');
    }
  }

  /// 按多个候选字段名取字符串值。教师给成数组时拼成「张三,李四」。
  static String _text(Map item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value == null) continue;

      if (value is List) {
        final parts = [
          for (final element in value)
            if (element != null && element.toString().trim().isNotEmpty)
              element.toString().trim(),
        ];
        if (parts.isNotEmpty) return parts.join(',');
        continue;
      }

      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  /// 星期几：认「星期一」「周一」「礼拜一」「Monday」「1」等写法
  static int? _parseWeekday(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    const chinese = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};
    for (final entry in chinese.entries) {
      if (text.contains('星期${entry.key}') ||
          text.contains('周${entry.key}') ||
          text.contains('礼拜${entry.key}')) {
        return entry.value;
      }
    }

    const english = {'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7};
    final lower = text.toLowerCase();
    for (final entry in english.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    final digit = RegExp(r'[1-7]').firstMatch(text);
    return digit == null ? null : int.parse(digit.group(0)!);
  }

  /// 单周 / 双周标记。true 表示只留单周，false 表示只留双周。
  static bool? _parityOf(String raw) {
    if (raw.contains('单')) return true;
    if (raw.contains('双')) return false;
    return null;
  }

  /// 把「1-16周」「3-18单周」「1,3,5周」「第2节」这类写法展开成数字列表。
  ///
  /// 做法是先按分隔符切成小段，再把每段里除了数字和连字符以外的字符统统去掉，
  /// 于是「第1-16周」和「1-16」等价，不必逐个句式写正则。
  static List<int> _expandRanges(String raw, {bool? parity}) {
    if (raw.trim().isEmpty) return const [];

    // 各种连接号统一成半角连字符，「1至16」也一并归一
    final normalized = raw
        .replaceAll(RegExp(r'[至~～–—－]'), '-')
        .replaceAll(RegExp(r'[（(]'), ',')
        .replaceAll(RegExp(r'[)）]'), ',');

    final values = <int>{};
    for (final chunk in normalized.split(RegExp(r'[,，;；、/|]'))) {
      final cleaned = chunk.replaceAll(RegExp(r'[^0-9\-]'), '');
      if (cleaned.isEmpty) continue;

      final range = RegExp(r'^(\d+)-(\d+)$').firstMatch(cleaned);
      if (range != null) {
        final first = int.parse(range.group(1)!);
        final second = int.parse(range.group(2)!);
        final low = first <= second ? first : second;
        final high = (first <= second ? second : first).clamp(1, _maxValue);
        for (var value = low; value <= high; value++) {
          if (value >= 1) values.add(value);
        }
        continue;
      }

      final single = RegExp(r'\d+').firstMatch(cleaned);
      if (single == null) continue;
      final value = int.parse(single.group(0)!);
      if (value >= 1 && value <= _maxValue) values.add(value);
    }

    final sorted = values.toList()..sort();
    if (parity == null) return sorted;
    return [
      for (final value in sorted)
        if (value.isOdd == parity) value,
    ];
  }
}

/// 一次 AI 识别的作息结果：一份或多份（图里分夏令/冬令、分院区就会有多个）
class AiPeriodsResult {
  const AiPeriodsResult({required this.presets, this.skipped = const []});

  final List<PeriodPreset> presets;

  /// 认不出、被跳过的条目及原因
  final List<String> skipped;
}

/// 把大模型返回的作息 JSON 转成作息预设。
///
/// 与 [AiCourseJsonParser] 同一套路，只是换成作息：用户把作息表和
/// [aiPeriodPrompt] 交给 AI，拿回 JSON 再粘进 App。这条路给的是没有内置作息
/// 的学校——不必为每所学校单独适配，也不用 App 联网。
///
/// 注意：AI 从图片里抄时间是会抄错的，解析只负责如实转成节次时间，
/// 套用之前一律由界面把每节时间摊开让用户过一眼（见课表设置的「套用学校作息」）。
class AiPeriodsParser {
  const AiPeriodsParser();

  /// 节次上限，防止 AI 写出「第 9999 节」
  static const int _maxPeriod = 40;

  /// 认这段回复里的节次字段名
  static const List<String> _startKeys = [
    'start', 'startTime', 'begin', 'from', '开始', '开始时间', '起',
  ];
  static const List<String> _endKeys = [
    'end', 'endTime', 'finish', 'to', '结束', '结束时间', '止',
  ];

  AiPeriodsResult parse(String raw) {
    final items = AiCourseJsonParser._extractItems(raw);
    if (items.isEmpty) {
      throw const AiImportException('AI 返回的内容是空的，请让它重新识别一次');
    }

    final skipped = <String>[];

    // 有的 AI 不给分组，直接把「一节一条」的数组给回来，那就整段当成一份作息
    // shortcut: 这种给法带不出名字（它是从分组对象里被拆出来的），一律叫「AI 识别的作息」；
    // 等真的有人抱怨名字，再去改 _extractItems 把外层对象一起带出来
    if (_isTimeRow(items.first)) {
      final times = _parseTimes(items, skipped, 'AI 识别的作息');
      if (times.isEmpty) throw AiImportException(_nothingFound(skipped));
      return AiPeriodsResult(
        presets: [PeriodPreset(label: 'AI 识别的作息', times: times)],
        skipped: skipped,
      );
    }

    final presets = <PeriodPreset>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) {
        skipped.add('第 ${i + 1} 份不是作息对象，已跳过');
        continue;
      }

      final label = AiCourseJsonParser._text(
        item,
        const ['label', 'name', 'title', '名称', '作息', '作息名称', '时段'],
      );
      final who = label.isEmpty ? '第 ${i + 1} 份' : label;
      final times = _parseTimes(_rowsOf(item), skipped, who);
      if (times.isEmpty) {
        skipped.add('$who：一节时间都没读出来，已跳过');
        continue;
      }
      presets.add(
        PeriodPreset(label: label.isEmpty ? 'AI 识别的作息' : label, times: times),
      );
    }

    if (presets.isEmpty) throw AiImportException(_nothingFound(skipped));
    return AiPeriodsResult(presets: presets, skipped: skipped);
  }

  /// 这份作息里的节次数组；没有嵌套数组时返回空列表
  static List<Object?> _rowsOf(Map item) {
    for (final key in const ['times', 'periods', 'list', '节次', '时间']) {
      final value = item[key];
      if (value is List) return value;
    }
    return const [];
  }

  /// 是不是「一节一条」那种行（自身带节次或时间，而不是包着 times 的分组对象）
  static bool _isTimeRow(Object? item) {
    if (item is! Map) return false;
    if (_rowsOf(item).isNotEmpty) return false;
    return ['period', 'index', 'no', 'start', 'startTime', '节次', '开始']
        .any((key) => item[key] != null);
  }

  /// 把一串节次对象转成 [PeriodTime]，认不出的逐条记原因
  static List<PeriodTime> _parseTimes(
    List<Object?> rows,
    List<String> skipped,
    String who,
  ) {
    final byPeriod = <int, PeriodTime>{};

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map) {
        skipped.add('$who 第 ${i + 1} 条不是节次对象，已跳过');
        continue;
      }

      final period = _parsePeriod(
        AiCourseJsonParser._text(
          row,
          const ['period', 'index', 'no', '节次', '第几节', '节'],
        ),
      );
      final start = _parseClock(AiCourseJsonParser._text(row, _startKeys));
      final end = _parseClock(AiCourseJsonParser._text(row, _endKeys));
      if (period == null || start == null || end == null) {
        skipped.add('$who 第 ${i + 1} 条没认出节次或时间，已跳过');
        continue;
      }
      if (_minutes(end) <= _minutes(start)) {
        // 结束早于开始基本是抄错了，宁可跳过也不写进课表
        skipped.add('$who 第 $period 节：结束 $end 早于开始 $start，已跳过');
        continue;
      }

      // 同一节出现两次（AI 常常把两套作息串在一起）时留第一条
      byPeriod.putIfAbsent(
        period,
        () => PeriodTime(period: period, start: start, end: end),
      );
    }

    final periods = byPeriod.keys.toList()..sort();
    return [for (final p in periods) byPeriod[p]!];
  }

  /// 节次：认「1」「第 1 节」「1-2」中的第一个数字
  static int? _parsePeriod(String raw) {
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match == null) return null;
    final value = int.parse(match.group(0)!);
    return value >= 1 && value <= _maxPeriod ? value : null;
  }

  /// 时间：认 `08:15`、`8:15`、`08：15`（全角冒号）。
  ///
  /// 分钟要求正好两位——「8:5」这种多半是抄漏了，宁可当认不出报出来。
  static String? _parseClock(String raw) {
    final match = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{2})(?!\d)').firstMatch(raw);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static int _minutes(String clock) {
    final parts = clock.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// 一节都没读出来时的提示：带上第一条原因，用户才知道该让 AI 补什么
  static String _nothingFound(List<String> skipped) => skipped.isEmpty
      ? '这些内容里没读出一节时间，请让 AI 重新识别一次'
      : '这些内容里没读出一节时间：${skipped.first}';
}
