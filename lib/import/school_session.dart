import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 教务系统的登录态缓存。
///
/// 为什么必须自己存：Android 与 iOS 都只把**持久 Cookie**写盘，而统一身份
/// 认证、WebVPN 发的多是会话 Cookie（没有过期时间），进程一退出就没了 ——
/// 于是每次导课、每次自动刷新都得让用户重新登录一遍，静默刷新根本没法静默。
///
/// 这里把登录后的 Cookie 捞出来落到应用私有目录，下次从同一个入口打开前先塞
/// 回 WebView。能恢复多久取决于学校会话的有效期，过期了照常让用户重新登录。
class SchoolSession {
  const SchoolSession();

  static const String _fileName = 'school_session.json';

  /// 登录Cookie一般挂在这两个域上：统一认证的入口与 WebVPN 的课表页
  static List<Uri> _originsOf(List<String> urls) => [
    for (final url in urls)
      if (Uri.tryParse(url) case final uri? when uri.host.isNotEmpty) uri,
  ];

  /// 把 [urls] 涉及的 Cookie 全部存下来（同一域名只存一份）
  Future<void> save(List<String> urls) async {
    try {
      final cookies = await _collect(urls);
      if (cookies.isEmpty) return;
      final dir = await getApplicationDocumentsDirectory();
      final payload = {
        for (final cookie in cookies)
          '${cookie.domain}|${cookie.path}|${cookie.name}': {
            'name': cookie.name,
            'value': cookie.value,
            'domain': cookie.domain,
            'path': cookie.path,
          },
      };
      await File('${dir.path}/$_fileName').writeAsString(jsonEncode(payload));
    } catch (_) {
      // 存不下只影响下次要重新登录，不能影响当前这次导入
    }
  }

  /// 打开页面前调：把上次存下的 Cookie 塞回 WebView。返回恢复了多少条。
  Future<int> restore(List<String> urls) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return 0;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return 0;

      final manager = WebViewCookieManager();
      var restored = 0;
      for (final entry in decoded.values) {
        if (entry is! Map) continue;
        final name = entry['name'];
        final value = entry['value'];
        final domain = entry['domain'];
        if (name is! String || value is! String || domain is! String) continue;
        if (name.isEmpty || domain.isEmpty) continue;
        try {
          await manager.setCookie(
            WebViewCookie(
              name: name,
              value: value,
              domain: domain,
              path: entry['path'] is String ? entry['path'] as String : '/',
            ),
          );
          restored++;
        } catch (_) {
          // 个别 Cookie 塞不进去（域不匹配等）就跳过，不影响其它的
        }
      }
      return restored;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) await file.delete();
      await WebViewCookieManager().clearCookies();
    } catch (_) {
      // 清不掉也不该崩，下次照样能用
    }
  }

  Future<List<WebViewCookie>> _collect(List<String> urls) async {
    final manager = WebViewCookieManager();
    final byKey = <String, WebViewCookie>{};
    for (final origin in _originsOf(urls)) {
      try {
        for (final cookie in await manager.getCookies(domain: origin)) {
          byKey['${cookie.domain}|${cookie.path}|${cookie.name}'] = cookie;
        }
      } catch (_) {
        // 某个域读不到就跳过
      }
    }
    return byKey.values.toList();
  }
}
