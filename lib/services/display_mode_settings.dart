import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 显示形态：分水岭逻辑——是否展示助力控制与传感器卡片。
///
/// 默认「自动」：连接上助力器（控制器 / 闪控）显示完整助力界面，断开则退回
/// 纯码表形态。用户可在设置里锁定为纯码表模式，此时即使连着助力器也隐藏助力界面。
/// 锁定开关优先级高于连接状态；切换形态不影响骑行记录。
class DisplayModeSettings extends ChangeNotifier {
  static const String preferenceKey = 'lock_pure_computer_mode';
  static const bool defaultLocked = false;

  bool _locked = defaultLocked;
  bool get locked => _locked;

  bool _loaded = false;
  bool get loaded => _loaded;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 综合判断：锁定为纯码表，或未连接任何助力器时为纯码表形态。
  bool isPureComputer({required bool controllerConnected, required bool remoteConnected}) {
    return _locked || (!controllerConnected && !remoteConnected);
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _locked = prefs.getBool(preferenceKey) ?? defaultLocked;
    } catch (_) {
      _locked = defaultLocked;
    }
    _loaded = true;
    _notify();
  }

  Future<bool> setLocked(bool value) async {
    if (_disposed) return false;
    if (value == _locked && _loaded) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(preferenceKey, value)) return false;
    } catch (_) {
      return false;
    }
    _locked = value;
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
