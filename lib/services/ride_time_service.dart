import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_service.dart';
import 'gps_service.dart';
import 'ride_recorder.dart';

/// 本次骑行计时：以「当前显示的速度」为准，有速度才累计，速度归零自动暂停。
///
/// 不读取设备上报的行程时间，也不按轮子圈数 / 定位间隔推算；每次重新连接
/// 控制器视为新的一次骑行并自动清零。服务由顶层 Provider 持有，切换页面
/// 不会丢失计时。
class RideTimeService extends ChangeNotifier {
  RideTimeService({
    required this.isConnected,
    required this.speedKmh,
    this.recordState,
  }) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTimer());
  }

  /// 从实际服务构造：速度取首页大字速度的同一来源（GPS 主来源优先）。
  ///
  /// [recordState] 可选：接入骑行记录器后，计时器跟随「开始/暂停/结束」状态，
  /// 点开始即走字；不传时保留旧行为（仅按速度 > 0 计时）。
  factory RideTimeService.fromServices(
    BleService ble,
    GpsService gps, {
    RideRecordState Function()? recordState,
  }) {
    return RideTimeService(
      isConnected: () => ble.isConnected,
      speedKmh: () {
        if (gps.source == SpeedSource.gps) return gps.speedKmh;
        final data = ble.bikeData;
        return data.speedAvailable ? data.speed : null;
      },
      recordState: recordState,
    );
  }

  /// 控制器是否已连接（用于识别「新的一次连接」）
  final bool Function() isConnected;

  /// 当前速度 km/h；null 表示暂无有效速度，按 0 处理
  final double? Function() speedKmh;

  /// 骑行记录状态；提供后计时器跟随「开始/暂停/结束」而非纯速度。
  final RideRecordState Function()? recordState;

  Timer? _timer;
  DateTime? _lastTick;
  bool _wasConnected = false;
  Duration _elapsed = Duration.zero;
  bool _running = false;

  /// 累计的有效骑行时长
  Duration get elapsed => _elapsed;

  /// 是否正在计时（速度 > 0）
  bool get running => _running;

  /// HH:MM（小时超过 99 时不截断）
  String get display {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(_elapsed.inHours)}:${two(_elapsed.inMinutes % 60)}';
  }

  void _onTimer() => tick(DateTime.now());

  /// 推进一次计时；公开给测试传入指定时间点，无需真实等待。
  void tick(DateTime now) {
    final last = _lastTick;
    final dt = last == null ? Duration.zero : now.difference(last);
    _lastTick = now;
    // App 被挂起后 Timer 可能一次性跳过很长一段，不补算，避免时间虚增
    final validInterval = dt > Duration.zero && dt < const Duration(seconds: 10);

    final stateProvider = recordState;
    if (stateProvider != null) {
      // 接入骑行记录：计时器跟随「开始/暂停/结束」状态。
      final state = stateProvider();
      if (state == RideRecordState.recording) {
        // 点开始即走字，不再依赖瞬时速度（自动暂停由记录器自身判定）
        _running = validInterval;
        if (_running) _elapsed += dt;
      } else if (state == RideRecordState.paused) {
        // 暂停：停走但保留已累计时长
        _running = false;
      } else {
        // idle：结束或未开始，归零待命
        _running = false;
        _elapsed = Duration.zero;
      }
      notifyListeners();
      return;
    }

    // 兼容旧行为：无记录状态接入时，仅按「有速度」计时。
    final connected = isConnected();
    // 每次重新连接视为新的一次骑行，计时清零
    if (connected && !_wasConnected) reset();
    _wasConnected = connected;

    final speed = speedKmh() ?? 0;
    _running = validInterval && speed > 0;
    if (_running) _elapsed += dt;

    notifyListeners();
  }

  /// 开始新的一次骑行
  void reset() {
    _elapsed = Duration.zero;
    _running = false;
    _lastTick = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
