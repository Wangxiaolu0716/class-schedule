import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 全局自定义字体：null 表示用系统自带字体。
///
/// 与主题模式同样是全局 notifier：改它在设置页，用它的是根部 `MaterialApp`。
final ValueNotifier<AppFont?> appFont = ValueNotifier<AppFont?>(null);

/// 一款已经导入并生效的字体包。
class AppFont {
  const AppFont({required this.name, required this.path});

  /// 显示用的名字，即用户选中的那个文件名
  final String name;

  /// 复制到应用私有目录后的路径
  final String path;
}

/// 字体包不可用时的提示。
///
/// 文案直接面向用户（会原样弹出来），所以写成能看懂的一句话。
class AppFontException implements Exception {
  const AppFontException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 自定义字体的读写。
///
/// 用户选中的字体包会被复制进应用私有目录，之后每次启动重新注册进引擎
/// （引擎只在本次进程里认注册过的字体，所以启动时要再注册一遍）。
/// 字体不进安装包：不导入时一个字节都不多占。
class AppFontStore {
  const AppFontStore();

  /// 注册进引擎时用的家族名。
  ///
  /// 同一时刻只有一款字体生效，用固定名字最省事：换字体时同名覆盖即可。
  static const String familyName = 'AppCustomFont';

  static const String _dirName = 'font';
  static const String _prefix = 'custom.';
  static const String _nameFile = 'font_name.txt';

  /// 引擎里当前注册的是哪一款，避免重复注册（比如同一份字节导入了两次）。
  static Uint8List? _registeredBytes;

  static bool _supported(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf');
  }

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 启动时调用：把上次导入的字体重新注册进引擎。
  ///
  /// 文件被系统清掉或读坏都只是退回系统字体，不能让 App 起不来。
  Future<AppFont?> load() async {
    try {
      final dir = await _dir();
      final files = await dir.list().toList();
      for (final file in files) {
        if (file is! File) continue;
        final name = file.uri.pathSegments.last;
        if (!name.startsWith(_prefix)) continue;

        final bytes = await file.readAsBytes();
        if (_rejectReason(bytes) != null) continue;
        await _register(bytes);
        return AppFont(name: await _displayName(dir, name), path: file.path);
      }
    } catch (_) {
      // 读不出来就当没设过字体
    }
    return null;
  }

  /// 导入一款字体包：先校验、再注册，都通过才落盘。
  Future<AppFont> import(File source, {required String displayName}) async {
    if (!_supported(source.path)) {
      throw const AppFontException('只支持 .ttf 和 .otf 字体文件');
    }

    final Uint8List bytes;
    try {
      bytes = await source.readAsBytes();
    } catch (_) {
      throw const AppFontException('读不到这个文件，换一个字体包试试');
    }

    final reason = _rejectReason(bytes);
    if (reason != null) throw AppFontException(reason);

    // 先注册：注册失败的文件不写进私有目录，免得下次启动又要踩一次
    await _register(bytes);

    final dir = await _dir();
    await _removeExisting(dir);
    final lower = source.path.toLowerCase();
    final target = File('${dir.path}/$_prefix${lower.endsWith('.otf') ? 'otf' : 'ttf'}');
    await target.writeAsBytes(bytes, flush: true);
    await File('${dir.path}/$_nameFile').writeAsString(displayName);

    return AppFont(name: displayName, path: target.path);
  }

  /// 恢复系统默认字体。
  Future<void> clear() async {
    _registeredBytes = null;
    final dir = await _dir();
    await _removeExisting(dir);
    final meta = File('${dir.path}/$_nameFile');
    if (await meta.exists()) await meta.delete();
  }

  Future<void> _removeExisting(Directory dir) async {
    for (final file in await dir.list().toList()) {
      if (file is File && file.uri.pathSegments.last.startsWith(_prefix)) {
        await file.delete();
      }
    }
  }

  Future<String> _displayName(Directory dir, String fallback) async {
    final meta = File('${dir.path}/$_nameFile');
    if (!await meta.exists()) return fallback;
    final name = (await meta.readAsString()).trim();
    return name.isEmpty ? fallback : name;
  }

  static Future<void> _register(Uint8List bytes) async {
    // 同一份字节已经注册过了就直接跳过：启动 load() 之后用户又选回同一款字体，
    // 重复注册会闪一下字重再稳回来，肉眼能看出来。
    if (_registeredBytes != null && _listEquals(_registeredBytes!, bytes)) return;
    final loader = FontLoader(familyName)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _registeredBytes = bytes;
  }

  static bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 看文件头判断能不能用，比等引擎报错要早，提示也更具体。
  ///
  /// ttf/otf 的头是 0x00010000 或 'OTTO' / 'true'；
  /// 字体合集 ttc（中文字体包常见）是 'ttcf'，引擎读不了，直接说清楚。
  static String? _rejectReason(Uint8List bytes) {
    if (bytes.length < 4) return '这个文件不完整，换一个字体包试试';

    final tag = String.fromCharCodes(bytes.sublist(0, 4));
    if (tag == 'ttcf') {
      return '这是字体合集（ttc），暂时用不了，请选单个 .ttf / .otf 文件';
    }
    final sfnt = tag == 'OTTO' || tag == 'true' || bytes[0] == 0 && bytes[1] == 1;
    if (!sfnt) return '这不是可用的字体文件，请选 .ttf / .otf';
    return null;
  }
}
