import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_service.dart';
import 'gps_service.dart';

/// 本次骑行计时：以「当前显示的速度」为准，有速度才累计，速度归零自动暂停。
///
/// 不读取设备上报的行程时间，也不按轮子圈数 / 定位间隔推算；每次重新连接
/// 控制器视为新的一次骑行并自动清零。服务由顶层 Provider 持有，切换页面
/// 不会丢失计时。
class RideTimeService extends ChangeNotifier {
  RideTimeService({
    required this.isConnected,
    required this.speedKmh,
  }) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTimer());
  }

  /// 从实际服务构造：速度取首页大字速度的同一来源（GPS 主来源优先）。
  factory RideTimeService.fromServices(BleService ble, GpsService gps) {
    return RideTimeService(
      isConnected: () => ble.isConnected,
      speedKmh: () {
        if (gps.source == SpeedSource.gps) return gps.speedKmh;
        final data = ble.bikeData;
        return data.speedAvailable ? data.speed : null;
      },
    );
  }

  /// 控制器是否已连接（用于识别「新的一次连接」）
  final bool Function() isConnected;

  /// 当前速度 km/h；null 表示暂无有效速度，按 0 处理
  final double? Function() speedKmh;

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

    final connected = isConnected();
    // 每次重新连接视为新的一次骑行，计时清零
    if (connected && !_wasConnected) reset();
    _wasConnected = connected;

    final speed = speedKmh() ?? 0;
    // App 被挂起后 Timer 可能一次性跳过很长一段，不补算，避免时间虚增
    final validInterval = dt > Duration.zero && dt < const Duration(seconds: 10);
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
