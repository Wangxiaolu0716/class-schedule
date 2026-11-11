/// 学校的作息时间表预设。
///
/// 教务系统的课表只给到「第几节有课」，不含钟点，因此默认只能套一份通用作息。
/// 但有些学校的作息是有官方时间表的（还分夏令/冬令两套），用户自己一节节敲
/// 既麻烦又容易敲错，所以这里按学校名内置一份，导入完让用户挑一个直接套用。
///
/// 判定只能靠学校名：学校列表在服务器上，App 里拿到的就是名字与网址，
/// 网址还可能随统一身份认证的 ticket 变化，用名字匹配最稳。
library;

import 'table_config.dart';

/// 一所学校的一套作息（如夏令时间 / 冬令时间）
class PeriodPreset {
  const PeriodPreset({required this.label, required this.times});

  /// 显示名，如「夏令时间」
  final String label;

  /// 各节起止时间
  final List<PeriodTime> times;
}

/// 按学校名找内置作息预设；没有对应学校时返回空列表
List<PeriodPreset> periodPresetsFor(String schoolName) {
  final name = schoolName.replaceAll(RegExp(r'\s+'), '');
  if (name.contains('湖州职业技术学院')) return huzhouPresets;
  if (name.contains('宁波城市职业技术学院')) return nbccPresets;
  return const [];
}

/// 湖州职业技术学院 2026-2027 学年作息时间表。
///
/// 两套的差别只在下午第 5-8 节：夏令 5 月 1 日起用、冬令 10 月 1 日起用，
/// 上午与晚间的节次完全一致。
const List<PeriodPreset> huzhouPresets = [
  PeriodPreset(label: '夏令时间', times: [
    PeriodTime(period: 1, start: '08:15', end: '09:00'),
    PeriodTime(period: 2, start: '09:05', end: '09:50'),
    PeriodTime(period: 3, start: '10:10', end: '10:55'),
    PeriodTime(period: 4, start: '11:00', end: '11:45'),
    PeriodTime(period: 5, start: '13:45', end: '14:30'),
    PeriodTime(period: 6, start: '14:35', end: '15:20'),
    PeriodTime(period: 7, start: '15:40', end: '16:25'),
    PeriodTime(period: 8, start: '16:30', end: '17:15'),
    PeriodTime(period: 9, start: '18:30', end: '19:15'),
    PeriodTime(period: 10, start: '19:20', end: '20:05'),
    PeriodTime(period: 11, start: '20:10', end: '20:55'),
  ]),
  PeriodPreset(label: '冬令时间', times: [
    PeriodTime(period: 1, start: '08:15', end: '09:00'),
    PeriodTime(period: 2, start: '09:05', end: '09:50'),
    PeriodTime(period: 3, start: '10:10', end: '10:55'),
    PeriodTime(period: 4, start: '11:00', end: '11:45'),
    PeriodTime(period: 5, start: '13:15', end: '14:00'),
    PeriodTime(period: 6, start: '14:05', end: '14:50'),
    PeriodTime(period: 7, start: '15:10', end: '15:55'),
    PeriodTime(period: 8, start: '16:00', end: '16:45'),
    PeriodTime(period: 9, start: '18:30', end: '19:15'),
    PeriodTime(period: 10, start: '19:20', end: '20:05'),
    PeriodTime(period: 11, start: '20:10', end: '20:55'),
  ]),
];

/// 宁波城市职业技术学院 2026-2027 学年作息时间表（校历备注第 3 条）。
///
/// 上午 1-4 节冬夏一致，从第 5 节起分两套：校历规定 5 月第一个完整周起
/// 用夏令时、11 月第一个完整周起用冬令时。两个校区时间不同，各列两套，
/// 导入后按自己所在校区挑一套即可（之后在课表设置里也能换）。
const List<PeriodPreset> nbccPresets = [
  PeriodPreset(label: '鄞州校区 · 夏令时间', times: [
    PeriodTime(period: 1, start: '08:15', end: '09:00'),
    PeriodTime(period: 2, start: '09:05', end: '09:50'),
    PeriodTime(period: 3, start: '10:05', end: '10:50'),
    PeriodTime(period: 4, start: '10:55', end: '11:40'),
    PeriodTime(period: 5, start: '13:30', end: '14:15'),
    PeriodTime(period: 6, start: '14:20', end: '15:05'),
    PeriodTime(period: 7, start: '15:20', end: '16:05'),
    PeriodTime(period: 8, start: '16:10', end: '16:55'),
    PeriodTime(period: 9, start: '17:05', end: '18:20'),
    PeriodTime(period: 10, start: '18:30', end: '19:15'),
    PeriodTime(period: 11, start: '19:20', end: '20:05'),
    PeriodTime(period: 12, start: '20:10', end: '20:55'),
  ]),
  PeriodPreset(label: '鄞州校区 · 冬令时间', times: [
    PeriodTime(period: 1, start: '08:15', end: '09:00'),
    PeriodTime(period: 2, start: '09:05', end: '09:50'),
    PeriodTime(period: 3, start: '10:05', end: '10:50'),
    PeriodTime(period: 4, start: '10:55', end: '11:40'),
    PeriodTime(period: 5, start: '13:00', end: '13:45'),
    PeriodTime(period: 6, start: '13:50', end: '14:35'),
    PeriodTime(period: 7, start: '14:50', end: '15:35'),
    PeriodTime(period: 8, start: '15:40', end: '16:25'),
    PeriodTime(period: 9, start: '16:35', end: '17:50'),
    PeriodTime(period: 10, start: '18:00', end: '18:45'),
    PeriodTime(period: 11, start: '18:50', end: '19:35'),
    PeriodTime(period: 12, start: '19:40', end: '20:25'),
  ]),
  PeriodPreset(label: '奉化校区 · 夏令时间', times: [
    PeriodTime(period: 1, start: '08:40', end: '09:20'),
    PeriodTime(period: 2, start: '09:25', end: '10:05'),
    PeriodTime(period: 3, start: '10:15', end: '10:55'),
    PeriodTime(period: 4, start: '11:00', end: '11:40'),
    PeriodTime(period: 5, start: '13:15', end: '13:55'),
    PeriodTime(period: 6, start: '14:00', end: '14:40'),
    PeriodTime(period: 7, start: '14:50', end: '15:30'),
    PeriodTime(period: 8, start: '15:35', end: '16:15'),
    PeriodTime(period: 9, start: '16:30', end: '17:10'),
    PeriodTime(period: 10, start: '17:40', end: '18:20'),
    PeriodTime(period: 11, start: '18:25', end: '19:05'),
    PeriodTime(period: 12, start: '19:15', end: '19:55'),
    PeriodTime(period: 13, start: '20:00', end: '20:40'),
  ]),
  PeriodPreset(label: '奉化校区 · 冬令时间', times: [
    PeriodTime(period: 1, start: '08:40', end: '09:20'),
    PeriodTime(period: 2, start: '09:25', end: '10:05'),
    PeriodTime(period: 3, start: '10:15', end: '10:55'),
    PeriodTime(period: 4, start: '11:00', end: '11:40'),
    PeriodTime(period: 5, start: '13:00', end: '13:40'),
    PeriodTime(period: 6, start: '13:45', end: '14:25'),
    PeriodTime(period: 7, start: '14:35', end: '15:15'),
    PeriodTime(period: 8, start: '15:20', end: '16:00'),
    PeriodTime(period: 9, start: '16:15', end: '16:55'),
    PeriodTime(period: 10, start: '17:30', end: '18:10'),
    PeriodTime(period: 11, start: '18:15', end: '18:55'),
    PeriodTime(period: 12, start: '19:05', end: '19:45'),
    PeriodTime(period: 13, start: '19:50', end: '20:30'),
  ]),
];