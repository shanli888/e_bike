import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「断开连接时显示演示数据」开关。
///
/// 只影响首页的展示数据：不写入 [BleService]、不启动 GPS、不下发助力指令。
/// 连接真实控制器后自动切回真实数据，避免演示数据被误当成车辆状态。
class DemoModeSettings extends ChangeNotifier {
  static const String preferenceKey = 'demo_mode_enabled';
  static const bool defaultEnabled = false;

  bool _enabled = defaultEnabled;
  bool get enabled => _enabled;

  bool _loaded = false;
  bool get loaded => _loaded;
  bool _disposed = false;

  /// 只有开关打开且控制器未连接时才填充演示数据。
  bool isActive(bool connected) => _enabled && !connected;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 读取持久化值；缺失或读取失败回退到默认关闭。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(preferenceKey) ?? defaultEnabled;
    } catch (_) {
      _enabled = defaultEnabled;
    }
    _loaded = true;
    _notify();
  }

  /// 保存成功后才更新界面；失败保留原值。
  Future<bool> setEnabled(bool value) async {
    if (_disposed) return false;
    if (value == _enabled && _loaded) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(preferenceKey, value)) return false;
    } catch (_) {
      return false;
    }
    _enabled = value;
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
