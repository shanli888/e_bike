import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/assist_mode.dart';
import '../theme/dashboard_theme.dart';

/// 圆形径向模式菜单：以 [origin]（父 Stack 局部坐标）为圆心，
/// 将 5 个助力模式按钮沿左半圆弧依次展开，背景带模糊遮罩。
///
/// 点击弧上任一按钮即选择该模式并收起；点击遮罩收起。
/// 展开/收起均有错峰缩放动画，遵循 prefers-reduced-motion 由外层统一处理。
class RadialModeMenu extends StatefulWidget {
  const RadialModeMenu({
    super.key,
    required this.origin,
    required this.selected,
    required this.enabled,
    required this.scale,
    required this.onSelected,
    required this.onDismiss,
  });

  /// 圆心在父 Stack 中的局部坐标（通常是模式触发按钮的中心）。
  final Offset origin;
  final AssistMode selected;
  final bool enabled;
  final double scale;
  final ValueChanged<AssistMode> onSelected;
  final VoidCallback onDismiss;

  @override
  State<RadialModeMenu> createState() => _RadialModeMenuState();
}

class _RadialModeMenuState extends State<RadialModeMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_ctrl.status == AnimationStatus.reverse) return;
    await _ctrl.reverse();
    if (mounted) widget.onDismiss();
  }

  void _choose(AssistMode mode) {
    widget.onSelected(mode);
    unawaited(_dismiss());
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    const modes = AssistMode.values;
    const radiusBase = 140.0;
    const circleBase = 64.0;
    final radius = radiusBase * s;
    final circle = circleBase * s;
    // 左半圆：从右上 108° 逆时针到右下 252°，与效果图一致（弧向左凸出）。
    const beginDeg = 108.0;
    const endDeg = 252.0;

    // 外层已用 Positioned.fill 撑满，这里直接用 Stack(fit: expand) 铺满其父级。
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // 模糊 + 压暗背景，点击空白处收起。
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final v = Curves.easeOut.transform(_ctrl.value);
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6 * v, sigmaY: 6 * v),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismiss,
                  child: Container(
                    color: const Color(0xFF080B14).withValues(alpha: v * 0.82),
                  ),
                ),
              );
            },
          ),
        ),
        // 弧线上的模式按钮（错峰弹出）。
        for (var i = 0; i < modes.length; i++) ...[
          _radialButton(
            modes[i],
            fraction: modes.length == 1 ? 0.5 : i / (modes.length - 1),
            index: i,
            beginDeg: beginDeg,
            endDeg: endDeg,
            radius: radius,
            circle: circle,
            s: s,
          ),
        ],
      ],
    );
  }

  Widget _radialButton(
    AssistMode mode, {
    required double fraction,
    required int index,
    required double beginDeg,
    required double endDeg,
    required double radius,
    required double circle,
    required double s,
  }) {
    final angle = (beginDeg + (endDeg - beginDeg) * fraction) * math.pi / 180;
    final dest = widget.origin +
        Offset(radius * math.cos(angle), radius * math.sin(angle));
    final start = index * 0.05;
    final interval = Interval(
      start,
      (start + 0.65).clamp(0.0, 1.0),
      curve: Curves.easeOutBack,
    );

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final raw = interval.transform(_ctrl.value);
        final p = raw.clamp(0.0, 1.0);
        final pos = Offset(
          widget.origin.dx + (dest.dx - widget.origin.dx) * p,
          widget.origin.dy + (dest.dy - widget.origin.dy) * p,
        );
        return Positioned(
          left: pos.dx - circle / 2,
          top: pos.dy - circle / 2,
          child: Transform.scale(
            scale: raw.clamp(0.0, 1.18),
            child: Opacity(
              opacity: p,
              child: _circle(mode, circle, s),
            ),
          ),
        );
      },
    );
  }

  Widget _circle(AssistMode mode, double circle, double s) {
    final selected = mode == widget.selected;
    final fg = selected ? const Color(0xFF1A1206) : DashColors.txt;
    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: GestureDetector(
        key: ValueKey('mode-menu-${mode.name}'),
        onTap: widget.enabled ? () => _choose(mode) : null,
        child: Container(
          width: circle,
          height: circle,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: selected ? DashColors.modeSelected : null,
            color: selected ? null : const Color(0xFF16203A),
            border: Border.all(
              color: selected
                  ? DashColors.orange
                  : Colors.white.withValues(alpha: 0.18),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? DashColors.orange.withValues(alpha: 0.35)
                    : Colors.black54,
                blurRadius: selected ? 16 : 8,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(mode.icon, size: 22 * s, color: fg),
              SizedBox(height: 3 * s),
              Text(
                mode.label,
                style: TextStyle(
                  fontSize: 11 * s,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
