import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assist_mode.dart';

class RememberedDevice {
  const RememberedDevice({required this.id, required this.name, required this.connectedAt});
  final String id;
  final String name;
  final DateTime connectedAt;
}

/// 本机记录仅代表上次连接和上次成功设置，不代表设备当前状态。
class RememberedDeviceStore {
  static const _deviceKey = 'last_ble_device_v1';
  static const _modePrefix = 'confirmed_assist_mode_v1_';

  Future<RememberedDevice?> loadDevice() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(_deviceKey);
      if (value == null) return null;
      final data = jsonDecode(value) as Map<String, dynamic>;
      final id = data['id'] as String;
      final name = data['name'] as String;
      final date = DateTime.parse(data['connectedAt'] as String);
      if (id.isEmpty) return null;
      return RememberedDevice(id: id, name: name, connectedAt: date);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDevice(RememberedDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceKey, jsonEncode({
      'id': device.id, 'name': device.name, 'connectedAt': device.connectedAt.toIso8601String(),
    }));
  }

  Future<AssistMode?> loadMode(String deviceId) async {
    final code = (await SharedPreferences.getInstance()).getInt('$_modePrefix$deviceId');
    return code == null ? null : AssistMode.tryFromCode(code);
  }

  Future<void> saveMode(String deviceId, AssistMode mode) async {
    await (await SharedPreferences.getInstance()).setInt('$_modePrefix$deviceId', mode.code);
  }
}
