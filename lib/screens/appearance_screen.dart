import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/appearance_background.dart';
import '../theme/table_style.dart';

/// 样式预设与背景。
///
/// 改动即时生效：直接改全局 [appAppearance]，课表页跟着重建，
/// 所以每动一下滑杆都能在下面那块预览里看到结果。
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final AppearanceStore _store = const AppearanceStore();
  TableAppearance _value = appAppearance.value;
  bool _busy = false;

  void _apply(TableAppearance next, {bool save = true}) {
    setState(() => _value = next);
    appAppearance.value = next;
    if (save) _store.save(next);
  }

  Future<void> _pickBackground() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      final path = picked?.path;
      if (path == null) return;
      final saved = await _store.importBackground(File(path));
      if (!mounted) return;
      _apply(
        _value.copyWith(
          background: _value.background.copyWith(imagePath: saved),
        ),
      );
    } catch (_) {
      _toast('这张图用不了，换一张试试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearBackground() async {
    await _store.clearBackground();
    if (!mounted) return;
    _apply(
      _value.copyWith(background: _value.background.copyWith(clearImage: true)),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = _value.background;
    return Scaffold(
      appBar: AppBar(title: const Text('样式与背景')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(height: 168, child: _buildPreview(dark)),
            ),
          ),
          _sectionHeader('样式预设'),
          _buildPresetGrid(),
          _sectionHeader('背景'),
          ListTile(
            title: Text(background.hasImage ? '更换背景图' : '选择背景图'),
            subtitle: Text(
              background.hasImage ? '已选一张，可调下面的透明度与模糊' : '从相册或文件里选一张，铺在课表下面',
            ),
            trailing: const Icon(Icons.image_outlined),
            onTap: _busy ? null : _pickBackground,
          ),
          if (background.hasImage)
            ListTile(
              title: const Text('去掉背景图'),
              trailing: const Icon(Icons.delete_outline),
              onTap: _clearBackground,
            ),
          _buildSlider(
            title: '背景透明度',
            value: background.opacity,
            min: 0.05,
            max: 1,
            divisions: 19,
            display: '${(background.opacity * 100).round()} %',
            onChanged: (v) => _apply(
              _value.copyWith(background: background.copyWith(opacity: v)),
              save: false,
            ),
            onChangeEnd: (v) => _apply(
              _value.copyWith(background: background.copyWith(opacity: v)),
            ),
          ),
          _buildSlider(
            title: '背景模糊',
            value: background.blur,
            min: 0,
            max: 24,
            divisions: 24,
            display: '${background.blur.round()}',
            onChanged: (v) => _apply(
              _value.copyWith(background: background.copyWith(blur: v)),
              save: false,
            ),
            onChangeEnd: (v) => _apply(
              _value.copyWith(background: background.copyWith(blur: v)),
            ),
          ),
          _buildSlider(
            title: '压暗',
            value: background.dim,
            min: 0,
            max: 0.6,
            divisions: 12,
            display: '${(background.dim * 100).round()} %',
            onChanged: (v) => _apply(
              _value.copyWith(background: background.copyWith(dim: v)),
              save: false,
            ),
            onChangeEnd: (v) => _apply(
              _value.copyWith(background: background.copyWith(dim: v)),
            ),
          ),
          _sectionHeader('课程格子'),
          _buildSlider(
            title: '卡片不透明度',
            value: _value.cardAlpha,
            min: 0.35,
            max: 1,
            divisions: 13,
            display: '${(_value.effectiveCardAlpha * 100).round()} %',
            onChanged: (v) =>
                _apply(_value.copyWith(cardAlpha: v), save: false),
            onChangeEnd: (v) => _apply(_value.copyWith(cardAlpha: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Text(
              '背景图铺得再花也不影响点格子：透明度降下来、模糊加上去，课文就压得住。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// 预览：用真实的画笔和背景层拼一小块课表，看到的即屏幕上会有的
  Widget _buildPreview(bool dark) {
    final palette = TablePalette(_value, dark: dark);
    const samples = ['高等数学', '大学英语', '程序设计', '体育'];
    return Stack(
      fit: StackFit.expand,
      children: [
        AppearanceBackground(appearance: _value, dark: dark),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  for (var i = 0; i < samples.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: palette
                              .cardColor(samples[i], faded: false)
                              .withValues(alpha: palette.cardAlpha),
                          borderRadius: BorderRadius.circular(8),
                          border: palette.preset.outlined
                              ? Border.all(
                                  color: palette.borderOn(
                                    palette.cardColor(samples[i], faded: false),
                                  ),
                                )
                              : null,
                        ),
                        child: Text(
                          samples[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: palette.textColorOn(
                              palette.cardColor(samples[i], faded: false),
                              secondary: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < samples.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: palette
                              .cardColor(samples[i], faded: true)
                              .withValues(alpha: palette.cardAlpha),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPresetGrid() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: [
          for (final preset in TableStylePreset.all)
            _buildPresetCard(preset, dark: dark),
        ],
      ),
    );
  }

  Widget _buildPresetCard(TableStylePreset preset, {required bool dark}) {
    final selected = preset.id == _value.presetId;
    final palette = TablePalette(
      _value.copyWith(presetId: preset.id),
      dark: dark,
    );
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _apply(_value.copyWith(presetId: preset.id)),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final name in const ['高数', '英语', '体育', '实验'])
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: palette.cardColor(name, faded: false),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                const Spacer(),
                if (selected)
                  Icon(Icons.check, size: 16, color: scheme.primary),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              preset.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Text(
                preset.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: scheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
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
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          Text(display, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
