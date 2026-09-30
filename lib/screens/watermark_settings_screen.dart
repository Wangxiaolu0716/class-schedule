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
            settings: _settings,
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