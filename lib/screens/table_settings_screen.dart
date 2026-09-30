import 'package:flutter/material.dart';

import '../import/course_cache.dart';
import '../models/course.dart';
import '../models/table_config.dart';
import 'parse_diagnostics_screen.dart';

/// 课表设置页。
///
/// 设置项对齐 WakeUp：教务系统不提供节次钟点与开学日期，
/// 这些都得在这里由用户配置。改动即时落盘。
class TableSettingsScreen extends StatefulWidget {
  const TableSettingsScreen({
    super.key,
    required this.config,
    required this.courses,
    required this.sessions,
  });

  final TableConfig config;
  final List<Course> courses;
  final List<CourseSession> sessions;

  @override
  State<TableSettingsScreen> createState() => _TableSettingsScreenState();
}

class _TableSettingsScreenState extends State<TableSettingsScreen> {
  static const List<String> _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  final CourseCache _cache = const CourseCache();
  late TableConfig _config = widget.config;

  Future<void> _update(TableConfig next) async {
    setState(() => _config = next);
    await _cache.saveConfig(next);
  }

  /// 课程名单里有、但没有任何排课时间的课程
  List<Course> get _unscheduled {
    final scheduled = widget.sessions.map((s) => s.name).toSet();
    return widget.courses.where((c) => !scheduled.contains(c.name)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentWeek = _config.currentWeek(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('课表设置')),
      body: ListView(
        children: [
          _sectionHeader('课表数据'),
          _buildNameTile(),
          ListTile(
            title: const Text('上课时间'),
            subtitle: Text(
              _config.periodTimes.isEmpty ? '未设置' : '第 1 节起共 ${_config.periodTimes.length} 节已设置',
            ),
            trailing: const Text('点击此处更改'),
            onTap: _editPeriodTimes,
          ),
          ListTile(
            title: const Text('开学时间'),
            subtitle: Text(
              _config.startDate == null
                  ? '未设置，设置后才能自动定位当前周'
                  : _formatDate(_config.startDate!),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickStartDate,
          ),
          ListTile(
            title: const Text('不知道开学日期？'),
            subtitle: const Text('按「今天是第几周」反推，结果一样准确'),
            trailing: const Icon(Icons.calculate_outlined),
            onTap: _deriveStartDate,
          ),
          ListTile(
            title: const Text('每周起始日'),
            subtitle: Text(_weekdayNames[_config.weekStartDay - 1]),
            onTap: _pickWeekStartDay,
          ),
          ListTile(
            title: const Text('当前周'),
            subtitle: Text(
              currentWeek == null ? '需先设置开学时间' : '第 $currentWeek 周',
            ),
          ),
          ListTile(
            title: const Text('一天课程节数'),
            subtitle: Text('${_config.periodsPerDay} 节'),
            onTap: () => _pickNumber(
              title: '一天课程节数',
              value: _config.periodsPerDay,
              min: 1,
              max: 20,
              onPicked: (v) => _update(_config.copyWith(periodsPerDay: v)),
            ),
          ),
          ListTile(
            title: const Text('学期周数'),
            subtitle: Text('${_config.totalWeeks} 周'),
            onTap: () => _pickNumber(
              title: '学期周数',
              value: _config.totalWeeks,
              min: 1,
              max: 30,
              onPicked: (v) => _update(_config.copyWith(totalWeeks: v)),
            ),
          ),
          _buildUnscheduledTile(),
          _sectionHeader('课表外观'),
          SwitchListTile(
            title: const Text('显示周六'),
            value: _config.showSaturday,
            onChanged: (v) => _update(_config.copyWith(showSaturday: v)),
          ),
          SwitchListTile(
            title: const Text('显示周日'),
            value: _config.showSunday,
            onChanged: (v) => _update(_config.copyWith(showSunday: v)),
          ),
          SwitchListTile(
            title: const Text('显示非本周课程'),
            subtitle: const Text('非本周课程淡显，便于看清整张课表的安排'),
            value: _config.showOtherWeeks,
            onChanged: (v) => _update(_config.copyWith(showOtherWeeks: v)),
          ),
          _buildSliderTile(
            title: '课程格子高度',
            value: _config.cellHeight,
            min: 40,
            max: 90,
            unit: 'dp',
            apply: (config, v) => config.copyWith(cellHeight: v),
          ),
          _buildSliderTile(
            title: '格子圆角半径',
            value: _config.cellRadius,
            min: 0,
            max: 16,
            unit: 'dp',
            decimals: 0,
            apply: (config, v) => config.copyWith(cellRadius: v),
          ),
          _sectionHeader('诊断'),
          ListTile(
            title: const Text('解析诊断'),
            subtitle: const Text('把课表页面 HTML 交给解析器跑一遍，看能否解析出课程'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ParseDiagnosticsScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNameTile() {
    return ListTile(
      title: const Text('课表名称'),
      subtitle: Text(_config.name),
      onTap: () async {
        final controller = TextEditingController(text: _config.name);
        final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('课表名称'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '例如：宁波城市职业技术学院'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('确定'),
              ),
            ],
          ),
        );
        if (name != null && name.isNotEmpty) {
          await _update(_config.copyWith(name: name));
        }
      },
    );
  }

  Widget _buildUnscheduledTile() {
    final courses = _unscheduled;
    return ListTile(
      title: const Text('无排课时间的课程'),
      subtitle: Text(
        courses.isEmpty ? '全部课程都已排课' : '${courses.length} 门',
      ),
      trailing: courses.isEmpty ? null : const Icon(Icons.chevron_right),
      onTap: courses.isEmpty
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('无排课时间的课程'),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '教务系统里这几门课没有排课时间，'
                          '因此不会出现在课表网格中。',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        for (final course in courses)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${course.name}（${course.courseId}）',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required String unit,
    required TableConfig Function(TableConfig config, double value) apply,
    int decimals = 0,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              label: '${value.toStringAsFixed(decimals)} $unit',
              onChanged: (v) => setState(() => _config = apply(_config, v)),
              onChangeEnd: (_) => _cache.saveConfig(_config),
            ),
          ),
          Text('${value.toStringAsFixed(decimals)} $unit'),
        ],
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final initial = _config.startDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3),
      helpText: '选择开学时间（第一周的起始日）',
    );
    if (picked == null) return;
    await _update(_config.copyWith(startDate: picked));
  }

  /// 按「今天是第几周」反推开学日期。
  ///
  /// 比让用户去翻校历算日期靠谱得多：各校课表页不给日期，但用户看一眼
  /// 教务系统就知道现在是第几周。
  Future<void> _deriveStartDate() async {
    await _pickNumber(
      title: '今天是第几周？',
      value: _config.currentWeek(DateTime.now()) ?? 1,
      min: 1,
      max: _config.totalWeeks,
      onPicked: _applyDerivedStartDate,
    );
  }

  Future<void> _applyDerivedStartDate(int week) async {
    final start = TableConfig.deriveStartDate(
      currentWeek: week,
      today: DateTime.now(),
      weekStartDay: _config.weekStartDay,
    );
    await _update(_config.copyWith(startDate: start));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已按第 $week 周推算：开学时间 ${_formatDate(start)}')),
    );
  }

  Future<void> _pickWeekStartDay() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('每周起始日'),
        children: [
          for (var day = 1; day <= 7; day++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, day),
              child: Text(_weekdayNames[day - 1]),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _update(_config.copyWith(weekStartDay: picked));
  }

  Future<void> _pickNumber({
    required String title,
    required int value,
    required int min,
    required int max,
    required void Function(int) onPicked,
  }) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          SizedBox(
            height: 300,
            width: 120,
            child: ListView.builder(
              itemCount: max - min + 1,
              itemBuilder: (context, index) {
                final number = min + index;
                return SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, number),
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontWeight:
                          number == value ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _editPeriodTimes() async {
    final updated = await Navigator.of(context).push<List<PeriodTime>>(
      MaterialPageRoute(
        builder: (_) => _PeriodTimesScreen(
          times: _config.periodTimes,
          periodsPerDay: _config.periodsPerDay,
        ),
      ),
    );
    if (updated == null) return;
    await _update(_config.copyWith(periodTimes: updated));
  }

  static String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';
}

/// 编辑各节次起止时间
class _PeriodTimesScreen extends StatefulWidget {
  const _PeriodTimesScreen({
    required this.times,
    required this.periodsPerDay,
  });

  final List<PeriodTime> times;
  final int periodsPerDay;

  @override
  State<_PeriodTimesScreen> createState() => _PeriodTimesScreenState();
}

class _PeriodTimesScreenState extends State<_PeriodTimesScreen> {
  late final Map<int, TextEditingController> _start = {};
  late final Map<int, TextEditingController> _end = {};

  @override
  void initState() {
    super.initState();
    for (var period = 1; period <= widget.periodsPerDay; period++) {
      PeriodTime? existing;
      for (final t in widget.times) {
        if (t.period == period) existing = t;
      }
      _start[period] = TextEditingController(text: existing?.start ?? '');
      _end[period] = TextEditingController(text: existing?.end ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _start.values) {
      c.dispose();
    }
    for (final c in _end.values) {
      c.dispose();
    }
    super.dispose();
  }

  static final RegExp _timeRe = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$');

  void _save() {
    final result = <PeriodTime>[];
    for (var period = 1; period <= widget.periodsPerDay; period++) {
      final start = _start[period]!.text.trim();
      final end = _end[period]!.text.trim();
      if (start.isEmpty && end.isEmpty) continue;
      if (!_timeRe.hasMatch(start) || !_timeRe.hasMatch(end)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('第 $period 节时间格式不对，应为 HH:mm')),
        );
        return;
      }
      result.add(PeriodTime(period: period, start: start, end: end));
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上课时间'),
        actions: [
          IconButton(
            tooltip: '保存',
            onPressed: _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: widget.periodsPerDay,
        itemBuilder: (context, index) {
          final period = index + 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text('第 $period 节'),
                ),
                Expanded(
                  child: TextField(
                    controller: _start[period],
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      hintText: '开始',
                      isDense: true,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('—'),
                ),
                Expanded(
                  child: TextField(
                    controller: _end[period],
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      hintText: '结束',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
