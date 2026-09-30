import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/custom_entry.dart';
import '../models/table_config.dart';

/// 编辑页的返回值：用户最后保存的是课程还是日程。
///
/// 页面上有「课程 / 日程」两个 Tab，用户可能中途切换，所以不能用
/// 单一类型承接返回值。
class CustomEntryResult {
  const CustomEntryResult.course(CustomCourse this.course) : schedule = null;

  const CustomEntryResult.schedule(CustomSchedule this.schedule) : course = null;

  final CustomCourse? course;
  final CustomSchedule? schedule;
}

/// 打开「添加 / 编辑课程或日程」页；用户取消时返回 null。
Future<CustomEntryResult?> showCustomEntryEditor(
  BuildContext context, {
  required TableConfig config,
  CustomCourse? course,
  CustomSchedule? schedule,
}) {
  return Navigator.of(context).push<CustomEntryResult>(
    MaterialPageRoute(
      builder: (_) => CustomEntryEditor(
        config: config,
        initialCourse: course,
        initialSchedule: schedule,
      ),
    ),
  );
}

/// 自建课程 / 日程的编辑页，字段对齐 WakeUp 的「添加课程 / 日程」。
class CustomEntryEditor extends StatefulWidget {
  const CustomEntryEditor({
    super.key,
    required this.config,
    this.initialCourse,
    this.initialSchedule,
  });

  final TableConfig config;

  /// 编辑已有的自建课程
  final CustomCourse? initialCourse;

  /// 编辑已有的自建日程
  final CustomSchedule? initialSchedule;

  @override
  State<CustomEntryEditor> createState() => _CustomEntryEditorState();
}

class _CustomEntryEditorState extends State<CustomEntryEditor> {
  static const List<String> _weekdayShort = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  /// 0=课程，1=日程
  late int _tab;
  late String _entryId;

  late final TextEditingController _name;
  late final TextEditingController _credits;
  late int _color;
  late List<_SlotDraft> _slots;

  late final TextEditingController _title;
  late final TextEditingController _location;
  late bool _allDay;
  late DateTime _start;
  late DateTime _end;
  late ScheduleRepeat _repeat;
  late String _tag;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final course = widget.initialCourse;
    final schedule = widget.initialSchedule;
    _tab = schedule != null ? 1 : 0;
    _entryId = course?.id ?? schedule?.id ?? _newId();

    _name = TextEditingController(text: course?.name ?? '');
    _credits = TextEditingController(text: _creditsText(course?.credits));
    _color = course?.color ?? customCourseColors.first;
    _slots = _draftsFrom(course);

    _title = TextEditingController(text: schedule?.title ?? '');
    _location = TextEditingController(text: schedule?.location ?? '');
    _allDay = schedule?.allDay ?? false;
    final today = DateTime.now();
    final first = widget.config.periodTimes.isEmpty
        ? null
        : widget.config.periodTimes.first;
    _start = schedule?.start ?? _atTime(today, first?.start ?? '08:15');
    _end = schedule?.end ?? _atTime(today, first?.end ?? '09:50');
    _repeat = schedule?.repeat ?? ScheduleRepeat.never;
    _tag = schedule?.tag ?? '其他';
    _note = TextEditingController(text: schedule?.note ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _credits.dispose();
    _title.dispose();
    _location.dispose();
    _note.dispose();
    for (final slot in _slots) {
      slot.dispose();
    }
    super.dispose();
  }

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static String _creditsText(double? credits) {
    if (credits == null) return '';
    return credits % 1 == 0 ? credits.toInt().toString() : credits.toString();
  }

  static DateTime _atTime(DateTime day, String time) {
    final parts = time.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 8 : 8;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  List<_SlotDraft> _draftsFrom(CustomCourse? course) {
    if (course == null || course.slots.isEmpty) return [_defaultSlot()];
    return [
      for (final slot in course.slots)
        _SlotDraft(
          weeks: [...slot.weeks],
          dayOfWeek: slot.dayOfWeek,
          periods: [...slot.periods],
          useCustomTime: slot.useCustomTime,
          startTime: slot.startTime,
          endTime: slot.endTime,
          room: slot.room,
          teacher: slot.teacher,
          note: slot.note,
        ),
    ];
  }

  /// 新时段的默认值：全学期、周一第 1-2 节（参考图的默认样子）
  _SlotDraft _defaultSlot() => _SlotDraft(
        weeks: [for (var week = 1; week <= widget.config.totalWeeks; week++) week],
        dayOfWeek: DateTime.monday,
        periods: const [1, 2],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        titleSpacing: 0,
        centerTitle: true,
        title: _buildTabSwitcher(),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              '保存',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [_buildCourseTab(), _buildScheduleTab()],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabButton('课程', 0, scheme),
          _buildTabButton('日程', 1, scheme),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index, ColorScheme scheme) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 课程 Tab

  Widget _buildCourseTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _card([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                hintText: '输入课程名称',
                border: InputBorder.none,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('颜色'),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Color(_color),
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
            onTap: _pickColor,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('学分'),
            trailing: SizedBox(
              width: 72,
              child: TextField(
                controller: _credits,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '选填',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
        ]),
        for (var i = 0; i < _slots.length; i++) ...[
          _buildSlotHeader(i, scheme),
          _buildSlotCard(_slots[i]),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addSlot,
          icon: const Icon(Icons.add),
          label: const Text('添加时段'),
        ),
      ],
    );
  }

  Widget _buildSlotHeader(int index, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 4, 0),
      child: Row(
        children: [
          Text(
            '时段${index + 1}',
            style: TextStyle(fontSize: 13, color: scheme.outline),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _duplicateSlot(index),
            icon: const Icon(Icons.copy_all_outlined, size: 16),
            label: const Text('复制'),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
          ),
          TextButton.icon(
            onPressed: _slots.length > 1 ? () => _removeSlot(index) : null,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('删除'),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(_SlotDraft slot) {
    return _card([
      ListTile(
        leading: const Icon(Icons.date_range_outlined),
        title: const Text('周数'),
        trailing: _trailingText('第${formatWeeks(slot.weeks)}周'),
        onTap: () => _pickWeeks(slot),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.schedule_outlined),
        title: const Text('节数'),
        trailing: _trailingText(
          '${_weekdayShort[slot.dayOfWeek - 1]} '
          '第${formatWeeks(slot.periods)}节',
        ),
        onTap: () => _pickPeriods(slot),
      ),
      const Divider(height: 1),
      SwitchListTile(
        secondary: const Icon(Icons.edit_calendar_outlined),
        title: const Text('自定义时间'),
        value: slot.useCustomTime,
        onChanged: (value) => setState(() => slot.useCustomTime = value),
      ),
      if (slot.useCustomTime) ...[
        const Divider(height: 1),
        _buildTimeTile('开始', slot.startTime),
        const Divider(height: 1),
        _buildTimeTile('结束', slot.endTime),
      ],
      const Divider(height: 1),
      _buildFieldTile(
        icon: Icons.place_outlined,
        hint: '教室',
        controller: slot.room,
      ),
      const Divider(height: 1),
      _buildFieldTile(
        icon: Icons.person_outline,
        hint: '老师',
        controller: slot.teacher,
      ),
      const Divider(height: 1),
      _buildFieldTile(
        icon: Icons.sticky_note_2_outlined,
        hint: '备注',
        controller: slot.note,
      ),
    ]);
  }

  // ---------------------------------------------------------------- 日程 Tab

  Widget _buildScheduleTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _card([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _title,
              decoration: const InputDecoration(
                hintText: '添加考试、活动会议、自习',
                border: InputBorder.none,
              ),
            ),
          ),
          const Divider(height: 1),
          _buildFieldTile(
            icon: Icons.place_outlined,
            hint: '位置（选填）',
            controller: _location,
          ),
        ]),
        _card([
          SwitchListTile(
            secondary: const Icon(Icons.wb_sunny_outlined),
            title: const Text('全天'),
            value: _allDay,
            onChanged: (value) => setState(() => _allDay = value),
          ),
          const Divider(height: 1),
          _buildDateTimeTile('开始', isStart: true),
          const Divider(height: 1),
          _buildDateTimeTile('结束', isStart: false),
        ]),
        _card([
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('重复'),
            trailing: Text(
              _repeat.label,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            onTap: _pickRepeat,
          ),
        ]),
        _card([
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('标签'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(tagColorOf(_tag)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(_tag, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
            onTap: _pickTag,
          ),
        ]),
        _card([
          _buildFieldTile(
            icon: Icons.sticky_note_2_outlined,
            hint: '备注（选填）',
            controller: _note,
          ),
        ]),
      ],
    );
  }

  // ---------------------------------------------------------------- 复用小部件

  Widget _card(List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _trailingText(String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, size: 18),
      ],
    );
  }

  Widget _buildFieldTile({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildTimeTile(String label, TextEditingController controller) {
    return ListTile(
      leading: const Icon(Icons.access_time),
      title: Text(label),
      trailing: Text(
        controller.text.isEmpty ? '未设置' : controller.text,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      onTap: () => _pickTime(controller),
    );
  }

  Widget _buildDateTimeTile(String label, {required bool isStart}) {
    final value = isStart ? _start : _end;
    final textStyle = Theme.of(context).textTheme.bodyLarge;
    return ListTile(
      leading: const Icon(Icons.schedule_outlined),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip('${value.year}年${value.month.toString().padLeft(2, '0')}月'
              '${value.day.toString().padLeft(2, '0')}日', () => _pickDate(isStart), textStyle),
          const SizedBox(width: 6),
          _chip(
            '${value.hour.toString().padLeft(2, '0')}:'
            '${value.minute.toString().padLeft(2, '0')}',
            _allDay ? null : () => _pickTimeOfDay(isStart),
            textStyle,
            enabled: !_allDay,
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String text,
    VoidCallback? onTap,
    TextStyle? style, {
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: style?.copyWith(
            color: enabled ? null : scheme.outline,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 取值动作

  void _addSlot() {
    setState(() => _slots.add(_defaultSlot()));
  }

  void _duplicateSlot(int index) {
    final source = _slots[index];
    setState(() {
      _slots.insert(
        index + 1,
        _SlotDraft(
          weeks: [...source.weeks],
          dayOfWeek: source.dayOfWeek,
          periods: [...source.periods],
          useCustomTime: source.useCustomTime,
          startTime: source.startTime.text,
          endTime: source.endTime.text,
          room: source.room.text,
          teacher: source.teacher.text,
          note: source.note.text,
        ),
      );
    });
  }

  void _removeSlot(int index) {
    setState(() => _slots.removeAt(index).dispose());
  }

  Future<void> _pickColor() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ColorPickerSheet(selected: _color),
    );
    if (picked == null) return;
    setState(() => _color = picked);
  }

  Future<void> _pickWeeks(_SlotDraft slot) async {
    final picked = await showModalBottomSheet<List<int>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _WeekPickerSheet(
        totalWeeks: widget.config.totalWeeks,
        selected: slot.weeks,
      ),
    );
    if (picked == null) return;
    setState(() => slot.weeks = picked);
  }

  Future<void> _pickPeriods(_SlotDraft slot) async {
    final picked = await showModalBottomSheet<_PeriodSelection>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PeriodPickerSheet(
        dayOfWeek: slot.dayOfWeek,
        periods: slot.periods,
        periodsPerDay: widget.config.periodsPerDay,
        periodTimes: widget.config.periodTimes,
      ),
    );
    if (picked == null) return;
    setState(() {
      slot.dayOfWeek = picked.dayOfWeek;
      slot.periods = picked.periods;
    });
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(controller.text),
    );
    if (picked == null) return;
    setState(() {
      controller.text = '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final current = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final value = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      if (isStart) {
        _start = value;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = value;
      }
    });
  }

  Future<void> _pickTimeOfDay(bool isStart) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    setState(() {
      final value = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (isStart) {
        _start = value;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = value;
      }
    });
  }

  Future<void> _pickRepeat() async {
    final picked = await showModalBottomSheet<ScheduleRepeat>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in ScheduleRepeat.values)
              ListTile(
                title: Text(value.label),
                trailing: value == _repeat ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _repeat = picked);
  }

  Future<void> _pickTag() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tag in scheduleTags)
              ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(tag.color),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(tag.name),
                trailing: tag.name == _tag ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(tag.name),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _tag = picked);
  }

  static TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length == 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour != null && minute != null) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }
    return const TimeOfDay(hour: 8, minute: 0);
  }

  // ---------------------------------------------------------------- 保存

  void _save() {
    if (_tab == 0) {
      _saveCourse();
    } else {
      _saveSchedule();
    }
  }

  void _saveCourse() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _warn('请填写课程名称');
      return;
    }
    final slots = <CustomSlot>[];
    for (var i = 0; i < _slots.length; i++) {
      final draft = _slots[i];
      if (draft.weeks.isEmpty) {
        _warn('时段${i + 1}还没有选择周数');
        return;
      }
      if (draft.periods.isEmpty) {
        _warn('时段${i + 1}还没有选择节次');
        return;
      }
      slots.add(CustomSlot(
        weeks: draft.weeks,
        dayOfWeek: draft.dayOfWeek,
        periods: draft.periods,
        useCustomTime: draft.useCustomTime,
        startTime: draft.startTime.text.trim(),
        endTime: draft.endTime.text.trim(),
        room: draft.room.text.trim(),
        teacher: draft.teacher.text.trim(),
        note: draft.note.text.trim(),
      ));
    }
    if (slots.isEmpty) {
      _warn('请至少添加一个时段');
      return;
    }
    Navigator.of(context).pop(
      CustomEntryResult.course(CustomCourse(
        id: _entryId,
        name: name,
        color: _color,
        credits: double.tryParse(_credits.text.trim()),
        slots: slots,
      )),
    );
  }

  void _saveSchedule() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _warn('请填写日程标题');
      return;
    }
    if (_end.isBefore(_start)) {
      _warn('结束时间不能早于开始时间');
      return;
    }
    Navigator.of(context).pop(
      CustomEntryResult.schedule(CustomSchedule(
        id: _entryId,
        title: title,
        location: _location.text.trim(),
        allDay: _allDay,
        start: _start,
        end: _end,
        repeat: _repeat,
        tag: _tag,
        note: _note.text.trim(),
      )),
    );
  }

  void _warn(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// 编辑中的时段草稿。放控制器是为了让教室/老师/备注能在原地输入。
class _SlotDraft {
  _SlotDraft({
    required this.weeks,
    required this.dayOfWeek,
    required this.periods,
    this.useCustomTime = false,
    String startTime = '',
    String endTime = '',
    String room = '',
    String teacher = '',
    String note = '',
  })  : startTime = TextEditingController(text: startTime),
        endTime = TextEditingController(text: endTime),
        room = TextEditingController(text: room),
        teacher = TextEditingController(text: teacher),
        note = TextEditingController(text: note);

  List<int> weeks;
  int dayOfWeek;
  List<int> periods;
  bool useCustomTime;
  final TextEditingController startTime;
  final TextEditingController endTime;
  final TextEditingController room;
  final TextEditingController teacher;
  final TextEditingController note;

  void dispose() {
    startTime.dispose();
    endTime.dispose();
    room.dispose();
    teacher.dispose();
    note.dispose();
  }
}

/// 节次选择的结果
class _PeriodSelection {
  const _PeriodSelection(this.dayOfWeek, this.periods);

  final int dayOfWeek;
  final List<int> periods;
}

/// 学期周次多选
class _WeekPickerSheet extends StatefulWidget {
  const _WeekPickerSheet({required this.totalWeeks, required this.selected});

  final int totalWeeks;
  final List<int> selected;

  @override
  State<_WeekPickerSheet> createState() => _WeekPickerSheetState();
}

class _WeekPickerSheetState extends State<_WeekPickerSheet> {
  late final Set<int> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final weeks = [for (var week = 1; week <= widget.totalWeeks; week++) week];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('周数', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selected.addAll(weeks)),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final week in weeks)
                      FilterChip(
                        label: Text('$week'),
                        selected: _selected.contains(week),
                        onSelected: (value) => setState(() {
                          if (value) {
                            _selected.add(week);
                          } else {
                            _selected.remove(week);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () {
                        final result = _selected.toList()..sort();
                        Navigator.of(context).pop(result);
                      },
                child: Text('确定（已选 ${_selected.length} 周）'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 星期 + 节次多选
class _PeriodPickerSheet extends StatefulWidget {
  const _PeriodPickerSheet({
    required this.dayOfWeek,
    required this.periods,
    required this.periodsPerDay,
    required this.periodTimes,
  });

  final int dayOfWeek;
  final List<int> periods;
  final int periodsPerDay;
  final List<PeriodTime> periodTimes;

  @override
  State<_PeriodPickerSheet> createState() => _PeriodPickerSheetState();
}

class _PeriodPickerSheetState extends State<_PeriodPickerSheet> {
  static const List<String> _weekdayShort = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  late int _dayOfWeek = widget.dayOfWeek;
  late final Set<int> _periods = {...widget.periods};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('节数', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var day = 1; day <= 7; day++)
                  ChoiceChip(
                    label: Text(_weekdayShort[day - 1]),
                    selected: _dayOfWeek == day,
                    onSelected: (_) => setState(() => _dayOfWeek = day),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var period = 1;
                        period <= widget.periodsPerDay;
                        period++)
                      FilterChip(
                        label: Text(_periodLabel(period)),
                        selected: _periods.contains(period),
                        onSelected: (value) => setState(() {
                          if (value) {
                            _periods.add(period);
                          } else {
                            _periods.remove(period);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _periods.isEmpty
                    ? null
                    : () {
                        final periods = _periods.toList()..sort();
                        Navigator.of(context)
                            .pop(_PeriodSelection(_dayOfWeek, periods));
                      },
                child: Text('确定（已选 ${_periods.length} 节）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _periodLabel(int period) {
    for (final time in widget.periodTimes) {
      if (time.period == period) return '$period\n${time.start}';
    }
    return '$period';
  }
}

/// 自建课程的配色选择
class _ColorPickerSheet extends StatelessWidget {
  const _ColorPickerSheet({required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('颜色', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final color in customCourseColors)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(color),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: color == selected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              )
                            : null,
                      ),
                      child: color == selected
                          ? const Icon(Icons.check, size: 20)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
