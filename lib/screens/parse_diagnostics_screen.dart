import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../import/course_cache.dart';
import '../parsers/parse_diagnostics.dart';

/// 离线解析工具：把一段页面 HTML 丢进解析器，告诉你能不能解析出课表、卡在哪。
///
/// 用途是验证别的学校——不用每试一所就发一版。两种输入方式：
/// - 直接选 App 里导出的页面文件（导入页右上角那个导出按钮生成的）
/// - 或者把 HTML 粘进来
class ParseDiagnosticsScreen extends StatefulWidget {
  const ParseDiagnosticsScreen({super.key});

  @override
  State<ParseDiagnosticsScreen> createState() => _ParseDiagnosticsScreenState();
}

class _ParseDiagnosticsScreenState extends State<ParseDiagnosticsScreen> {
  final CourseCache _cache = const CourseCache();
  final TextEditingController _paste = TextEditingController();
  final ParseDiagnostics _diagnostics = const ParseDiagnostics();

  List<File> _files = const [];
  bool _loadingFiles = true;

  /// 报告正文；为 null 表示还没解析过
  String? _report;

  /// 这次报告是从哪来的，便于对照
  String _source = '';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final files = await _cache.listDebugPages();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loadingFiles = false;
    });
  }

  Future<void> _analyzeFile(File file) async {
    final html = await file.readAsString();
    if (!mounted) return;
    setState(() {
      _source = file.uri.pathSegments.last;
      _report = _diagnostics.report(html);
    });
  }

  void _analyzePasted() {
    final html = _paste.text;
    if (html.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先粘贴一段页面 HTML 再解析')),
      );
      return;
    }
    setState(() {
      _source = '粘贴的 HTML';
      _report = _diagnostics.report(html);
    });
  }

  Future<void> _copyReport() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('报告已复制，可直接发给作者')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('解析诊断'),
        actions: [
          if (_report != null)
            IconButton(
              tooltip: '复制报告',
              onPressed: _copyReport,
              icon: const Icon(Icons.copy_all_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '把课表页面的 HTML 交给解析器跑一遍，看能不能解析出课程、'
            '卡在哪一步。验证别的学校时用得上，不必每试一所就发一版。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          _sectionTitle('一、选一个导出的页面'),
          if (_loadingFiles)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            )
          else if (_files.isEmpty)
            Text(
              '还没有导出的页面。在导入页点右上角的导出按钮就会生成一个。',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._files.map(
              (file) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined, size: 20),
                title: Text(
                  file.uri.pathSegments.last,
                  style: const TextStyle(fontSize: 13),
                ),
                onTap: () => _analyzeFile(file),
              ),
            ),
          const SizedBox(height: 10),
          _sectionTitle('二、或者直接粘贴 HTML'),
          TextField(
            controller: _paste,
            maxLines: 6,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: '<html>…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _analyzePasted,
              child: const Text('解析'),
            ),
          ),
          if (_report != null) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _sectionTitle('三、报告（来源：$_source）'),
                ),
                TextButton.icon(
                  onPressed: _copyReport,
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  label: const Text('复制'),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                _report!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}