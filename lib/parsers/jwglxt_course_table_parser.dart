import '../models/course.dart';
import 'course_table_parser.dart';

/// 正方新版教务系统（jwglxt，正方 V-8 系）的学生课表解析器。
///
/// 与 [EamsCourseTableParser] 覆盖的 EAMS 版是同一家厂商的两代不同产品：
/// EAMS 把课表以 `TaskActivity` 脚本的形式吐给前端，jwglxt 则直接渲染成 HTML
/// 表格，数据格式完全不同，所以必须分开解析。
///
/// 这里解析的是 jwglxt 课表页里的**列表式**课表（`#kblist_table`）。同一页面
/// 通常还会渲染一份网格式课表（用于「一览」视图），但列表式结构更规整：
/// 每个星期一个 `<tbody id="xq_N">`，每条排课的节次直接从 `id="jc_星期-起-止"`
/// 读出来，正文里带周数、地点、教师，比反推网格坐标可靠得多。
class JwglxtCourseTableParser implements CourseTableParser {
  const JwglxtCourseTableParser();

  @override
  String get name => '正方新版 jwglxt';

  @override
  bool matches(String html) => html.contains('kblist_table');

  /// 每个星期的区块，`N` 为星期（1=周一 … 7=周日）
  static final RegExp _weekdayBlockRe =
      RegExp(r'<tbody[^>]*id="xq_(\d+)"[^>]*>');

  /// 排课行的节次标记：`id="jc_2-1-2"` 表示星期二第 1-2 节
  static final RegExp _periodRe = RegExp(r'id="jc_(\d+)-(\d+)-(\d+)"');

  /// 课程名所在的标题
  static final RegExp _titleRe =
      RegExp(r'<span class="title">(.*?)</span>', dotAll: true);

  static final RegExp _studentIdRe = RegExp(r'学号：\s*(\d+)');
  static final RegExp _semesterRe =
      RegExp(r'(\d{4}-\d{4})学年第\s*(\d+)\s*学期');

  /// 课程名后面跟着的类型标记：★-理论 ■-上机 ◆-实践 ☆-实验
  static final RegExp _typeMarksRe = RegExp(r'[★■◆☆]');

  /// 网格课表底部那行「其它课程：军事技能☆陆佳辉(共2周)/11-12周/无;」。
  ///
  /// 它渲染在 `kblist_table` 之前、不属于任何 `<tbody id="xq_N">`，
  /// 所以既有逻辑扫不到，得单独按全文找一次。
  static final RegExp _otherCoursesRe =
      RegExp(r'其[它他]课程\s*[：:]([\s\S]*?)(?:<br|</div>)');

  @override
  CourseTableData parse(String html) {
    final sessions = <CourseSession>[];
    final courses = <String, Course>{};

    for (final block in _weekdayBlocks(html)) {
      for (final session in _sessionsIn(block.text, block.dayOfWeek)) {
        sessions.add(session);
        // 课程名单：按教学班去重，把直观的信息凑出来（这一页没有独立的名单表）
        courses.putIfAbsent(
          session.courseId,
          () => Course(
            courseId: session.courseId,
            // jwglxt 课表页不给课程代码，留空而不是瞎编
            code: '',
            name: session.name,
            teacher: session.teacher,
          ),
        );
      }
    }

    // 网格课表底部还有一行「其它课程」。这类课（军训、实践之类）没有节次，
    // 进不了课表网格，但列进课程名单才不会被当成漏掉的课。
    for (final match in _otherCoursesRe.allMatches(html)) {
      for (final course in _otherCourses(_stripTags(match.group(1)!))) {
        // 同一门课若已有排课记录（名字一致），就不要重复列
        if (courses.values.any((c) => c.name == course.name)) continue;
        courses.putIfAbsent(course.courseId, () => course);
      }
    }

    return CourseTableData(
      sessions: sessions,
      courses: courses.values.toList(),
      periodsPerDay: _periodsPerDay(sessions),
      studentId: _studentIdRe.firstMatch(html)?.group(1),
      semesterId: _semester(html),
    );
  }

  /// 按 `<tbody id="xq_N">` 切出每个星期的区块。
  ///
  /// 刻意不去截取整张 `kblist_table`：嵌套表格会让 `</table>` 配对变得不可靠，
  /// 而 `xq_N` 这个 id 本身足够独特，切到下一个 tbody 就够了。
  List<({int dayOfWeek, String text})> _weekdayBlocks(String html) {
    final matches = _weekdayBlockRe.allMatches(html).toList();
    final blocks = <({int dayOfWeek, String text})>[];

    for (var i = 0; i < matches.length; i++) {
      final day = int.tryParse(matches[i].group(1)!);
      if (day == null || day < 1 || day > 7) continue;

      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : html.length;
      var text = html.substring(start, end);

      // 万一区块里还嵌了别的表格，截到它结束为止
      final tableEnd = text.indexOf('</table>');
      if (tableEnd >= 0) text = text.substring(0, tableEnd);

      blocks.add((dayOfWeek: day, text: text));
    }
    return blocks;
  }

  /// 解析一个星期区块里的全部排课
  List<CourseSession> _sessionsIn(String block, int dayOfWeek) {
    final matches = _periodRe.allMatches(block).toList();
    final sessions = <CourseSession>[];

    for (var i = 0; i < matches.length; i++) {
      // 这一行的范围：从节次标记到下一行开头
      final start = matches[i].start;
      final nextRow = block.indexOf('<tr', matches[i].end);
      final end = nextRow >= 0
          ? nextRow
          : (i + 1 < matches.length ? matches[i + 1].start : block.length);
      final row = block.substring(start, end);

      final parsedStart = int.tryParse(matches[i].group(2)!);
      final parsedEnd = int.tryParse(matches[i].group(3)!);
      if (parsedStart == null || parsedEnd == null) continue;
      if (parsedEnd < parsedStart) continue;

      final name = _cleanName(
        _titleRe.firstMatch(row)?.group(1) ?? '',
      );
      if (name.isEmpty) continue;

      final room = _value(row, '上课地点');
      final teacher = _value(row, '教师');
      final className = _value(row, '教学班');
      sessions.add(
        CourseSession(
          // 教学班作为课程序号：它在一所学校内唯一，比课程名可靠。
          // 有的学校（湖州职业技术学院）这一栏叫「教学班组成」、干脆没有
          // 「教学班：」，那就用课名加教师兜底，否则所有课会挤成同一条
          courseId: className.isNotEmpty
              ? className
              : (teacher.isEmpty ? name : '$name-$teacher'),
          name: name,
          teacher: teacher,
          room: room,
          dayOfWeek: dayOfWeek,
          periods: [for (var p = parsedStart; p <= parsedEnd; p++) p],
          weeks: parseWeeks(_value(row, '周数')),
        ),
      );
    }
    return sessions;
  }

  /// 取出 `标签：值` 里的值。值后面紧跟着标签或行尾，所以取到 `<` 为止即可。
  ///
  /// 冒号写法各校不一：有的写 `教师：张老师`，有的写 `教师 ：张老师`
  /// （湖州职业技术学院就是这种），还有的用半角冒号，这里都认。
  static String _value(String row, String label) {
    final match = RegExp('$label\\s*[：:]\\s*([^<]*)').firstMatch(row);
    final value = match?.group(1)?.trim() ?? '';
    // 值里可能还夹着图标 span 留下的空格
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 课程名去掉 `` 后面的类型标记（★-理论 ■-上机 ◆-实践 ☆-实验）
  static String _cleanName(String raw) => _stripTags(raw)
      .replaceAll(_typeMarksRe, '')
      .trim();

  /// 去掉 HTML 标签，并把常见的实体还原成空格
  static String _stripTags(String raw) => raw
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();

  /// 解析「其它课程」那一行，格式形如
  /// `军事技能☆陆佳辉(共2周)/11-12周/无; 入学教育☆王老师(共1周)/1周/无;`
  ///
  /// 每条以 `/` 分段，第一段是「课名+类型标记+教师」，后面的周次与地点
  /// 对网格课表没有意义（[Course] 也装不下），这里只用第一段。
  static List<Course> _otherCourses(String text) {
    final result = <Course>[];
    for (final item in text.split(RegExp(r'[;；]'))) {
      final head = item.trim().split('/').first.trim();
      if (head.isEmpty) continue;

      // 去掉「(共2周)」这类补充说明
      final body = head.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '').trim();
      if (body.isEmpty) continue;

      // 类型标记夹在课名与教师之间：军事技能☆陆佳辉
      final split = RegExp(r'^(.+?)[★■◆☆〇]\s*(.*)$').firstMatch(body);
      final name = _cleanName(split?.group(1) ?? body);
      if (name.isEmpty) continue;

      final teacher = (split?.group(2) ?? '').trim();
      result.add(
        Course(
          // 与排课记录同一套规则：课名加教师，避免不同课挤成同一条
          courseId: teacher.isEmpty ? name : '$name-$teacher',
          code: '',
          name: name,
          teacher: teacher,
        ),
      );
    }
    return result;
  }

  static String? _semester(String html) {
    final match = _semesterRe.firstMatch(html);
    if (match == null) return null;
    return '${match.group(1)}-${match.group(2)}';
  }

  static int? _periodsPerDay(List<CourseSession> sessions) {
    if (sessions.isEmpty) return null;
    return sessions.map((s) => s.endPeriod).reduce((a, b) => a > b ? a : b);
  }

  /// 解析周数文本，如 `4-17周`、`1,3,5周`、`4-17周(单)`。
  ///
  /// 单双周既可能写在括号里，也可能直接跟在周数后面，这里统一处理：
  /// 先记下有没有「单」「双」，再抽数字，最后按标记过滤。
  static List<int> parseWeeks(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];

    final odd = text.contains('单');
    final even = text.contains('双');
    // 括号内容单独处理，避免打扰后面的区间解析
    final cleaned = text
        .replaceAll(RegExp(r'[（(][^）)]*[）)]'), '')
        .replaceAll(RegExp(r'[周\s]'), '');

    final weeks = <int>{};
    for (final part in cleaned.split(',')) {
      if (part.isEmpty) continue;

      final range = RegExp(r'^(\d+)-(\d+)$').firstMatch(part);
      if (range != null) {
        final from = int.parse(range.group(1)!);
        final to = int.parse(range.group(2)!);
        for (var week = from; week <= to; week++) {
          weeks.add(week);
        }
        continue;
      }

      final single = RegExp(r'^(\d+)').firstMatch(part);
      if (single != null) weeks.add(int.parse(single.group(1)!));
    }

    if (odd) weeks.removeWhere((week) => week.isEven);
    if (even) weeks.removeWhere((week) => week.isOdd);

    final sorted = weeks.toList()..sort();
    return sorted;
  }
}