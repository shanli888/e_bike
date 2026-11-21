import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/ride_record.dart';
import 'ride_repository.dart';

/// 骑行记录状态
enum RideRecordState {
  idle('待记录'),
  recording('记录中'),
  paused('已暂停');

  const RideRecordState(this.label);
  final String label;
}

/// 骑行记录器：一次骑行的开始 / 暂停 / 继续 / 结束状态机。
///
/// 自己管理一条独立的定位流（bestForNavigation, 1s），与 GpsService 的测速流
/// 解耦——这样无论速度来源是蓝牙还是 GPS，只要用户点了「开始骑行」就能记录
/// 轨迹。定位权限在服务内检查，失败通过 [status] 暴露给 UI。
///
/// 指标口径（与产品文档 §4 一致）：
/// - 距离：相邻有效点的球面距离累加，过滤 >200m 的跳点与精度 >50m 的定位。
/// - 移动时长：仅在速度 >0.5km/h 且未暂停时累加（沿用「有速度才算移动」）。
/// - 均速：距离 / 移动时长；极速：取定位速度最大值。
/// - 爬升/下降：相邻点高程差，绝对值 >1m 才计入（滤掉 GPS 高程抖动）。
/// - 卡路里：MET 模型，骑行 MET=6.0，体重默认 70kg（预留设置）。
class RideRecorder extends ChangeNotifier {
  RideRecorder(this._repository, {this.defaultWeightKg = 70.0});

  final RideRepository _repository;
  final double defaultWeightKg;
  static const double _metCycling = 6.0;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool _disposed = false;
  RideRecordState _state = RideRecordState.idle;
  RideRecordState get state => _state;
  bool get isIdle => _state == RideRecordState.idle;
  bool get isRecording => _state == RideRecordState.recording;
  bool get isPaused => _state == RideRecordState.paused;
  bool get isActive => _state != RideRecordState.idle;

  String _status = '未开始';
  String get status => _status;

  DateTime? _startTime;
  DateTime? _endTime;
  DateTime? _lastTick;
  Duration _moving = Duration.zero;
  double _distanceKm = 0;
  double _maxSpeedKmh = 0;
  double _ascentM = 0;
  double _descentM = 0;

  final List<RidePoint> _points = <RidePoint>[];
  List<RidePoint> get points => List.unmodifiable(_points);

  StreamSubscription<Position>? _sub;
  Position? _last;

  /// 实时展示用：时长 / 距离 / 均速 / 爬升 / 卡路里
  Duration get elapsed => _moving;
  double get distanceKm => _distanceKm;
  double get avgSpeedKmh =>
      _moving.inSeconds > 0 ? _distanceKm / (_moving.inSeconds / 3600) : 0;
  double get maxSpeedKmh => _maxSpeedKmh;
  double get ascentM => _ascentM;
  double get calories => (_metCycling * defaultWeightKg *
          (_moving.inSeconds / 3600))
      .round()
      .toDouble();

  /// 开始新骑行；若已在记录中则忽略。返回是否成功启动定位。
  Future<bool> start() async {
    if (_state != RideRecordState.idle) return false;

    // 权限与服务检查
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      _status = '请先打开手机定位（GPS）';
      notifyListeners();
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _status = '未授予定位权限';
      notifyListeners();
      return false;
    }

    // 重置本次数据
    _startTime = DateTime.now();
    _endTime = null;
    _lastTick = null;
    _moving = Duration.zero;
    _distanceKm = 0;
    _maxSpeedKmh = 0;
    _ascentM = 0;
    _descentM = 0;
    _points.clear();
    _last = null;
    _state = RideRecordState.recording;
    _status = '正在等待定位…';
    notifyListeners();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '骑行记录中',
        notificationText: '正在后台记录你的骑行轨迹',
        enableWakeLock: true,
      ),
    );

    await _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object e) {
        _status = '定位异常：$e';
        notifyListeners();
      },
    );
    return true;
  }

  void pause() {
    if (_state != RideRecordState.recording) return;
    _state = RideRecordState.paused;
    _lastTick = null;
    _status = '已暂停';
    notifyListeners();
  }

  void resume() {
    if (_state != RideRecordState.paused) return;
    _state = RideRecordState.recording;
    _lastTick = null;
    _status = '正在记录…';
    notifyListeners();
  }

  /// 结束并落库，返回保存的骑行（失败返回 null）。
  Future<RideSession?> finish() async {
    if (!isActive) return null;
    await _sub?.cancel();
    _sub = null;
    _endTime = DateTime.now();

    final start = _startTime ?? _endTime!;
    final end = _endTime!;
    final session = RideSession(
      id: 'ride_${start.millisecondsSinceEpoch}',
      startTime: start,
      endTime: end,
      movingSeconds: _moving.inSeconds,
      distanceKm: _distanceKm,
      avgSpeedKmh: avgSpeedKmh,
      maxSpeedKmh: _maxSpeedKmh,
      ascentM: _ascentM,
      descentM: _descentM,
      calories: calories.round(),
      name: _autoName(start),
      points: List<RidePoint>.from(_points),
    );
    try {
      await _repository.save(session);
      _status = '已保存';
    } catch (e) {
      _status = '保存失败：$e';
    }
    _resetToIdle();
    return session;
  }

  /// 放弃本次骑行（不落库）
  Future<void> discard() async {
    await _sub?.cancel();
    _sub = null;
    _resetToIdle();
  }

  void _resetToIdle() {
    _state = RideRecordState.idle;
    _startTime = null;
    _endTime = null;
    _lastTick = null;
    _moving = Duration.zero;
    _distanceKm = 0;
    _maxSpeedKmh = 0;
    _ascentM = 0;
    _descentM = 0;
    _points.clear();
    _last = null;
    _status = '未开始';
    notifyListeners();
  }

  String _autoName(DateTime t) {
    final hour = t.hour;
    if (hour < 6) return '夜骑';
    if (hour < 11) return '晨骑';
    if (hour < 14) return '午间骑行';
    if (hour < 18) return '下午骑行';
    return '夜骑';
  }

  void _onPosition(Position p) {
    if (!isActive) return;
    if (p.accuracy > 100) {
      _status = '定位精度差（${p.accuracy.toStringAsFixed(0)} m）';
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final speedKmh = p.speed > 0 ? p.speed * 3.6 : 0.0;

    // 采样点：暂停时也记录轨迹，但不累加移动指标（减速带/红灯不虚增里程）
    final shouldRecord = _shouldAddPoint(p);
    if (shouldRecord) {
      _points.add(RidePoint(
        lat: p.latitude,
        lon: p.longitude,
        alt: p.altitude,
        t: now,
        speedKmh: speedKmh,
        accuracy: p.accuracy,
      ));
    }

    if (_state == RideRecordState.recording) {
      // 移动时长：有速度才累计，且过滤挂起后的大间隔
      final dt = _lastTick == null ? Duration.zero : now.difference(_lastTick!);
      if (dt > Duration.zero && dt < const Duration(seconds: 10)) {
        if (speedKmh > 0.5) _moving += dt;
      }
      _lastTick = now;

      // 距离 + 爬升只基于有效相邻点
      final prev = _last;
      if (prev != null && p.accuracy <= 50) {
        final meters = Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          p.latitude,
          p.longitude,
        );
        if (meters >= 1 && meters < 200) {
          _distanceKm += meters / 1000;
        }
        final dh = p.altitude - prev.altitude;
        if (dh.abs() >= 1.0) {
          if (dh > 0) {
            _ascentM += dh;
          } else {
            _descentM += -dh;
          }
        }
      }
      if (speedKmh > _maxSpeedKmh && speedKmh < 120) _maxSpeedKmh = speedKmh;
    }

    _last = p;
    _status = '正在记录（精度 ${p.accuracy.toStringAsFixed(0)} m）';
    notifyListeners();
  }

  bool _shouldAddPoint(Position p) {
    final prev = _last;
    if (prev == null) return true;
    final meters = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      p.latitude,
      p.longitude,
    );
    // 至少移动 3m 才记一个点，控制文件大小；停顿超过 10s 强制记点保留停靠信息
    if (meters >= 3) return true;
    final gap = DateTime.now().difference(
        _points.isEmpty ? prev.timestamp : _points.last.t);
    return gap > const Duration(seconds: 10);
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
