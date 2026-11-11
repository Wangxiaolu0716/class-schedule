import 'package:flutter/material.dart';

import '../watermark/watermark_overlay.dart';
import '../watermark/watermark_settings.dart';

/// 水印的隐藏设置页：三指轻敲屏幕三次进入。
///
/// 改动即时通过 [onChanged] 抛给上层，所以整块屏幕上的水印会跟着变，
/// 页内的预览框只是把效果放大给你看。退出时由上层统一落盘。
class WatermarkSettingsScreen extends StatefulWidget {
  const WatermarkSettingsScreen({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final WatermarkSettings initial;
  final ValueChanged<WatermarkSettings> onChanged;

  @override
  State<WatermarkSettingsScreen> createState() =>
      _WatermarkSettingsScreenState();
}

class _WatermarkSettingsScreenState extends State<WatermarkSettingsScreen> {
  late WatermarkSettings _settings = widget.initial;

  void _apply(WatermarkSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('水印设置')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '隐藏页 · 三指轻敲屏幕三次可以再次回到这里',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _buildPreview(),
          _sectionHeader('水印参数'),
          // 文案自己填：不同版本/不同用途的水印内容不一样
          ListTile(
            title: const Text('水印文字'),
            subtitle: Text(
              _settings.text.isEmpty ? '（空，水印不会显示任何字）' : _settings.text,
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editText,
          ),
          // 默认关闭；要用水印时从这里打开，打开后整屏立刻盖上去
          SwitchListTile(
            title: const Text('显示水印'),
            subtitle: const Text('默认关闭，只在这个隐藏页里开关'),
            value: _settings.enabled,
            onChanged: (value) => _apply(_settings.copyWith(enabled: value)),
          ),
          _buildSlider(
            title: '字号',
            value: _settings.fontSize,
            min: 10,
            max: 40,
            divisions: 30,
            display: '${_settings.fontSize.toStringAsFixed(0)} sp',
            apply: (v) => _settings.copyWith(fontSize: v),
          ),
          _buildSlider(
            title: '疏密',
            value: _settings.spacing,
            min: 120,
            max: 420,
            divisions: 30,
            display: '间距 ${_settings.spacing.toStringAsFixed(0)} dp',
            apply: (v) => _settings.copyWith(spacing: v),
          ),
          _buildSlider(
            title: '透明度',
            value: _settings.opacity,
            min: 0.02,
            max: 0.30,
            divisions: 28,
            display: '${(_settings.opacity * 100).toStringAsFixed(0)} %',
            apply: (v) => _settings.copyWith(opacity: v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _apply(WatermarkSettings.defaults),
                  // 恢复默认会把水印一并关掉，这是刻意的：默认就是没有水印
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('恢复默认'),
                ),
                const Spacer(),
                Text(
                  '改动已生效，退出即保存',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 改水印文案。留空就等于关掉水印显示的那行字。
  Future<void> _editText() async {
    final controller = TextEditingController(text: _settings.text);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('水印文字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '例如：内部测试 / @你的名字',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    _apply(_settings.copyWith(text: text));
  }

  /// 预览：直接用同一套画笔，看到的就是屏幕上真实的效果。
  ///
  /// 底色与文字跟着主题走，否则深色模式下这块预览会亮得像贴了张白纸。
  Widget _buildPreview() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 190,
          child: AppWatermark(
            // 预览强制打开：水印开关关着时也要能看清字号/疏密的效果
            settings: _settings.copyWith(enabled: true),
            child: Container(
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Text(
                '预览',
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required WatermarkSettings Function(double value) apply,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => _apply(apply(v)),
            ),
          ),
          SizedBox(
            width: 108,
            child: Text(display, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
