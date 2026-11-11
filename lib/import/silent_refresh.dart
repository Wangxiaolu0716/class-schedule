import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/course.dart';
import '../parsers/eams_course_table_parser.dart';
import 'course_cache.dart';
import 'course_table_fetch.dart';
import 'school_session.dart';
import 'school_config.dart';

/// 打开课表时静默刷一次教务。
///
/// 只有「能自动导课」的学校（配了课表页与接口路径）才走得通：其它学校要
/// 用户自己翻页面。全程不显示界面，登录态失效、超时、页面结构变了都只是
/// 悄悄放弃 —— 课表还是上次那份，绝不会因为刷新失败变成空白。
///
/// 用一个 1×1 的 WebView 干活：它必须真的挂在树上才拿得到渲染后的页面，
/// 但不需要被看见，也不接管点击。
class SilentCourseRefresher extends StatefulWidget {
  const SilentCourseRefresher({
    super.key,
    required this.school,
    required this.onDone,
    this.timeout = const Duration(seconds: 25),
  });

  final SchoolConfig school;

  /// 成功时给出解析好的课表（原始 HTML 已顺手写进缓存），失败给 null
  final ValueChanged<CourseTableData?> onDone;

  final Duration timeout;

  @override
  State<SilentCourseRefresher> createState() => _SilentCourseRefresherState();
}

class _SilentCourseRefresherState extends State<SilentCourseRefresher> {
  final CourseCache _cache = const CourseCache();
  late final WebViewController _controller;
  Timer? _timer;

  /// 只处理第一轮页面加载：重定向会连着触发多次 onPageFinished，
  /// 每次都跑一遍请求等于把教务系统敲十几下。
  bool _handled = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _onPageFinished,
          // 连不上就直接放弃，不打扰用户
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) _finish(null);
          },
        ),
      );
    _timer = Timer(widget.timeout, () => _finish(null));
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final userAgent = widget.school.userAgent;
    if (userAgent.isNotEmpty) _controller.setUserAgent(userAgent);

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // 与导入页一致：WebVPN 改写后的页面用 http 加载资源，
      // 不放行混合内容的话页面只剩没有样式的纯文字
      await platform.setMixedContentMode(MixedContentMode.alwaysAllow);
    }

    // 先恢复上次登录留下的 Cookie：没有它，静默刷新十有八九会掉回登录页
    await const SchoolSession().restore([
      widget.school.loginUrl,
      widget.school.courseTablePageUrl,
    ]);

    final entry =
        widget.school.courseTablePageUri ??
        Uri.tryParse(widget.school.loginUrl);
    if (entry == null) {
      _finish(null);
      return;
    }
    await _controller.loadRequest(entry);
  }

  Future<void> _onPageFinished(String url) async {
    if (_handled || _finished) return;
    _handled = true;

    try {
      final html = await CourseTableFetch.readHtml(_controller);
      // 掉回登录页了：要密码的地方没法替用户登，直接放弃
      if (_hasPasswordField(html)) {
        _finish(null);
        return;
      }
      if (CourseTableFetch.looksLikeCourseTable(html)) {
        await _finishWith(html);
        return;
      }

      // 入口页本身不含课表，得按候选参数请求一次接口。
      // 静默场景只试前几个候选，试太多会让「打开就刷新」变成几十秒的等待。
      final candidates = EamsCourseTableParser.buildCourseTableParamsCandidates(
        html,
      );
      for (final body in candidates.take(3)) {
        if (_finished) return;
        final result = await const CourseTableFetch().fetch(
          _controller,
          actionPath: widget.school.courseTableActionPath,
          body: body,
          attempts: 10,
        );
        final response = result.html;
        if (response != null &&
            CourseTableFetch.looksLikeCourseTable(response)) {
          await _finishWith(response);
          return;
        }
      }
      _finish(null);
    } catch (_) {
      _finish(null);
    }
  }

  Future<void> _finishWith(String html) async {
    final data = const EamsCourseTableParser().parse(html);
    if (data.sessions.isEmpty) {
      _finish(null);
      return;
    }
    // 先落盘再回调：万一回调里抛错，下次启动至少还有新数据
    try {
      await _cache.save(html);
      // 会话被服务端续过就把新的 Cookie 也存一份
      await const SchoolSession().save([
        widget.school.loginUrl,
        widget.school.courseTablePageUrl,
      ]);
    } catch (_) {
      // 存不下来也先把界面刷了，用户看到的是最新一版
    }
    _finish(data);
  }

  void _finish(CourseTableData? data) {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    widget.onDone(data);
  }

  static bool _hasPasswordField(String html) {
    final lower = html.toLowerCase();
    return lower.contains('type="password"') ||
        lower.contains("type='password'") ||
        lower.contains('type=password');
  }

  @override
  Widget build(BuildContext context) {
    // 1×1 挂在角落：看不见、不吃点击，但足够让平台视图真正初始化
    return IgnorePointer(
      child: SizedBox(
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0.01,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
