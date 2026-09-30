import '../models/course.dart';
import 'course_table_parser.dart';
import 'eams_course_table_parser.dart';

/// 离线排查：把「这段页面能不能解析出课表、卡在哪一步」讲清楚。
///
/// 存在的意义是验证别的学校——不用每试一所就发一版。把页面 HTML 丢进来，
/// 报告会直接告诉你属于哪种情况：页面不对、是入口页、系统不认得、还是
/// 认出来了但结构被学校改过。
class ParseDiagnostics {
  const ParseDiagnostics();

  /// 预览多少条排课，够肉眼核对就行
  static const int previewCount = 5;

  static const List<String> _weekdayNames = [
    '', '周一', '周二', '周三', '周四', '周五', '周六', '周日',
  ];

  static final RegExp _activityRe = RegExp(r'new\s+TaskActivity');

  /// 生成一份纯文本报告，可以整体复制发出去
  String report(String html) {
    final buffer = StringBuffer();

    final activityCount = _activityRe.allMatches(html).length;
    final candidates =
        EamsCourseTableParser.buildCourseTableParamsCandidates(html);

    // 每套解析器都试一遍：先看认不认得出，再看能解析出几段
    final attempts = <_Attempt>[];
    for (final parser in supportedParsers) {
      final matched = parser.matches(html);
      var sessions = 0;
      if (matched) {
        try {
          sessions = parser.parse(html).sessions.length;
        } catch (_) {
          sessions = -1; // 解析时抛了异常，报告里单独标出来
        }
      }
      attempts.add(_Attempt(parser.name, matched, sessions));
    }

    final parsed = _firstSuccess(attempts, html);

    _writeInput(buffer, html, activityCount);
    _writeParsers(buffer, attempts);
    _writeParams(buffer, candidates);
    _writeResult(buffer, parsed);
    _writePreview(buffer, parsed);
    _writeConclusion(
      buffer,
      parsed: parsed,
      attempts: attempts,
      activityCount: activityCount,
      candidateCount: candidates.length,
    );

    return buffer.toString();
  }

  /// 找到第一个成功解析的结果（与 import 流程用的是同一套判断）
  ParsedCourseTable? _firstSuccess(List<_Attempt> attempts, String html) {
    for (final parser in supportedParsers) {
      final attempt = attempts.firstWhere(
        (a) => a.name == parser.name,
        orElse: () => _Attempt(parser.name, false, 0),
      );
      if (attempt.sessions <= 0) continue;
      return ParsedCourseTable(data: parser.parse(html), parserName: parser.name);
    }
    return null;
  }

  void _writeInput(StringBuffer buffer, String html, int activityCount) {
    final frames = html.split(EamsCourseTableParser.frameMarker).length - 1;
    buffer
      ..writeln('=== 输入 ===')
      ..writeln('字符数：${html.length}')
      ..writeln('框架分隔标记：$frames 个${frames > 0 ? '（页面是 frameset，已按框架拆开）' : ''}')
      ..writeln('含 <html 标签：${html.contains('<html') ? '是' : '否'}')
      ..writeln('含 new TaskActivity：$activityCount 处')
      ..writeln();
  }

  void _writeParsers(StringBuffer buffer, List<_Attempt> attempts) {
    buffer.writeln('=== 解析器识别 ===');
    for (final attempt in attempts) {
      if (!attempt.matched) {
        buffer.writeln('· ${attempt.name}：未识别');
        continue;
      }
      if (attempt.sessions < 0) {
        buffer.writeln('· ${attempt.name}：识别到，但解析时抛异常');
        continue;
      }
      buffer.writeln('· ${attempt.name}：识别到，解析出 ${attempt.sessions} 段排课');
    }
    buffer.writeln();
  }

  void _writeParams(StringBuffer buffer, List<String> candidates) {
    buffer.writeln('=== 课表接口参数（仅 EAMS 入口页有意义）===');
    if (candidates.isEmpty) {
      buffer.writeln('没提取到参数。');
    } else {
      buffer.writeln('候选参数 ${candidates.length} 组（自动导入时会依次尝试）：');
      for (var i = 0; i < candidates.length; i++) {
        buffer.writeln('  ${i + 1}) ${candidates[i]}');
      }
    }
    buffer.writeln();
  }

  void _writeResult(StringBuffer buffer, ParsedCourseTable? parsed) {
    buffer.writeln('=== 解析结果 ===');
    final data = parsed?.data;
    if (data == null) {
      buffer.writeln('没有可用结果（没有任何解析器解析出课程）。');
      buffer.writeln();
      return;
    }

    final sessions = data.sessions;
    buffer
      ..writeln('使用的解析器：${parsed!.parserName}')
      ..writeln('一天节数：${data.periodsPerDay ?? '未取到'}')
      ..writeln('排课段：${sessions.length}')
      ..writeln('课程名单：${data.courses.length} 门')
      ..writeln('学生 ID：${data.studentId ?? '未取到'}')
      ..writeln('学期 ID：${data.semesterId ?? '未取到'}');

    if (sessions.isNotEmpty) {
      final weeks = sessions.expand((s) => s.weeks).toList()..sort();
      if (weeks.isNotEmpty) {
        buffer.writeln('周次范围：${weeks.first} - ${weeks.last}');
      }
    }
    buffer.writeln();
  }

  void _writePreview(StringBuffer buffer, ParsedCourseTable? parsed) {
    final sessions = parsed?.data.sessions ?? const <CourseSession>[];
    if (sessions.isEmpty) return;

    final count = sessions.length < previewCount ? sessions.length : previewCount;
    buffer.writeln('=== 前 $count 条排课 ===');
    for (final session in sessions.take(previewCount)) {
      final day = session.dayOfWeek >= 1 && session.dayOfWeek <= 7
          ? _weekdayNames[session.dayOfWeek]
          : '周${session.dayOfWeek}';
      buffer.writeln(
        '· ${session.name} $day 第${session.startPeriod}-${session.endPeriod}节 '
        '周次${formatWeeks(session.weeks)}'
        '${session.room.isEmpty ? '' : ' @${session.room}'}',
      );
    }
    buffer.writeln();
  }

  void _writeConclusion(
    StringBuffer buffer, {
    required ParsedCourseTable? parsed,
    required List<_Attempt> attempts,
    required int activityCount,
    required int candidateCount,
  }) {
    buffer.writeln('=== 结论 ===');

    if (parsed != null) {
      buffer.writeln('解析正常（由「${parsed.parserName}」解析）。这份页面可以直接用。');
      return;
    }

    if (candidateCount > 0) {
      buffer
        ..writeln('这是「我的课表」入口页，本身不含课表数据 —— 课表要靠 App 去请求接口。')
        ..writeln('自动模式（本校）能处理；手动导课需要先在页面里翻到课表页。');
      return;
    }

    final recognized = attempts.where((a) => a.matched).toList();

    // 先看有没有 EAMS 的脚本痕迹：有 TaskActivity 却解析不出排课，
    // 说明结构被改过，这比「认得出来但没数据」更具体
    if (activityCount > 0) {
      buffer
        ..writeln('页面里有 $activityCount 处 TaskActivity，但没解析出任何排课。')
        ..writeln('说明它不是标准的正方 EAMS 结构（或者被学校改过），')
        ..writeln('需要针对该格式补一个解析器。把这份报告发出来即可定位。');
      return;
    }

    if (recognized.isNotEmpty) {
      final names = recognized.map((a) => a.name).join('、');
      buffer
        ..writeln('系统认得出来（$names），但没解析出任何排课。')
        ..writeln('很可能是停在了查询页而不是课表页 —— 手动导课时请先翻到能看全整张课表的页面。')
        ..writeln('若确实停在课表页仍如此，说明该校结构有定制，把这份报告发出来即可定位。');
      return;
    }

    buffer
      ..writeln('这一页既不是课表页，也不是「我的课表」入口页，')
      ..writeln('而且没有任何已支持的解析器认得它。')
      ..writeln('手动导课时请先翻到能看全整张课表的页面，再点「导课」。');
  }
}

/// 一套解析器在这次输入上的表现
class _Attempt {
  const _Attempt(this.name, this.matched, this.sessions);

  final String name;
  final bool matched;

  /// 解析出的排课段数；-1 表示解析时抛了异常
  final int sessions;
}