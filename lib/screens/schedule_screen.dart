import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../import/course_cache.dart';
import '../import/school_config.dart';
import '../import/school_picker.dart';
import '../import/webview_import_screen.dart';
import '../models/course.dart';
import '../models/custom_entry.dart';
import '../models/grid_layout.dart';
import '../models/table_config.dart';
import '../parsers/course_table_parser.dart';
import 'custom_entry_editor.dart';
import 'session_detail_sheet.dart';
import 'table_settings_screen.dart';

/// 周视图课表。
///
/// 参考 WakeUp 的呈现方式：
/// - 左侧列出节次与具体钟点
/// - 顶部为周次与日期条，可左右滑动切换周
/// - 本周课程用实色，非本周课程淡显并标注「非本周」，
///   这样即使某一周没课，整张课表的形状依然完整可见
/// - 点课程色块可查看教师、教室、节数、时间、周次等详情
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const List<String> _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
  static const double _labelWidth = 46;

  final CourseCache _cache = const CourseCache();
  final PageController _weekController = PageController();

  CourseTableData? _data;
  TableConfig _config = const TableConfig();
  int _week = 1;
  bool _loading = true;

  /// 用户自建的课程 / 日程。与导入的课表分开存，重新导入不会被冲掉。
  List<CustomCourse> _customCourses = const [];
  List<CustomSchedule> _customSchedules = const [];

  /// 自建条目换算出的排课记录，渲染前与导入的课程合并
  List<CourseSession> _customSessions = const [];

  /// 自建条目的 courseId → 格子颜色
  Map<String, int> _customColors = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _weekController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final html = await _cache.load();
    final savedConfig = await _cache.loadConfig();
    final customCourses = await _cache.loadCustomCourses();
    final customSchedules = await _cache.loadCustomSchedules();

    // 缓存里的 HTML 可能是任意一套系统导进来的（本校 EAMS 或别校 jwglxt），
    // 所以让所有解析器都试一遍，而不是写死 EAMS
    var data = html == null ? null : parseWithAny(html)?.data;
    // 解析不出课时也给一张空课表，保证「重新导入」入口还在
    if (html != null && data == null) {
      data = const CourseTableData(sessions: [], courses: []);
    }
    // 没导入过课表、但用户自建了课程/日程时，同样要能进课表界面
    if (data == null && (customCourses.isNotEmpty || customSchedules.isNotEmpty)) {
      data = const CourseTableData(sessions: [], courses: []);
    }

    var config = savedConfig;
    if (data != null) {
      if (config == null) {
        // 首次导入：按实际数据生成初始配置（节数、周数、开学时间），并落盘。
        // 正常流程走到这里时配置已经由 _import 存好了，这里的兜底值只用于
        // 「有缓存 HTML 却没有配置」这种异常情况。
        config = TableConfig.initialFor(
          name: nbccSchool.tableName,
          maxPeriod: _maxPeriodOf(data),
          maxWeek: _maxWeekOf(data),
          startDate: fallbackSemesterStart,
        );
        await _cache.saveConfig(config);
      } else if (config.startDate == null) {
        // 早期版本保存的配置没有开学时间，补上默认值
        config = config.copyWith(startDate: fallbackSemesterStart);
        await _cache.saveConfig(config);
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
      if (config != null) _config = config;
      _customCourses = customCourses;
      _customSchedules = customSchedules;
      _rebuildCustomSessions();
      _week = data == null ? 1 : _initialWeek(_config, data);
    });
    if (data != null) _jumpToWeek(_week);
  }

  /// 自建条目 → 排课记录与颜色表。
  ///
  /// 换算出的记录和导入的课程混成一个列表再进网格，分列、「二选一」合并、
  /// 本周/非本周淡显这些布局逻辑就能直接复用。
  void _rebuildCustomSessions() {
    final sessions = <CourseSession>[];
    final colors = <String, int>{};
    for (final course in _customCourses) {
      sessions.addAll(customCourseSessions(course));
      colors['$customCourseIdPrefix${course.id}'] = course.color;
    }
    for (final schedule in _customSchedules) {
      sessions.addAll(customScheduleSessions(schedule, _config));
      colors['$customScheduleIdPrefix${schedule.id}'] = tagColorOf(schedule.tag);
    }
    _customSessions = sessions;
    _customColors = colors;
  }

  /// 导入的课程 + 用户自建的条目
  List<CourseSession> get _sessions => [...?_data?.sessions, ..._customSessions];

  int _initialWeek(TableConfig config, CourseTableData data) {
    final week = config.currentWeek(DateTime.now()) ?? _firstWeekOf(data);
    return week.clamp(1, _maxPage(config));
  }

  int _maxPage(TableConfig config) => config.totalWeeks < 1 ? 1 : config.totalWeeks;

  /// 数据中最早出现课程的周次，用作没设置开学时间时的兜底
  int _firstWeekOf(CourseTableData data) {
    final weeks = data.sessions.expand((s) => s.weeks).toList()..sort();
    return weeks.isEmpty ? 1 : weeks.first;
  }

  static int _maxPeriodOf(CourseTableData data) {
    if (data.sessions.isEmpty) return data.periodsPerDay ?? 12;
    return data.sessions.map((s) => s.endPeriod).reduce((a, b) => a > b ? a : b);
  }

  static int _maxWeekOf(CourseTableData data) {
    final weeks = data.sessions.expand((s) => s.weeks);
    if (weeks.isEmpty) return 20;
    return weeks.reduce((a, b) => a > b ? a : b);
  }

  /// 首帧后再跳页，此时 PageView 已挂载
  void _jumpToWeek(int week) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_weekController.hasClients) return;
      _weekController.jumpToPage(week - 1);
    });
  }

  /// 切换周：同时更新标题与页面位置
  void _goToWeek(int week) {
    final target = week.clamp(1, _maxPage(_config));
    if (target == _week) return;
    setState(() => _week = target);
    if (_weekController.hasClients) {
      _weekController.animateToPage(
        target - 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  /// 导入课表。
  ///
  /// 先让用户选学校：本校走全自动（识别页面 + 自己请求课表接口）；
  /// 其它学校走手动导课（用户自己登录并翻到课表页，再点「导课」）。
  /// 两条路最后都返回 [ImportResult]，这里统一收尾。
  Future<void> _import() async {
    final lastUrl = await _cache.loadManualEntryUrl();
    if (!mounted) return;

    final school = await showSchoolPicker(context, lastManualUrl: lastUrl);
    if (school == null || !mounted) return;

    // 手动模式填的地址存一份，下次预填，省得反复手打
    if (!school.autoImport) {
      await _cache.saveManualEntryUrl(school.loginUrl);
      if (!mounted) return;
    }

    final result = await Navigator.of(context).push<ImportResult>(
      MaterialPageRoute(builder: (_) => WebViewImportScreen(school: school)),
    );
    if (result == null || !mounted) return;

    final config = TableConfig.initialFor(
      name: result.school.tableName,
      maxPeriod: _maxPeriodOf(result.data),
      maxWeek: _maxWeekOf(result.data),
      startDate: result.school.startDate,
    );
    await _cache.saveConfig(config);
    final week = _initialWeek(config, result.data);
    if (!mounted) return;
    setState(() {
      _data = result.data;
      _config = config;
      _week = week;
    });
    _jumpToWeek(week);

    // 别校课表页基本都不含日期，拿不到开学时间就提示一次：
    // 缺它就没法自动定位当前周，顶部日期条也不会显示具体日期
    if (result.school.startDate == null) {
      await _promptStartDate();
    }
  }

  /// 导入完成后，如果开学时间还是空的，引导用户去设置
  Future<void> _promptStartDate() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.event_outlined),
        title: const Text('还需要设置开学时间'),
        content: const Text(
          '这所学校的课表页里没有日期，无法自动推断开学时间。\n'
          '设置之后，应用才能自动定位当前周，并在顶部显示每天的具体日期。\n\n'
          '不知道确切日期也没关系，可以在设置里按「今天是第几周」反推。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (!mounted || go != true) return;
    await _openSettings();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TableSettingsScreen(
          config: _config,
          courses: _data?.courses ?? const [],
          sessions: _data?.sessions ?? const [],
        ),
      ),
    );
    // 设置页里的改动即时落盘，返回后重新读取
    final saved = await _cache.loadConfig();
    if (saved == null || !mounted) return;
    setState(() {
      _config = saved;
      _week = _week.clamp(1, _maxPage(saved));
      // 节次钟点、周数变了，日程换算出的节次也跟着变
      _rebuildCustomSessions();
    });
  }

  // ------------------------------------------------------------ 自建课程/日程

  Future<void> _addCustom() async {
    final result = await showCustomEntryEditor(context, config: _config);
    if (result == null || !mounted) return;
    await _applyCustomChange(() {
      if (result.course != null) {
        _customCourses = [..._customCourses, result.course!];
      }
      if (result.schedule != null) {
        _customSchedules = [..._customSchedules, result.schedule!];
      }
    });
  }

  Future<void> _editCustomCourse(CustomCourse course) async {
    final result = await showCustomEntryEditor(
      context,
      config: _config,
      course: course,
    );
    if (result == null || !mounted) return;
    await _applyCustomChange(() {
      // 用户可以顺手把 Tab 切到「日程」，所以两种结果都要接
      _customCourses = [
        for (final item in _customCourses)
          if (item.id != course.id) item,
        if (result.course != null) result.course!,
      ];
      if (result.schedule != null) {
        _customSchedules = [..._customSchedules, result.schedule!];
      }
    });
  }

  Future<void> _editCustomSchedule(CustomSchedule schedule) async {
    final result = await showCustomEntryEditor(
      context,
      config: _config,
      schedule: schedule,
    );
    if (result == null || !mounted) return;
    await _applyCustomChange(() {
      _customSchedules = [
        for (final item in _customSchedules)
          if (item.id != schedule.id) item,
        if (result.schedule != null) result.schedule!,
      ];
      if (result.course != null) {
        _customCourses = [..._customCourses, result.course!];
      }
    });
  }

  Future<void> _deleteCustomCourse(CustomCourse course) async {
    final ok = await _confirmDelete(course.name);
    if (ok != true || !mounted) return;
    await _applyCustomChange(() {
      _customCourses = [
        for (final item in _customCourses)
          if (item.id != course.id) item,
      ];
    });
  }

  Future<void> _deleteCustomSchedule(CustomSchedule schedule) async {
    final ok = await _confirmDelete(schedule.title);
    if (ok != true || !mounted) return;
    await _applyCustomChange(() {
      _customSchedules = [
        for (final item in _customSchedules)
          if (item.id != schedule.id) item,
      ];
    });
  }

  Future<bool?> _confirmDelete(String name) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 自建条目改动后的统一收尾：刷新界面、落盘、必要时补一张空课表
  Future<void> _applyCustomChange(void Function() change) async {
    setState(() {
      change();
      _rebuildCustomSessions();
    });
    await _cache.saveCustomCourses(_customCourses);
    await _cache.saveCustomSchedules(_customSchedules);
    await _ensureDataForCustom();
  }

  /// 从没导入过课表时，自建条目也需要一张（空的）课表来承载
  Future<void> _ensureDataForCustom() async {
    if (_data != null) return;
    var config = _config;
    if (config.periodTimes.isEmpty) {
      config = TableConfig.initialFor(
        name: nbccSchool.tableName,
        maxPeriod: config.periodsPerDay,
        maxWeek: config.totalWeeks,
        startDate: config.startDate ?? fallbackSemesterStart,
      );
      await _cache.saveConfig(config);
    }
    if (!mounted) return;
    setState(() {
      _data = const CourseTableData(sessions: [], courses: []);
      _config = config;
      _rebuildCustomSessions();
    });
  }

  /// 点格子：导入的课程只看详情，自建条目还能顺手编辑/删除
  void _openSession(CourseSession session) {
    final course = _customCourseOf(session.courseId);
    if (course != null) {
      final slot = _slotOf(course, session);
      showSessionDetail(
        context,
        session: session,
        course: null,
        config: _config,
        creditsText: _creditsText(course.credits),
        timeRangeText: slot?.customTimeRange,
        note: slot?.note,
        footnote: '这是你自己添加的课程，可随时编辑或删除。',
        onEdit: () {
          Navigator.of(context).pop();
          _editCustomCourse(course);
        },
        onDelete: () {
          Navigator.of(context).pop();
          _deleteCustomCourse(course);
        },
      );
      return;
    }

    final schedule = _customScheduleOf(session.courseId);
    if (schedule != null) {
      _showScheduleDetail(schedule);
      return;
    }

    showSessionDetail(
      context,
      session: session,
      course: _courseOf(session),
      config: _config,
    );
  }

  void _showScheduleDetail(CustomSchedule schedule) {
    showCustomScheduleDetail(
      context,
      schedule: schedule,
      onEdit: () {
        Navigator.of(context).pop();
        _editCustomSchedule(schedule);
      },
      onDelete: () {
        Navigator.of(context).pop();
        _deleteCustomSchedule(schedule);
      },
    );
  }

  CustomCourse? _customCourseOf(String courseId) {
    if (!courseId.startsWith(customCourseIdPrefix)) return null;
    final id = courseId.substring(customCourseIdPrefix.length);
    for (final course in _customCourses) {
      if (course.id == id) return course;
    }
    return null;
  }

  CustomSchedule? _customScheduleOf(String courseId) {
    if (!courseId.startsWith(customScheduleIdPrefix)) return null;
    final id = courseId.substring(customScheduleIdPrefix.length);
    for (final schedule in _customSchedules) {
      if (schedule.id == id) return schedule;
    }
    return null;
  }

  /// 找出这条排课记录对应的时段，用来展示备注与自定义钟点
  static CustomSlot? _slotOf(CustomCourse course, CourseSession session) {
    for (final slot in course.slots) {
      if (slot.dayOfWeek == session.dayOfWeek &&
          slot.startPeriod == session.startPeriod &&
          slot.endPeriod == session.endPeriod) {
        return slot;
      }
    }
    return null;
  }

  static String _creditsText(double? credits) {
    if (credits == null) return '—';
    return credits % 1 == 0 ? credits.toInt().toString() : credits.toString();
  }

  /// 当天要展示的全天日程。它们没有钟点、落不到节次上，改在日期下方画色条。
  List<CustomSchedule> _allDayOn(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return [
      for (final schedule in _customSchedules)
        if (schedule.allDay && _occursOn(schedule, day)) schedule,
    ];
  }

  static bool _occursOn(CustomSchedule schedule, DateTime day) {
    final start = DateTime(
      schedule.start.year,
      schedule.start.month,
      schedule.start.day,
    );
    if (day.isBefore(start)) return false;
    return switch (schedule.repeat) {
      ScheduleRepeat.never => day.isAtSameMomentAs(start),
      ScheduleRepeat.daily => true,
      ScheduleRepeat.weekly => day.difference(start).inDays % 7 == 0,
    };
  }

  /// 需要显示的星期（1=周一 … 7=周日），受「显示周六/周日」控制
  List<int> get _visibleDays {
    final days = <int>[];
    for (var i = 0; i < 7; i++) {
      final weekday = ((_config.weekStartDay - 1 + i) % 7) + 1;
      if (weekday == DateTime.saturday && !_config.showSaturday) continue;
      if (weekday == DateTime.sunday && !_config.showSunday) continue;
      days.add(weekday);
    }
    return days;
  }

  int? get _currentWeek => _config.currentWeek(DateTime.now());

  /// 左上角显示的今日日期与星期
  String get _todayLabel {
    final now = DateTime.now();
    return '${now.year}年${now.month}月${now.day}日 '
        '周${_weekdayNames[now.weekday - 1]}';
  }

  Course? _courseOf(CourseSession session) {
    for (final course in _data?.courses ?? const <Course>[]) {
      if (course.courseId == session.courseId) return course;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Android 10+ 默认会给系统导航栏加一层半透明底衬，
      // 在浅色界面下显脏，这里关掉
      value: const SystemUiOverlayStyle(
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: data == null
              ? const Text('课表')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _config.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _todayLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              tooltip: '添加课程或日程',
              onPressed: _addCustom,
              icon: const Icon(Icons.add),
            ),
            if (data != null)
              IconButton(
                tooltip: '课表设置',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            if (data != null)
              IconButton(
                tooltip: '重新导入',
                onPressed: _import,
                icon: const Icon(Icons.sync),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : data == null
                      ? _buildEmpty()
                      : _buildSchedule(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.calendar_month_outlined, size: 64),
          const SizedBox(height: 16),
          const Text('还没有课表数据'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.login),
            label: const Text('登录教务系统导入'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addCustom,
            icon: const Icon(Icons.add),
            label: const Text('手动添加课程或日程'),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedule() {
    return Column(
      children: [
        _buildWeekBar(),
        Expanded(
          child: PageView.builder(
            controller: _weekController,
            // 默认分页弹簧刚度只有 100，松手后吸附的尾段拖得很长
            physics: const _SnappySettlePhysics(),
            itemCount: _maxPage(_config),
            onPageChanged: (index) => setState(() => _week = index + 1),
            itemBuilder: (context, index) => _buildWeekPage(index + 1),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekBar() {
    final current = _currentWeek;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _week > 1 ? () => _goToWeek(_week - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('第 $_week 周', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            onPressed: _week < _maxPage(_config)
                ? () => _goToWeek(_week + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          if (current != null && current != _week)
            TextButton(
              onPressed: () => _goToWeek(current),
              child: const Text('回到本周'),
            ),
        ],
      ),
    );
  }

  Widget _buildWeekPage(int week) {
    final periodsPerDay = _config.periodsPerDay;
    final days = _visibleDays;
    // 学期前几周常常还没开课，此时整屏都是「非本周」，
    // 明确提示一下，避免被误读成课表数据缺失
    final hasClassThisWeek = _sessions.any((s) => s.hasClassInWeek(week));

    return Column(
      children: [
        if (!hasClassThisWeek)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '本周无课，可左右滑动查看其他周',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        _buildDayHeader(days, week),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: periodsPerDay * _config.cellHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPeriodLabels(periodsPerDay),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final cellWidth = constraints.maxWidth / days.length;
                        return Stack(
                          children: [
                            _buildGridLines(periodsPerDay, days.length),
                            for (var i = 0; i < days.length; i++)
                              ..._buildDaySlots(
                                week: week,
                                weekday: days[i],
                                dayIndex: i,
                                cellWidth: cellWidth,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayHeader(List<int> days, int week) {
    final firstDay = _config.firstDayOfWeek(week);
    final today = DateTime.now();

    return Row(
      children: [
        _buildMonthCell(firstDay),
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: _buildDayHeaderCell(
              weekday: days[i],
              date: firstDay?.add(Duration(days: i)),
              isToday: firstDay != null &&
                  _isSameDay(firstDay.add(Duration(days: i)), today),
            ),
          ),
      ],
    );
  }

  /// 日期条左端的格子，填上这一周所属的月份。
  ///
  /// 跨月的周（如 9/28–10/4）按该周第一天所在的月份显示。
  Widget _buildMonthCell(DateTime? firstDay) {
    return Container(
      width: _labelWidth,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.black12, width: 0.5),
        ),
      ),
      child: firstDay == null
          ? null
          : Text(
              '${firstDay.month}月',
              style: Theme.of(context).textTheme.bodySmall,
            ),
    );
  }

  Widget _buildDayHeaderCell({
    required int weekday,
    required DateTime? date,
    required bool isToday,
  }) {
    final allDay = date == null ? const <CustomSchedule>[] : _allDayOn(date);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.black12, width: 0.5),
          bottom: BorderSide(color: Colors.black12, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _weekdayNames[weekday - 1],
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (date != null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: isToday
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 12,
                  color: isToday
                      ? Theme.of(context).colorScheme.onPrimary
                      : null,
                ),
              ),
            ),
          // 全天日程没有钟点，落不到节次格子里，改在日期下方画一条色条
          for (final schedule in allDay)
            GestureDetector(
              onTap: () => _showScheduleDetail(schedule),
              // 色条本身很细，用 opaque + 内边距撑出可点的范围
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Color(tagColorOf(schedule.tag)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 左侧节次列：节次 + 起止钟点
  Widget _buildPeriodLabels(int periodsPerDay) {
    return SizedBox(
      width: _labelWidth,
      child: Column(
        children: [
          for (var period = 1; period <= periodsPerDay; period++)
            SizedBox(
              height: _config.cellHeight,
              child: _buildPeriodLabel(period),
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodLabel(int period) {
    final time = _config.timeOf(period);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$period',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (time != null) ...[
            const SizedBox(height: 2),
            Text(time.start, style: const TextStyle(fontSize: 9, height: 1.1)),
            Text(time.end, style: const TextStyle(fontSize: 9, height: 1.1)),
          ],
        ],
      ),
    );
  }

  Widget _buildGridLines(int periodsPerDay, int dayCount) {
    const border = Border(
      left: BorderSide(color: Colors.black12, width: 0.5),
      top: BorderSide(color: Colors.black12, width: 0.5),
    );
    return Column(
      children: [
        for (var period = 0; period < periodsPerDay; period++)
          Expanded(
            child: Row(
              children: [
                for (var day = 0; day < dayCount; day++)
                  const Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: border),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 某一天的课程格子。本周课程实色，非本周课程淡显。
  ///
  /// 本周与非本周课程一起参与分列：若两者占用同一节次，
  /// 分开排布才不会出现后画的整宽格子盖住先画的问题。
  List<Widget> _buildDaySlots({
    required int week,
    required int weekday,
    required int dayIndex,
    required double cellWidth,
  }) {
    final seen = <String>{};
    final sessions = <CourseSession>[];
    for (final session in _sessions) {
      if (session.dayOfWeek != weekday) continue;
      final isThisWeek = session.hasClassInWeek(week);
      if (!isThisWeek && !_config.showOtherWeeks) continue;
      final key = '${session.name}|${session.startPeriod}'
          '|${session.endPeriod}|${session.weeks.join(',')}';
      if (!seen.add(key)) continue;
      sessions.add(session);
    }

    // 二选一的课程（如军事理论与形势与政策1）只显示本周要上的那一门，
    // 避免并排分列后各自只剩半宽、文字被挤得看不清
    return [
      for (final slot in layoutDay(resolveAlternatives(sessions, week)))
        _positioned(
          slot,
          dayIndex,
          cellWidth,
          isThisWeek: slot.session.hasClassInWeek(week),
        ),
    ];
  }

  Widget _positioned(
    GridSlot slot,
    int dayIndex,
    double cellWidth, {
    required bool isThisWeek,
  }) {
    final session = slot.session;
    final width = cellWidth / slot.columns;
    return Positioned(
      left: dayIndex * cellWidth + slot.column * width,
      top: (session.startPeriod - 1) * _config.cellHeight,
      width: width,
      height: session.periodCount * _config.cellHeight,
      child: _buildSessionCard(session, isThisWeek: isThisWeek),
    );
  }

  Widget _buildSessionCard(CourseSession session, {required bool isThisWeek}) {
    // 非本周课程进一步降低饱和度并提亮，与本周课程形成明显对比
    final color = _sessionColor(session, faded: !isThisWeek);

    return GestureDetector(
      onTap: () => _openSession(session),
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(_config.cellRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.name,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: isThisWeek
                    ? const Color(0xFF111827)
                    : const Color(0xFF9AA2AE),
              ),
            ),
            if (session.room.isNotEmpty)
              Text(
                '@${session.room}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  height: 1.1,
                  color: isThisWeek
                      ? const Color(0xFF374151)
                      : const Color(0xFFAFB6C1),
                ),
              ),
            const Spacer(),
            if (!isThisWeek)
              const Text(
                '非本周',
                style: TextStyle(fontSize: 8, color: Color(0xFFAFB6C1)),
              ),
          ],
        ),
      ),
    );
  }

  /// 格子颜色：自建课程用自选色，日程用标签色，导入课程按课名哈希生成。
  ///
  /// 自建色同样要在「非本周」时降饱和、提明度，才能和导入课程保持同一套
  /// 视觉规则——靠饱和度与明暗区分是否本周要上。
  Color _sessionColor(CourseSession session, {required bool faded}) {
    final custom = _customColors[session.courseId];
    if (custom == null) return _colorFor(session.name, faded: faded);
    final color = Color(custom);
    if (!faded) return color;
    return HSLColor.fromColor(color)
        .withSaturation(0.10)
        .withLightness(0.96)
        .toColor();
  }

  /// 按课程名生成稳定的浅色背景，同一门课每次颜色一致。
  ///
  /// 本周课程用柔和的浅色块（中低饱和 + 高明度），长时间看不刺眼；
  /// 非本周课程再降饱和、提明度，靠饱和度与明暗区分是否本周要上。
  Color _colorFor(String name, {bool faded = false}) {
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return faded
        ? HSLColor.fromAHSL(1, hue, 0.10, 0.96).toColor()
        : HSLColor.fromAHSL(1, hue, 0.45, 0.89).toColor();
  }
}

/// 分页吸附用的弹簧，比 Flutter 默认值更硬。
///
/// `PageView` 会把这里传入的 physics 作为父级交给 `PageScrollPhysics`，
/// 而 `PageScrollPhysics` 吸附时读取 `spring`（该 getter 会向上取父级），
/// 因此只替换弹簧就能调整松手后的收尾手感，不必重写分页目标计算。
///
/// 刚度是唯一的调节旋钮，吸附时长大致与 `1 / √stiffness` 成正比：
/// - `100`（Flutter 默认）—— 收尾拖沓
/// - `500` —— 偏急
/// - `300`（当前）—— 干脆但不突兀
///
/// 质量与阻尼比保持默认不变（`ratio: 1.0` 为临界阻尼，不会回弹），
/// 吸附终点与分页行为完全不受影响。
class _SnappySettlePhysics extends ScrollPhysics {
  const _SnappySettlePhysics({super.parent});

  /// `SpringDescription.withDampingRatio` 不是 const 构造，
  /// 缓存成静态字段避免每次读取都新建
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 0.5,
    stiffness: 300,
    ratio: 1.0,
  );

  @override
  _SnappySettlePhysics applyTo(ScrollPhysics? ancestor) =>
      _SnappySettlePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => _spring;
}
