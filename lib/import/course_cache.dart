import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/custom_entry.dart';
import '../models/table_config.dart';

/// 课表本地存储：原始课表 HTML 与课表配置。
///
/// 缓存的是**原始 HTML**而不是解析结果：解析器是唯一的数据来源，
/// 以后修正解析逻辑后重新解析缓存即可，不会出现旧数据格式不兼容的问题。
class CourseCache {
  const CourseCache();

  static const String _fileName = 'course_table.html';
  static const String _configFileName = 'table_config.json';
  static const String _manualUrlFileName = 'manual_entry_url.txt';
  static const String _customCourseFileName = 'custom_courses.json';
  static const String _customScheduleFileName = 'custom_schedules.json';

  Future<Directory> _documentsDir() => getApplicationDocumentsDirectory();

  Future<void> save(String html) async {
    final dir = await _documentsDir();
    await File('${dir.path}/$_fileName').writeAsString(html);
  }

  Future<String?> load() async {
    final dir = await _documentsDir();
    final file = File('${dir.path}/$_fileName');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> clear() async {
    final dir = await _documentsDir();
    final file = File('${dir.path}/$_fileName');
    if (await file.exists()) await file.delete();
  }

  /// 保存课表配置
  Future<void> saveConfig(TableConfig config) async {
    final dir = await _documentsDir();
    await File('${dir.path}/$_configFileName')
        .writeAsString(jsonEncode(config.toJson()));
  }

  /// 读取课表配置；尚未配置过时返回 null
  Future<TableConfig?> loadConfig() async {
    final dir = await _documentsDir();
    final file = File('${dir.path}/$_configFileName');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return TableConfig.fromJson(decoded);
      }
    } catch (_) {
      // 配置损坏时按未配置处理，重新生成即可
    }
    return null;
  }

  /// 记住手动导课时填过的教务网址。
  ///
  /// 「其它学校」的用户每次重新导入都要手打地址太烦，存一份下次预填。
  Future<void> saveManualEntryUrl(String url) async {
    final dir = await _documentsDir();
    await File('${dir.path}/$_manualUrlFileName').writeAsString(url);
  }

  Future<String?> loadManualEntryUrl() async {
    final dir = await _documentsDir();
    final file = File('${dir.path}/$_manualUrlFileName');
    if (!await file.exists()) return null;
    final text = (await file.readAsString()).trim();
    return text.isEmpty ? null : text;
  }

  /// 自建课程 / 日程。
  ///
  /// 单独存文件而不是混进缓存的课表 HTML：重新导入会整体覆盖 HTML，
  /// 而自建条目必须留着。
  Future<List<CustomCourse>> loadCustomCourses() =>
      _loadEntries(_customCourseFileName, CustomCourse.fromJson);

  Future<void> saveCustomCourses(List<CustomCourse> courses) =>
      _writeEntries(_customCourseFileName, courses.map((c) => c.toJson()));

  Future<List<CustomSchedule>> loadCustomSchedules() =>
      _loadEntries(_customScheduleFileName, CustomSchedule.fromJson);

  Future<void> saveCustomSchedules(List<CustomSchedule> schedules) =>
      _writeEntries(_customScheduleFileName, schedules.map((s) => s.toJson()));

  Future<List<T>> _loadEntries<T>(
    String fileName,
    T? Function(Map<String, dynamic>) parse,
  ) async {
    final dir = await _documentsDir();
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final result = <T>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = parse(item);
        if (parsed != null) result.add(parsed);
      }
      return result;
    } catch (_) {
      // 文件损坏时按「没有自建条目」处理，不至于连课表都打不开
      return [];
    }
  }

  Future<void> _writeEntries(
    String fileName,
    Iterable<Map<String, dynamic>> entries,
  ) async {
    final dir = await _documentsDir();
    await File('${dir.path}/$fileName')
        .writeAsString(jsonEncode(entries.toList()));
  }

  /// 把一段 HTML 另存一份，用于排查问题，返回文件路径。
  ///
  /// [tag] 用于区分来源：`page` 是用户点导出时的当前页，
  /// `response` 是课表接口返回但没解析出课表的内容。两者时间戳对得上，
  /// 便于定位到底是页面不对还是接口没返回课表。
  ///
  /// 写到**外部存储**的应用目录（`/sdcard/Android/data/<包名>/files/debug/`），
  /// 而不是应用私有目录：release 包不可调试，私有目录连 adb 都读不到，
  /// 而外部目录既能用 adb pull 取回，也能用手机文件管理器直接查看。
  Future<String> saveDebugPage(String html, {String tag = 'page'}) async {
    final debugDir = await _debugDir();

    // 带时间戳，避免多次导出互相覆盖
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp(r'[:\-]'), '');
    final file = File('${debugDir.path}/${tag}_$stamp.html');
    await file.writeAsString(html);
    return file.path;
  }

  /// 列出导出的调试页面，最新的在前。
  ///
  /// 文件名带时间戳，所以按名字倒序就是按时间倒序，不用逐个取文件属性。
  Future<List<File>> listDebugPages() async {
    final debugDir = await _debugDir();
    if (!await debugDir.exists()) return const [];

    final files = <File>[];
    await for (final entity in debugDir.list()) {
      if (entity is File && entity.path.endsWith('.html')) files.add(entity);
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<Directory> _debugDir() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/debug');
    await dir.create(recursive: true);
    return dir;
  }
}