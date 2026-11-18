import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 手动模式「+ / -」按钮与 BR80 闪控「上 / 下」键共用的步进设置。
///
/// 只决定每次按下调整多少个百分点，不写入电机控制器，也不影响滑块直接选值。
class AssistStepSettings extends ChangeNotifier {
  static const String preferenceKey = 'assist_step_percent';
  static const int defaultStep = 5;
  static const int minStep = 1;
  static const int maxStep = 50;

  int _step = defaultStep;
  int get step => _step;

  bool _loaded = false;
  bool get loaded => _loaded;
  bool _disposed = false;

  static int clampStep(int value) => value.clamp(minStep, maxStep);

  static int clampPercent(int value) => value.clamp(0, 99);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 读取持久化值；无效或缺失回退到默认 5%。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(preferenceKey);
      _step = value == null ? defaultStep : clampStep(value);
    } catch (_) {
      _step = defaultStep;
    }
    _loaded = true;
    _notify();
  }

  /// 保存成功后才更新界面；失败保留原值。
  Future<bool> setStep(int value) async {
    if (_disposed) return false;
    final target = clampStep(value);
    if (target == _step && _loaded) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setInt(preferenceKey, target)) return false;
    } catch (_) {
      return false;
    }
    _step = target;
    _loaded = true;
    _notify();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 一次步进后的目标百分比（0~99，与手动模式滑块范围一致）。
/// [direction] 为 +1（加 / 上键）或 -1（减 / 下键）。
int assistStepTarget(int current, int direction, int step) {
  final magnitude = AssistStepSettings.clampStep(step);
  return AssistStepSettings.clampPercent(
      current + (direction < 0 ? -magnitude : magnitude));
}
