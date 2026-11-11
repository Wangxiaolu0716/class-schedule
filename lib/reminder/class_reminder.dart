import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import '../models/table_config.dart';

/// 提前多少分钟提醒
const int reminderLeadMinutes = 15;

/// 每次重排往后铺几天（正好一周，覆盖一轮完整的课表）
const int reminderHorizonDays = 7;

/// 一条课前提醒：什么时候弹、弹什么
class ClassReminder {
  const ClassReminder({
    required this.at,
    required this.title,
    required this.body,
  });

  /// 该弹通知的时刻（本机时间）
  final DateTime at;

  final String title;
  final String body;
}

/// 算出 [now] 之后、未来 [days] 天内要弹的全部课前提醒。
///
/// 纯计算，不碰插件也不碰文件，所以能直接单测。三件事要算对：
/// - 周次：由开学日期往后推，落在学期外的日子不要
/// - 星期：调休那天按另一天的课表上课
/// - 时间：钟点来自「上课时间」设置，取每节的开课时间往前 [leadMinutes] 分钟；
///   已经过去的时间点直接丢掉（今天上午开 App 不该补弹下午的课）
///
/// 同一格里撞在一起的两门课合成一条通知，免得同一分钟弹两下。
List<ClassReminder> upcomingClassReminders({
  required List<CourseSession> sessions,
  required TableConfig config,
  required DateTime now,
  int leadMinutes = reminderLeadMinutes,
  int days = reminderHorizonDays,
}) {
  final start = config.startDate;
  if (start == null) return const [];
  final first = DateTime(start.year, start.month, start.day);
  final today = DateTime(now.year, now.month, now.day);

  final atBySlot = <String, DateTime>{};
  final sessionsBySlot = <String, List<CourseSession>>{};

  for (var offset = 0; offset < days; offset++) {
    final date = today.add(Duration(days: offset));
    final passed = date.difference(first).inDays;
    if (passed < 0) continue;
    final week = passed ~/ 7 + 1;
    if (week > config.totalWeeks) continue;

    // 调休：这一天实际按哪个星期的课表上课
    final weekday = config.swapOn(date)?.sourceWeekday ?? date.weekday;

    for (final session in sessions) {
      if (session.dayOfWeek != weekday) continue;
      if (!session.hasClassInWeek(week)) continue;

      // 这一节还没配钟点就算不出来（上课时间没设置的节次）
      final time = config.timeOf(session.startPeriod);
      if (time == null) continue;
      final startsAt = _onDate(date, time.start);
      if (startsAt == null) continue;

      final at = startsAt.subtract(Duration(minutes: leadMinutes));
      if (!at.isAfter(now)) continue;

      final key = '${date.year}/${date.month}/${date.day}#${session.startPeriod}';
      atBySlot[key] = at;
      (sessionsBySlot[key] ??= []).add(session);
    }
  }

  final slots = atBySlot.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return [
    for (final slot in slots)
      ClassReminder(
        at: slot.value,
        title: '还有 $leadMinutes 分钟上课',
        body: _bodyOf(sessionsBySlot[slot.key]!),
      ),
  ];
}

/// 「第 1 节  高等数学 · 综合楼313」
String _bodyOf(List<CourseSession> sessions) {
  final first = sessions.first;
  final names = sessions.map((s) => s.name).toSet().join('、');
  final room = first.room.trim();
  return '第 ${first.startPeriod} 节  $names${room.isEmpty ? '' : ' · $room'}';
}

/// 把「08:15」这样的钟点拼到 [date] 那一天；认不出返回 null
DateTime? _onDate(DateTime date, String clock) {
  final parts = clock.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

/// 「课前通知」开关的本地存储，与其它设置一样放应用私有目录
class ReminderStore {
  const ReminderStore();

  static const String _fileName = 'class_reminder.txt';

  Future<bool> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    if (!await file.exists()) return false;
    return (await file.readAsString()).trim() == 'on';
  }

  Future<void> save(bool enabled) async {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/$_fileName').writeAsString(enabled ? 'on' : 'off');
  }
}

/// 课前通知：把「未来一周里每次上课前 15 分钟」排进系统通知队列。
///
/// 走系统闹钟，所以 App 没开着、被划掉也能弹。代价是队列有尽头：一次只排
/// 未来一周的量，每次打开 App（或改课表、改设置）都重排一次接着往下续，
/// 一周没碰过 App 就会断在最后一条之后。
class ClassReminderService {
  const ClassReminderService();

  /// 通知渠道 id。改它等于换一个渠道，用户对该渠道的免打扰设置会跟着重来
  static const String _channelId = 'class_reminder';

  /// 测试提醒占用的固定 id：正式提醒用 0 起的下标，不会撞上
  static const int _testId = 999999;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '课前提醒',
      channelDescription: '上课前 15 分钟提醒',
      importance: Importance.high,
      priority: Priority.high,
      // 通知栏的小图标：安卓只取它的 Alpha 通道再染白，所以这张是纯白日历剪影
      // （res/drawable-*/ic_stat_class.png，由 tools/make_icons.ps1 生成），
      // 不设的话会拿应用图标去染，整块变成方块
      icon: _notifIcon,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// 通知小图标的资源名。必须落在 res/drawable 下，插件是按 drawable 去找的
  static const String _notifIcon = 'ic_stat_class';

  /// 初始化插件与时区；重复调用无副作用
  Future<void> init() => _ensureReady();

  static Future<void> _ensureReady() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // 取不到设备时区就退回 UTC：闹钟会偏几个钟头，但总比抛异常把 App 拦在后面
      // （真机上这条路基本走不到，Android 一定给得出时区名）
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_notifIcon),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  Future<bool> isEnabled() => const ReminderStore().load();

  /// 已经排进系统的提醒条数，给设置页做副标题
  Future<int> scheduledCount() async {
    await _ensureReady();
    return (await _plugin.pendingNotificationRequests()).length;
  }

  /// 打开/关闭。打开时要权限，拿不到就保持关闭并返回 false——
  /// 免得界面上写着「已开启」却一条都不会响。
  Future<bool> setEnabled(
    bool enabled, {
    required List<CourseSession> sessions,
    required TableConfig config,
  }) async {
    await _ensureReady();

    if (!enabled) {
      await _plugin.cancelAll();
      await const ReminderStore().save(false);
      return true;
    }

    if (!await _requestPermissions()) {
      await const ReminderStore().save(false);
      return false;
    }

    await const ReminderStore().save(true);
    await sync(sessions: sessions, config: config);
    return true;
  }

  /// 发一条 10 秒后的测试提醒。
  ///
  /// 给「这会儿没课、想马上确认这台手机弹不弹得出来」用：锁屏等着看就行。
  /// 返回 false 表示通知权限没拿到（弹不出来，得先去系统设置里允许）。
  Future<bool> sendTest() async {
    await _ensureReady();
    if (!await _requestPermissions()) return false;
    await _plugin.zonedSchedule(
      id: _testId,
      title: '测试提醒：通知是通的',
      body: '正式提醒会在上课前 $reminderLeadMinutes 分钟弹出，就像这样',
      scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10)),
      notificationDetails: _details,
      androidScheduleMode: await _scheduleMode(),
    );
    return true;
  }

  /// 按当前课表重排未来一周的提醒；开关关着就只是清空
  Future<int> sync({
    required List<CourseSession> sessions,
    required TableConfig config,
  }) async {
    await _ensureReady();
    // 先清空再排：课表改了、调休改了，旧的提醒就都不作数了
    await _plugin.cancelAll();
    if (!await isEnabled()) return 0;

    final reminders = upcomingClassReminders(
      sessions: sessions,
      config: config,
      now: DateTime.now(),
    );
    final mode = await _scheduleMode();
    for (var i = 0; i < reminders.length; i++) {
      final reminder = reminders[i];
      await _plugin.zonedSchedule(
        id: i,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: mode,
      );
    }
    return reminders.length;
  }

  /// 精确闹钟权限没给时退回「大概时间」：可能晚几分钟，但总比不响强
  static Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return AndroidScheduleMode.exactAllowWhileIdle;
    final allowed = await android.canScheduleExactNotifications() ?? false;
    return allowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static Future<bool> _requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // Android 13 起通知要用户点头；精确闹钟在 14 起还要单独授权
      if (!(await android.requestNotificationsPermission() ?? false)) return false;
      if (!(await android.canScheduleExactNotifications() ?? false)) {
        await android.requestExactAlarmsPermission();
      }
      return true;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }
}