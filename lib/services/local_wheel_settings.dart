import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 仅影响手机对标准 CSC 轮速的换算，不写入电机控制器。
class LocalWheelSettings extends ChangeNotifier {
  static const _preferenceKey = 'local_csc_wheel_diameter_mm';
  static const int defaultDiameterMm = 660; // 26 英寸近似值
  static const int minDiameterMm = 200;
  static const int maxDiameterMm = 1000;

  int _diameterMm = defaultDiameterMm;
  int get diameterMm => _diameterMm;
  double get circumferenceMeters => _diameterMm / 1000.0 * math.pi;
  bool _loaded = false;
  bool get loaded => _loaded;
  bool _saving = false;
  bool get saving => _saving;
  bool _disposed = false;
  int _revision = 0;

  static int diameterFromInches(double inches) {
    if (!inches.isFinite || inches <= 0) throw ArgumentError('轮胎尺寸无效');
    final mm = (inches * 25.4).round();
    if (mm < minDiameterMm || mm > maxDiameterMm) throw ArgumentError('轮径超出范围');
    return mm;
  }

  /// 仅读取持久化值；无效的旧数据回退到默认值。
  Future<void> load() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_preferenceKey);
      if (_disposed || revision != _revision) return;
      _diameterMm = value != null && value >= minDiameterMm && value <= maxDiameterMm
          ? value : defaultDiameterMm;
    } catch (_) {
      if (_disposed || revision != _revision) return;
      _diameterMm = defaultDiameterMm;
    }
    _loaded = true;
    notifyListeners();
  }

  /// 保存成功后才更新界面；失败保留原值。
  Future<bool> setDiameterMm(int value) async {
    if (_disposed || _saving || value < minDiameterMm || value > maxDiameterMm) return false;
    _revision++;
    _saving = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setInt(_preferenceKey, value);
      if (!saved || _disposed) return false;
      _diameterMm = value;
      _loaded = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
