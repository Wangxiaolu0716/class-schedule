import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/course.dart';
import '../parsers/course_table_parser.dart';
import '../parsers/eams_course_table_parser.dart';
import 'course_cache.dart';
import 'school_config.dart';

/// 导入结果：课表数据 + 用的是哪份学校配置
class ImportResult {
  const ImportResult({required this.data, required this.school});

  final CourseTableData data;

  /// 用来给课表起名、定开学日期
  final SchoolConfig school;
}

/// 用 WebView 导入课表，支持两种模式。
///
/// **自动模式**（[SchoolConfig.autoImport] 为 true，即预置了端点的学校）：
/// 用户自行登录，App 识别「我的课表」入口页、自行请求课表接口并解析，
/// 成功就自动返回。宁波城市职业技术学院走的就是这条。
///
/// **手动模式**（其它学校）：各校系统不同、端点无法预知，因此不猜——用户自己
/// 登录并翻到课表页，点右下角「导课」，App 抓取当前**渲染后**的页面结构交给
/// 解析器。参考项目 WakeUp 也是这个思路，区别是他们靠人工点按钮，我们还能
/// 自动识别页面参数。
///
/// 登录凭据始终由用户在真实的教务系统页面里输入，App 不接触账号密码。
class WebViewImportScreen extends StatefulWidget {
  const WebViewImportScreen({super.key, required this.school});

  final SchoolConfig school;

  @override
  State<WebViewImportScreen> createState() => _WebViewImportScreenState();
}

class _WebViewImportScreenState extends State<WebViewImportScreen> {
  final CourseCache _cache = const CourseCache();
  late final WebViewController _controller;

  late String _status = widget.school.autoImport
      ? '请在下方页面登录 WebVPN'
      : '请先登录，再翻到能看全整张课表的页面';

  /// 正在抓取，避免重复触发
  bool _capturing = false;

  /// 最近一次课表请求的失败原因（成功或未发起时为 null），仅自动模式用
  String? _fetchError;

  /// 手动模式下是否使用桌面端 UA
  bool _desktopMode = false;

  SchoolConfig get _school => widget.school;

  /// 当前该用的 User-Agent；空串表示不改 WebView 默认值
  String get _userAgent =>
      _desktopMode ? desktopUserAgent : _school.userAgent;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _onPageFinished,
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              setState(() => _status = '页面加载失败：${error.description}');
            }
          },
        ),
      );
    _applyUserAgent();
    _prepareAndLoad();
  }

  void _applyUserAgent() {
    if (_userAgent.isNotEmpty) _controller.setUserAgent(_userAgent);
  }

  /// 先完成平台相关配置，再加载入口页。
  Future<void> _prepareAndLoad() async {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // WebVPN 重写后的页面会用 http 加载样式与脚本等资源，
      // WebView 默认会拦截这种「混合内容」，页面就只剩没有样式的纯文字。
      await platform.setMixedContentMode(MixedContentMode.alwaysAllow);
    }
    await _controller.loadRequest(Uri.parse(_school.loginUrl));
  }

  Future<void> _onPageFinished(String url) async {
    // 手动模式一律不自动抓：用户还在自己翻页面，突然弹走会很突兀
    if (!mounted || _capturing || !_school.autoImport) return;
    await _captureIfCourseTable();
  }

  // ------------------------------------------------------------ 自动模式

  /// 当前页面若已是课表页就解析并返回。返回 true 表示导入已结束。
  Future<bool> _captureIfCourseTable() async {
    _capturing = true;
    _fetchError = null;
    try {
      var html = await _readPageHtml();

      // 「我的课表」入口页本身不含课表：课表由页面以 AJAX 填进 contentDiv。
      // 但该页依赖的框架脚本（jQuery / Beangle 的 bg.*）在 WebVPN 下
      // 加载失败，直接调用页面自己的 searchTable() 会静默抛错，
      // 因此这里用原生 fetch 自行请求课表接口。
      //
      // 触发条件不是「含 contentDiv」，而是「能提取出候选参数」：
      // 入口页的结构未必都带 contentDiv，只认它会漏掉整类页面。
      var attempted = 0;
      if (!html.contains('new TaskActivity')) {
        final candidates =
            EamsCourseTableParser.buildCourseTableParamsCandidates(html);

        for (var i = 0; i < candidates.length; i++) {
          attempted++;
          if (mounted) {
            setState(
              () => _status = '正在加载课表…（第 $attempted/${candidates.length} 种参数）',
            );
          }
          final response = await _fetchCourseTable(candidates[i]);
          if (response == null) continue; // 网络/HTTP 层失败，原因已记在 _fetchError
          if (response.contains('new TaskActivity')) {
            html = response;
            break;
          }
          // 服务端有返回但不含课表：这是定位问题的关键证据，落盘留存
          await _cache.saveDebugPage(response, tag: 'response');
        }
      }

      if (!html.contains('new TaskActivity')) {
        if (mounted) {
          final reason = _fetchError;
          setState(() {
            _status = reason == null
                ? '请在页面中进入：课程管理 → 我的课表'
                : '课表抓取失败（$reason），可点右上角导出后反馈';
          });
        }
        return false;
      }

      return await _finish(html, const EamsCourseTableParser().parse(html));
    } finally {
      _capturing = false;
    }
  }

  /// 在页面里用原生 `fetch` 请求课表接口，返回响应文本。
  ///
  /// 不使用页面自身的 jQuery / `bg.*`（它们在 WebVPN 下加载失败），
  /// 只用浏览器原生能力；与页面同源，Cookie 会自动携带。
  ///
  /// HTTP 或网络层失败时返回 null，并把原因记到 [_fetchError]。
  Future<String?> _fetchCourseTable(String body) async {
    final script = '''
window.__nbccState = 'pending';
window.__nbccHtml = '';
fetch('${_school.courseTableActionPath}', {
  method: 'POST',
  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
  credentials: 'same-origin',
  body: ${jsonEncode(body)}
}).then(function (response) {
  if (!response.ok) {
    window.__nbccState = 'http-' + response.status;
    return '';
  }
  return response.text();
}).then(function (text) {
  if (text) {
    window.__nbccHtml = text;
    window.__nbccState = 'ok';
  }
}).catch(function (error) {
  window.__nbccState = 'error:' + error;
});
'triggered'
''';
    await _evaluateJs(script);

    for (var attempt = 0; attempt < 25; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return null;
      final state = await _evaluateJs('String(window.__nbccState)');
      if (state.contains('ok')) {
        final html = await _evaluateJs('String(window.__nbccHtml)');
        return html.isEmpty ? null : html;
      }
      if (state.contains('http-') || state.contains('error:')) {
        _fetchError = '请求失败：$state';
        return null;
      }
    }
    _fetchError = '请求超时';
    return null;
  }

  /// 直接跳转到预置的「我的课表」入口页
  Future<void> _openCourseTable() async {
    final uri = _school.courseTablePageUri;
    if (uri == null) return;
    setState(() => _status = '正在打开「我的课表」…');
    await _controller.loadRequest(uri);
  }

  // ------------------------------------------------------------ 手动模式

  /// 手动导课：抓当前**渲染后**的页面，交给解析器。
  ///
  /// 刻意不主动请求任何接口：各校课表接口路径不同，猜不出来，硬猜只会失败得
  /// 更隐蔽。而用户既然已经把页面翻到课表页了，页面自己的 JS 早已把表格画好，
  /// 直接读 DOM 拿到的就是成品数据。
  ///
  /// 事先不知道对方用的是哪套教务系统，所以已支持的解析器挨个试。
  Future<void> _captureManually() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _status = '正在读取当前页面…';
    });

    try {
      final html = await _readPageHtml();
      final parsed = parseWithAny(html);

      if (parsed == null) {
        if (!mounted) return;
        setState(() {
          _status = '这一页没找到课表。请先翻到能看全整张课表的页面，再点「导课」；'
              '若确实停在课表页仍失败，可到「课表设置 → 诊断 → 解析诊断」看具体原因。';
        });
        return;
      }

      await _finish(html, parsed.data);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// 切换桌面 / 手机 User-Agent。
  ///
  /// 换 UA 必须重新加载：页面是旧 UA 渲染出来的那版，不重载等于没切。
  Future<void> _toggleUserAgent() async {
    final current = await _controller.currentUrl();
    setState(() {
      _desktopMode = !_desktopMode;
      _status = _desktopMode
          ? '已切到桌面模式，正在重新加载…'
          : '已切回手机模式，正在重新加载…';
    });
    _applyUserAgent();
    if (current != null) {
      await _controller.loadRequest(Uri.parse(current));
    }
  }

  // ------------------------------------------------------------ 公共部分

  /// 解析成功后的收尾：存缓存、带着结果返回
  Future<bool> _finish(String html, CourseTableData data) async {
    if (data.sessions.isEmpty) {
      if (mounted) {
        setState(() => _status = '页面里没解析到课程，请确认已经打开课表页');
      }
      return false;
    }

    await _cache.save(html);
    if (!mounted) return true;
    Navigator.of(context).pop(ImportResult(data: data, school: _school));
    return true;
  }

  /// 收集当前页面及所有同源子框架的 HTML。
  ///
  /// 教务系统普遍使用 frameset 框架页，课表常嵌在子框架里，
  /// 只读顶层 `documentElement` 会漏掉真正的内容。
  ///
  /// 分隔标记由 [EamsCourseTableParser.frameMarker] 统一定义，
  /// 解析时据此把各框架拆开（避免跨框架取到别的表单的参数）。
  static String get _collectHtmlJs => '''
(function () {
  var parts = [];
  function walk(w, depth) {
    var header = '${EamsCourseTableParser.frameMarker}' + depth + '-->';
    try {
      parts.push(header + '\\n' + w.document.documentElement.outerHTML);
    } catch (e) {
      parts.push(header + ' 无法读取: ' + e);
    }
    try {
      for (var i = 0; i < w.frames.length; i++) {
        walk(w.frames[i], depth + 1);
      }
    } catch (e) {}
  }
  walk(window, 0);
  return parts.join('\\n\\n');
})()
''';

  /// 读取当前页面（含子框架）的完整 HTML
  Future<String> _readPageHtml() => _evaluateJs(_collectHtmlJs);

  Future<String> _evaluateJs(String script) async {
    final result = await _controller.runJavaScriptReturningResult(script);
    final text = result.toString();
    // iOS 侧返回的是 JSON 字符串，需要剥掉外层引号
    if (text.length > 1 && text.startsWith('"') && text.endsWith('"')) {
      try {
        return jsonDecode(text) as String;
      } catch (_) {
        return text;
      }
    }
    return text;
  }

  /// 导出当前页面 HTML，用于排查解析问题
  Future<void> _exportCurrentPage() async {
    final html = await _readPageHtml();
    final path = await _cache.saveDebugPage(html);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已导出到：$path'),
        duration: const Duration(seconds: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auto = _school.autoImport;

    return Scaffold(
      appBar: AppBar(
        title: Text(auto ? '登录并导入课表' : '手动导课'),
        actions: [
          if (auto && _school.hasCourseTablePage)
            IconButton(
              tooltip: '打开我的课表',
              onPressed: _openCourseTable,
              icon: const Icon(Icons.table_chart_outlined),
            ),
          if (!auto)
            IconButton(
              tooltip: _desktopMode ? '切回手机模式' : '切到桌面模式',
              onPressed: _toggleUserAgent,
              icon: Icon(
                _desktopMode ? Icons.smartphone : Icons.desktop_windows_outlined,
              ),
            ),
          IconButton(
            tooltip: '导出当前页面 HTML（排查用）',
            onPressed: _exportCurrentPage,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(_status, style: const TextStyle(fontSize: 13)),
                ),
                // 教务系统页面走 WebVPN 后样式往往会丢失、只剩链接列表，
                // 直接给出跳转入口，避免用户在没有样式的菜单里翻找
                if (auto && _school.hasCourseTablePage)
                  TextButton(
                    onPressed: _openCourseTable,
                    child: const Text('直达我的课表'),
                  ),
              ],
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
      floatingActionButton: auto
          ? null
          : FloatingActionButton.extended(
              onPressed: _capturing ? null : _captureManually,
              icon: const Icon(Icons.download_for_offline_outlined),
              label: const Text('导课'),
            ),
    );
  }
}