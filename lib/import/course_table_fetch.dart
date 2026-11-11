import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import '../parsers/eams_course_table_parser.dart';

/// 在教务系统页面里「读页面 / 请求课表接口」这两个动作。
///
/// 抽出来是因为导入页与静默刷新用的是同一段 JS：WebVPN 下页面自带的
/// jQuery / `bg.*` 加载失败，只能靠原生 fetch 自己请求接口，这套逻辑
/// 一处写错就两处都错，所以只留一份。
class CourseTableFetch {
  const CourseTableFetch();

  /// 读当前页面（含子框架）的完整 HTML
  static Future<String> readHtml(WebViewController controller) =>
      evaluateJs(controller, _collectHtmlJs);

  static Future<String> evaluateJs(
    WebViewController controller,
    String script,
  ) async {
    final result = await controller.runJavaScriptReturningResult(script);
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

  /// 用页面里的原生 `fetch` 请求课表接口，返回响应文本。
  ///
  /// 与页面同源，Cookie 会自动带上。失败时返回错误说明而不是抛异常：
  /// 调用点要拿它做「静默放弃 / 提示用户」的判断。
  Future<({String? html, String? error})> fetch(
    WebViewController controller, {
    required String actionPath,
    required String body,
    int attempts = 25,
  }) async {
    final script =
        '''
window.__nbccState = 'pending';
window.__nbccHtml = '';
fetch(${jsonEncode(actionPath)}, {
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
    await evaluateJs(controller, script);

    for (var attempt = 0; attempt < attempts; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      String state;
      try {
        state = await evaluateJs(controller, 'String(window.__nbccState)');
      } catch (_) {
        // 页面在请求途中被换掉（重定向）时读不到全局变量，按失败处理
        return (html: null, error: '页面已跳转');
      }
      if (state.contains('ok')) {
        final html = await evaluateJs(controller, 'String(window.__nbccHtml)');
        return html.isEmpty
            ? (html: null, error: '接口返回空内容')
            : (html: html, error: null);
      }
      if (state.contains('http-') || state.contains('error:')) {
        return (html: null, error: '请求失败：$state');
      }
    }
    return (html: null, error: '请求超时');
  }

  /// 拼好的课表 HTML 是否真的含课表
  static bool looksLikeCourseTable(String html) =>
      html.contains('new TaskActivity');

  static String get _collectHtmlJs =>
      '''
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
}
