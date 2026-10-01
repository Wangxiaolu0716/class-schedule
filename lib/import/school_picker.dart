import 'package:flutter/material.dart';

import 'school_config.dart';
import 'school_service.dart';

/// 补全并校验用户填的教务网址。
///
/// 用户经常只贴 `jw.example.edu.cn`（没有协议头），或者直接复制一大串带参数的
/// 门户地址。没有协议头 WebView 打不开，所以这里统一补成 https，
/// 顺带挡掉明显填错的输入。返回 null 表示这个地址不可用。
String? normalizeSchoolUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final withScheme = text.contains('://') ? text : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null) return null;
  // 必须有主机名，且协议只能是 http/https（避免 file:// 之类被填进来）
  if (uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.toString();
}

/// 选择从哪里导入课表。返回 null 表示用户取消。
///
/// [lastManualUrl] 是上次手动导课时填过的教务网址，用于预填，省得重复输入。
Future<SchoolConfig?> showSchoolPicker(
  BuildContext context, {
  String? lastManualUrl,
}) async {
  final pick = await showModalBottomSheet<_Pick>(
    context: context,
    // 让搜索时的软键盘把内容顶上去，而不是盖住列表
    isScrollControlled: true,
    builder: (_) => const _SchoolPickerSheet(),
  );
  if (pick == null || !context.mounted) return null;

  if (pick.autoImport) return nbccSchool;
  if (pick.ai) return SchoolConfig.aiImport();

  final school = pick.school;
  if (school != null) {
    return SchoolConfig.manual(school.url, name: school.name);
  }

  final url = await askEntryUrl(context, lastManualUrl);
  if (url == null) return null;
  return SchoolConfig.manual(url);
}

/// 用户在列表里选了什么
class _Pick {
  const _Pick.auto()
      : autoImport = true,
        school = null,
        ai = false;
  const _Pick.school(this.school)
      : autoImport = false,
        ai = false;
  const _Pick.manual()
      : autoImport = false,
        school = null,
        ai = false;
  const _Pick.ai()
      : autoImport = false,
        school = null,
        ai = true;

  final bool autoImport;
  final SchoolInfo? school;

  /// 走 AI 识别导入
  final bool ai;
}

/// 学校选择面板：搜索框 + 列表
class _SchoolPickerSheet extends StatefulWidget {
  const _SchoolPickerSheet();

  @override
  State<_SchoolPickerSheet> createState() => _SchoolPickerSheetState();
}

class _SchoolPickerSheetState extends State<_SchoolPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SchoolInfo> get _filtered =>
      SchoolService.schools.where((school) => school.matches(_search.text)).toList();

  @override
  Widget build(BuildContext context) {
    // 搜索时不再固定显示本校和「手动输入」，免得搜 A 校却看到一堆无关项
    final searching = _search.text.trim().isNotEmpty;
    final filtered = _filtered;

    // 弹窗高度在打开时就定死，不跟着内容走。
    //
    // showModalBottomSheet 的高度默认由内容决定，列表一长一短、或者键盘一弹，
    // 外壳就会在入场动画还没播完时跳一截，看起来像「闪一下」。固定之后，
    // 内容切换只是内部替换，外壳纹丝不动。
    final media = MediaQuery.of(context);
    final preferred = media.size.height * 0.68;
    // 键盘弹出时把高度让出来，否则固定高度会被键盘盖住、列表只露一条缝
    final allowed = media.size.height - media.viewInsets.bottom - 120;
    final height = allowed > 0 && allowed < preferred ? allowed : preferred;

    return SizedBox(
      height: height,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 18),
            Text('选择学校', style: Theme.of(context).textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '搜索学校名称',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            // 本校固定在顶部：它是主要入口，不参与滚动
            if (!searching)
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(nbccSchool.name),
                subtitle: const Text('自动识别课表页并抓取，推荐'),
                onTap: () => Navigator.pop(context, const _Pick.auto()),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final school in filtered)
                    ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: Text(school.name),
                      // 如实标注验证状态：列表里有，不代表一定能用
                      subtitle: Text(
                        school.verified ? '已验证可用' : '尚未验证，可能不适用',
                        style: TextStyle(
                          fontSize: 12,
                          color: school.verified
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, _Pick.school(school)),
                    ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 26),
                      child: Center(
                        child: Text(
                          searching ? '没有匹配的学校' : '暂时还没有其它学校',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            // 「手动输入网址」固定在最底部，不放进滚动列表：
            // 以后学校再多，它也不用滚到最底下才找得到
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('其它学校（手动输入网址）'),
              subtitle: const Text('自己填教务系统地址，再在应用内登录导课'),
              onTap: () => Navigator.pop(context, const _Pick.manual()),
            ),
            // 内置解析器认不出来的学校（页面结构特殊、或还没适配过）走这条
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI 识别导入'),
              subtitle: const Text('让 AI 看课表截图，把结果粘回来就能导入'),
              onTap: () => Navigator.pop(context, const _Pick.ai()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 让用户填教务系统入口地址。返回 null 表示用户取消或填的地址不可用。
///
/// 「手动导课」和「AI 识别导入」都要先有一个入口地址才能打开教务系统，
/// 所以这段单独抽出来共用。
Future<String?> askEntryUrl(BuildContext context, String? lastUrl) {
  final controller = TextEditingController(text: lastUrl ?? '');
  String? error;

  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('教务系统网址'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '填入学校教务系统的入口地址即可，后面在应用内自己登录、'
                '再翻到课表页抓取。',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'jw.example.edu.cn',
                  isDense: true,
                  errorText: error,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final normalized = normalizeSchoolUrl(controller.text);
              if (normalized == null) {
                // 地址不可用就别放行，否则用户进去只会看到一个打不开的白页
                setState(() => error = '地址看起来不对，请检查后重试');
                return;
              }
              Navigator.pop(context, normalized);
            },
            child: const Text('开始导入'),
          ),
        ],
      ),
    ),
  );
}