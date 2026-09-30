import 'package:flutter_test/flutter_test.dart';
import 'package:nbcc_schedule/import/school_config.dart';
import 'package:nbcc_schedule/import/school_picker.dart';

void main() {
  group('学校配置', () {
    test('本校配置：端点齐全、走自动导入、固定移动端 UA', () {
      final school = nbccSchool;

      expect(school.id, 'nbcc');
      expect(school.autoImport, isTrue);
      expect(school.loginUrl, startsWith('https://'));
      expect(school.hasCourseTablePage, isTrue);
      expect(school.courseTablePageUri!.host, 'jwgl.webvpn.nbcc.cn');
      expect(school.courseTableActionPath, startsWith('/'));
      expect(school.userAgent, androidMobileUserAgent);
      expect(school.startDate, isNotNull);
    });

    test('课表接口必须是相对路径，否则注入 fetch 时会跨域', () {
      expect(nbccSchool.courseTableActionPath.startsWith('/'), isTrue);
      expect(nbccSchool.courseTableActionPath.contains('://'), isFalse);
    });

    test('手动配置：没有预置端点，不走自动导入', () {
      final school = SchoolConfig.manual('https://jw.example.edu.cn/');

      expect(school.autoImport, isFalse);
      expect(school.courseTablePageUrl, isEmpty);
      expect(school.courseTableActionPath, isEmpty);
      expect(school.hasCourseTablePage, isFalse);
      expect(school.courseTablePageUri, isNull);
    });

    test('学校名会用作课表名，未知学校退回默认名', () {
      expect(nbccSchool.tableName, '宁波城市职业技术学院');
      expect(SchoolConfig.manual('https://a.cn/').tableName, '我的课表');
    });
  });

  group('教务网址补全与校验', () {
    test('缺协议头时补成 https', () {
      expect(normalizeSchoolUrl('jw.example.edu.cn'), 'https://jw.example.edu.cn');
    });

    test('已经带协议的地址原样保留，含参数也不动', () {
      const url = 'http://jw.example.edu.cn/login?x=1';
      expect(normalizeSchoolUrl(url), url);
    });

    test('首尾空白会被去掉', () {
      expect(
        normalizeSchoolUrl('  jw.example.edu.cn  '),
        'https://jw.example.edu.cn',
      );
    });

    test('空串、纯空白、没有主机名的一律判为不可用', () {
      expect(normalizeSchoolUrl(''), isNull);
      expect(normalizeSchoolUrl('   '), isNull);
      expect(normalizeSchoolUrl('https://'), isNull);
    });

    test('非 http/https 协议被挡掉，避免把本地路径填进来', () {
      expect(normalizeSchoolUrl('file:///etc/passwd'), isNull);
      expect(normalizeSchoolUrl('ftp://a.cn'), isNull);
    });
  });
}