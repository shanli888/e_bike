import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ride_record.dart';
import '../services/ride_repository.dart';
import '../services/tencent_static_map.dart';
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
          ? const Center(
              child: CircularProgressIndicator(color: DashColors.orange))
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
          Icon(Icons.route,
              size: 56, color: DashColors.muted.withValues(alpha: 0.5)),
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
                  fontFamily: DashFonts.segClassic,
                  fontSize: 20,
                  color: color)),
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

/// 骑行详情页：汇总指标、曲线和轨迹地图。
class RideDetailScreen extends StatefulWidget {
  const RideDetailScreen({super.key, required this.ride, this.loadMap});

  final RideSession ride;
  final Future<Uint8List> Function(Uri)? loadMap;

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  bool _showOnlineMap = true;
  Uri? _mapUri;
  Future<Uint8List>? _mapImage;

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: DashColors.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              _trackMap(ride, topInset, size),
              _rideSheet(ride, size, topInset, bottomInset),
              Positioned(
                top: topInset + 8,
                left: 16,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: DashColors.card,
                    foregroundColor: DashColors.txt,
                  ),
                  icon: const BackButtonIcon(),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rideSheet(
    RideSession ride,
    Size size,
    double topInset,
    double bottomInset,
  ) {
    const restingExtent = 0.53;
    const handleHeight = 26.0;
    const corners = BorderRadius.vertical(top: Radius.circular(30));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = MediaQuery.highContrastOf(context);

    return DraggableScrollableSheet(
      initialChildSize: restingExtent,
      minChildSize: restingExtent,
      maxChildSize:
          (1 - (topInset + 64) / size.height).clamp(restingExtent, 1.0),
      snap: !reduceMotion,
      snapAnimationDuration: const Duration(milliseconds: 260),
      shouldCloseOnMinExtent: false,
      builder: (context, scrollController) => Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: DecoratedBox(
            key: const ValueKey('ride-detail-sheet'),
            decoration: const BoxDecoration(
              borderRadius: corners,
              boxShadow: [
                BoxShadow(
                  color: Color(0x50000918),
                  blurRadius: 26,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: corners,
              child: Stack(
                children: [
                  if (!highContrast)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 80,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  if (highContrast)
                    const Positioned.fill(
                        child: ColoredBox(color: DashColors.bg))
                  else ...[
                    const Positioned.fill(
                      top: 80,
                      child: ColoredBox(color: DashColors.bg),
                    ),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 80,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xD9101729), DashColors.bg],
                          ),
                        ),
                      ),
                    ),
                  ],
                  ListView(
                    key: const ValueKey('ride-detail-scroll'),
                    controller: scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      24,
                      handleHeight + 10,
                      24,
                      bottomInset + 28,
                    ),
                    children: [
                      _rideSummary(ride),
                      const SizedBox(height: 22),
                      const Text(
                        '骑行数据',
                        style: TextStyle(
                          color: DashColors.txt,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _metricsGrid(ride),
                      const SizedBox(height: 20),
                      SpeedElevationChart(
                        points: ride.points,
                        maxSpeedKmh: ride.maxSpeedKmh,
                      ),
                    ],
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: handleHeight,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xEB131A2B), Color(0x00131A2B)],
                          ),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 36,
                            height: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xFF9AA6BC),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(2)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rideSummary(RideSession ride) {
    final date = ride.startTime;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ride.name.trim().isEmpty ? '骑行' : ride.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: DashColors.txt,
            fontSize: 25,
            height: 1.18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${date.year}年${date.month}月${date.day}日 · $hour:$minute',
          style: const TextStyle(color: DashColors.muted2, fontSize: 13),
        ),
      ],
    );
  }

  Widget _trackMap(RideSession ride, double topInset, Size size) {
    return ColoredBox(
      key: const ValueKey('ride-track-map'),
      color: const Color(0xFF0E1626),
      child: ride.points.length < 2
          ? const Align(
              alignment: Alignment(0, -0.5),
              child: Text('本次无轨迹点', style: TextStyle(color: DashColors.muted)))
          : _showOnlineMap
              ? _onlineMap(ride.points, topInset, size)
              : _gridMap(ride.points, topInset),
    );
  }

  Widget _gridMap(List<RidePoint> points, double topInset,
      {bool loading = false, bool failed = false}) {
    return Stack(
      children: [
        // 网格底图 + 轨迹均由本地自绘，不依赖任何地图 SDK / key / 网络瓦片。
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey('ride-track-grid'),
            painter: _TrackPainter(points, topInset),
          ),
        ),
        Positioned(
          top: topInset + 64,
          right: 20,
          child: const Text('N ↑',
              style: TextStyle(color: DashColors.muted, fontSize: 11)),
        ),
        Positioned(
          right: 20,
          top: topInset + 86,
          child: const Text('简略网格轨迹 · 非导航地图',
              style: TextStyle(color: DashColors.muted, fontSize: 11)),
        ),
        Positioned(
          right: 12,
          top: topInset + 8,
          child: loading
              ? const SizedBox.shrink()
              : _mapLabelButton(
                  onPressed: () => setState(() {
                    if (failed) _mapImage = null;
                    _showOnlineMap = true;
                  }),
                  label: failed ? '重试腾讯地图' : '显示腾讯地图',
                ),
        ),
      ],
    );
  }

  Widget _onlineMap(List<RidePoint> points, double topInset, Size size) {
    final mapHeight = size.height * 0.5;
    final scale = 640 / math.max(size.width, mapHeight);
    final uri = TencentStaticMap.forRide(
      points,
      width: math.max(1, (size.width * scale).round()),
      height: math.max(1, (mapHeight * scale).round()),
    );
    if (_mapUri != uri || _mapImage == null) {
      _mapUri = uri;
      _mapImage = (widget.loadMap ?? TencentStaticMapCache.shared.load)(uri);
    }
    return FutureBuilder<Uint8List>(
      key: ValueKey(uri),
      future: _mapImage,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return _gridMap(points, topInset,
              loading: snapshot.connectionState != ConnectionState.done,
              failed: snapshot.hasError);
        }
        return _mapImageView(snapshot.requireData, topInset, mapHeight);
      },
    );
  }

  Widget _mapImageView(Uint8List bytes, double topInset, double mapHeight) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: mapHeight,
          child: Image.memory(
            bytes,
            key: const ValueKey('ride-tencent-map'),
            fit: BoxFit.fill,
          ),
        ),
        Positioned(
          top: topInset + 8,
          right: 12,
          child: _mapLabelButton(
            onPressed: () => setState(() => _showOnlineMap = false),
            label: '网格轨迹',
          ),
        ),
        Positioned(
          top: topInset + 54,
          right: 12,
          child: _mapLabelButton(
            onPressed: () => launchUrl(Uri.https('lbs.qq.com', '/')),
            label: TencentStaticMap.attribution,
          ),
        ),
      ],
    );
  }

  Widget _mapLabelButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF263746),
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
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
    return Table(
      key: const ValueKey('ride-metrics-grid'),
      border: const TableBorder(
        horizontalInside: BorderSide(color: DashColors.subDivider),
      ),
      children: [
        for (var i = 0; i < cells.length; i += 2)
          TableRow(
            children: [
              for (var index = i; index < i + 2; index++)
                Padding(
                  key: ValueKey('ride-metric-$index'),
                  padding: EdgeInsets.fromLTRB(
                    index.isEven ? 0 : 8,
                    8,
                    index.isEven ? 8 : 0,
                    9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cells[index].$1,
                        style: const TextStyle(
                          color: DashColors.muted2,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          text: cells[index].$2,
                          children: [
                            if (cells[index].$3.isNotEmpty)
                              TextSpan(
                                text: ' ${cells[index].$3}',
                                style: const TextStyle(
                                  color: DashColors.muted2,
                                  fontSize: 12,
                                  letterSpacing: 0,
                                ),
                              ),
                          ],
                        ),
                        style: TextStyle(
                          color: index == 0 ? DashColors.green : DashColors.txt,
                          fontSize: index < 2 ? 29 : 23,
                          height: 1.12,
                          letterSpacing: -0.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// 等距投影轨迹绘制：把经纬度线性映射到画布局部坐标，不依赖任何地图底图/SDK。
/// 底图是自绘的经纬网格（仅作空间参考，不含任何真实地理要素/边界/地名）。
class _TrackPainter extends CustomPainter {
  _TrackPainter(this.points, this.topInset);

  final List<RidePoint> points;
  final double topInset;

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
    var span = spanX > spanY ? spanX : spanY;
    // 两点重合时给一个默认视野，仍能画出网格底图，不至于整块空白。
    if (span < 1e-9) {
      span = 0.01;
      minLon -= 0.005;
      maxLon += 0.005;
      minLat -= 0.005;
      maxLat += 0.005;
    }
    const pad = 26.0;
    final drawW = size.width - pad * 2;
    final routeTop = math.min(topInset + 88, size.height * 0.28);
    final routeBottom = size.height * 0.47;
    final drawH = routeBottom - routeTop;
    final scale = drawW < drawH ? drawW / span : drawH / span;
    final offX = (size.width - spanX * scale) / 2;
    final offY = routeTop + (drawH - spanY * scale) / 2;

    // 先画简略网格底图（视野覆盖整块画布，随轨迹范围自适应步长）。
    _drawGrid(canvas, size, minLat, maxLat, minLon, cosLat, scale, offX, offY);

    Offset toOffset(RidePoint p) => Offset(
          offX + (p.lon - minLon) * cosLat * scale,
          offY + (maxLat - p.lat) * scale,
        );

    final path = Path()
      ..moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
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

  /// 自绘经纬度参考网格：按视野跨度取 1/2/5×10^n 的整齐步长，
  /// 让画布上大约出现 4~8 条线。不绘制任何真实地理要素。
  void _drawGrid(Canvas canvas, Size size, double minLat, double maxLat,
      double minLon, double cosLat, double scale, double offX, double offY) {
    final lonStep = _niceStep((size.width / scale / cosLat) / 6);
    final latStep = _niceStep((size.height / scale) / 6);
    if (lonStep <= 0 || latStep <= 0) return;

    // 画布可见范围对应的经纬度（把 offX/offY 的平移反推回地理坐标）。
    final viewMinLon = minLon - offX / (cosLat * scale);
    final viewMaxLon = minLon + (size.width - offX) / (cosLat * scale);
    final viewMaxLat = maxLat + offY / scale;
    final viewMinLat = maxLat - (size.height - offY) / scale;

    final minor = Paint()
      ..color = DashColors.line.withValues(alpha: 0.6)
      ..strokeWidth = 0.8;
    final major = Paint()
      ..color = DashColors.line.withValues(alpha: 0.95)
      ..strokeWidth = 1.4;

    // 竖线（经线）：lon 递增，x 随之右移。
    var i = 0;
    for (var lon = (viewMinLon / lonStep).floor() * lonStep;
        lon <= viewMaxLon + 1e-12;
        lon += lonStep, i++) {
      final x = offX + (lon - minLon) * cosLat * scale;
      canvas.drawLine(
          Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
    }
    // 横线（纬线）：lat 递增，y 随之上移。
    i = 0;
    for (var lat = (viewMinLat / latStep).floor() * latStep;
        lat <= viewMaxLat + 1e-12;
        lat += latStep, i++) {
      final y = offY + (maxLat - lat) * scale;
      canvas.drawLine(
          Offset(0, y), Offset(size.width, y), i % 5 == 0 ? major : minor);
    }
  }

  /// 取接近 raw 的整齐步长（1/2/5 × 10^n）。
  static double _niceStep(double raw) {
    if (raw <= 0 || !raw.isFinite) return 0;
    final power = math.log(raw) / math.ln10;
    final base = math.pow(10, power.floor()).toDouble();
    final f = raw / base;
    final m = f <= 1
        ? 1.0
        : f <= 2
            ? 2.0
            : f <= 5
                ? 5.0
                : 10.0;
    return m * base;
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) =>
      old.points != points || old.topInset != topInset;
}
