import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 闪控（BR80）连接状态图标。
///
/// 按设计稿的两态 SVG（`icon_connected_flat.svg` /
/// `icon_disconnected_flat.svg`）用 [CustomPainter] 重绘：实心圆 + 圆角方块镂空
/// （快门）+ 上下左右四个三角按键 + 右上两道弧线（蓝牙信号）。两态形状完全一致，
/// 仅用颜色区分：已连接绿 `#22C55E`，未连接灰 `#8B93A1`，可直接做颜色过渡。
///
/// 顶部状态栏与设备页共用这一个组件。
class RemoteGlyph extends StatelessWidget {
  const RemoteGlyph({
    super.key,
    required this.connected,
    this.size = 18,
  });

  /// 闪控是否已连接。
  final bool connected;

  /// 图标边长（逻辑像素），按设计稿 96×96 viewBox 等比缩放。
  final double size;

  /// 设计稿规定的两态颜色。
  static const Color connectedColor = Color(0xFF22C55E);
  static const Color disconnectedColor = Color(0xFF8B93A1);

  /// 当前状态对应的图标颜色，供测试与调试读取。
  Color get color => connected ? connectedColor : disconnectedColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: connected ? '闪控已连接' : '闪控未连接',
      child: SizedBox(
        key: const ValueKey('remote-glyph'),
        width: size,
        height: size,
        child: CustomPaint(painter: RemoteGlyphPainter(color: color)),
      ),
    );
  }
}

/// 按设计稿路径绘制的闪控图标画笔。
class RemoteGlyphPainter extends CustomPainter {
  RemoteGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 设计稿 viewBox 是 96×96，但图形实际只占 x≈12–78、y≈10–72，四周留了大片空白，
    // 直接按 96 缩放会让图标显得很小。这里按实际内容边界裁剪并居中，去掉空白边框。
    const contentLeft = 11.0;
    const contentTop = 8.0;
    const contentRight = 79.0;
    const contentBottom = 73.0;
    const contentWidth = contentRight - contentLeft;
    const contentHeight = contentBottom - contentTop;
    final scale =
        size.width / (contentWidth > contentHeight ? contentWidth : contentHeight);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(
        -(contentLeft + contentRight) / 2, -(contentTop + contentBottom) / 2);

    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: const Offset(38, 46), radius: 26))
      ..addRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(28, 39, 20, 14), const Radius.circular(3)));
    void triangle(double ax, double ay, double bx, double by, double cx,
        double cy) {
      path
        ..moveTo(ax, ay)
        ..lineTo(bx, by)
        ..lineTo(cx, cy)
        ..close();
    }

    triangle(38, 23, 45, 34, 31, 34); // 上键
    triangle(38, 69, 45, 58, 31, 58); // 下键
    triangle(15, 46, 26, 39, 26, 53); // 左键
    triangle(61, 46, 50, 39, 50, 53); // 右键
    canvas.drawPath(
      path,
      Paint()..color = color,
    );

    // 两道同心弧线：半径 32 / 40，圆心与主体圆一致，对应设计稿的蓝牙信号。
    const center = Offset(38, 46);
    final outerStart = math.atan2(-14, 38);
    final outerEnd = math.atan2(-34, 21);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 32),
      math.atan2(-11, 30),
      math.atan2(-28, 15) - math.atan2(-11, 30),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 40),
      outerStart,
      outerEnd - outerStart,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RemoteGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
