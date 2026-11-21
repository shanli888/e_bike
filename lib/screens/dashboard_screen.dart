import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/assist_mode.dart';
import '../models/bike_data.dart';
import '../models/command_result.dart';
import '../models/demo_ride_data.dart';
import '../services/assist_remote_scheduler.dart';
import '../services/assist_step_action.dart';
import '../services/assist_step_settings.dart';
import '../services/ble_service.dart';
import '../services/br80_protocol.dart';
import '../services/br80_service.dart';
import '../services/demo_mode_settings.dart';
import '../services/display_mode_settings.dart';
import '../services/gps_service.dart';
import '../theme/dashboard_theme.dart';
import '../theme/sensor_status.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/ride_record_bar.dart';
import '../widgets/needle_speedometer.dart';
import '../widgets/segment_display.dart';

/// 陀螺仪双向分段条的配置：`side` 为 -1 下坡（向左）、0 平路、1 上坡（向右），
/// `level` 为单侧亮起的格数（0~5）；`hasData` 为 false 时全部熄灭。
class SlopeBar {
  const SlopeBar({
    required this.hasData,
    this.side = 0,
    this.level = 0,
  });
  final bool hasData;
  final int side;
  final int level;
}

/// 主界面 - 码表显示
///
/// 视觉基准：《智能码表界面 · 布局规格说明书》与 `speedometer-redesign.html`
/// （390×844 一屏无滚动，§1.2 分区表 / §1.4 配色 / §2 坐标 / §4 数字规则）。
/// 骑行时间、副速度对比、可配置步进、闪控联动等既有功能全部保留。
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onOpenDevices,
    this.onOpenHistory,
    this.onStartRide,
    this.onFinishRide,
    this.demoClock,
    this.showStartupSweep = false,
  });

  final bool showStartupSweep;

  /// 未连接时点「去连接」跳到设备页（由外层底部导航切换）
  final VoidCallback? onOpenDevices;

  /// 打开骑行历史页
  final VoidCallback? onOpenHistory;

  /// 骑行记录：开始 / 结束（含汇总弹层）
  final Future<void> Function()? onStartRide;
  final Future<void> Function()? onFinishRide;

  /// 演示数据的时间源；仅供测试注入固定/可推进的时钟，生产环境用系统时间。
  final DateTime Function()? demoClock;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _refreshTimer;

  /// 速度区当前页：0=指针表盘（默认），1=数码管数字。左右滑动切换。
  int _speedPage = 0;
  late final Br80Service _remote;
  Br80KeyEvent? _handledRemotePress;
  ModalRoute<dynamic>? _route;

  /// 速度区本次横向拖动累计位移，用于松手时判断切换方向（比甩动速度更稳）。
  double _speedDragDx = 0;

  /// 正在等待设备确认的指令说明（非空时禁用助力按钮）
  String? _pendingCommand;
  double? _percentDraft;
  String _version = '--';

  /// 演示模式下的助力控件状态：只存在于 State，不写入 BleService。
  AssistMode? _demoMode;
  int? _demoPercent;
  int? _demoLevel;

  /// 规格基准：844 视口扣除模拟状态栏 38、标题栏 55、标签栏 66 后的内容区。
  static const double _designContentHeight = 685;

  /// 主速度小数位正上方的来源图标，与小数数字顶部保持的间距（基准 px）。
  /// 原先 9px 太贴字，按反馈上移到 16px。
  static const double _primarySourceIconGap = 16.0;

  /// 顶部一栏里「骑行时间」与「副速度」两组数码管共用的字号，保证同款字体。
  static const double _topSegmentHeight = 22.0;
  static const Color _topSegmentInk = Color(0xBFE9F1FF);

  @override
  void initState() {
    super.initState();
    _remote = context.read<Br80Service>();
    _handledRemotePress = _remote.lastPressedKey;
    _remote.addListener(_onRemoteChanged);
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      // 测试环境或插件不可用时保留占位符
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _remote.removeListener(_onRemoteChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onRemoteChanged() {
    final press = _remote.lastPressedKey;
    if (identical(press, _handledRemotePress)) return;
    _handledRemotePress = press;
    final direction = press?.speedPageDirection;
    if (direction != null && _route?.isCurrent != false) {
      _changeSpeedPage(direction);
    }
  }

  void _changeSpeedPage(int direction) {
    setState(() => _speedPage = (_speedPage + direction) % 2);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<BleService, GpsService, DemoModeSettings, DisplayModeSettings>(
      builder: (context, ble, gps, demoSettings, displayMode, _) {
        // 连上真实控制器后自动切回真实数据，演示数据只在断连时生效。
        final demo = demoSettings.isActive(ble.isConnected);
        // 演示数据每次重建都按当前时间取一组值，配合 500ms 刷新形成循环动画。
        final demoNow = widget.demoClock?.call() ?? DateTime.now();
        final data = demo ? DemoRideData.bikeData(demoNow) : ble.bikeData;

        // 分水岭：控制器 / 闪控任一连接即完整模式；锁定开关优先。
        // 演示模式视为「虚拟连接」——它存在的意义就是预览完整助力界面，
        // 因此演示开启时不进入纯码表模式，继续展示助力卡与传感器演示数据。
        final remote = context.watch<Br80Service>();
        final isPure = !demo &&
            displayMode.isPureComputer(
              controllerConnected: ble.isConnected,
              remoteConnected: remote.isConnected,
            );

        return LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final scale =
                (h.isFinite ? h / _designContentHeight : 1.0).clamp(0.55, 1.15);
            return DecoratedBox(
              decoration:
                  const BoxDecoration(gradient: DashColors.pageBackground),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 速度区吃掉剩余空间（规格 218px）
                  Expanded(child: _buildSpeedHero(ble, gps, data, scale, demo)),
                  // 表盘页走极简沉浸模式：收起 AVG/MAX/km 一排，把空间让给放大后的表盘。
                  // 数字页保持原样。widget 仍在树中（高度归零 + 裁剪），既有断言不受影响。
                  _buildSubTable(ble, gps, data, scale, demo,
                      collapsed: _speedPage == 0),
                  _buildSpeedPageIndicator(scale),
                  // 记录控制条：两种模式都显示；纯码表模式占据主位（非紧凑）。
                  RideRecordBar(
                    scale: scale,
                    compact: !isPure,
                    onStart: () => widget.onStartRide?.call(),
                    onFinish: () => widget.onFinishRide?.call(),
                    onViewHistory: widget.onOpenHistory,
                    onConnectAssist: isPure ? widget.onOpenDevices : null,
                  ),
                  // 纯码表模式隐藏助力卡与传感器行；腾出的空间给记录控制条与表盘。
                  if (!isPure) ...[
                    _buildAssistCard(ble, scale, demo),
                    _buildSensorRow(data, scale),
                  ],
                  _buildVersionLine(scale),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 速度来源图标：GPS 用定位图标（绿），蓝牙用蓝牙图标（蓝）。
  Widget _buildSourceIcon(bool isGps,
      {required double size, String keyPrefix = 'source'}) {
    return Icon(
      isGps ? Icons.gps_fixed : Icons.bluetooth,
      key: ValueKey('$keyPrefix-icon-${isGps ? 'gps' : 'bluetooth'}'),
      size: size,
      color: isGps ? DashColors.sourceGps : DashColors.sourceBluetooth,
    );
  }

  /// 主速度区：指针表盘（默认）与七段液晶大字左右滑动切换，右上角副速度常驻。
  ///
  /// 两视图始终 Stack 叠加在各自的原位置，仅切换透明度：这样数码管视图的
  /// key / 布局坐标保持不变（既有测试与无障碍读取不受影响），同时默认呈现
  /// 用户选定的仿真指针表盘。左右滑动或按闪控左右键均可循环切换。
  Widget _buildSpeedHero(
      BleService ble, GpsService gps, BikeData data, double s, bool demo) {
    final useGps = gps.source == SpeedSource.gps;
    final value = demo
        ? data.speed
        : (useGps ? gps.speedKmh : (data.speedAvailable ? data.speed : null));
    final speedText = value?.clamp(0, 99.9).toStringAsFixed(1);
    final showComparison = gps.comparisonEnabled;
    final secondaryValue = demo
        ? DemoRideData.secondarySpeedKmh.toStringAsFixed(1)
        : (useGps
            ? (data.speedAvailable ? data.speed.toStringAsFixed(1) : '--')
            : (gps.speedKmh?.toStringAsFixed(1) ?? '--'));

    // 表盘标线与副表采用同一套来源逻辑：演示模式固定演示 AVG/MAX；
    // 真实模式采用对应速度来源的本地统计。
    final markerUseGps = !demo && gps.source == SpeedSource.gps;
    final avgMark = demo
        ? DemoRideData.avgSpeedKmh
        : (markerUseGps
            ? gps.avgSpeedKmh
            : (data.tripAvailable ? data.avgSpeed : null));
    final maxMark = demo
        ? DemoRideData.maxSpeedKmh
        : (markerUseGps
            ? gps.maxSpeedKmh
            : (data.tripAvailable ? data.maxSpeed : null));

    final showGauge = _speedPage == 0;

    return Padding(
      // 左右留白收到最小，把宽度尽量让给放大后的表盘（FittedBox 仍会按高度兜底）。
      padding: EdgeInsets.symmetric(horizontal: 4 * s),
      child: GestureDetector(
        // 横向滑动切换视图；translucent 让整块区域都能接收拖动，
        // 同时 tap 手势仍下发给子级（副速度 pill），两者不抢占。
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _speedDragDx = 0,
        onHorizontalDragUpdate: (details) => _speedDragDx += details.delta.dx,
        onHorizontalDragEnd: (_) {
          // 手势方向与翻页方向相反；位移过小则不切换。
          if (_speedDragDx.abs() > 40) {
            _changeSpeedPage(_speedDragDx < 0 ? 1 : -1);
          }
          _speedDragDx = 0;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 数码管视图：位置与尺寸完全沿用旧实现，仅淡入淡出。
            AnimatedOpacity(
              key: const ValueKey('speed-number-page'),
              opacity: showGauge ? 0 : 1,
              duration: const Duration(milliseconds: 260),
              child: Center(child: _buildSpeedNumber(speedText, useGps, s)),
            ),
            // 指针表盘视图：默认可见。表盘页收起副表后区域更高，放大填充。
            AnimatedOpacity(
              key: const ValueKey('speed-gauge-page'),
              opacity: showGauge ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              child: Padding(
                padding: EdgeInsets.only(bottom: 10 * s),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: NeedleSpeedometer(
                      speed: value,
                      useGps: useGps,
                      avgSpeed: avgMark,
                      peakSpeed: maxMark,
                      showStartupSweep: widget.showStartupSweep,
                      size: 420 * s,
                    ),
                  ),
                ),
              ),
            ),
            // 右上角副速度（切换来源）：表盘页极简模式淡出隐藏，数字页显示。
            // 保留透明热区而非移除：既不破坏视觉简洁，又让表盘页右上角仍可切来源
            // （表盘中心图标随之变化），同时兼容既有 key / tap 断言。
            if (showComparison)
              Positioned(
                right: 2 * s,
                top: 6 * s,
                child: AnimatedOpacity(
                  opacity: showGauge ? 0 : 1,
                  duration: const Duration(milliseconds: 220),
                  child: _buildSecondaryPill(
                    secondaryValue,
                    !useGps,
                    s,
                    onTap: () => unawaited(_toggleSpeedSource(gps, useGps)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedPageIndicator(double s) {
    final showGauge = _speedPage == 0;
    return Semantics(
      label: showGauge ? '当前为仪表盘码表' : '当前为数字码表',
      child: SizedBox(
        key: const ValueKey('speed-page-indicator'),
        height: 16 * s,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pageDot(active: showGauge, s: s),
            SizedBox(width: 6 * s),
            _pageDot(active: !showGauge, s: s),
          ],
        ),
      ),
    );
  }

  Widget _pageDot({required bool active, required double s}) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: active ? 14 * s : 5 * s,
        height: 5 * s,
        decoration: BoxDecoration(
          color:
              active ? DashColors.orange : Colors.white.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(3 * s),
        ),
      );

  /// 单击右上角副速度区域：在蓝牙 / GPS 之间交替切换主速度来源。
  /// 大字与副速度的数值随之互换，副速度始终展示「另一个来源」。
  Future<void> _toggleSpeedSource(GpsService gps, bool useGps) async {
    final next = useGps ? SpeedSource.bluetooth : SpeedSource.gps;
    final ok = await gps.setSource(next);
    if (!mounted) return;
    if (!ok) {
      showAppToast(context, 'GPS 不可用：${gps.status}', error: true);
    } else {
      showAppToast(
          context, '主速度切换为${next.label} · 副速度显示${useGps ? 'GPS' : '蓝牙'}');
    }
  }

  /// 整数 2 位 / 小数 1 位，128px : 74px 基线对齐（规格 §2.3）。
  /// 小数位正上方在原型里是 km/h，按「保留现有功能」改为速度来源图标。
  Widget _buildSpeedNumber(String? text, bool useGps, double s) {
    const bigH = 128.0;
    const smallH = 74.0;
    // DSEG7 字体的数字 advance width = 0.816em，用于整行宽度与来源图标定位。
    const ratio = DashFonts.advanceRatio;
    const bigW = bigH * ratio;
    const smallW = smallH * ratio;
    const gap1 = bigH * 0.055;
    const dotW = bigH * 0.102;
    const gap2 = bigH * 0.042;
    const totalW = bigW * 2 + gap1 + dotW + gap2 + smallW;
    const fracCenterX = bigW * 2 + gap1 + dotW + gap2 + smallW / 2;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: totalW * s,
        height: bigH * s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              bottom: 0,
              child: SegmentNumber(
                key: const ValueKey('primary-speed'),
                text: text,
                integerDigits: 2,
                fractionDigits: 1,
                height: bigH * s,
                fractionHeight: smallH * s,
                semanticsLabel: text ?? '--',
              ),
            ),
            Positioned(
              left: (fracCenterX - 8) * s,
              bottom: (smallH + _primarySourceIconGap) * s,
              child:
                  _buildSourceIcon(useGps, size: 15 * s, keyPrefix: 'primary'),
            ),
          ],
        ),
      ),
    );
  }

  /// 副速度对比（右上角，与设置里的「副速度对比」开关联动）。
  ///
  /// 数值也用 DSEG7 数码管，和左侧骑行时间同款字号；整块可点击，
  /// 单击即在蓝牙 / GPS 之间交替切换主速度来源。
  Widget _buildSecondaryPill(String value, bool useGps, double s,
      {required VoidCallback onTap}) {
    final hasData = value != '--';
    return GestureDetector(
      key: const ValueKey('compare-speed-pill'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 7 * s, vertical: 4 * s),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12 * s),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildSourceIcon(useGps, size: 14 * s),
            SizedBox(width: 5 * s),
            SegmentNumber(
              key: const ValueKey('secondary-speed'),
              text: hasData ? value : null,
              integerDigits: 2,
              fractionDigits: 1,
              height: _topSegmentHeight * s,
              fractionHeight: _topSegmentHeight * 0.79 * s,
              color: _topSegmentInk,
              semanticsLabel: hasData ? '副速度 $value' : '副速度无数据',
            ),
          ],
        ),
      ),
    );
  }

  /// 副表：三列等宽 AVG / MAX / km，角标位于各自小数位正上方（规格 §2.4）
  Widget _buildSubTable(
      BleService ble, GpsService gps, BikeData data, double s, bool demo,
      {bool collapsed = false}) {
    // 演示时三列都取演示数据，忽略 GPS 主来源与真实设备的空值标记。
    final useGps = !demo && gps.source == SpeedSource.gps;
    final avg = useGps ? gps.avgSpeedKmh : data.avgSpeed;
    final max = useGps ? gps.maxSpeedKmh : data.maxSpeed;
    final trip = useGps ? gps.tripKm : data.tripDistance;
    final available = demo || useGps || data.tripAvailable;

    // 表盘页收起这一排：高度平滑归零 + 裁剪，让位给放大的表盘。
    // 子树保留在 widget 树中（高度 0 不影响 key 查找），数字页恢复原高度。
    return AnimatedContainer(
      key: const ValueKey('sub-table-row'),
      duration: const Duration(milliseconds: 260),
      height: collapsed ? 0 : 76 * s,
      clipBehavior: Clip.hardEdge,
      margin: collapsed
          ? EdgeInsets.zero
          : EdgeInsets.fromLTRB(14 * s, 2 * s, 14 * s, 0),
      decoration: BoxDecoration(
        border: collapsed
            ? null
            : const Border(
                top: BorderSide(color: DashColors.subLine),
                bottom: BorderSide(color: DashColors.subLine),
              ),
      ),
      child: Row(
        children: [
          _buildSubColumn('AVG', available ? avg.toStringAsFixed(1) : null, s),
          _buildSubDivider(s),
          _buildSubColumn('MAX', available ? max.toStringAsFixed(1) : null, s),
          _buildSubDivider(s),
          _buildSubColumn('km', available ? trip.toStringAsFixed(1) : null, s,
              padInteger: false),
        ],
      ),
    );
  }

  Widget _buildSubColumn(String tag, String? value, double s,
      {bool padInteger = true}) {
    const bigH = 36.0;
    const smallH = 28.0;
    // DSEG7 字体的数字 advance width = 0.816em，用于整行宽度与来源图标定位。
    const ratio = DashFonts.advanceRatio;
    const bigW = bigH * ratio;
    const smallW = smallH * ratio;
    const gap1 = bigH * 0.055;
    const dotW = bigH * 0.102;
    const gap2 = bigH * 0.042;

    // 里程/最高速可能超过 99.9，整数位按实际位数扩展，再由 FittedBox 缩到列宽，
    // 避免 123.4 被截成 23.4。
    var integerDigits = 2;
    if (value != null) {
      final dot = value.indexOf('.');
      final rawLen = dot < 0 ? value.length : dot;
      if (rawLen > integerDigits) integerDigits = rawLen;
    }
    final totalW = bigW * integerDigits + gap1 + dotW + gap2 + smallW;
    final fracCenterX = totalW - smallW / 2;

    return Expanded(
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: (totalW + 8) * s,
            height: (bigH + 12) * s,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 4 * s,
                  bottom: 0,
                  child: SegmentNumber(
                    key: ValueKey('sub-value-$tag'),
                    text: value,
                    integerDigits: integerDigits,
                    fractionDigits: 1,
                    height: bigH * s,
                    fractionHeight: smallH * s,
                    color: DashColors.segSub,
                    padInteger: padInteger,
                    semanticsLabel: value == null
                        ? '$tag 无数据'
                        : (tag == 'km' ? '$value km' : '$tag $value'),
                  ),
                ),
                Positioned(
                  left: (fracCenterX + 4 - 13) * s,
                  bottom: (smallH + 5) * s,
                  child: Text(
                    tag,
                    key: ValueKey('sub-tag-$tag'),
                    style: TextStyle(
                        color: DashColors.muted,
                        fontSize: 11 * s,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6 * s),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubDivider(double s) => Center(
        child: Container(
          width: 1,
          height: 60 * s,
          color: DashColors.subDivider,
        ),
      );

  /// 助力控制卡片：整页唯一暖色高亮块（规格 §2.5）
  Widget _buildAssistCard(BleService ble, double s, bool demo) {
    // Keep room for the slider's minimum touch height on short displays.
    final sliderExtra = (kMinInteractiveDimension - 48 * s)
        .clamp(0.0, kMinInteractiveDimension);
    return Container(
      height: 212 * s + sliderExtra,
      margin: EdgeInsets.symmetric(horizontal: 16 * s),
      decoration: BoxDecoration(
        gradient: DashColors.assistBorder,
        borderRadius: BorderRadius.circular(16 * s),
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(
          gradient: DashColors.assistFill,
          borderRadius: BorderRadius.circular(15 * s),
        ),
        padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 12 * s),
        child: ble.isConnected
            ? _buildAssistBody(ble, s, demo: false)
            : (demo
                ? _buildAssistBody(ble, s, demo: true)
                : _buildConnectPrompt(ble, s)),
      ),
    );
  }

  Widget _buildAssistBody(BleService ble, double s, {required bool demo}) {
    final mode = demo ? (_demoMode ?? AssistMode.manual) : ble.assistMode;
    final manual = mode == AssistMode.manual;
    // 闪控按键先给出本地预览值让滑杆立刻跟随，1 秒防抖后才真正写设备。
    final scheduler = context.watch<AssistRemoteScheduler>();
    final percent = demo
        ? (_demoPercent ?? DemoRideData.assistPercent)
        : (scheduler.previewPercent ?? ble.assistPercent);
    final level =
        demo ? (_demoLevel ?? DemoRideData.assistLevel) : ble.assistLevel;
    // 有指令在等待设备回包时短暂禁用按钮，避免连点重复下发。
    final idle = _pendingCommand == null;
    // 演示期控件同样可用，但所有操作只改本地 state，绝不调用 _runCommand。
    final controlsEnabled = demo || (manual && ble.isConnected && idle);
    final modeEnabled = demo || (ble.isConnected && idle);
    final remote = context.watch<Br80Service>();
    final step = context.watch<AssistStepSettings>().step;
    // 按键监视这类调试信息不再占用助力卡，只保留操作结果与默认说明。
    final hasNotice = remote.message != null;
    final defaultHint = demo ? '助力控制仅在本机预览，不会下发指令' : '拖动滑杆调整助力，实时下发给控制器';
    final hint = remote.message ?? defaultHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.directions_bike, size: 19 * s, color: DashColors.orange),
            SizedBox(width: 8 * s),
            Text('助力控制',
                style: TextStyle(
                    color: DashColors.txt,
                    fontSize: 16 * s,
                    fontWeight: FontWeight.w700)),
            // 手动模式在标题后实时显示当前助力百分比（含闪控按键的本地预览值）。
            if (manual) ...[
              SizedBox(width: 8 * s),
              Text('$percent%',
                  key: const ValueKey('assist-percent'),
                  style: TextStyle(
                      color: DashColors.orange,
                      fontSize: 16 * s,
                      fontWeight: FontWeight.w800)),
            ],
            const Spacer(),
          ],
        ),
        SizedBox(height: 6 * s),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: hasNotice ? DashColors.orange : DashColors.green,
              fontSize: 12.5 * s),
        ),
        SizedBox(height: 10 * s),
        _buildModeRow(ble, modeEnabled, s, selected: mode, demo: demo),
        SizedBox(height: 10 * s),
        _buildControlRow(ble, controlsEnabled, manual, percent, step, s,
            demo: demo,
            level: level,
            pressedDirection: scheduler.pressedDirection),
      ],
    );
  }

  /// 演示助力 +/- 与等级点击：只在 State 里改数值，不接触 BleService。
  void _adjustDemoAssist(int delta) {
    setState(() {
      if ((_demoMode ?? AssistMode.manual) == AssistMode.manual) {
        _demoPercent =
            ((_demoPercent ?? DemoRideData.assistPercent) + delta).clamp(0, 99);
      } else {
        _demoLevel =
            ((_demoLevel ?? DemoRideData.assistLevel) + delta).clamp(0, 5);
      }
      _percentDraft = null;
    });
  }

  /// 模式按钮行：5 个上下结构按钮，手动默认选中
  Widget _buildModeRow(BleService ble, bool enabled, double s,
      {required AssistMode selected, required bool demo}) {
    return Row(
      children: [
        for (var i = 0; i < AssistMode.values.length; i++) ...[
          if (i > 0) SizedBox(width: 7 * s),
          Expanded(
              child: _buildModeChip(
                  ble, enabled, AssistMode.values[i], s, selected, demo)),
        ],
      ],
    );
  }

  Widget _buildModeChip(BleService ble, bool enabled, AssistMode mode, double s,
      AssistMode currentMode, bool demo) {
    final selected = currentMode == mode;
    const ink = DashColors.orange;
    return GestureDetector(
      key: ValueKey('mode-${mode.name}'),
      onTap: enabled
          ? (demo
              ? () => setState(() {
                    _demoMode = mode;
                    _percentDraft = null;
                  })
              : () => _runCommand(
                  ble, () => ble.setAssistMode(mode), '模式 ${mode.label}'))
          : null,
      child: Container(
        height: 48 * s,
        decoration: BoxDecoration(
          gradient: selected ? DashColors.modeSelected : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(11 * s),
          border: Border.all(
            color: selected
                ? DashColors.orange.withValues(alpha: 0.48)
                : DashColors.line,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(mode.icon,
                size: 15 * s, color: selected ? ink : DashColors.muted2),
            SizedBox(height: 3 * s),
            Text(
              mode.label,
              maxLines: 1,
              style: TextStyle(
                  color: selected ? ink : DashColors.muted2,
                  fontSize: 11 * s,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlRow(BleService ble, bool enabled, bool manual,
      int percent, int step, double s,
      {required bool demo, required int level, int? pressedDirection}) {
    return Row(
      children: [
        _buildStepButton(
          key: const ValueKey('assist-minus'),
          icon: Icons.remove,
          enabled: enabled && (manual ? percent > 0 : level > 0),
          pressed: pressedDirection == -1,
          s: s,
          onTap: demo
              ? () => _adjustDemoAssist(-(manual ? step : 1))
              : () => _runCommand(
                    ble,
                    () => manual
                        ? applyAssistStep(ble, -1, step)
                        : ble.stepAssist(-1),
                    manual ? '助力 -$step%' : '助力 -1',
                  ),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: manual
              ? _buildPercentSlider(ble, enabled, percent, s, demo: demo)
              : _buildLevelSegments(ble, enabled, level, s, demo: demo),
        ),
        SizedBox(width: 8 * s),
        _buildStepButton(
          key: const ValueKey('assist-plus'),
          icon: Icons.add,
          enabled: enabled && (manual ? percent < 99 : level < 5),
          pressed: pressedDirection == 1,
          s: s,
          onTap: demo
              ? () => _adjustDemoAssist(manual ? step : 1)
              : () => _runCommand(
                    ble,
                    () => manual
                        ? applyAssistStep(ble, 1, step)
                        : ble.stepAssist(1),
                    manual ? '助力 +$step%' : '助力 +1',
                  ),
        ),
      ],
    );
  }

  /// 手动模式百分比滑块（松手才下发，避免拖动过程刷屏）
  Widget _buildPercentSlider(
      BleService ble, bool enabled, int percent, double s,
      {required bool demo}) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4 * s,
        activeTrackColor: DashColors.orange.withValues(alpha: 0.6),
        inactiveTrackColor: Colors.white.withValues(alpha: 0.13),
        thumbColor: DashColors.segOn,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.5 * s),
      ),
      child: Slider(
        key: const ValueKey('assist-slider'),
        value: _percentDraft ?? percent.toDouble(),
        min: 0,
        max: 99,
        divisions: 99,
        label: '${(_percentDraft ?? percent.toDouble()).round()}%',
        onChanged: enabled
            ? (value) {
                // 手动拖动优先于仍在倒计时的闪控调速。
                context.read<AssistRemoteScheduler>().cancel();
                setState(() => _percentDraft = value);
              }
            : null,
        onChangeEnd: enabled
            ? (value) {
                if (demo) {
                  setState(() {
                    _demoPercent = value.round();
                    _percentDraft = null;
                  });
                } else {
                  setState(() => _percentDraft = null);
                  _runCommand(
                      ble,
                      () => ble.setAssistPercent(value.round(), priority: true),
                      '手动助力 ${value.round()}%');
                }
              }
            : null,
      ),
    );
  }

  /// 五段助力等级（非手动模式）
  Widget _buildLevelSegments(BleService ble, bool enabled, int level, double s,
      {required bool demo}) {
    return Row(
      children: List.generate(5, (i) {
        final active = i < level;
        return Expanded(
          child: GestureDetector(
            onTap: enabled
                ? (demo
                    ? () => setState(() => _demoLevel = i + 1)
                    : () => _runCommand(
                        ble, () => ble.setAssistLevel(i + 1), '助力 ${i + 1} 档'))
                : null,
            child: Container(
              height: 48 * s,
              margin: EdgeInsets.symmetric(horizontal: 2 * s),
              decoration: BoxDecoration(
                color: active
                    ? DashColors.orange.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(9 * s),
                border: Border.all(
                  color: active
                      ? DashColors.orange
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white38,
                    fontSize: 15 * s,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepButton({
    Key? key,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required double s,
    bool pressed = false,
  }) {
    // pressed：闪控上/下键按下时对应的按钮高亮，和手指点按的观感一致。
    final active = pressed && enabled;
    return GestureDetector(
      key: key,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: 48 * s,
        height: 48 * s,
        decoration: BoxDecoration(
          color: active
              ? DashColors.orange.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: enabled ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(11 * s),
          border: Border.all(
            color: active
                ? DashColors.orange
                : Colors.white.withValues(alpha: enabled ? 0.1 : 0.04),
            width: active ? 1.4 : 1,
          ),
        ),
        child: Icon(icon,
            size: 20 * s,
            color: active
                ? const Color(0xFF20160A)
                : Colors.white.withValues(alpha: enabled ? 0.85 : 0.2)),
      ),
    );
  }

  /// 传感器卡片行：电量 / 温度 / 陀螺仪（坡度）。
  ///
  /// 电量与温度按档位变色（见 [SensorStatus]）；电量卡额外显示连续进度条，
  /// 温度沿用 10 格单向分段条；陀螺仪改用 11 格双向条，从中心零点向两侧填充。
  Widget _buildSensorRow(BikeData data, double s) {
    final battery = data.batteryLevelAvailable
        ? data.batteryLevel.clamp(0, 100).toInt()
        : null;
    final voltage = data.voltage > 0 ? data.voltage.toStringAsFixed(1) : null;
    final temp = data.temperatureAvailable ? data.controllerTemperature : null;
    final slope = data.gyroAngleAvailable ? data.slope : null;
    return Container(
      height: 109 * s,
      margin: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 0),
      child: Row(
        children: [
          _buildBatteryCard(battery, voltage, s),
          SizedBox(width: 8 * s),
          _buildSensorCard(
            keyName: 'temperature',
            title: '温度',
            accent: SensorStatus.temperatureColor(temp),
            badge: SensorStatus.temperatureBandLabel(temp),
            segments: temp == null ? 0 : (temp / 10).round().clamp(0, 10),
            value: temp?.toStringAsFixed(1),
            unit: '℃',
            s: s,
          ),
          SizedBox(width: 8 * s),
          _buildSensorCard(
            keyName: 'gyro',
            title: '陀螺仪',
            accent: DashColors.blue,
            bar: slope == null
                ? const SlopeBar(hasData: false)
                : SlopeBar(
                    hasData: true,
                    side: slope < 0 ? -1 : (slope > 0 ? 1 : 0),
                    level: (slope.abs() / 5).round().clamp(0, 5),
                  ),
            value: slope?.toStringAsFixed(1),
            unit: '°',
            s: s,
          ),
        ],
      ),
    );
  }

  /// 电量卡：百分比 + 连续进度条 + 电压，三者与描边统一跟随档位配色。
  Widget _buildBatteryCard(int? percent, String? voltage, double s) {
    final accent = SensorStatus.batteryColor(percent);
    final percentText = percent == null ? '未知' : '$percent%';
    return Expanded(
      child: Semantics(
        container: true,
        label: '电量 $percentText，${SensorStatus.batteryBandLabel(percent)}，'
            '电压 ${voltage ?? '未知'} 伏',
        child: Container(
          key: const ValueKey('battery-card'),
          padding: EdgeInsets.fromLTRB(9 * s, 10 * s, 9 * s, 9 * s),
          decoration: BoxDecoration(
            color: DashColors.card,
            borderRadius: BorderRadius.circular(13 * s),
            border: Border.all(color: DashColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('电量',
                        style: TextStyle(
                            color: const Color(0xFFD6DEED),
                            fontSize: 11.5 * s,
                            fontWeight: FontWeight.w600)),
                    SizedBox(width: 4 * s),
                    Text(percent == null ? '--' : percentText,
                        key: const ValueKey('battery-percent'),
                        style: TextStyle(
                            color: accent,
                            fontSize: 13 * s,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              SizedBox(height: 6 * s),
              _buildBatteryBar(percent, accent, s),
              const Spacer(),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(voltage ?? '--',
                          key: const ValueKey('battery-voltage'),
                          style: TextStyle(
                              color: accent,
                              fontSize: 32 * s,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5 * s)),
                      SizedBox(width: 2 * s),
                      Text('V',
                          style: TextStyle(
                              color: accent,
                              fontSize: 15 * s,
                              fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单一连续进度条：只按真实百分比填充当前档位色。
  ///
  /// 底轨不分区、填充不透明，避免分区线从填充里透出、或低电量时
  /// 右侧露出其它档位的颜色，让进度条看起来被切成几段。
  Widget _buildBatteryBar(int? percent, Color accent, double s) {
    return Container(
      key: const ValueKey('battery-bar'),
      height: 12 * s,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6 * s),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5 * s),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                key: const ValueKey('battery-track'),
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            if (percent != null)
              Positioned.fill(
                child: FractionallySizedBox(
                  widthFactor: SensorStatus.batteryProgress(percent),
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    key: const ValueKey('battery-fill'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        // 完全不透明的由深到亮渐变，底轨不会透出来。
                        colors: [
                          Color.lerp(Colors.black, accent, 0.72)!,
                          accent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard({
    required String title,
    required Color accent,
    String? badge,
    int segments = 0,
    required String? value,
    required String unit,
    required double s,
    String? keyName,
    SlopeBar? bar,
  }) {
    return Expanded(
      child: Container(
        key: keyName == null ? null : ValueKey('$keyName-card'),
        padding: EdgeInsets.fromLTRB(9 * s, 10 * s, 9 * s, 9 * s),
        decoration: BoxDecoration(
          color: DashColors.card,
          borderRadius: BorderRadius.circular(13 * s),
          border: Border.all(color: DashColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: const Color(0xFFD6DEED),
                          fontSize: 11.5 * s,
                          fontWeight: FontWeight.w600)),
                  if (badge != null) ...[
                    SizedBox(width: 3 * s),
                    Text(badge,
                        style: TextStyle(
                            color: accent,
                            fontSize: 11.5 * s,
                            fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
            SizedBox(height: 6 * s),
            bar != null
                ? _buildSlopeBar(bar, s)
                : _buildSegmentBar(accent, segments, s),
            const Spacer(),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value ?? '--',
                        key:
                            keyName == null ? null : ValueKey('$keyName-value'),
                        style: TextStyle(
                            color: accent,
                            fontSize: 32 * s,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5 * s)),
                    SizedBox(width: 2 * s),
                    Text(unit,
                        style: TextStyle(
                            color: accent,
                            fontSize: 15 * s,
                            fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentBar(Color accent, int active, double s) {
    return Container(
      height: 15 * s,
      padding: EdgeInsets.all(3 * s),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(6 * s),
        border: Border.all(color: DashColors.line),
      ),
      child: Row(
        children: List.generate(
          10,
          (i) => Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 0.6 * s),
              decoration: BoxDecoration(
                color:
                    i < active ? accent : Colors.white.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(2 * s),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 坡度双向条：11 格，中心格（索引 5）是零点锚点。
  ///
  /// 无数据全灰；平路（level==0）只亮中心蓝格；下坡中心与左侧格为绿色、
  /// 上坡中心与右侧格为红色，方向格按 [SlopeBar.level] 填充。
  Widget _buildSlopeBar(SlopeBar bar, double s) {
    const center = 5;
    const total = 11;
    final idle = Colors.white.withValues(alpha: 0.09);
    return Container(
      key: const ValueKey('slope-bar'),
      height: 15 * s,
      padding: EdgeInsets.all(3 * s),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(6 * s),
        border: Border.all(color: DashColors.blue.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: List.generate(total, (i) {
          final directionColor =
              bar.side < 0 ? DashColors.green : DashColors.red;
          final isCenter = i == center;
          final filled = bar.hasData &&
              ((isCenter) ||
                  (bar.side < 0 && i >= center - bar.level && i < center) ||
                  (bar.side > 0 && i > center && i <= center + bar.level));
          // 0 附近（level==0）只有中心格亮蓝；有坡度时中心格跟随方向色，整条同色。
          final color = !filled
              ? idle
              : (bar.level == 0 ? DashColors.blue : directionColor);
          return Expanded(
            child: Container(
              key: ValueKey('slope-segment-$i'),
              margin: EdgeInsets.symmetric(horizontal: 0.6 * s),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2 * s),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildVersionLine(double s) {
    return Container(
      height: 16 * s,
      margin: EdgeInsets.only(top: 10 * s, bottom: 12 * s),
      alignment: Alignment.center,
      child: Text(
        'v$_version · 2026-11-20',
        style: TextStyle(
            color: DashColors.muted, fontSize: 11 * s, letterSpacing: 0.6 * s),
      ),
    );
  }

  Widget _buildConnectPrompt(BleService ble, double s) {
    // 闪控连接状态已移到顶部状态栏，这里只提示控制器未连接。
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_disabled, size: 34 * s, color: DashColors.muted),
          SizedBox(height: 10 * s),
          Text('未连接控制器',
              style: TextStyle(color: DashColors.txt, fontSize: 14 * s)),
          SizedBox(height: 4 * s),
          Text('连接后可使用助力控制与闪控',
              style: TextStyle(color: DashColors.muted, fontSize: 11 * s)),
          SizedBox(height: 12 * s),
          OutlinedButton.icon(
            onPressed: () => widget.onOpenDevices?.call(),
            icon: Icon(Icons.bluetooth_searching, size: 16 * s),
            label: Text('去连接', style: TextStyle(fontSize: 12 * s)),
            style: OutlinedButton.styleFrom(
              foregroundColor: DashColors.orange,
              side: BorderSide(color: DashColors.orange.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  /// 执行一条助力指令：等待设备回包确认后再提示结果
  Future<void> _runCommand(
    BleService ble,
    Future<CommandResult> Function() action,
    String label,
  ) async {
    // 用户手动操作优先：丢弃仍在倒计时的闪控调速，避免之后覆盖刚设的值。
    context.read<AssistRemoteScheduler>().cancel();
    if (!ble.isConnected) {
      await showAppDialog(
        context,
        title: '未连接设备',
        message: '助力控制需要先连接控制器。要现在去连接吗？',
        icon: Icons.bluetooth_disabled,
        primaryLabel: '去连接',
        onPrimary: () => widget.onOpenDevices?.call(),
      );
      return;
    }
    if (_pendingCommand != null) return;

    setState(() => _pendingCommand = label);
    final result = await action();
    if (!mounted) return;
    setState(() => _pendingCommand = null);

    if (result.isError) {
      await showAppDialog(
        context,
        title: result.title,
        message: result.message,
        icon: Icons.error_outline,
        color: Colors.red,
        primaryLabel: result == CommandResult.notConnected ? '去连接' : null,
        onPrimary: () => widget.onOpenDevices?.call(),
      );
      return;
    }

    switch (result) {
      case CommandResult.ok:
        showAppToast(context, '$label · 设备已确认');
      case CommandResult.atLimit:
        showAppToast(context, '助力已达到 ${ble.assistPercent}%');
      case CommandResult.noResponse:
        showAppToast(context, '$label · 未确认，可能已执行，请核实后再操作', warning: true);
      case CommandResult.deviceError:
        showAppToast(context, '$label · 设备返回失败', error: true);
      default:
        showAppToast(context, '$label · 发送失败', error: true);
    }
  }
}

/// 竖长矩形轮廓 + 顶部短线 + 内部上下两个实心点的双键闪控图标
