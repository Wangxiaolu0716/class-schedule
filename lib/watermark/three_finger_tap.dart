import 'dart:async';

import 'package:flutter/material.dart';

/// 三指轻敲屏幕三次触发 [onTrigger]（彩蛋入口）。
///
/// 用 [Listener] 观察原始指针事件，而不是 [GestureDetector]：`Listener` 不参与
/// 手势竞争，只旁观，因此包在应用外面不会抢走任何原有的点击与滑动。
class ThreeFingerTapDetector extends StatefulWidget {
  const ThreeFingerTapDetector({
    super.key,
    required this.onTrigger,
    required this.child,
  });

  final VoidCallback onTrigger;
  final Widget child;

  /// 相邻两次敲击之间允许的最大间隔，超过就把计数清零
  static const Duration betweenTaps = Duration(milliseconds: 1200);

  /// 三根手指的落下时间差上限。超过说明是「先后按到」而不是一起按下
  static const Duration fingerSpread = Duration(milliseconds: 200);

  @override
  State<ThreeFingerTapDetector> createState() => _ThreeFingerTapDetectorState();
}

class _ThreeFingerTapDetectorState extends State<ThreeFingerTapDetector> {
  /// 当前按住屏幕的手指，值是它的落下时刻
  final Map<int, Duration> _down = {};

  /// 本次触摸是否满足「三指同时按下」
  bool _threeFingerTouch = false;

  int _taps = 0;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _handleDown(PointerDownEvent event) {
    _down[event.pointer] = event.timeStamp;
    if (_down.length < 3) return;

    // 三根手指同时在屏幕上还不够，第一根与最后一根的落下时刻也得够接近
    var earliest = _down.values.first;
    for (final stamp in _down.values) {
      if (stamp < earliest) earliest = stamp;
    }
    _threeFingerTouch =
        event.timeStamp - earliest <= ThreeFingerTapDetector.fingerSpread;
  }

  /// 一次触摸结束（抬起或被系统取消）。
  ///
  /// 只有全部手指都离开屏幕才结算一次敲击，否则三指的一次触碰
  /// 会被算成三次，一下就凑满三下了。
  void _handleUp(int pointer) {
    final wasThreeFinger = _threeFingerTouch;
    _down.remove(pointer);
    if (_down.isNotEmpty) return;

    _threeFingerTouch = false;
    if (wasThreeFinger) _registerTap();
  }

  void _registerTap() {
    _resetTimer?.cancel();
    _taps++;
    if (_taps >= 3) {
      _taps = 0;
      widget.onTrigger();
      return;
    }
    _resetTimer = Timer(ThreeFingerTapDetector.betweenTaps, () => _taps = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // translucent：自己也进命中结果（保证收得到事件），但不挡住底层控件
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerUp: (event) => _handleUp(event.pointer),
      onPointerCancel: (event) => _handleUp(event.pointer),
      child: widget.child,
    );
  }
}