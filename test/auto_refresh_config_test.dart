import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/import/school_config.dart';
import 'package:nbcc_schedule/models/table_config.dart';

void main() {
  group('自动刷新相关的设置', () {
    test('默认关闭：不做任何网络请求', () {
      expect(const TableConfig().autoRefresh, isFalse);
    });

    test('开关存得进配置，重新导入也不会被冲掉', () {
      const previous = TableConfig(autoRefresh: true);
      final fresh = TableConfig.initialFor(
        name: '某校',
        maxPeriod: 10,
        maxWeek: 18,
      );

      final merged = TableConfig.mergeImport(fresh: fresh, previous: previous);
      final restored = TableConfig.fromJson(
        jsonDecode(jsonEncode(merged.toJson())) as Map<String, dynamic>,
      );

      expect(merged.autoRefresh, isTrue);
      expect(restored.autoRefresh, isTrue);
    });

    test('老配置里没有这个字段时按关闭处理', () {
      final config = TableConfig.fromJson({'name': '我的课表'});

      expect(config.autoRefresh, isFalse);
    });
  });

  group('上次导入的学校', () {
    const school = SchoolConfig(
      id: 'remote',
      name: '宁波城市职业技术学院',
      loginUrl: 'https://ids.example.edu.cn/',
      courseTablePageUrl:
          'https://example.edu.cn/eams/courseTableForStd.action',
      courseTableActionPath: '/eams/courseTableForStd!courseTable.action',
      autoImport: true,
    );

    test('序列化后能原样读回来，静默刷新才知道去哪个入口', () {
      final restored = SchoolConfig.fromJson(
        jsonDecode(jsonEncode(school.toJson())) as Map<String, dynamic>,
      );

      expect(restored, isNotNull);
      expect(restored!.loginUrl, school.loginUrl);
      expect(restored.courseTablePageUrl, school.courseTablePageUrl);
      expect(restored.courseTableActionPath, school.courseTableActionPath);
      expect(restored.autoImport, isTrue);
    });

    test('没有入口地址的记录等于没存过，别拿它去发请求', () {
      expect(SchoolConfig.fromJson(const {}), isNull);
      expect(SchoolConfig.fromJson(const {'name': '某校'}), isNull);
    });
  });
}
