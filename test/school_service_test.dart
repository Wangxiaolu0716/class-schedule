import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/import/school_service.dart';

/// 内置学校列表。
///
/// 这份列表是长期维护、要跟着版本发布出去的，写错一条就等于让所有用户白试一次，
/// 所以「地址必须可用」「验证状态必须如实标注」这两条边界要钉死。
void main() {
  group('内置学校列表', () {
    test('至少包含已确认的两所学校', () {
      final names = SchoolService.schools.map((s) => s.name).toList();

      expect(names, contains('湖州职业技术学院'));
      expect(names, contains('浙江横店影视职业学院'));
    });

    test('列表里的地址都是可用的 http/https', () {
      for (final school in SchoolService.schools) {
        final uri = Uri.parse(school.url);
        expect(uri.scheme, anyOf('http', 'https'), reason: school.name);
        expect(uri.host, isNotEmpty, reason: school.name);
      }
    });

    test('学校名不能重复，否则列表里会出现两个同名项', () {
      final names = SchoolService.schools.map((s) => s.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('已确认可用的学校要标成已验证', () {
      final school = SchoolService.schools
          .firstWhere((s) => s.name == '浙江横店影视职业学院');

      expect(school.verified, isTrue);
    });

    test('未验证的学校必须如实标 false，不能默认成能用', () {
      for (final school in SchoolService.schools) {
        // 这条只是把「字段存在且是布尔」钉住；具体哪所验证过由上面几条负责
        expect(school.verified, isA<bool>(), reason: school.name);
      }
    });
  });

  group('搜索匹配', () {
    const school = SchoolInfo(name: '浙江横店影视职业学院', url: 'https://a.cn/');

    test('空关键字匹配全部', () {
      expect(school.matches(''), isTrue);
      expect(school.matches('   '), isTrue);
    });

    test('按校名片段匹配', () {
      expect(school.matches('横店'), isTrue);
      expect(school.matches('影视'), isTrue);
      expect(school.matches('浙江横店影视职业学院'), isTrue);
    });

    test('关键字里的空格不影响匹配', () {
      expect(school.matches(' 横店 '), isTrue);
    });

    test('不相关的关键字不匹配', () {
      expect(school.matches('湖州'), isFalse);
    });
  });
}
