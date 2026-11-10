import 'package:flutter/services.dart';

/// 调用系统设置页（部分机型不允许 App 直接开关蓝牙，只能引导用户手动开）
class SystemSettings {
  const SystemSettings._();

  static const MethodChannel _channel =
      MethodChannel('bike_computer/system_settings');

  /// 打开系统的「蓝牙」设置页
  static Future<bool> openBluetoothSettings() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('openBluetoothSettings');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
