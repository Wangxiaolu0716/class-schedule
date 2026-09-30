/// 学校列表里的一所学校
class SchoolInfo {
  const SchoolInfo({
    required this.name,
    required this.url,
    this.type = '',
    this.verified = false,
  });

  /// 学校名称，会用作课表默认名称
  final String name;

  /// 教务系统入口地址（登录页或统一身份认证页）
  final String url;

  /// 教务系统类型，如 `jwglxt`。目前只作记录：解析是挨个试的，不靠它猜
  final String type;

  /// 是否已经拿真实课表页验证过。没验证过的要如实标出来，
  /// 不能让用户以为「列表里有就一定能用」
  final bool verified;

  /// 搜索匹配：按校名做包含匹配，忽略大小写与空格
  bool matches(String keyword) {
    final query = keyword.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (query.isEmpty) return true;
    return name.replaceAll(RegExp(r'\s+'), '').toLowerCase().contains(query);
  }
}

/// 其它学校的列表。
///
/// 这份列表**直接内置在包里，不依赖任何服务器**，因此 App 完全离线也能选学校，
/// 也不会因为某个接口挂了就用不了。
///
/// 代价是加学校要改代码、发新版本。只收录**已验证可用**或**明确标注待验证**的
/// 学校：解析器目前只覆盖正方 EAMS 与新版 jwglxt 两套体系，放一堆支持不了的
/// 学校进去，只会让用户白试一遍，所以宁可列表短。
///
/// 想加学校请提 issue（模板见仓库 `.github/ISSUE_TEMPLATE/`），
/// 附上教务系统入口地址与系统类型即可，验证通过后会被加进这里。
class SchoolService {
  const SchoolService();

  /// 内置学校列表
  static const List<SchoolInfo> schools = [
    SchoolInfo(
      name: '湖州职业技术学院',
      url: 'https://cas.huvtc.edu.cn/login?service=https%3A%2F%2Fcas.huvtc.edu.cn'
          '%2Fapi%2Fblade-auth%2Fcas%2FcreateTicket%3Fservice%3Dhttp%3A%2F%2F'
          'jwxt.huvtc.edu.cn%2Fjwglxt%2Fxtgl%2Findex_initMenu.html',
      type: 'jwglxt',
      verified: true,
    ),
    SchoolInfo(
      name: '浙江横店影视职业学院',
      url: 'http://jwgl.hcft.edu.cn/jwglxt/',
      type: 'jwglxt',
      verified: true,
    ),
  ];
}
