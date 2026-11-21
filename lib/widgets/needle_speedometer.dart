import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/dashboard_theme.dart';

/// Fan-shaped speedometer with upright tick labels and a wider perspective road.
class NeedleSpeedometer extends StatefulWidget {
  const NeedleSpeedometer({
    super.key,
    required this.speed,
    required this.useGps,
    this.size = 220,
    this.avgSpeed,
    this.peakSpeed,
    this.showStartupSweep = false,
  });

  /// 当前速度（km/h）；null 表示无数据，指针停在起点。
  final double? speed;

  /// 平均速度标线（km/h）；null 或 0 表示不绘制。
  final double? avgSpeed;

  /// 最高速度标线（km/h）；null 或 0 表示不绘制。
  /// 不叫 maxSpeed 是为了避开量程常量 [NeedleSpeedometer.maxSpeed]。
  final double? peakSpeed;
  final bool showStartupSweep;

  /// 速度来源：true=GPS，false=蓝牙（仅用于语义标签）。
  final bool useGps;

  /// 表盘宽度，调用方按屏幕缩放后传入；高度按设计稿比例 179/200 自适应。
  final double size;

  static const double maxSpeed = 60;

  /// 设计稿扇形：起点 -110°、扫过 220°（下半截裁掉）。
  static const double startDeg = -110;
  static const double sweepDeg = 220;

  /// 速度 → 动画进度（0..1）。抽成纯函数便于验证低速时不会出现负值。
  static double progressFor(double? speed) =>
      (speed ?? 0).clamp(0.0, maxSpeed) / maxSpeed;

  /// 标线专用：null / 非有限值 / 0 都不画，其余夹到 0..60 后换算进度。
  static double? markerProgress(double? value) {
    if (value == null || !value.isFinite || value <= 0) return null;
    return value.clamp(0.0, maxSpeed) / maxSpeed;
  }

  /// 动画进度 → 弧度（-135°..+135°）。
  /// 保留此接口供既有断言使用（历史上完整圆表盘的指针范围）。
  static double radiansFor(double progress) =>
      (-135 + 270 * progress) * math.pi / 180;

  /// 实际绘制用：动画进度 → 扇形弧度（-110°..+110°）。
  static double fanAngleFor(double progress) =>
      (startDeg + sweepDeg * progress) * math.pi / 180;

  /// 路纹滚动速率（圈/秒）：与速度进度成正比，0 速为 0（路面完全静止），
  /// 满速约 0.9 圈/秒。抽成纯函数便于验证「速度为 0 时不滚动」。
  static double roadCyclesPerSec(double progress) => progress * 0.9;

  @override
  State<NeedleSpeedometer> createState() => _NeedleSpeedometerState();
}

class _NeedleSpeedometerState extends State<NeedleSpeedometer>
    with TickerProviderStateMixin {
  /// 指针平滑扫动（速度变化时）。
  late final AnimationController _needleCtrl = AnimationController(vsync: this);
  late final AnimationController _startupCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animateNeedleTo(NeedleSpeedometer.progressFor(widget.speed));
      }
    });

  /// 道路行程 0..1，由 Ticker 按车速推进（AnimationController 无 speed setter）。
  final _travel = ValueNotifier<double>(0);
  double? _lastElapsedMs;
  late final Ticker _roadTicker;
  late final Listenable _repaint =
      Listenable.merge([_needleCtrl, _startupCtrl, _travel]);
  bool _reduceMotion = false;
  bool _startupDecided = false;

  @override
  void initState() {
    super.initState();
    _needleCtrl.value = NeedleSpeedometer.progressFor(widget.speed);
    _roadTicker = createTicker((elapsed) {
      final ms = elapsed.inMicroseconds / 1000;
      final dt =
          _lastElapsedMs == null ? 0.0 : (ms - _lastElapsedMs!).clamp(0, 64);
      _lastElapsedMs = ms;
      // 路纹滚动速度与实时车速成正比：越快越急，0 速完全静止。
      // 用平滑后的指针进度，起步/刹车时路面有自然的加减速。
      final ratio = _needleCtrl.value;
      final cyclesPerSec = NeedleSpeedometer.roadCyclesPerSec(ratio);
      _travel.value = (_travel.value + dt / 1000 * cyclesPerSec) % 1.0;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_startupDecided) {
      _startupDecided = true;
      if (widget.showStartupSweep && !_reduceMotion) {
        _needleCtrl.value = 0;
        _startupCtrl.forward();
      }
    }
    if (_reduceMotion) {
      _startupCtrl.stop();
      _needleCtrl.value = NeedleSpeedometer.progressFor(widget.speed);
      _roadTicker.stop();
      _lastElapsedMs = null;
    }
    // 道路是持续循环动效，仅在发布版真机运行；测试环境保持静止以免 pumpAndSettle 不收敛。
    if (kReleaseMode && !_reduceMotion && !_roadTicker.isActive) {
      _roadTicker.start();
    }
  }

  @override
  void didUpdateWidget(covariant NeedleSpeedometer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = NeedleSpeedometer.progressFor(widget.speed);
    if (_startupCtrl.isAnimating ||
        target == NeedleSpeedometer.progressFor(oldWidget.speed)) {
      return;
    }
    if (_reduceMotion) {
      _needleCtrl.value = target;
      return;
    }
    _animateNeedleTo(target);
  }

  void _animateNeedleTo(double target) {
    // 显式指定时长，让小幅变化也能跨多帧，并从当前显示位置继续转动。
    _needleCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 440),
      curve: Curves.easeOutSine,
    );
  }

  @override
  void dispose() {
    _startupCtrl.dispose();
    _needleCtrl.dispose();
    _roadTicker.dispose();
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size;
    final h = w * 179 / 200;
    final fontFamily = DefaultTextStyle.of(context).style.fontFamily;

    final baseLabel = widget.speed == null
        ? '速度无数据，来源${widget.useGps ? 'GPS' : '蓝牙'}'
        : '当前速度 ${widget.speed!.toStringAsFixed(1)} 公里每小时，'
            '来源${widget.useGps ? 'GPS' : '蓝牙'}';
    final markerParts = <String>[
      if (NeedleSpeedometer.markerProgress(widget.avgSpeed) != null)
        '平均速度${widget.avgSpeed!.clamp(0, NeedleSpeedometer.maxSpeed).toStringAsFixed(1)}',
      if (NeedleSpeedometer.markerProgress(widget.peakSpeed) != null)
        '最高速度${widget.peakSpeed!.clamp(0, NeedleSpeedometer.maxSpeed).toStringAsFixed(1)}',
    ];
    final label =
        markerParts.isEmpty ? baseLabel : '$baseLabel，${markerParts.join('，')}';

    return Semantics(
      container: true,
      label: label,
      child: SizedBox(
        key: const ValueKey('needle-speedometer'),
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: _FanPainter(
                  needle: _needleCtrl,
                  startup: _startupCtrl,
                  fontFamily: fontFamily,
                  travel: _travel,
                  avgSpeed: widget.avgSpeed,
                  peakSpeed: widget.peakSpeed,
                  repaint: _repaint,
                ),
                size: Size(w, h),
                willChange: true,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: w * 0.665,
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      widget.speed?.toStringAsFixed(1) ?? '--',
                      key: const ValueKey('gauge-speed-readout'),
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: DashColors.segOn,
                        fontFamily: DashFonts.segMini,
                        fontSize: w * 0.126,
                        height: 1,
                      ),
                    ),
                    SizedBox(height: w * 0.018),
                    Text(
                      'km/h',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: DashColors.muted2,
                        fontSize: w * 0.025,
                        height: 1,
                        letterSpacing: w * 0.006,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FanPainter extends CustomPainter {
  _FanPainter({
    required this.needle,
    required this.startup,
    required this.travel,
    required this.fontFamily,
    this.avgSpeed,
    this.peakSpeed,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// 指针动画进度 0..1（当前速度）。
  final Animation<double> needle;
  final AnimationController startup;
  static const _sweepSpacing = 0.30;
  static const _sweepTravel = 1 + 2 * _sweepSpacing;
  static const _sweepOut = Interval(0, 0.43, curve: Curves.easeInOutSine);
  static const _sweepBack = Interval(0.53, 0.96, curve: Curves.easeInOutSine);

  double _sweepProgress(int order) {
    final time = startup.value;
    final offset = order * _sweepSpacing;
    // 共用一条行程，按满量程距离错开；每根指针在各自端点停住。
    final out =
        (_sweepOut.transform(time) * _sweepTravel - offset).clamp(0.0, 1.0);
    final back =
        (_sweepBack.transform(time) * _sweepTravel - offset).clamp(0.0, 1.0);
    return out - back;
  }

  double get progress => startup.isAnimating ? _sweepProgress(0) : needle.value;

  /// 道路行程 0..1（循环），驱动横纹与中心虚线流动。
  final ValueListenable<double> travel;
  final String? fontFamily;

  /// 平均 / 最高速度标线的原始值（km/h）。
  final double? avgSpeed;
  final double? peakSpeed;
  double? get _avgProgress => startup.isAnimating
      ? _sweepProgress(1)
      : NeedleSpeedometer.markerProgress(avgSpeed);
  double? get _maxProgress => startup.isAnimating
      ? _sweepProgress(2)
      : NeedleSpeedometer.markerProgress(peakSpeed);

  static const double _boxW = 200;
  static const Offset _c = Offset(100, 108);

  static const _startDeg = NeedleSpeedometer.startDeg;
  static const _sweepDeg = NeedleSpeedometer.sweepDeg;
  static const _rimHighlightRadius = 93.0;
  static const _avgColor = Color(0xFF65D8EF);
  static const _maxColor = Color(0xFFFFC02E);

  static const _dialColors = [
    Color(0xFF16263D),
    Color(0xFF101A2B),
    Color(0xFF050a16),
  ];
  static const _needleColors = [
    Color(0xFF8f1018),
    Color(0xFFff2d38),
    Color(0xFFff6b6b),
  ];
  static const _arcColors = [
    Color(0xFF5a1218),
    Color(0xFFd42a34),
    Color(0xFFff5b62),
  ];

  // 道路：远端收进盘面开口的 V 形区域，近端铺到盒边附近。
  static const _roadFarY = 115.0;
  static const _roadNearY = 176.0;
  static const _roadFarHalf = 20.0;
  static const _roadNearHalf = 99.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _boxW;
    canvas.save();
    canvas.scale(scale);

    _drawRoad(canvas);
    _drawCase(canvas);
    _drawArc(canvas);
    _drawTicks(canvas);
    _drawSpeedMarkers(canvas);
    _drawNeedle(canvas);
    _drawGlass(canvas);

    canvas.restore();
  }

  /// 设计稿极坐标：0° 指向正上方，顺时针为正。
  Offset _polar(double r, double deg) {
    final a = deg * math.pi / 180;
    return Offset(_c.dx + r * math.sin(a), _c.dy - r * math.cos(a));
  }

  /// 向 path 添加一段圆弧（Flutter 角度：0 指向右）。
  void _arcTo(Path path, double r, double startDeg, double endDeg) {
    path.arcTo(
      Rect.fromCircle(center: _c, radius: r),
      (startDeg - 90) * math.pi / 180,
      (endDeg - startDeg) * math.pi / 180,
      false,
    );
  }

  Path _sectorPath(double r, double startDeg, double endDeg) {
    final p = Path()..moveTo(_c.dx, _c.dy);
    _arcTo(p, r, startDeg, endDeg);
    p.close();
    return p;
  }

  /* ---------------- 透视道路 ---------------- */
  void _drawRoad(Canvas canvas) {
    const yFar = _roadFarY, yNear = _roadNearY;
    const wFar = _roadFarHalf, wNear = _roadNearHalf;
    const roadRect = Rect.fromLTWH(
      100 - wNear,
      yFar,
      wNear * 2,
      yNear - yFar,
    );

    // 路面梯形：由远及近渐亮
    final surface = Path()
      ..moveTo(100 - wFar, yFar)
      ..lineTo(100 + wFar, yFar)
      ..lineTo(100 + wNear, yNear)
      ..lineTo(100 - wNear, yNear)
      ..close();
    canvas.drawPath(
      surface,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00182439), Color(0x50182439), Color(0x60162843)],
          stops: [0.0, 0.42, 1.0],
        ).createShader(roadRect),
    );

    // 左右边缘线
    final edgeShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x005CA8D8), Color(0x235CA8D8), Color(0x826EBFD9)],
      stops: [0.0, 0.34, 1.0],
    ).createShader(roadRect);
    final edgePaint = Paint()
      ..shader = edgeShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(100 - wFar, yFar),
      const Offset(100 - wNear, yNear),
      edgePaint,
    );
    canvas.drawLine(
      const Offset(100 + wFar, yFar),
      const Offset(100 + wNear, yNear),
      edgePaint,
    );

    // 中心虚线（dash 8 / gap 8，随行程向后流动）
    _drawDashed(
      canvas,
      const Offset(100, yFar),
      const Offset(100, yNear),
      8,
      8,
      (travel.value * 16) % 16,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00A8C5DF), Color(0x28A8C5DF)],
          stops: [0.0, 0.8],
        ).createShader(roadRect)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawLine(
      const Offset(100 - wNear, yNear),
      const Offset(100 + wNear, yNear),
      edgePaint,
    );

    // 6 条横纹：由远及近滚动，近处更宽更亮
    const count = 6;
    for (var i = 0; i < count; i++) {
      final p = ((i / count) + travel.value) % 1;
      final y = yFar + (yNear - yFar) * p;
      final hw = wFar + (wNear - wFar) * p;
      final opacity = 0.17 * p;
      canvas.drawLine(
        Offset(100 - hw, y),
        Offset(100 + hw, y),
        Paint()
          ..color = const Color(0xFFcfe2ff).withValues(alpha: opacity)
          ..strokeWidth = 0.35 + 0.6 * p
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawDashed(Canvas canvas, Offset from, Offset to, double dash,
      double gap, double offset, Paint paint) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len, uy = dy / len;
    var pos = -offset;
    while (pos < len) {
      final a = pos < 0 ? 0.0 : pos;
      final b = (pos + dash).clamp(0.0, len);
      if (b > a) {
        canvas.drawLine(
          Offset(from.dx + ux * a, from.dy + uy * a),
          Offset(from.dx + ux * b, from.dy + uy * b),
          paint,
        );
      }
      pos += dash + gap;
    }
  }

  /* ---------------- 无框盘面 ---------------- */
  void _drawCase(Canvas canvas) {
    const end = _startDeg + _sweepDeg;

    canvas.drawPath(
      _sectorPath(92, _startDeg, end),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.82,
          colors: _dialColors,
          stops: [0.0, 0.58, 1.0],
        ).createShader(const Rect.fromLTWH(8, 16, 184, 184)),
    );

    final rim = Path();
    _arcTo(rim, 92, _startDeg, end);
    canvas.drawPath(
      rim,
      Paint()
        ..color = const Color(0x605A6E85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final rimHighlight = Path();
    _arcTo(rimHighlight, _rimHighlightRadius, _startDeg + 9, end - 9);
    canvas.drawPath(
      rimHighlight,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xA4C2D2E4), Color(0x08788DA6)],
        ).createShader(Rect.fromCircle(center: _c, radius: _rimHighlightRadius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );

    final inner = Path();
    _arcTo(inner, 48, _startDeg, end);
    canvas.drawPath(
      inner,
      Paint()
        ..color = const Color(0x1596B4E6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /* ---------------- 发光弧 ---------------- */
  void _drawArc(Canvas canvas) {
    const r = 84.0;
    const liveWidth = 2.3;
    const avgRadius = r + 0.75;
    const avgWidth = 4.1;
    const maxInner = r - liveWidth / 2;
    const maxOuter = avgRadius + avgWidth / 2;
    const end = _startDeg + _sweepDeg;
    final rect = Rect.fromCircle(center: _c, radius: r);

    // 底轨
    final track = Path();
    _arcTo(track, r, _startDeg, end);
    canvas.drawPath(
      track,
      Paint()
        ..color = const Color(0x1292B0DA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    void drawTripArc(
        double? progress, double radius, double width, Color color) {
      if (progress == null || progress == 0) return;
      final arc = Path();
      _arcTo(arc, radius, _startDeg, _startDeg + _sweepDeg * progress);
      canvas.drawPath(
          arc,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round);
    }

    drawTripArc(
      _maxProgress,
      (maxInner + maxOuter) / 2,
      maxOuter - maxInner,
      _maxColor,
    );
    drawTripArc(_avgProgress, avgRadius, avgWidth, _avgColor);

    // 红色实时弧在顶层，始终跟随指针。
    final filled = _startDeg + _sweepDeg * progress;
    if (filled > _startDeg + 0.1) {
      final shader = const SweepGradient(
        startAngle: (_startDeg - 90) * math.pi / 180,
        endAngle: (end - 90) * math.pi / 180,
        colors: _arcColors,
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect);
      final active = Path();
      _arcTo(active, r, _startDeg, filled);
      canvas.drawPath(
        active,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
      );
      canvas.drawPath(
        active,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = liveWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /* ---------------- 刻度 ---------------- */
  void _drawTicks(Canvas canvas) {
    const steps = 30;
    const majorEvery = 5;
    final minorPaint = Paint()
      ..color = const Color(0x73C8DBF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final majorPaint = Paint()
      ..color = const Color(0xFFdbe8fb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final textStyle = TextStyle(
      fontFamily: fontFamily,
      color: const Color(0xFFC4D6F2),
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );

    for (var i = 0; i <= steps; i++) {
      final deg = _startDeg + _sweepDeg * i / steps;
      final major = i % majorEvery == 0;
      final inner = _polar(major ? 75 : 79, deg);
      final outer = _polar(81, deg);
      canvas.drawLine(inner, outer, major ? majorPaint : minorPaint);
      if (major) {
        final p = _polar(64.5, deg);
        final tp = TextPainter(
          text: TextSpan(
            text: (NeedleSpeedometer.maxSpeed * i / steps).round().toString(),
            style: textStyle,
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  void _drawSpeedMarkers(Canvas canvas) {
    final avg = _avgProgress;
    final max = _maxProgress;
    if (avg != null) {
      final deg = _startDeg + _sweepDeg * avg;
      _drawSpeedMarker(canvas, deg, _avgColor);
      _drawArcLabel(canvas, 'AVG', _avgColor, deg, 101);
    }
    if (max != null) {
      final deg = _startDeg + _sweepDeg * max;
      _drawSpeedMarker(canvas, deg, _maxColor);
      final nearAvg = avg != null && (avg - max).abs() < 0.06;
      if (!nearAvg) _drawArcLabel(canvas, 'MAX', _maxColor, deg, 101);
    }
  }

  void _drawSpeedMarker(Canvas canvas, double deg, Color color) {
    // 局部纵轴朝向圆心，外侧弧边比表盘高光稍向外伸出。
    final outer = _polar(_rimHighlightRadius, deg);
    const outerRadius = _rimHighlightRadius + 1;
    const halfWidth = 14.0;
    final halfAngle = math.asin(halfWidth / outerRadius);
    final edgeDepth = _rimHighlightRadius - outerRadius * math.cos(halfAngle);
    final marker = Path()
      ..addArc(
        Rect.fromCircle(
          center: const Offset(0, _rimHighlightRadius),
          radius: outerRadius,
        ),
        -math.pi / 2 - halfAngle,
        2 * halfAngle,
      )
      ..cubicTo(halfWidth, 3, 11.5, 3.5, 7.5, 3.5)
      ..cubicTo(3.6, 3.5, 0.9, 5.2, 0, 8.5)
      ..cubicTo(-0.9, 5.2, -3.6, 3.5, -7.5, 3.5)
      ..cubicTo(-11.5, 3.5, -halfWidth, 3, -halfWidth, edgeDepth)
      ..close();
    canvas.save();
    canvas.translate(outer.dx, outer.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.drawPath(marker, Paint()..color = color);
    canvas.restore();
  }

  void _drawArcLabel(
    Canvas canvas,
    String label,
    Color color,
    double deg,
    double radius,
  ) {
    final upright = (deg + 90) % 180 - 90;
    final direction = deg.abs() > 90 ? -1 : 1;
    for (var i = 0; i < label.length; i++) {
      final offset = (i - (label.length - 1) / 2) * 3.8 * direction;
      final tp = TextPainter(
        text: TextSpan(
          text: label[i],
          style: TextStyle(
            color: color,
            fontFamily: fontFamily,
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final position = _polar(radius, deg + offset);
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate((upright + offset) * math.pi / 180);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  /* ---------------- 指针 + 轴心 ---------------- */
  void _drawNeedle(Canvas canvas) {
    Path body() => Path()
      ..moveTo(100, 108)
      ..lineTo(95.5, 114)
      ..lineTo(100, 28)
      ..lineTo(104.5, 114)
      ..close();
    Path tail() => Path()
      ..moveTo(97, 108)
      ..lineTo(100, 128)
      ..lineTo(103, 108)
      ..close();

    final deg = NeedleSpeedometer.fanAngleFor(progress);
    canvas.save();
    canvas.translate(_c.dx, _c.dy);
    canvas.rotate(deg);
    canvas.translate(-_c.dx, -_c.dy);

    // 落盘投影
    canvas.save();
    canvas.translate(2, 3);
    canvas.drawPath(body(), Paint()..color = const Color(0x99000000));
    canvas.restore();
    // 尾部
    canvas.drawPath(tail(), Paint()..color = const Color(0xFF7d2a2e));
    // 针身金属渐变
    const needleGradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: _needleColors,
      stops: [0.0, 0.45, 1.0],
    );
    canvas.drawPath(
      body(),
      Paint()
        ..shader =
            needleGradient.createShader(const Rect.fromLTWH(95, 28, 10, 86))
        ..style = PaintingStyle.fill,
    );
    canvas.restore();

    // 轴心（不随针转）
    canvas.drawCircle(
      const Offset(101, 110),
      9,
      Paint()..color = const Color(0x8C000000),
    );
    canvas.drawCircle(_c, 8.5, Paint()..color = const Color(0xFF0a1020));
    canvas.drawCircle(
      _c,
      8.5,
      Paint()
        ..color = const Color(0x4DFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(_c, 5, Paint()..color = const Color(0xFFff3b47));
    canvas.drawCircle(_c, 1.8, Paint()..color = const Color(0xFF0a1020));
  }

  /* ---------------- 玻璃罩高光 ---------------- */
  void _drawGlass(Canvas canvas) {
    const end = _startDeg + _sweepDeg;
    canvas.save();
    canvas.clipPath(_sectorPath(92, _startDeg, end));
    canvas.drawPath(
      _sectorPath(92, _startDeg + 4, end - 4),
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // 高光下移到盘面内侧，避免在外弧形成一圈像"表框"的亮边。
          colors: [Color(0x12FFFFFF), Color(0x03FFFFFF), Color(0x00FFFFFF)],
        ).createShader(const Rect.fromLTWH(8, 44, 184, 84)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FanPainter oldDelegate) =>
      oldDelegate.needle != needle ||
      oldDelegate.travel != travel ||
      oldDelegate.fontFamily != fontFamily ||
      oldDelegate.avgSpeed != avgSpeed ||
      oldDelegate.peakSpeed != peakSpeed;
}
