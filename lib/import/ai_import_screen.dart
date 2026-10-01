import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/course.dart';
import '../parsers/ai_json_parser.dart';
import 'course_cache.dart';
import 'school_config.dart';
import 'school_picker.dart';
import 'webview_import_screen.dart';

/// AI 识别导入：把 AI 返回的课表 JSON 粘进来，转成课表数据。
///
/// 给没有内置解析器的学校用。课表来源有两条路，任选其一：
/// - 在应用内打开教务系统，翻到课表页导出**页面结构**（推荐，信息比截图全）
/// - 自己截图，把截图和提示词一起发给 AI
///
/// 然后把 AI 返回的 JSON 粘回这里即可。全程在本机完成：不联网、不调用任何
/// 接口、用不到密钥，课表也不外传——发给哪个 AI 由用户自己决定。
///
/// 确认后通过 [Navigator.pop] 返回解析好的 [CourseTableData]。
class AiImportScreen extends StatefulWidget {
  const AiImportScreen({super.key, this.lastManualUrl});

  /// 上次填过的教务网址，用于预填，省得反复手打
  final String? lastManualUrl;

  @override
  State<AiImportScreen> createState() => _AiImportScreenState();
}

class _AiImportScreenState extends State<AiImportScreen> {
  static const AiCourseJsonParser _parser = AiCourseJsonParser();
  static const List<String> _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  final CourseCache _cache = const CourseCache();
  final TextEditingController _input = TextEditingController();

  /// 教务系统入口地址；为空表示还没填过
  String? _entryUrl;

  /// 从课表页导出的结构；为空表示还没有，只能走截图那条路
  PageStructure? _structure;

  AiParseResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entryUrl = widget.lastManualUrl;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// 打开教务系统，让用户自己登录并翻到课表页，再把页面结构带回来。
  ///
  /// 比让用户自己去截图省事，信息也更全：表格的合并关系、单元格里的
  /// 全部文字都在，AI 不容易认错。
  Future<void> _openSchool() async {
    var url = _entryUrl;
    if (url == null || url.isEmpty) {
      url = await askEntryUrl(context, null);
      if (url == null || !mounted) return;
      setState(() => _entryUrl = url);
      await _cache.saveManualEntryUrl(url);
    }
    if (!mounted) return;

    final structure = await Navigator.of(context).push<PageStructure>(
      MaterialPageRoute(
        builder: (_) => WebViewImportScreen(
          school: SchoolConfig.manual(url!),
          exportStructure: true,
        ),
      ),
    );
    if (structure == null || !mounted) return;

    setState(() => _structure = structure);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          structure.truncated
              // 截断了就说明大概率抓错了页面，如实说清楚，别让用户白折腾
              ? '已获取页面结构，但内容过长只带了前半段，识别不全的话改用截图吧'
              : '已获取页面结构，接下来把提示词和它一起发给 AI',
        ),
      ),
    );
  }

  /// 换个教务网址。之前导出的结构随之作废——地址换了，那份结构就不算数了。
  Future<void> _changeUrl() async {
    final url = await askEntryUrl(context, _entryUrl);
    if (url == null || !mounted) return;
    setState(() {
      _entryUrl = url;
      _structure = null;
    });
    await _cache.saveManualEntryUrl(url);
  }

  /// 复制给 AI 的内容：提示词，外加（如果导出过）页面结构。
  Future<void> _copyForAi() async {
    final structure = _structure;
    final text = structure == null
        ? aiImportPrompt
        : '$aiImportPrompt\n\n'
            '下面是课表页面的结构（已去掉脚本和样式）。\n\n'
            '${structure.text}';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          structure == null
              ? '提示词已复制，连同课表截图一起发给 AI'
              : '提示词和页面结构已一起复制，直接粘给 AI 即可',
        ),
      ),
    );
  }

  void _runParse() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = '请先把 AI 返回的内容粘进来';
        _result = null;
      });
      return;
    }

    try {
      final result = _parser.parse(text);
      setState(() {
        _result = result;
        _error = null;
      });
    } on AiImportException catch (e) {
      setState(() {
        _error = e.message;
        _result = null;
      });
    } catch (_) {
      setState(() {
        _error = '这段内容解析不了，看看是不是没复制完整';
        _result = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final structure = _structure;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 识别导入')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _card(
            theme,
            title: '没有内置解析器的学校怎么办',
            child: const Text(
              '让 AI 先替你「看」课表，再把结果粘回来。\n'
              '适合网页结构特殊、或者还没适配过的教务系统，'
              '不用等我们写解析器。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          _card(
            theme,
            title: '1. 把课表交给 AI',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '点下面的按钮在应用内打开学校教务系统，登录后翻到能看全整张课表的'
                  '页面，再点右下角「导出结构」——页面结构会自动带回来，'
                  '它比截图信息更全，AI 不容易认错。',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _openSchool,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(structure == null ? '打开学校教务系统' : '重新导出'),
                    ),
                    if (_entryUrl != null) ...[
                      const SizedBox(width: 4),
                      TextButton(onPressed: _changeUrl, child: const Text('换地址')),
                    ],
                  ],
                ),
                if (_entryUrl != null)
                  Text(
                    _entryUrl!,
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                  ),
                if (structure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '已获取页面结构（${structure.text.length} 字）'
                      '${structure.truncated ? '，内容过长已截断' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                const Divider(height: 26),
                const Text(
                  '不方便在应用里登录也行：自己在教务系统里截图，'
                  '把截图和提示词一起发给 AI。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 6),
                const Text(
                  '提示：课表页面里可能有你的姓名和学号，发给 AI 前留意一下。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _copyForAi,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: Text(structure == null ? '复制提示词' : '复制提示词 + 页面结构'),
                ),
              ],
            ),
          ),
          _card(
            theme,
            title: '2. 把 AI 返回的内容粘回来',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _input,
                  maxLines: 6,
                  minLines: 4,
                  decoration: const InputDecoration(
                    hintText: '把 AI 返回的那段 JSON 整段粘进来，'
                        '带 ```json 代码块也没关系',
                    hintStyle: TextStyle(fontSize: 12),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _runParse,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('识别'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
              ),
            ),
          if (result != null) ..._buildPreview(theme, result),
        ],
      ),
      bottomNavigationBar: result == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(result.data),
                  child: Text('导入这 ${result.data.sessions.length} 门课'),
                ),
              ),
            ),
    );
  }

  /// 解析成功后的预览：条数、跳过的条目、以及逐条课程
  List<Widget> _buildPreview(ThemeData theme, AiParseResult result) {
    final sessions = result.data.sessions;

    return [
      _card(
        theme,
        title: '识别结果：${sessions.length} 条',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '确认没问题就点底部的「导入」。如果 AI 认错了几门，'
              '重新识别一次再粘回来即可。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            for (final note in result.notes) ...[
              const SizedBox(height: 6),
              Text(
                note,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              ),
            ],
            for (final skipped in result.skipped) ...[
              const SizedBox(height: 6),
              Text(
                skipped,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      for (final session in sessions)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(session.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            '${_weekdayNames[session.dayOfWeek - 1]} '
            '第${session.startPeriod}-${session.endPeriod}节 · '
            '${formatWeeks(session.weeks)}周'
            '${session.room.isEmpty ? '' : ' · ${session.room}'}'
            '${session.teacher.isEmpty ? '' : ' · ${session.teacher}'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ];
  }

  Widget _card(ThemeData theme, {required String title, required Widget child}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
