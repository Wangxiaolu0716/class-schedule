/// 导入课表所需的「学校相关」配置。
///
/// 关键认知：解析层（[EamsCourseTableParser]）解析的是正方 EAMS 的标准格式
/// ——`TaskActivity` 数组、`index = 星期 × unitCount + 节次`、周次位图——
/// 这些与具体学校无关。真正因校而异的是下面这些东西：从哪个入口登录、
/// 「我的课表」页和课表接口的路径、用哪个 User-Agent、第一周从哪天算起。
///
/// 所以新增一所学校时，改的应该是这里的配置，而不是解析器。
library;

/// 固定的安卓移动端 UA。
///
/// 本校 WebVPN 门户的桌面端登录流程不可用（只有手机端能登进去），
/// 因此强制使用移动端 UA，保证 WebView 始终走移动端通道。
/// 对其它学校来说这也是个合理的默认值。
const String androidMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// 桌面端 UA，手动导课时可以切过去。
///
/// 不少学校的教务系统按 UA 返回不同页面：拿手机 UA 访问可能只给一个
/// 精简版、甚至根本进不去。这种时候切到桌面 UA 往往就能看到完整课表，
/// 参考项目 WakeUp 也提供了「电脑模式」这个开关。
const String desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 正方 EAMS 课表接口的默认相对路径。
///
/// 学校列表里没单独写 `courseTableActionPath` 时用它。必须是相对路径：
/// 这段会被注入页面，以同源方式 fetch，写成绝对地址会跨域。
const String eamsCourseTableActionPath =
    '/eams/courseTableForStd!courseTable.action';

/// 一所学校的导入配置
class SchoolConfig {
  const SchoolConfig({
    required this.id,
    required this.name,
    required this.loginUrl,
    this.fallbackLoginUrl = '',
    this.courseTablePageUrl = '',
    this.courseTableActionPath = '',
    this.userAgent = '',
    this.startDate,
    this.autoImport = false,
  });

  /// 「其它学校」：只给一个登录入口，没有任何预置端点。
  ///
  /// 各校系统不同，无法预知课表接口，也不该去猜，因此这类配置一律
  /// 走手动导课：用户自己在页面里翻到课表页，再点按钮抓取。
  factory SchoolConfig.manual(String loginUrl, {String name = ''}) =>
      SchoolConfig(
        id: 'manual',
        name: name,
        loginUrl: loginUrl,
        userAgent: androidMobileUserAgent,
      );

  /// 「AI 识别导入」：课表由用户粘回来的 AI 结果决定，不需要登录任何站点。
  ///
  /// 没有课表页也就拿不到开学日期，所以 [startDate] 留空，
  /// 导入完成后沿用既有的「引导用户去设置开学时间」那条路。
  factory SchoolConfig.aiImport() => SchoolConfig(
    id: 'ai',
    name: '',
    loginUrl: '',
    userAgent: androidMobileUserAgent,
  );

  /// 内部标识，用于区分不同学校的配置
  final String id;

  /// 学校名，会用作课表默认名称；空串表示未知学校
  final String name;

  /// 登录入口地址。自动模式下是学校门户，手动模式下由用户自己填
  final String loginUrl;

  /// 主入口打不开时的备用入口；空串表示没有。
  ///
  /// 学校换统一身份认证域名时，新域名未必立刻对所有网络可达（校园网内外
  /// 解析可能不同），留一条旧入口兜底，总比让用户对着「页面加载失败」强。
  final String fallbackLoginUrl;

  /// 「我的课表」入口页完整地址，只有自动模式用得上
  final String courseTablePageUrl;

  /// 课表数据接口路径。用相对路径，因为它是注入到页面里以同源方式请求的
  final String courseTableActionPath;

  /// 固定 User-Agent；空串表示不改 WebView 默认值
  final String userAgent;

  /// 第一周起始日；为空表示不预设
  final DateTime? startDate;

  /// 是否走「主动识别页面 + 自动抓取接口」。
  ///
  /// 只有预置了端点的学校才是 true。
  final bool autoImport;

  /// 是否走「AI 识别导入」：课表来自用户粘回来的 AI 结果，不经过 WebView
  bool get isAiImport => id == 'ai';

  /// 「我的课表」入口页地址；未配置时为 null
  Uri? get courseTablePageUri =>
      courseTablePageUrl.isEmpty ? null : Uri.tryParse(courseTablePageUrl);

  /// 备用登录入口；未配置时为 null
  Uri? get fallbackLoginUri =>
      fallbackLoginUrl.isEmpty ? null : Uri.tryParse(fallbackLoginUrl);

  /// 是否配置了「直达我的课表」的入口
  bool get hasCourseTablePage => courseTablePageUri != null;

  /// 课表的默认名称
  String get tableName => name.trim().isEmpty ? '我的课表' : name;

  /// 存盘用：静默刷新要认得上次是从哪所学校导进来的
  Map<String, dynamic> toJson() => {
    'name': name,
    'loginUrl': loginUrl,
    'fallbackLoginUrl': fallbackLoginUrl,
    'courseTablePageUrl': courseTablePageUrl,
    'courseTableActionPath': courseTableActionPath,
    'userAgent': userAgent,
    'startDate': startDate?.toIso8601String(),
    'autoImport': autoImport,
  };

  static SchoolConfig? fromJson(Map<String, dynamic> json) {
    final loginUrl = json['loginUrl'] as String? ?? '';
    final pageUrl = json['courseTablePageUrl'] as String? ?? '';
    // 没有入口地址就没有刷新可言，直接当作没存过
    if (loginUrl.isEmpty && pageUrl.isEmpty) return null;
    final rawDate = json['startDate'] as String?;
    return SchoolConfig(
      id: 'last',
      name: json['name'] as String? ?? '',
      loginUrl: loginUrl,
      fallbackLoginUrl: json['fallbackLoginUrl'] as String? ?? '',
      courseTablePageUrl: pageUrl,
      courseTableActionPath: json['courseTableActionPath'] as String? ?? '',
      userAgent: json['userAgent'] as String? ?? '',
      startDate: rawDate == null ? null : DateTime.tryParse(rawDate),
      autoImport: json['autoImport'] as bool? ?? false,
    );
  }
}

/// 宁波城市职业技术学院（当前仅验证鄞州校区）
///
/// 这条配置现在只作**离线兜底**：线上以服务器 `schools.json` 里同名那条为准，
/// 改入口地址不用发版。这里保留一份，是为了学校列表拉不到时 App 还能用。
final SchoolConfig nbccSchool = SchoolConfig(
  id: 'nbcc',
  name: '宁波城市职业技术学院',
  // 学校新的统一身份认证入口。主地址打不开时退回熟悉的 WebVPN 登录页。
  loginUrl: 'https://ids.nbcc.cn/',
  fallbackLoginUrl: 'https://webvpn.nbcc.edu.cn/login',
  // 登录成功后要去的「我的课表」页。学校 2026-10 换成了新版 WebVPN：
  // 后端主机被编成 /http/<hex>/ 这段固定前缀（不随会话变化，别改成别的域名）。
  courseTablePageUrl:
      'https://webvpn.nbcc.edu.cn'
      '/http/77726476706e69737468656265737421fae04690693e6a537d468aa2'
      '/eams/courseTableForStd.action',
  courseTableActionPath: eamsCourseTableActionPath,
  userAgent: androidMobileUserAgent,
  // 教务系统不提供开学日期（课表页里既无钟点也无日期），这里给默认值。
  // 依据：教务系统移动端显示「第 5 周 = 10-05 ~ 10-11」，反推第 1 周为 09-07。
  startDate: DateTime(2026, 9, 7),
  autoImport: true,
);

/// 缓存里没有配置、又走到「按数据生成初始配置」时的兜底开学日期。
///
/// 正常流程不会用到：首次导入会带上所选学校的 [SchoolConfig.startDate]。
final DateTime fallbackSemesterStart = DateTime(2026, 9, 7);
