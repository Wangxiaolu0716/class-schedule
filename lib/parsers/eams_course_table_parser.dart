import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/course.dart';
import 'course_table_parser.dart';

/// EAMS 系教务系统（`/eams/…`、Struts2 `.action` 架构）的课表解析器。
///
/// 课表的真实数据不在渲染好的 HTML 表格里，而在页面底部的脚本中，
/// 每个排课块对应一个 `TaskActivity`：
///
/// ```js
/// activity = new TaskActivity(actTeacherId.join(','), actTeacherName.join(','),
///     "21116(020D01G35)", "体育健康1(020D01G35)", "526",
///     "鄞州5-201乒乓球馆(鄞州校区)",
///     "00000111101111111100000000000000000000000000000000000", null, null, ...);
/// index = 3*unitCount + 2;
/// table0.activities[index][table0.activities[index].length] = activity;
/// ```
///
/// 编码规则（已用真实课表页面交叉验证）：
/// - 位置：`index = 星期 * unitCount + 节次`。星期 `0=周一 … 6=周日`，
///   节次 `0` 起，`unitCount` 为每天节数（`var unitCount = 14`）。
/// - 周次：`TaskActivity` 的第 5 个字符串参数是周次位图，下标 `w`（1 起）
///   为 `'1'` 表示第 `w` 周有课，最长支持 50 周。单双周直接由此得出。
class EamsCourseTableParser implements CourseTableParser {
  const EamsCourseTableParser();

  @override
  String get name => '正方 EAMS';

  /// EAMS 的特征：课表以 `TaskActivity` 脚本吐给前端。
  ///
  /// 入口页（「我的课表」那张表单）不含课表本身，但会带 `courseTableForStd`，
  /// 一起认出来，便于诊断报告区分「这是入口页」和「完全不认识」。
  @override
  bool matches(String html) =>
      html.contains('new TaskActivity') || html.contains('courseTableForStd');

  static final RegExp _unitCountRe = RegExp(r'var\s+unitCount\s*=\s*(\d+)');
  static final RegExp _activityRe = RegExp(r'new\s+TaskActivity\s*\((.*)\)\s*;');
  static final RegExp _indexRe =
      RegExp(r'index\s*=\s*(\d+)\s*\*\s*unitCount\s*\+\s*(\d+)\s*;');
  static final RegExp _actTeachersRe = RegExp(r'var\s+actTeachers\s*=\s*\[(.*)\]\s*;');
  static final RegExp _teacherNameRe = RegExp(r'name\s*:\s*"([^"]*)"');
  static final RegExp _semesterIdRe = RegExp(r'semester\.id\s*=\s*(\d+)');
  static final RegExp _studentIdRe = RegExp(r'[?&]ids\s*=\s*(\d+)');

  /// 提取「我的课表」入口页里提交给课表接口的学生 ID
  static final RegExp _entryIdsRe = RegExp(
    '''addInput\\(\\s*form\\s*,\\s*["']ids["']\\s*,\\s*["'](\\d+)["']''',
  );

  /// 提取「我的课表」入口页里的学期 ID
  static final RegExp _entrySemesterRe = RegExp(
    '''semesterCalendar\\(\\{[^}]*value\\s*:\\s*["'](\\d+)["']''',
  );

  /// 采集多框架 HTML 时插入的框架分隔标记前缀。
  ///
  /// 采集脚本按 `前缀 + 序号 + '-->'` 生成（见 `webview_import_screen`），
  /// 解析时据此把各框架拆开，避免跨框架取到别的表单的参数。
  static const String frameMarker = '<!--NBCC-FRAME:';

  static final RegExp _frameSplitRe =
      RegExp('${RegExp.escape(frameMarker)}(\\d+)-->');

  static final RegExp _tagValueRe =
      RegExp('''\\bvalue\\s*=\\s*["']([^"']*)["']''');

  /// 课表接口的项目 ID。入口页的「项目」下拉由接口动态填充，
  /// 未选择时使用默认项目 1。
  static const String defaultProjectId = '1';

  /// 从「我的课表」入口页（`courseTableForStd.action`）的 HTML 中
  /// 提取课表接口参数，返回若干**候选**请求体（按可信度排序）。
  ///
  /// 入口页用 `bg.form.addInput(form,"ids","123456")` 带上学生 ID，
  /// 用 `semesterCalendar({…,value:"279"})` 带上学期 ID；
  /// 两者每次都会变化，必须动态提取而不能写死。
  ///
  /// 采集到的 HTML 是多个框架拼接的结果，因此先按 [frameMarker] 拆分，
  /// **只在含课表表单的那个框架里取参数** —— 直接对整段文本取第一个
  /// `addInput(form,"ids",…)` 会取到别的表单（例如成绩查询）的学号，
  /// 请求就会带着错误的学号，服务端返回的页面里自然没有课表。
  ///
  /// 取不到学生 ID 时返回空列表：不猜，避免拼出一个必然失败的请求。
  static List<String> buildCourseTableParamsCandidates(String pageHtml) {
    final frame = _courseTableFrame(pageHtml);
    final ids = _entryIdsRe.firstMatch(frame)?.group(1);
    if (ids == null) return const [];

    // 学期号首选页面里 semesterCalendar 的初始化值（样本中 semester.id
    // 隐藏域是空的），隐藏域仅作兜底
    final semesterIdInScript = _entrySemesterRe.firstMatch(frame)?.group(1);
    final semesterIdInInput = _numericInputValue(frame, 'semester.id');
    final projectId = _numericInputValue(frame, 'project.id') ?? defaultProjectId;

    final candidates = <String>[];
    void add({String? semesterId, required bool withProject}) {
      if (semesterId == null) return;
      final body = StringBuffer('ignoreHead=1&setting.kind=std&startWeek=');
      if (withProject) body.write('&project.id=$projectId');
      body.write('&semester.id=$semesterId&ids=$ids');
      final value = body.toString();
      if (!candidates.contains(value)) candidates.add(value);
    }

    add(semesterId: semesterIdInScript, withProject: true);
    add(semesterId: semesterIdInScript, withProject: false);
    add(semesterId: semesterIdInInput, withProject: true);
    add(semesterId: semesterIdInInput, withProject: false);
    return candidates.take(3).toList();
  }

  /// 在多框架拼接的 HTML 里挑出含课表表单的那个框架。
  ///
  /// `split` 带捕获组，结果中序号与框架内容交替出现，所以偶数位才是
  /// 框架内容（下标 0 是首个标记之前的内容，通常为空）。
  static String _courseTableFrame(String pageHtml) {
    final parts = pageHtml.split(_frameSplitRe);
    for (var i = 0; i < parts.length; i += 2) {
      final content = parts[i];
      if (content.contains('courseTableForStd') ||
          content.contains('courseTableForm')) {
        return content;
      }
    }
    return pageHtml;
  }

  /// 取表单里某个数值型隐藏域的值（如 `name="semester.id"`）。
  ///
  /// 先定位含该 `name` 的标签、再从标签里取 `value`，这样不依赖
  /// `name` 与 `value` 的先后顺序。缺失或非数字时返回 null。
  static String? _numericInputValue(String html, String name) {
    final tagRe = RegExp(
      '''<[^>]*\\bname\\s*=\\s*["']${RegExp.escape(name)}["'][^>]*>''',
    );
    final tag = tagRe.firstMatch(html)?.group(0);
    if (tag == null) return null;

    final value = _tagValueRe.firstMatch(tag)?.group(1);
    if (value == null || !RegExp(r'^\d+$').hasMatch(value)) return null;
    return value;
  }

  /// 解析课表页面 [html]。
  ///
  /// 传入的应当是 `courseTableForStd!courseTable.action` 返回的整页 HTML。
  @override
  CourseTableData parse(String html) {
    int? periodsPerDay;
    final activities = <_RawActivity>[];
    _RawActivity? current;
    var currentTeachers = '';

    for (final line in const LineSplitter().convert(html)) {
      final unitCount = _unitCountRe.firstMatch(line);
      if (unitCount != null) {
        periodsPerDay = int.tryParse(unitCount.group(1)!);
      }

      // 教师名不在 TaskActivity 的参数里，来自紧邻其上的 actTeachers 数组
      final teachers = _actTeachersRe.firstMatch(line);
      if (teachers != null) {
        currentTeachers = _teacherNameRe
            .allMatches(teachers.group(1)!)
            .map((m) => m.group(1)!)
            .join(',');
        continue;
      }

      final activity = _activityRe.firstMatch(line);
      if (activity != null) {
        final raw = _RawActivity.parse(activity.group(1)!, currentTeachers);
        if (raw != null) {
          activities.add(raw);
          current = raw;
        }
        continue;
      }

      final index = _indexRe.firstMatch(line);
      if (index != null && current != null) {
        current.slots.add(_Slot(
          day: int.parse(index.group(1)!),
          period: int.parse(index.group(2)!),
        ));
      }
    }

    final sessions = <CourseSession>[];
    for (final raw in activities) {
      sessions.addAll(raw.toSessions());
    }

    return CourseTableData(
      sessions: sessions,
      courses: _parseCourseList(html),
      periodsPerDay: periodsPerDay,
      studentId: _studentIdRe.firstMatch(html)?.group(1),
      semesterId: _semesterIdRe.firstMatch(html)?.group(1),
    );
  }

  /// 解析页面下方的课程名单表格（含未排课时间的课程）。
  ///
  /// 该表格的 `id` 形如 `grid12042826911`，每次部署都不一样，因此按
  /// `table.gridtable` 且 `id` 以 `grid` 开头来定位，不写死具体 id。
  List<Course> _parseCourseList(String html) {
    final document = html_parser.parse(html);

    Element? table;
    for (final candidate in document.querySelectorAll('table.gridtable')) {
      if (candidate.id.startsWith('grid')) {
        table = candidate;
        break;
      }
    }
    if (table == null) return const [];

    final courses = <Course>[];
    for (final row in table.querySelectorAll('tbody tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 6) continue;

      final code = cells[1].text.trim();
      final name = cells[2].text.trim();
      if (name.isEmpty) continue;

      courses.add(Course(
        courseId: cells[4].text.trim(),
        code: code,
        name: name,
        credits: double.tryParse(cells[3].text.trim()),
        teacher: cells[5].text.trim(),
      ));
    }
    return courses;
  }
}

/// 一个节次位置（星期 + 节次，均为 0 起）
class _Slot {
  const _Slot({required this.day, required this.period});

  final int day;
  final int period;
}

/// 一个 `TaskActivity` 排课块及其占用的所有节次
class _RawActivity {
  static final RegExp _quotedRe = RegExp(r'"([^"]*)"');
  static final RegExp _joinRe = RegExp(r"\.join\(\s*'[^']*'\s*\)");
  static final RegExp _nameCodeRe = RegExp(r'^(.*?)\(([^()]*)\)\s*$');

  _RawActivity({
    required this.courseId,
    required this.name,
    required this.room,
    required this.teacher,
    required this.weeks,
  });

  final String courseId;
  final String name;
  final String room;
  final String teacher;
  final List<int> weeks;
  final List<_Slot> slots = [];

  static _RawActivity? parse(String args, String teacher) {
    // 先去掉 actTeacherId.join(',') / actTeacherName.join(',')，
    // 否则其中的逗号会被当成字符串参数混进来
    final cleaned = args.replaceAll(_joinRe, '');
    final quoted =
        _quotedRe.allMatches(cleaned).map((m) => m.group(1)!).toList();
    if (quoted.length < 5) return null;

    // quoted = ["21116(020D01G35)", "体育健康1(020D01G35)", "526",
    //           "鄞州5-201乒乓球馆(鄞州校区)", "00000111…"]
    final match = _nameCodeRe.firstMatch(quoted[1]);

    return _RawActivity(
      courseId: match?.group(2)?.trim() ?? '',
      name: match?.group(1)?.trim() ?? quoted[1],
      room: quoted[3],
      teacher: teacher,
      weeks: _decodeWeeks(quoted[4]),
    );
  }

  /// 周次位图：下标 `w`（1 起）为 `'1'` 表示第 `w` 周有课
  static List<int> _decodeWeeks(String bitmap) {
    final weeks = <int>[];
    for (var week = 1; week < bitmap.length; week++) {
      if (bitmap[week] == '1') weeks.add(week);
    }
    return weeks;
  }

  /// 把占用的节次按星期分组，连续的节次合并成一段课
  List<CourseSession> toSessions() {
    final periodsByDay = <int, List<int>>{};
    for (final slot in slots) {
      periodsByDay.putIfAbsent(slot.day, () => []).add(slot.period);
    }

    final sessions = <CourseSession>[];
    periodsByDay.forEach((day, periods) {
      final sorted = periods.toSet().toList()..sort();
      for (final run in _consecutiveRuns(sorted)) {
        sessions.add(CourseSession(
          courseId: courseId,
          name: name,
          teacher: teacher,
          room: room,
          dayOfWeek: day + 1,
          periods: [for (var p = run.first; p <= run.last; p++) p + 1],
          weeks: weeks,
        ));
      }
    });
    return sessions;
  }

  static List<List<int>> _consecutiveRuns(List<int> sorted) {
    final runs = <List<int>>[];
    for (final value in sorted) {
      if (runs.isNotEmpty && value == runs.last.last + 1) {
        runs.last.add(value);
      } else {
        runs.add([value]);
      }
    }
    return runs;
  }
}