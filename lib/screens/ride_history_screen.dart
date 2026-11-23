import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ride_record.dart';
import '../services/ride_repository.dart';
import '../theme/dashboard_theme.dart';
import '../widgets/speed_elevation_chart.dart';

/// 骑行历史列表页：生涯统计 + 每次骑行卡片，点击进入详情。
class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key, required this.repository});

  final RideRepository repository;

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  List<RideSession> _rides = const [];
  ({int count, double distanceKm, double ascentM})? _totals;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rides = await widget.repository.listAll();
    final totals = await widget.repository.totals();
    if (!mounted) return;
    setState(() {
      _rides = rides;
      _totals = totals;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashColors.bg,
      appBar: AppBar(
        title: const Text('骑行记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DashColors.orange))
          : _rides.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: DashColors.orange,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _summaryStrip(),
                      const SizedBox(height: 12),
                      Text(
                        '全部骑行（${_rides.length}）',
                        style: const TextStyle(
                            color: DashColors.muted,
                            fontSize: 12,
                            letterSpacing: 1),
                      ),
                      const SizedBox(height: 6),
                      ..._rides.map((r) => _rideCard(r)),
                    ],
                  ),
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route, size: 56, color: DashColors.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('还没有骑行记录',
              style: TextStyle(color: DashColors.txt, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('回到码表页点击「开始骑行」即可记录',
              style: TextStyle(color: DashColors.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _summaryStrip() {
    final t = _totals!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: DashColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DashColors.line),
      ),
      child: Row(
        children: [
          _stat('${t.count}', '次骑行', DashColors.txt),
          _stat(t.distanceKm.toStringAsFixed(1), '总里程 km', DashColors.green),
          _stat(t.ascentM.toStringAsFixed(0), '总爬升 m', DashColors.amber),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontFamily: DashFonts.segClassic, fontSize: 20, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: DashColors.muted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _rideCard(RideSession r) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RideDetailScreen(ride: r)),
      ),
      child: Container(
        key: ValueKey('ride-card-${r.id}'),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: DashColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DashColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pedal_bike, color: DashColors.green, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(r.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: DashColors.txt,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${r.startTime.month}/${r.startTime.day} '
                        '${_two(r.startTime.hour)}:${_two(r.startTime.minute)}',
                        style: const TextStyle(
                            color: DashColors.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                // IconButton 的最小点击区会把标题行撑到 40px；这里用
                // 固定 22px 的 InkWell 保留点击语义，让卡片更紧凑。
                SizedBox(
                  width: 22,
                  height: 22,
                  child: InkWell(
                    key: ValueKey('delete-${r.id}'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _confirmDelete(r),
                    child: const Icon(Icons.delete_outline,
                        color: DashColors.red, size: 18),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: DashColors.muted, size: 16),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _cell('距离', r.distanceKm.toStringAsFixed(2), 'km'),
                _cell('时长', r.durationLabel, ''),
                _cell('均速', r.avgSpeedKmh.toStringAsFixed(1), ''),
                _cell('爬升', r.ascentM.toStringAsFixed(0), 'm'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 删除前二次确认，避免误触丢失骑行数据。
  Future<void> _confirmDelete(RideSession ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DashColors.card,
        title: const Text('删除骑行记录',
            style: TextStyle(color: DashColors.txt, fontSize: 17)),
        content: Text(
          '确定删除「${ride.name}」吗？\n删除后无法恢复。',
          style: const TextStyle(color: DashColors.muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            key: const ValueKey('delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: DashColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.repository.delete(ride.id);
    await _load();
  }

  Widget _cell(String label, String value, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 数值用 DSEG7、单位用普通字体：数字字体渲染字母会变形。
          // 紧凑排版：单位并入标签行（仍用普通字体），四列只保留
          // 「数值 / 标签+单位」两行，避免为无单位列多留一整行空白。
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                      fontFamily: DashFonts.segClassic,
                      fontSize: 16,
                      height: 1.0,
                      color: DashColors.txt)),
            ),
          ),
          const SizedBox(height: 1),
          SizedBox(
            height: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: DashColors.muted, fontSize: 10, height: 1.0)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(unit,
                      style: const TextStyle(
                          color: DashColors.muted, fontSize: 9, height: 1.0)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// 骑行详情页：汇总指标 + 简易轨迹缩略图（自绘，WGS-84 等距投影）。
class RideDetailScreen extends StatelessWidget {
  const RideDetailScreen({super.key, required this.ride});

  final RideSession ride;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashColors.bg,
      appBar: AppBar(title: const Text('骑行详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _trackMap(ride),
          const SizedBox(height: 16),
          SpeedElevationChart(
            points: ride.points,
            maxSpeedKmh: ride.maxSpeedKmh,
          ),
          const SizedBox(height: 16),
          _metricsGrid(ride),
        ],
      ),
    );
  }

  Widget _trackMap(RideSession ride) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DashColors.line),
      ),
      child: ride.points.length < 2
          ? const Center(
              child: Text('本次无轨迹点',
                  style: TextStyle(color: DashColors.muted)))
          : CustomPaint(
              painter: _TrackPainter(ride.points),
              size: Size.infinite,
            ),
    );
  }

  Widget _metricsGrid(RideSession ride) {
    final cells = <(String, String, String)>[
      ('距离', ride.distanceKm.toStringAsFixed(2), 'km'),
      ('移动时长', ride.durationLabel, ''),
      ('均速', ride.avgSpeedKmh.toStringAsFixed(1), 'km/h'),
      ('极速', ride.maxSpeedKmh.toStringAsFixed(1), 'km/h'),
      ('爬升', ride.ascentM.toStringAsFixed(0), 'm'),
      ('下降', ride.descentM.toStringAsFixed(0), 'm'),
      ('最高海拔', RideChartData.maxAltitude(ride.points).toStringAsFixed(0), 'm'),
      ('消耗', '${ride.calories}', 'kcal'),
    ];
    return GridView.count(
      key: const ValueKey('ride-metrics-grid'),
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.15,
      children: cells
          .map((c) => Container(
                decoration: BoxDecoration(
                  color: DashColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DashColors.line),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(c.$1,
                        style: const TextStyle(
                            color: DashColors.muted, fontSize: 11)),
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(c.$2,
                          style: const TextStyle(
                              fontFamily: DashFonts.segClassic,
                              fontSize: 20,
                              color: DashColors.txt)),
                    ),
                    if (c.$3.isNotEmpty)
                      Text(c.$3,
                          style: const TextStyle(
                              color: DashColors.muted, fontSize: 9)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

/// 等距投影轨迹绘制：把经纬度线性映射到画布局部坐标，不依赖任何地图底图/SDK。
class _TrackPainter extends CustomPainter {
  _TrackPainter(this.points);

  final List<RidePoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    var minLat = points.first.lat;
    var maxLat = minLat;
    var minLon = points.first.lon;
    var maxLon = minLon;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }
    // 纬度随纬度的经度缩放，避免高纬度拉伸
    final cosLat = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final spanX = ((maxLon - minLon) * cosLat).abs();
    final spanY = (maxLat - minLat).abs();
    final span = spanX > spanY ? spanX : spanY;
    if (span == 0) return;
    const pad = 26.0;
    final drawW = size.width - pad * 2;
    final drawH = size.height - pad * 2;
    final scale = drawW < drawH ? drawW / span : drawH / span;
    final offX = (size.width - spanX * scale) / 2;
    final offY = (size.height - spanY * scale) / 2;

    Offset toOffset(RidePoint p) => Offset(
          offX + (p.lon - minLon) * cosLat * scale,
          offY + (maxLat - p.lat) * scale,
        );

    final path = Path()..moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toOffset(p);
      path.lineTo(o.dx, o.dy);
    }

    // 外发光底层
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = DashColors.green.withValues(alpha: 0.14),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = DashColors.green,
    );

    // 起终点
    final start = toOffset(points.first);
    final end = toOffset(points.last);
    canvas.drawCircle(start, 5, Paint()..color = DashColors.green);
    canvas.drawCircle(end, 5, Paint()..color = const Color(0xFFFF4D5E));
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) => old.points != points;
}
