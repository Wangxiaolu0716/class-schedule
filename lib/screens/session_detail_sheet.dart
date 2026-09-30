import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/custom_entry.dart';
import '../models/table_config.dart';

/// 弹出课程色块的详细信息。
///
/// 展示的都是导入时真实拿到的字段；教务系统的课表接口不提供
/// 同班同学名单，因此该项标注为暂不可用，而不是留空或猜测。
///
/// [creditsText]、[timeRangeText]、[note]、[footnote] 供自建课程覆盖默认值；
/// [onEdit] / [onDelete] 传了才显示对应按钮。
Future<void> showSessionDetail(
  BuildContext context, {
  required CourseSession session,
  required Course? course,
  required TableConfig config,
  String? creditsText,
  String? timeRangeText,
  String? note,
  String? footnote,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  final teacher = session.teacher.isNotEmpty
      ? session.teacher
      : (course?.teacher ?? '');
  final custom = session.courseId.startsWith(customCourseIdPrefix) ||
      session.courseId.startsWith(customScheduleIdPrefix);

  final rows = <(String, String)>[
    ('课程名称', session.name),
    if (course != null && course.code.isNotEmpty) ('课程代码', course.code),
    // 自建条目的 id 是内部生成的，露出来只会让人困惑
    if (session.courseId.isNotEmpty && !custom) ('课程序号', session.courseId),
    ('教师', teacher.isEmpty ? '—' : teacher),
    ('教室', session.room.isEmpty ? '—' : session.room),
    (
      '节数',
      '第 ${session.startPeriod}-${session.endPeriod} 节，'
          '共 ${session.periodCount} 节',
    ),
    ('时间', timeRangeText ?? _timeRangeOf(session, config)),
    ('星期', _weekdayNames[session.dayOfWeek - 1]),
    ('周次', formatWeeks(session.weeks)),
    ('学分', creditsText ?? _creditsOf(course?.credits)),
    if (note != null && note.isNotEmpty) ('备注', note),
  ];

  return _show(
    context,
    title: session.name,
    subtitle: '${_weekdayNames[session.dayOfWeek - 1]} '
        '第 ${session.startPeriod}-${session.endPeriod} 节 · '
        '周次 ${formatWeeks(session.weeks)}',
    rows: rows,
    footnote: footnote ?? '同学名单：教务系统课表接口未提供，暂无法显示。',
    onEdit: onEdit,
    onDelete: onDelete,
  );
}

/// 弹出全天日程的详情（没有节次，用不上课程色块那一套）
Future<void> showCustomScheduleDetail(
  BuildContext context, {
  required CustomSchedule schedule,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  final range = schedule.allDay
      ? '${_formatDate(schedule.start)} 全天'
      : '${_formatDate(schedule.start)} ${_formatClock(schedule.start)}'
          ' - ${_formatClock(schedule.end)}';

  return _show(
    context,
    title: schedule.title,
    subtitle: range,
    rows: [
      ('标题', schedule.title),
      ('位置', schedule.location.isEmpty ? '—' : schedule.location),
      ('时间', range),
      ('重复', schedule.repeat.label),
      ('标签', schedule.tag),
      if (schedule.note.isNotEmpty) ('备注', schedule.note),
    ],
    footnote: '',
    onEdit: onEdit,
    onDelete: onDelete,
  );
}

Future<void> _show(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<(String, String)> rows,
  required String footnote,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DetailSheet(
      title: title,
      subtitle: subtitle,
      rows: rows,
      footnote: footnote,
      onEdit: onEdit,
      onDelete: onDelete,
    ),
  );
}

/// 节次时间，取自课表设置里的节次钟点
String _timeRangeOf(CourseSession session, TableConfig config) {
  final start = config.timeOf(session.startPeriod)?.start;
  final end = config.timeOf(session.endPeriod)?.end;
  if (start == null || end == null) {
    return '未设置（可在「课表设置 → 上课时间」补充）';
  }
  return '$start - $end';
}

String _creditsOf(double? credits) {
  if (credits == null) return '—';
  return credits % 1 == 0 ? credits.toInt().toString() : credits.toString();
}

String _formatDate(DateTime date) =>
    '${date.year}年${date.month.toString().padLeft(2, '0')}月'
    '${date.day.toString().padLeft(2, '0')}日';

String _formatClock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.footnote,
    this.onEdit,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final List<(String, String)> rows;
  final String footnote;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 24),
            for (final (label, value) in rows)
              _DetailRow(label: label, value: value),
            if (footnote.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(footnote, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (onEdit != null || onDelete != null) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  if (onEdit != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('编辑'),
                      ),
                    ),
                  if (onEdit != null && onDelete != null)
                    const SizedBox(width: 12),
                  if (onDelete != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const List<String> _weekdayNames = [
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
