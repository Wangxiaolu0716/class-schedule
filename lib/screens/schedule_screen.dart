import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../import/ai_import_screen.dart';
import '../import/course_cache.dart';
import '../import/school_config.dart';
import '../import/school_picker.dart';
import '../import/webview_import_screen.dart';
import '../models/course.dart';
import '../models/custom_entry.dart';
import '../models/grid_layout.dart';
import '../models/school_periods.dart';
import '../models/table_config.dart';
import '../parsers/course_table_parser.dart';
import '../import/silent_refresh.dart';
import '../theme/appearance_background.dart';
import '../theme/table_style.dart';
import 'appearance_screen.dart';
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

class _ScheduleScreenState extends State<ScheduleScreen>
    with WidgetsBindingObserver {
  static const List<String> _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
  static const double _labelWidth = 46;

  final CourseCache _cache = const CourseCache();
  final PageController _weekController = PageController();

  CourseTableData? _data;
  TableConfig _config = const TableConfig();
  int _week = 1;
  bool _loading = true;

  /// 彩蛋「仅显示单日程」下选中的星期（1=周一 … 7=周日）。
  ///
  /// 为 null 表示还没点过日期条，用今天；今天若被「显示周六/周日」藏了，
  /// 就退回第一天。
  int? _singleDay;
  bool get _singleDayMode => _config.easterEggUnlocked && _config.singleDayOnly;

  /// 长按日期列「复制」下来的星期（1=周一 … 7=周日）。
  ///
  /// 为 null 表示剪贴板是空的，长按菜单里也就不会出现「粘贴」。
  int? _copiedWeekday;

  /// 在空白格上点出来的待添加范围（所在周 + 星期 + 起止节次，含端点）。
  ///
  /// 为 null 表示当前没有正在划定的范围，课表上也就不会出现那个加号。
  int? _draftWeek;
  int? _draftDay;
  int _draftStart = 1;
  int _draftEnd = 1;

  /// 拖右侧手柄时固定不动的那一端：手往下拖延长下界，往上拖延长上界
  int _dragPinned = 1;
  double _dragDelta = 0;

  /// 用户自建的课程 / 日程。与导入的课表分开存，重新导入不会被冲掉。
  List<CustomCourse> _customCourses = const [];
  List<CustomSchedule> _customSchedules = const [];

  /// 自建条目换算出的排课记录，渲染前与导入的课程合并
  List<CourseSession> _customSessions = const [];

  /// 自建条目的 courseId → 格子颜色
  Map<String, int> _customColors = const {};

  /// 正在静默刷新教务；为 true 时标题下挂一条细进度条
  bool _silentRefreshing = false;

  /// 这一次刷新是用户手动点的（失败要说话，成功要提示）
  bool _manualRefresh = false;

  /// 上次自动刷新的时刻。回到前台会触发一次，短时间内反复切来切去
  /// 不该把教务系统敲个不停
  DateTime? _lastAutoRefreshAt;

  /// 正在刷新的那所学校；非 null 时页面上挂着隐形 WebView
  SchoolConfig? _autoRefreshSchool;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时静默刷一次课表（有节流，见 _maybeAutoRefresh）
    if (state == AppLifecycleState.resumed) _maybeAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (data == null &&
        (customCourses.isNotEmpty || customSchedules.isNotEmpty)) {
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
    _maybeAutoRefresh();
  }

  /// 静默刷一次教务。
  ///
  /// 只有上次从「能自动导课」的学校导进来才刷得动：手动导课的学校没有
  /// 可请求的接口路径。失败一律静默 —— 课表还是上次那份，不会变空。
  /// 自动触发有 15 分钟节流：来回切前后台不该把教务系统敲个不停。
  Future<void> _maybeAutoRefresh({bool manual = false}) async {
    if (_silentRefreshing || _autoRefreshSchool != null) return;
    if (_data == null) return;
    if (!manual) {
      if (!_config.autoRefresh) return;
      final last = _lastAutoRefreshAt;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 15)) {
        return;
      }
      _lastAutoRefreshAt = DateTime.now();
    }

    final school = await _cache.loadLastSchool();
    if (!mounted) return;
    if (school == null || !school.autoImport) {
      if (manual) _toast('这所学校是手动导课的，没有可自动刷新的接口');
      return;
    }
    setState(() {
      _autoRefreshSchool = school;
      _manualRefresh = manual;
      _silentRefreshing = true;
    });
  }

  /// 刷新结果：拿到课表就地换掉，拿不到就什么都不改
  Future<void> _onRefreshDone(CourseTableData? data) async {
    if (!mounted) return;
    final manual = _manualRefresh;
    setState(() {
      _silentRefreshing = false;
      _autoRefreshSchool = null;
      _manualRefresh = false;
    });
    if (data == null) {
      if (manual) _toast('刷新没成功，登录状态可能过期了，重新导入一次即可');
      return;
    }

    var config = _config;
    // 只放大不缩小：教务那边节数/周数变多要跟上，变少则保留用户已调好的值
    final maxPeriod = _maxPeriodOf(data);
    if (maxPeriod > config.periodsPerDay) {
      config = config.copyWith(periodsPerDay: maxPeriod);
    }
    final maxWeek = _maxWeekOf(data);
    if (maxWeek > config.totalWeeks) {
      config = config.copyWith(totalWeeks: maxWeek);
    }
    await _cache.saveConfig(config);
    if (!mounted) return;
    setState(() {
      _data = data;
      _config = config;
      _rebuildCustomSessions();
      _week = _week.clamp(1, _maxPage(config));
    });
    if (manual) _toast('课表已更新');
  }

  /// 点「第 N 周」直接跳到任意一周，不必一页页滑过去
  Future<void> _pickWeek() async {
    final maxWeek = _maxPage(_config);
    final current = _currentWeek;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('跳到第几周', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var week = 1; week <= maxWeek; week++)
                    ChoiceChip(
                      label: Text('$week'),
                      selected: week == _week,
                      // 当前周单独点一下图标，滑远了一眼能找到回去
                      avatar: week == current
                          ? const Icon(Icons.today, size: 14)
                          : null,
                      onSelected: (_) => Navigator.pop(context, week),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) _goToWeek(picked);
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
      colors['$customScheduleIdPrefix${schedule.id}'] = tagColorOf(
        schedule.tag,
      );
    }
    _customSessions = sessions;
    _customColors = colors;
  }

  /// 导入的课程 + 用户自建的条目
  List<CourseSession> get _sessions => [
    ...?_data?.sessions,
    ..._customSessions,
  ];

  int _initialWeek(TableConfig config, CourseTableData data) {
    final week = config.currentWeek(DateTime.now()) ?? _firstWeekOf(data);
    return week.clamp(1, _maxPage(config));
  }

  int _maxPage(TableConfig config) =>
      config.totalWeeks < 1 ? 1 : config.totalWeeks;

  /// 数据中最早出现课程的周次，用作没设置开学时间时的兜底
  int _firstWeekOf(CourseTableData data) {
    final weeks = data.sessions.expand((s) => s.weeks).toList()..sort();
    return weeks.isEmpty ? 1 : weeks.first;
  }

  static int _maxPeriodOf(CourseTableData data) {
    if (data.sessions.isEmpty) return data.periodsPerDay ?? 12;
    return data.sessions
        .map((s) => s.endPeriod)
        .reduce((a, b) => a > b ? a : b);
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
  /// 其它学校走手动导课（用户自己登录并翻到课表页，再点「导课」）；
  /// 内置解析器认不出来的学校走 AI 识别（让 AI 看截图，把 JSON 粘回来）。
  /// 三条路最后都得到 [ImportResult]，收尾逻辑共用 [_applyImport]。
  Future<void> _import() async {
    final lastUrl = await _cache.loadManualEntryUrl();
    if (!mounted) return;

    final school = await showSchoolPicker(context, lastManualUrl: lastUrl);
    if (school == null || !mounted) return;

    // AI 识别这条路不在这里解析：课表由用户在界面里粘回来的 AI 结果决定，
    // 要打开教务系统也是进去之后自己开
    if (school.isAiImport) {
      final data = await Navigator.of(context).push<CourseTableData>(
        MaterialPageRoute(
          builder: (_) => AiImportScreen(lastManualUrl: lastUrl),
        ),
      );
      if (data == null || !mounted) return;
      await _applyImport(ImportResult(data: data, school: school));
      return;
    }

    // 手动模式填的地址存一份，下次预填，省得反复手打
    if (!school.autoImport) {
      await _cache.saveManualEntryUrl(school.loginUrl);
      if (!mounted) return;
    }

    final result = await Navigator.of(context).push<ImportResult>(
      MaterialPageRoute(builder: (_) => WebViewImportScreen(school: school)),
    );
    if (result == null || !mounted) return;
    await _applyImport(result);
  }

  /// 导入结果统一收尾：落盘配置、切到当前周、必要时引导设置开学时间。
  Future<void> _applyImport(ImportResult result) async {
    if (!mounted) return;

    final previous = _config;
    final fresh = TableConfig.initialFor(
      name: result.school.tableName,
      maxPeriod: _maxPeriodOf(result.data),
      maxWeek: _maxWeekOf(result.data),
      startDate: result.school.startDate,
    );
    // 用户手动调过的节次钟点、开学时间等不能被一次重新导入冲掉
    var config = TableConfig.mergeImport(fresh: fresh, previous: previous);

    // 首次导入时，若这所学校有官方作息表（如湖州职业技术学院的夏令/冬令），
    // 让用户直接套用，省得一节节手敲。重新导入时不动用户已经调好的时间。
    if (previous.periodTimes.isEmpty) {
      final preset = await _pickPeriodPreset(result.school.name);
      if (!mounted) return;
      if (preset != null) config = config.copyWith(periodTimes: preset.times);
    }

    await _cache.saveConfig(config);
    // 记下这所学校：下次打开课表时静默刷新要用它的入口与接口路径
    await _cache.saveLastSchool(result.school);
    if (!mounted) return;
    final week = _initialWeek(config, result.data);
    setState(() {
      _data = result.data;
      _config = config;
      _week = week;
    });
    _jumpToWeek(week);

    // 换了课表，课前提醒整批重排

    // 别校课表页基本都不含日期，拿不到开学时间就提示一次：
    // 缺它就没法自动定位当前周，顶部日期条也不会显示具体日期
    if (result.school.startDate == null) {
      await _promptStartDate();
    }
  }

  /// 让用户挑一套学校官方作息；这所学校没有内置作息表时直接返回 null
  Future<PeriodPreset?> _pickPeriodPreset(String schoolName) async {
    final presets = periodPresetsFor(schoolName);
    if (presets.isEmpty) return null;
    return showDialog<PeriodPreset>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('$schoolName 的作息时间'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: Text(
              '选一套作息时间套用到课表上，之后也能在课表设置里改。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          for (final preset in presets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, preset),
              child: Text(preset.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('先不套用'),
          ),
        ],
      ),
    );
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
      // 节数可能被改小，之前划定的范围得作废
      _draftWeek = null;
      _draftDay = null;
    });
    // 开学时间/周数/钟点改了，课前提醒要跟着重算
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

  /// 实际画出来的列：正常是一整周，彩蛋模式下只有选中的那一天
  List<int> get _gridDays {
    final visible = _visibleDays;
    if (!_singleDayMode) return visible;
    final today = DateTime.now().weekday;
    final picked =
        _singleDay ?? (visible.contains(today) ? today : visible.first);
    // 选中的那天可能被「显示周六/周日」藏起来了，遇到就退回第一天
    return [visible.contains(picked) ? picked : visible.first];
  }

  /// 单日程模式下，日期条上高亮的就是正在展示的那天
  int? get _selectedDay => _singleDayMode ? _gridDays.first : null;

  int? get _currentWeek => _config.currentWeek(DateTime.now());

  /// 单日程模式下选中那天的日期；算不出来时为 null
  DateTime? get _singleDayDate {
    if (!_singleDayMode) return null;
    final firstDay = _config.firstDayOfWeek(_week);
    if (firstDay == null) return null;
    final index = _visibleDays.indexOf(_gridDays.first);
    if (index < 0) return null;
    return firstDay.add(Duration(days: index));
  }

  /// 左上角显示的日期与星期。
  ///
  /// 单日程模式下跟着选中的那天走——一直标着「今天」而屏幕上不是今天，
  /// 很容易看错。
  String get _todayLabel {
    final day = _singleDayDate;
    if (day != null) {
      return '${day.year}年${day.month}月${day.day}日 '
          '周${_weekdayNames[day.weekday - 1]}';
    }
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
    // 外观是全局的：在设置页挑了新预设，回来这里立刻跟着变
    return ValueListenableBuilder<TableAppearance>(
      valueListenable: appAppearance,
      builder: (context, appearance, _) => _buildScaffold(context, appearance),
    );
  }

  Widget _buildScaffold(BuildContext context, TableAppearance appearance) {
    final data = _data;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Android 10+ 默认会给系统导航栏加一层半透明底衬，
      // 在浅色界面下显脏，这里关掉
      value: SystemUiOverlayStyle(
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        // 深色下要换成浅色图标，否则黑底黑图标看不见
        systemNavigationBarIconBrightness: _isDark
            ? Brightness.light
            : Brightness.dark,
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
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                if (value == 'refresh') _maybeAutoRefresh(manual: true);
                if (value == 'import') _import();
                if (value == 'appearance') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppearanceScreen()),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.refresh),
                    title: Text('从教务刷新'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.sync),
                    title: Text('重新导入 / 换学校'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'appearance',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.palette_outlined),
                    title: Text('样式与背景'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            // 预设底色与自定义背景图铺在最底下，上面照旧是原来的内容
            Positioned.fill(
              child: AppearanceBackground(
                appearance: appearance,
                dark: _isDark,
              ),
            ),
            Column(
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
            // 刷新时只在顶端露一条 2px 的进度条，不打断看课表
            if (_silentRefreshing)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            // 静默刷新用的隐形 WebView：必须真挂在树上才拿得到渲染后的页面
            if (_autoRefreshSchool != null)
              Positioned(
                right: 0,
                top: 0,
                child: SilentCourseRefresher(
                  school: _autoRefreshSchool!,
                  onDone: _onRefreshDone,
                ),
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
            onPageChanged: (index) => setState(() {
              _week = index + 1;
              // 换周了，上一周点出来的待添加范围不再有意义
              _draftWeek = null;
              _draftDay = null;
            }),
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
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pickWeek,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '第 $_week 周',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Icon(Icons.expand_more, size: 18),
                ],
              ),
            ),
          ),
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
    // 含底部预留的空档：晚自习那几行没有课，但要画出来给人加课
    final periodsPerDay = _config.totalPeriods;
    // 日期条始终列出一整周（单日程模式下要靠它换天），格子则按 _gridDays 画
    final headerColumns = _columnsFor(week, _visibleDays);
    final columns = _columnsFor(week, _gridDays);
    // 学期前几周常常还没开课，此时整屏都是「非本周」，
    // 明确提示一下，避免被误读成课表数据缺失
    final hasClassThisWeek =
        _sessions.any((s) => s.hasClassInWeek(week)) ||
        columns.any((c) => c.swapped);
    final days = _gridDays;

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
        _buildDayHeader(headerColumns, week),
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
                            // 点空白格就地加课。压在课程格子下面，
                            // 有课的位置被格子挡住，点上去还是看课程详情
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) => _onGridTap(
                                  details.localPosition,
                                  week: week,
                                  columns: columns,
                                  cellWidth: cellWidth,
                                  rowCount: periodsPerDay,
                                ),
                              ),
                            ),
                            for (var i = 0; i < columns.length; i++)
                              ..._buildDaySlots(
                                week: week,
                                column: columns[i],
                                dayIndex: i,
                                cellWidth: cellWidth,
                              ),
                            if (_draftWeek == week && _draftDay != null)
                              _buildDraftOverlay(
                                days,
                                cellWidth,
                                periodsPerDay,
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

  /// 当前显示的这几列各自的「真实星期 / 日期 / 实际要展示哪天课」。
  ///
  /// 调休列（如周六补周三的课）[effectiveWeekday] 与 [weekday] 不同，
  /// 格子按 [effectiveWeekday] 铺课程，日期条仍显示真实的那一天。
  List<_DayColumn> _columnsFor(int week, List<int> weekdays) {
    final visible = _visibleDays;
    final firstDay = _config.firstDayOfWeek(week);
    return [
      for (final weekday in weekdays)
        _columnFor(
          weekday,
          firstDay?.add(Duration(days: visible.indexOf(weekday))),
        ),
    ];
  }

  _DayColumn _columnFor(int weekday, DateTime? date) {
    final swap = date == null ? null : _config.swapOn(date);
    return _DayColumn(
      weekday: weekday,
      date: date,
      effectiveWeekday: swap?.sourceWeekday ?? weekday,
      swapped: swap != null,
    );
  }

  Widget _buildDayHeader(List<_DayColumn> columns, int week) {
    final today = DateTime.now();

    return Row(
      children: [
        _buildMonthCell(_config.firstDayOfWeek(week)),
        for (var i = 0; i < columns.length; i++)
          Expanded(
            child: _buildDayHeaderCell(
              column: columns[i],
              isToday:
                  columns[i].date != null &&
                  _isSameDay(columns[i].date!, today),
              isSelected: columns[i].weekday == _selectedDay,
              // 只有单日程模式需要挑日子，平时点日期条什么也不做
              onTap: _singleDayMode
                  ? () => setState(() => _singleDay = columns[i].weekday)
                  : null,
              onLongPress: () => _showDayMenu(columns[i]),
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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _gridLine, width: 0.5)),
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
    required _DayColumn column,
    required bool isToday,
    bool isSelected = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final weekday = column.weekday;
    final date = column.date;
    final allDay = date == null ? const <CustomSchedule>[] : _allDayOn(date);
    final scheme = Theme.of(context).colorScheme;
    final cell = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: _gridLine, width: 0.5),
          bottom: BorderSide(color: _gridLine, width: 0.5),
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
                  : isSelected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.2,
                      ),
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
          // 调休列：标出这天实际按周几的课表上课
          if (column.swapped)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '补周${_weekdayNames[column.effectiveWeekday - 1]}',
                style: TextStyle(fontSize: 9, color: scheme.primary),
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
    if (onTap == null && onLongPress == null) return cell;
    return GestureDetector(
      // 整格可点，而不是只有数字那一小块
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: cell,
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 长按日期列：复制这天的课、粘贴到这天、或取消这天的调休。
  ///
  /// 国内学校的「调休」本质就是「周末那天上周几的课」，所以这里的复制/粘贴
  /// 落成的就是一条调休规则（某个日期按周几的课表上课），与设置页里手填的
  /// 完全等价——两处共用同一份数据，改哪边都算数。
  Future<void> _showDayMenu(_DayColumn column) async {
    final date = column.date;
    final copied = _copiedWeekday;
    final label = _weekdayNames[column.effectiveWeekday - 1];

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                date == null
                    ? '周${_weekdayNames[column.weekday - 1]}'
                    : '${date.month}月${date.day}日 '
                          '周${_weekdayNames[column.weekday - 1]}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text('复制这天的课（周$label）'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (copied != null)
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: Text('粘贴：这天改上周${_weekdayNames[copied - 1]}的课'),
                enabled: date != null,
                onTap: date == null
                    ? null
                    : () => Navigator.pop(context, 'paste'),
              ),
            if (column.swapped)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('取消这天的调休'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'copy') {
      setState(() => _copiedWeekday = column.effectiveWeekday);
      _toast('已复制周$label 的课，长按要调休的那天粘贴');
      return;
    }
    if (date == null) return;
    if (action == 'paste' && copied != null) {
      await _setSwap(date, copied);
      if (!mounted) return;
      _toast('这天已改成上周${_weekdayNames[copied - 1]}的课');
      return;
    }
    if (action == 'clear') {
      await _setSwap(date, null);
      if (!mounted) return;
      _toast('已取消这天的调休');
    }
  }

  /// 写入或取消一条调休规则（[sourceWeekday] 为 null 表示取消这天），并落盘
  Future<void> _setSwap(DateTime date, int? sourceWeekday) async {
    final next = [
      for (final swap in _config.daySwaps)
        if (!swap.isOn(date)) swap,
      if (sourceWeekday != null)
        DaySwap(date: date, sourceWeekday: sourceWeekday),
    ];
    final config = _config.copyWith(daySwaps: next);
    setState(() {
      _config = config;
      // 调休变了，之前划定的待添加范围作废
      _draftWeek = null;
      _draftDay = null;
    });
    await _cache.saveConfig(config);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
    return GestureDetector(
      // 点这一格就地改它的起止钟点，比进设置里翻一遍快
      behavior: HitTestBehavior.opaque,
      onTap: () => _editPeriodTime(period),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$period',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (time != null) ...[
              const SizedBox(height: 2),
              Text(
                time.start,
                style: const TextStyle(fontSize: 9, height: 1.1),
              ),
              Text(time.end, style: const TextStyle(fontSize: 9, height: 1.1)),
            ],
          ],
        ),
      ),
    );
  }

  /// 改某一节的起止钟点。改完立刻落盘，日程换算出的节次也跟着更新。
  Future<void> _editPeriodTime(int period) async {
    final time = _config.timeOf(period);
    var start =
        _parseTimeOfDay(time?.start) ?? const TimeOfDay(hour: 8, minute: 0);
    var end =
        _parseTimeOfDay(time?.end) ?? const TimeOfDay(hour: 8, minute: 45);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('第 $period 节'),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                title: const Text('开始'),
                trailing: Text(_formatTimeOfDay(start)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: start,
                  );
                  if (picked != null) setLocal(() => start = picked);
                },
              ),
              ListTile(
                dense: true,
                title: const Text('结束'),
                trailing: Text(_formatTimeOfDay(end)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: end,
                  );
                  if (picked != null) setLocal(() => end = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final times = [
      for (final t in _config.periodTimes)
        if (t.period != period) t,
      PeriodTime(
        period: period,
        start: _formatTimeOfDay(start),
        end: _formatTimeOfDay(end),
      ),
    ]..sort((a, b) => a.period.compareTo(b.period));
    final next = _config.copyWith(periodTimes: times);
    setState(() {
      _config = next;
      // 钟点变了，按时间换算节次的自建日程要重算
      _rebuildCustomSessions();
    });
    await _cache.saveConfig(next);
  }

  static TimeOfDay? _parseTimeOfDay(String? text) {
    if (text == null) return null;
    final parts = text.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatTimeOfDay(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Widget _buildGridLines(int periodsPerDay, int dayCount) {
    final border = Border(
      left: BorderSide(color: _gridLine, width: 0.5),
      top: BorderSide(color: _gridLine, width: 0.5),
    );
    return Column(
      children: [
        for (var period = 0; period < periodsPerDay; period++)
          Expanded(
            child: Row(
              children: [
                for (var day = 0; day < dayCount; day++)
                  Expanded(
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
    required _DayColumn column,
    required int dayIndex,
    required double cellWidth,
  }) {
    final weekday = column.effectiveWeekday;
    final seen = <String>{};
    final sessions = <CourseSession>[];
    for (final session in _sessions) {
      if (session.dayOfWeek != weekday) continue;
      final isThisWeek = session.hasClassInWeek(week);
      if (!isThisWeek && !_config.showOtherWeeks) continue;
      final key =
          '${session.name}|${session.startPeriod}'
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

  // ------------------------------------------------ 空白处点选范围、就地加课

  /// 某一格是否被课表占着。
  ///
  /// 只看本周真的会上课的条目：别的周的课淡显出来只是为了看清整张课表的
  /// 形状，本周那一格其实是空的。把它们也算成占用的话，某一周某天的课
  /// （如第 14 周周六的实训）会把其它周同一格全锁死，想加课也点不动。
  bool _isCellTaken(int week, int weekday, int period) {
    for (final session in _sessions) {
      if (session.dayOfWeek != weekday) continue;
      if (!session.hasClassInWeek(week)) continue;
      if (period >= session.startPeriod && period <= session.endPeriod) {
        return true;
      }
    }
    return false;
  }

  /// 点在空白格上：把这一格选起来，并在格子右侧给出加号与拖动手柄
  void _onGridTap(
    Offset local, {
    required int week,
    required List<_DayColumn> columns,
    required double cellWidth,
    required int rowCount,
  }) {
    final index = (local.dx / cellWidth).floor().clamp(0, columns.length - 1);
    final period = (local.dy / _config.cellHeight).floor() + 1;
    if (period < 1 || period > rowCount) return;

    // 调休列上不加课：它借用的是别的星期的课，在这上面新建课程会被记成
    // 那个真实星期每周都上，与「只调这一天」的意图不符
    if (columns[index].swapped) return;

    final weekday = columns[index].weekday;
    if (_isCellTaken(week, weekday, period)) return;

    final sameCell =
        _draftWeek == week &&
        _draftDay == weekday &&
        _draftStart == period &&
        _draftEnd == period;
    setState(() {
      // 同一格再点一次即取消，免得范围一直挂在课表上
      _draftWeek = sameCell ? null : week;
      _draftDay = sameCell ? null : weekday;
      _draftStart = period;
      _draftEnd = period;
    });
  }

  /// 拖手柄：以按住时的那一端为锚，往上拖延长上界、往下拖延长下界
  void _onHandleDrag(double dy, int rowCount) {
    _dragDelta += dy;
    final steps = (_dragDelta / _config.cellHeight).round();
    final moved = (_dragPinned + steps).clamp(1, rowCount);
    setState(() {
      if (moved >= _dragPinned) {
        _draftStart = _dragPinned;
        _draftEnd = moved;
      } else {
        _draftStart = moved;
        _draftEnd = _dragPinned;
      }
    });
  }

  /// 划定范围内画出的那块：一个加号，右边一个可上下拖的手柄
  Widget _buildDraftOverlay(List<int> days, double cellWidth, int rowCount) {
    final column = days.indexOf(_draftDay!);
    if (column < 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: column * cellWidth,
      top: (_draftStart - 1) * _config.cellHeight,
      width: cellWidth,
      height: (_draftEnd - _draftStart + 1) * _config.cellHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  _addCustomAtRange(_draftDay!, _draftStart, _draftEnd),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  border: Border.all(color: scheme.primary, width: 1),
                  borderRadius: BorderRadius.circular(_config.cellRadius),
                ),
                child: Icon(Icons.add, color: scheme.primary, size: 26),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _buildDragHandle(rowCount),
          ),
        ],
      ),
    );
  }

  /// 手柄：一根竖着的小白条，上下各一个箭头，拖动即改范围
  Widget _buildDragHandle(int rowCount) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _addCustomAtRange(_draftDay!, _draftStart, _draftEnd),
      onVerticalDragStart: (_) {
        _dragPinned = _draftStart;
        _dragDelta = 0;
      },
      onVerticalDragUpdate: (details) =>
          _onHandleDrag(details.delta.dy, rowCount),
      // 松手即认为范围定好了，直接进添加页
      onVerticalDragEnd: (_) =>
          _addCustomAtRange(_draftDay!, _draftStart, _draftEnd),
      child: Container(
        width: 22,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(11),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_arrow_up, size: 16, color: scheme.primary),
            const SizedBox(height: 6),
            Icon(Icons.keyboard_arrow_down, size: 16, color: scheme.primary),
          ],
        ),
      ),
    );
  }

  /// 按划定的星期与节次打开添加页，内容预先填好
  Future<void> _addCustomAtRange(
    int weekday,
    int startPeriod,
    int endPeriod,
  ) async {
    final periods = [for (var p = startPeriod; p <= endPeriod; p++) p];
    setState(() {
      _draftWeek = null;
      _draftDay = null;
    });

    final result = await showCustomEntryEditor(
      context,
      config: _config,
      initialWeekday: weekday,
      initialPeriods: periods,
    );
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

  Widget _buildSessionCard(CourseSession session, {required bool isThisWeek}) {
    // 非本周课程进一步降低饱和度并提亮，与本周课程形成明显对比
    final color = _sessionColor(session, faded: !isThisWeek);

    final palette = _palette;
    final card = Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        // 背景图要透得出来：不透明度由外观里的滑杆决定
        color: color.withValues(alpha: palette.cardAlpha),
        borderRadius: BorderRadius.circular(_config.cellRadius),
        border: palette.preset.outlined
            ? Border.all(color: palette.borderOn(color))
            : null,
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
              // 浅色格子配深字，深色格子配浅字，由卡片自身亮度决定
              color: palette.textColorOn(color, secondary: false),
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
                color: palette.textColorOn(color, secondary: true),
              ),
            ),
          const Spacer(),
          if (!isThisWeek)
            Text(
              '非本周',
              style: TextStyle(
                fontSize: 8,
                color: palette.textColorOn(color, secondary: true),
              ),
            ),
        ],
      ),
    );

    // 非本周的课只是淡显出来看形状，那一格本周其实是空的，
    // 因此不接管点击，让下面那层接着做「就地加课」
    if (!isThisWeek) return IgnorePointer(child: card);
    return GestureDetector(onTap: () => _openSession(session), child: card);
  }

  /// 是否深色主题。整套格子配色都以它为基准切换。
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  /// 当前外观（预设 + 深浅色）解析出来的具体颜色
  TablePalette get _palette => TablePalette(appAppearance.value, dark: _isDark);

  /// 网格线：浅色下是淡黑，深色下得换成淡白，否则整片网格看不见
  Color get _gridLine => _palette.gridLine;

  /// 格子颜色：导入课程按预设取色（同一门课每次一致），
  /// 自建课程用用户自己选的颜色。
  ///
  /// 自建色同样要跟「是否本周」走同一套视觉规则——靠饱和度与明暗区分
  /// 是否本周要上，否则自建条目会在一屏里显得格格不入。
  Color _sessionColor(CourseSession session, {required bool faded}) {
    final custom = _customColors[session.courseId];
    if (custom == null) {
      return _palette.cardColor(session.name, faded: faded);
    }
    final hsl = HSLColor.fromColor(Color(custom));
    if (!faded) return hsl.toColor();
    return (_isDark
            ? hsl
                  .withSaturation(hsl.saturation * 0.45)
                  .withLightness(hsl.lightness * 0.62)
            : hsl.withSaturation(0.10).withLightness(0.96))
        .toColor();
  }
}

/// 课表上的一列：日期条上的真实星期，加上这一天实际要展示哪天课。
///
/// 平时两者相同；遇上调休（如周六补周三的课）时 [effectiveWeekday] 是周三，
/// 格子按周三铺课程，日期条仍显示「周六 11 日」这个真实的日子。
class _DayColumn {
  const _DayColumn({
    required this.weekday,
    required this.date,
    required this.effectiveWeekday,
    required this.swapped,
  });

  /// 真实星期，1=周一 … 7=周日
  final int weekday;

  /// 这一列对应的具体日期；没设置开学时间时为 null
  final DateTime? date;

  /// 实际用于取课的星期
  final int effectiveWeekday;

  /// 这一天是否配了调休规则
  final bool swapped;
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
