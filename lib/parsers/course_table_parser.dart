import '../models/course.dart';
import 'eams_course_table_parser.dart';
import 'jwglxt_course_table_parser.dart';

/// 课表解析器的统一接口。
///
/// 各校教务系统的差别主要在登录方式和页面结构。把「从一段 HTML 里读出课表」
/// 抽成接口后，新增一套体系（比如正方新版 jwglxt）只需要加一个实现，
/// 导入流程和诊断工具都不用改。
abstract class CourseTableParser {
  const CourseTableParser();

  /// 解析器名字，诊断报告里用它说明「是谁认出来的」
  String get name;

  /// 这份 HTML 是否属于本解析器负责的体系。
  ///
  /// 只看特征标记，不做完整解析，用来快速筛掉无关页面。
  bool matches(String html);

  /// 解析课表。解析不出课程时返回空课表，而不是抛异常。
  CourseTableData parse(String html);
}

/// 一次成功的解析：数据 + 是哪套解析器认出来的
class ParsedCourseTable {
  const ParsedCourseTable({required this.data, required this.parserName});

  final CourseTableData data;
  final String parserName;
}

/// 已支持的解析器，按尝试顺序排列
const List<CourseTableParser> supportedParsers = [
  EamsCourseTableParser(),
  JwglxtCourseTableParser(),
];

/// 依次尝试所有解析器，返回第一个能解析出课程的。
///
/// 「手动导课」拿到的是用户当前所在页面，事先并不知道是哪套系统，只能挨个试。
/// 认出来但一门课都没有的情况会继续试下一个——比如停在了查询页而不是课表页。
ParsedCourseTable? parseWithAny(String html) {
  for (final parser in supportedParsers) {
    if (!parser.matches(html)) continue;
    final data = parser.parse(html);
    if (data.sessions.isEmpty) continue;
    return ParsedCourseTable(data: data, parserName: parser.name);
  }
  return null;
}

/// 哪些解析器认出了这段 HTML（用于诊断报告）
List<String> matchedParserNames(String html) => [
      for (final parser in supportedParsers)
        if (parser.matches(html)) parser.name,
    ];