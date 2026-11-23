import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ride_record.dart';
import '../theme/dashboard_theme.dart';

/// 图表用的单采样点：由轨迹点换算出的累计距离、经过分钟、瞬时速度与海拔。
@immutable
class ChartSample {
  const ChartSample({
    required this.distanceKm,
    required this.minutes,
    required this.speedKmh,
    required this.altitudeM,
  });

  final double distanceKm;
  final double minutes;
  final double speedKmh;
  final double altitudeM;
}

/// 纯数据工具：把轨迹点换算成图表采样，并计算极值。
/// 独立于 Flutter 绘制，便于单测。
class RideChartData {
  RideChartData._();

  /// 相邻两点球面距离（米），WGS-84 等距近似，与记录器口径一致。
  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const radius = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * radius * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  /// 轨迹点 -> 图表采样。累计距离忽略 >200m 的跳点（与记录器滤波一致）。
  static List<ChartSample> samples(List<RidePoint> points) {
    if (points.isEmpty) return const [];
    final start = points.first.t;
    final out = <ChartSample>[];
    var accM = 0.0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (i > 0) {
        final prev = points[i - 1];
        final meters = haversineMeters(prev.lat, prev.lon, p.lat, p.lon);
        if (meters <= 200) accM += meters;
      }
      out.add(ChartSample(
        distanceKm: accM / 1000,
        minutes: p.t.difference(start).inSeconds / 60.0,
        speedKmh: p.speedKmh,
        altitudeM: p.alt,
      ));
    }
    return out;
  }

  static double maxAltitude(List<RidePoint> points) {
    var m = 0.0;
    for (final p in points) {
      if (p.alt > m) m = p.alt;
    }
    return m;
  }

  static double maxSpeed(List<RidePoint> points) {
    var m = 0.0;
    for (final p in points) {
      if (p.speedKmh > m) m = p.speedKmh;
    }
    return m;
  }
}

/// X 轴口径：按累计距离或按经过时间。
enum ChartXAxis { distance, time }

/// 速度与海拔双轴图表卡片。
/// - 左轴（橙）：速度 km/h，折线；
/// - 右轴（灰）：海拔 m，填充面积；
/// - X 轴可在「距离 / 时间」间切换。
class SpeedElevationChart extends StatefulWidget {
  const SpeedElevationChart({
    super.key,
    required this.points,
    this.maxSpeedKmh,
    this.height = 224,
  });

  final List<RidePoint> points;

  /// 汇总里的极速。若给出且大于轨迹采样最大值，用于速度轴上界，避免截顶。
  final double? maxSpeedKmh;
  final double height;

  @override
  State<SpeedElevationChart> createState() => _SpeedElevationChartState();
}

class _SpeedElevationChartState extends State<SpeedElevationChart> {
  ChartXAxis _axis = ChartXAxis.distance;

  @override
  Widget build(BuildContext context) {
    final samples = RideChartData.samples(widget.points);
    final maxSpeed =
        math.max(RideChartData.maxSpeed(widget.points), widget.maxSpeedKmh ?? 0);
    final maxAlt = RideChartData.maxAltitude(widget.points);

    return Container(
      key: const ValueKey('speed-elevation-chart'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: DashColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DashColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('速度与海拔',
                  style: TextStyle(
                      color: DashColors.txt,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              _AxisSwitch(axis: _axis, onChanged: (a) => setState(() => _axis = a)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _headline(
                    keyName: 'chart-max-speed',
                    value: maxSpeed.toStringAsFixed(1),
                    unit: 'km/h',
                    label: '最大速度',
                    color: DashColors.orange),
              ),
              Expanded(
                child: _headline(
                    keyName: 'chart-max-altitude',
                    value: maxAlt.toStringAsFixed(0),
                    unit: 'm',
                    label: '最高海拔',
                    color: DashColors.muted2),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: widget.height,
            child: samples.length < 2
                ? const Center(
                    child: Text('轨迹点不足，暂无图表',
                        key: ValueKey('chart-empty'),
                        style:
                            TextStyle(color: DashColors.muted, fontSize: 12)))
                : CustomPaint(
                    key: ValueKey('chart-painter-${_axis.name}'),
                    painter: _ChartPainter(samples, _axis),
                    size: Size.infinite,
                  ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Legend(color: DashColors.orange, label: '速度', line: true),
              SizedBox(width: 20),
              _Legend(color: DashColors.muted2, label: '海拔', line: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headline({
    required String keyName,
    required String value,
    required String unit,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                key: ValueKey(keyName),
                style: TextStyle(
                    fontFamily: DashFonts.segClassic,
                    fontSize: 26,
                    color: color)),
            const SizedBox(width: 4),
            Text(unit,
                style: const TextStyle(color: DashColors.muted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: DashColors.muted, fontSize: 11)),
      ],
    );
  }
}

class _AxisSwitch extends StatelessWidget {
  const _AxisSwitch({required this.axis, required this.onChanged});

  final ChartXAxis axis;
  final ValueChanged<ChartXAxis> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(ChartXAxis a, String label) {
      final selected = a == axis;
      return GestureDetector(
        key: ValueKey('chart-axis-${a.name}'),
        onTap: () => onChanged(a),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? DashColors.orange.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? DashColors.orange : DashColors.line),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? DashColors.orange : DashColors.muted,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [btn(ChartXAxis.distance, '距离'), btn(ChartXAxis.time, '时间')],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.line});

  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: line ? 2 : 9,
          decoration: BoxDecoration(
            color: line
                ? color
                : color.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(line ? 1 : 2),
            border: line ? null : Border.all(color: color.withValues(alpha: 0.7)),
          ),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(color: DashColors.muted, fontSize: 11)),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.samples, this.axis);

  final List<ChartSample> samples;
  final ChartXAxis axis;

  static const left = 38.0;
  static const right = 38.0;
  static const top = 10.0;
  static const bottom = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    if (w <= 0 || h <= 0) return;

    double xOf(ChartSample s) {
      final maxX = axis == ChartXAxis.distance
          ? samples.last.distanceKm
          : samples.last.minutes;
      final v = axis == ChartXAxis.distance ? s.distanceKm : s.minutes;
      return maxX <= 0 ? left : left + (v / maxX) * w;
    }

    // 速度轴 0 ~ ceil(max/10)*10（至少 10）；海拔轴 floor(min)~ceil(max) 留起伏空间。
    var maxSpeed = 0.0;
    for (final s in samples) {
      if (s.speedKmh > maxSpeed) maxSpeed = s.speedKmh;
    }
    final speedTop = math.max(10.0, (maxSpeed / 10).ceil() * 10.0);
    var minAlt = double.infinity;
    var maxAlt = double.negativeInfinity;
    for (final s in samples) {
      if (s.altitudeM < minAlt) minAlt = s.altitudeM;
      if (s.altitudeM > maxAlt) maxAlt = s.altitudeM;
    }
    if (!minAlt.isFinite) {
      minAlt = 0;
      maxAlt = 1;
    }
    final altFloor = (minAlt / 10).floor() * 10.0;
    var altCeil = (maxAlt / 10).ceil() * 10.0;
    if (altCeil - altFloor < 10) altCeil = altFloor + 10;

    double ySpeed(double v) => top + h - (v / speedTop).clamp(0.0, 1.0) * h;
    double yAlt(double v) =>
        top + h - ((v - altFloor) / (altCeil - altFloor)).clamp(0.0, 1.0) * h;

    // 网格 + 左右轴刻度（4 等分）。
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), gridPaint);
      final speedLabel = (speedTop * (1 - i / 4)).round().toString();
      final altLabel = (altFloor + (altCeil - altFloor) * (1 - i / 4))
          .round()
          .toString();
      _text(canvas, speedLabel, Offset(left - 5, y - 6),
          DashColors.orange.withValues(alpha: 0.75), 9, TextAlign.right);
      _text(canvas, altLabel, Offset(left + w + 5, y - 6),
          DashColors.muted2.withValues(alpha: 0.75), 9, TextAlign.left);
    }

    // 海拔灰色填充面积。
    final area = Path()
      ..moveTo(xOf(samples.first), top + h);
    for (final s in samples) {
      area.lineTo(xOf(s), yAlt(s.altitudeM));
    }
    area
      ..lineTo(xOf(samples.last), top + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()..color = DashColors.muted2.withValues(alpha: 0.22),
    );

    // 速度橙色折线。
    final line = Path()..moveTo(xOf(samples.first), ySpeed(samples.first.speedKmh));
    for (final s in samples.skip(1)) {
      line.lineTo(xOf(s), ySpeed(s.speedKmh));
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = DashColors.orange,
    );

    // X 轴刻度：起点 / 中点 / 终点。
    final maxX = axis == ChartXAxis.distance
        ? samples.last.distanceKm
        : samples.last.minutes;
    String xLabel(double v) => axis == ChartXAxis.distance
        ? v.toStringAsFixed(v < 10 ? 1 : 0)
        : '${v.round()}′';
    _text(canvas, xLabel(0), Offset(left, top + h + 5), DashColors.muted, 9,
        TextAlign.left);
    _text(canvas, xLabel(maxX / 2), Offset(left + w / 2, top + h + 5),
        DashColors.muted, 9, TextAlign.center);
    _text(canvas, xLabel(maxX), Offset(left + w, top + h + 5), DashColors.muted,
        9, TextAlign.right);
  }

  void _text(Canvas canvas, String text, Offset pos, Color color, double size,
      TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: size)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.samples != samples || old.axis != axis;
}
