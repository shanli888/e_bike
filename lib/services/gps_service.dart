import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 速度来源
enum SpeedSource {
  bluetooth('蓝牙'),
  gps('GPS');

  const SpeedSource(this.label);

  final String label;
}

/// GPS 测速：用手机定位算速度、里程和极速
///
/// 显示对比时可同时启用 GPS；关闭对比且主来源为蓝牙时停止定位。
class GpsService extends ChangeNotifier {
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  static const String _prefGpsEnabled = 'speed_source_gps';
  static const String _prefCompareEnabled = 'speed_compare_gps';

  bool _comparisonEnabled = false;
  bool get comparisonEnabled => _comparisonEnabled;
  bool get gpsRequested => _source == SpeedSource.gps || _comparisonEnabled;
  bool _disposed = false;
  int _startGeneration = 0;
  Future<bool>? _starting;

  SpeedSource _source = SpeedSource.bluetooth;
  SpeedSource get source => _source;

  bool get enabled => _source == SpeedSource.gps;

  /// 当前速度 km/h，未定位到之前为 null
  double? _speedKmh;
  double? get speedKmh => _speedKmh;

  double _maxSpeedKmh = 0;
  double get maxSpeedKmh => _maxSpeedKmh;

  double _avgSpeedKmh = 0;
  double get avgSpeedKmh => _avgSpeedKmh;

  /// 本次里程 km
  double _tripKm = 0;
  double get tripKm => _tripKm;

  /// 给界面看的状态文案
  String _status = '未开启';
  String get status => _status;

  bool get hasFix => _speedKmh != null;

  StreamSubscription<Position>? _sub;
  Position? _last;
  DateTime? _lastTime;
  double _speedWeight = 0;
  double _speedSum = 0;

  /// 启动时读取上次选择
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_prefGpsEnabled) ?? false;
      _comparisonEnabled = prefs.getBool(_prefCompareEnabled) ?? false;
      _source = saved ? SpeedSource.gps : SpeedSource.bluetooth;
      if (_disposed) return;
      notifyListeners();
      if (gpsRequested) await _ensureGps();
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('读取速度来源设置失败: $e');
    }
  }

  /// 切换速度来源
  Future<bool> setSource(SpeedSource source) async {
    if (_source == source) return true;

    _source = source;
    var started = true;
    if (gpsRequested) {
      started = await _ensureGps();
    } else {
      await _stopGps();
    }
    if (_disposed) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setBool(_prefGpsEnabled, source == SpeedSource.gps);
      debugPrint('保存速度来源: gps=${source == SpeedSource.gps} ok=$ok');
    } catch (e) {
      debugPrint('保存速度来源设置失败: $e');
    }
    notifyListeners();
    return started;
  }

  /// 开启副速度对比会请求定位权限并增加耗电；关闭后保留主速度设置。
  Future<bool> setComparisonEnabled(bool enabled) async {
    if (_comparisonEnabled == enabled) return true;
    _comparisonEnabled = enabled;
    var ok = true;
    if (gpsRequested) {
      ok = await _ensureGps();
    } else {
      await _stopGps();
    }
    if (_disposed) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefCompareEnabled, enabled);
    } catch (e) {
      debugPrint('保存速度对比设置失败: $e');
    }
    if (!_disposed) notifyListeners();
    return ok;
  }

  /// 重新请求定位（用户打开定位服务后可重试）。
  Future<bool> retry() async {
    if (!gpsRequested) return false;
    final ok = await _ensureGps();
    if (!_disposed) notifyListeners();
    return ok;
  }

  Future<bool> _ensureGps() async {
    if (_disposed || !gpsRequested) return false;
    if (_sub != null) return true;
    final current = _starting;
    if (current != null) {
      final ok = await current;
      if (ok || _disposed || !gpsRequested) return ok;
      if (identical(_starting, current)) _starting = null;
    }
    final operation = _startGps();
    _starting = operation;
    try {
      return await operation;
    } finally {
      if (identical(_starting, operation)) _starting = null;
    }
  }

  void resetTrip() {
    _tripKm = 0;
    _maxSpeedKmh = 0;
    _speedSum = 0;
    _speedWeight = 0;
    _avgSpeedKmh = 0;
    notifyListeners();
  }

  Future<bool> _startGps() async {
    if (_sub != null) return true;
    final generation = ++_startGeneration;
    bool active() => !_disposed && generation == _startGeneration && gpsRequested;

    _status = '检查定位服务…';
    notifyListeners();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!active()) return false;
    if (!serviceEnabled) {
      _status = '请先打开手机定位（GPS）';
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (!active()) return false;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!active()) return false;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _status = '未授予定位权限';
      return false;
    }

    _status = '正在等待定位…';
    notifyListeners();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      intervalDuration: const Duration(seconds: 1),
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object e) {
        _status = '定位异常：$e';
        notifyListeners();
      },
    );
    return true;
  }

  Future<void> _stopGps() async {
    _startGeneration++;
    await _sub?.cancel();
    _sub = null;
    _last = null;
    _lastTime = null;
    _speedKmh = null;
    _status = '已切换为蓝牙测速';
    notifyListeners();
  }

  void _onPosition(Position position) {
    if (_disposed || !gpsRequested) return;
    // 定位精度太差（室内/地下车库）时不更新数值，避免速度乱跳
    if (position.accuracy > 100) {
      _status = '定位精度差（${position.accuracy.toStringAsFixed(0)} m），等待信号…';
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final dt = _lastTime == null ? 0.0 : now.difference(_lastTime!).inMilliseconds / 1000.0;

    // 1) 优先用系统给的速度（m/s）
    double? kmh;
    if (position.speedAccuracy >= 0 && position.speed >= 0) {
      kmh = position.speed * 3.6;
    }

    // 2) 没有速度就用两次定位的距离 / 时间
    if (kmh == null && _last != null && dt > 0.5) {
      final meters = Geolocator.distanceBetween(
        _last!.latitude,
        _last!.longitude,
        position.latitude,
        position.longitude,
      );
      kmh = meters / dt * 3.6;
    }

    // 过滤明显不合理的值（地下车库漂移、静止抖动）
    if (kmh != null && (kmh.isNaN || kmh < 0 || kmh > 120)) kmh = null;
    if (kmh != null && kmh < 1.0) kmh = 0;

    if (kmh != null) {
      _speedKmh = kmh;
      if (kmh > _maxSpeedKmh) _maxSpeedKmh = kmh;
      if (dt > 0 && dt < 10) {
        _speedSum += kmh * dt;
        _speedWeight += dt;
        if (_speedWeight > 0) _avgSpeedKmh = _speedSum / _speedWeight;
      }
    }

    // 里程累加（过滤掉定位跳点）
    if (_last != null && position.accuracy <= 50) {
      final meters = Geolocator.distanceBetween(
        _last!.latitude,
        _last!.longitude,
        position.latitude,
        position.longitude,
      );
      if (meters > 1.0 && meters < 200) {
        _tripKm += meters / 1000.0;
      }
    }

    _last = position;
    _lastTime = now;
    _status = '定位中（精度 ${position.accuracy.toStringAsFixed(0)} m）';
    notifyListeners();
  }

  /// 两点间距离（米），暴露给需要的地方
  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  @override
  void dispose() {
    _disposed = true;
    _startGeneration++;
    _sub?.cancel();
    super.dispose();
  }
}
