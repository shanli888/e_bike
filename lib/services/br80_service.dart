import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_constants.dart';
import 'br80_protocol.dart';

/// BR80 闪控的独立 BLE 连接：与电机控制器互不占用。
///
/// 连接流程与 H5 客户端 `lvbu-ble/js/remote.js` 对齐（已实机验证）：
/// 1. 枚举全部服务，订阅所有可通知特征（不假设只有 A2A4）；
/// 2. 对 A2A3 开通知，失败可忽略（真实设备常没有 CCCD）；
/// 3. 向 A2A3 写单字节 0xFF 激活，带响应写失败再试无响应写；
/// 4. 等待 300ms、主动读一次可读特征，再读标准电池 180F/2A19。
class Br80Service extends ChangeNotifier {
  Br80Service(
      {required this.onAssistStep, this.onStopAssist, this.onKeyPressed});

  /// 回调参数是助力调整方向：+1（上键，等同手动 +）、-1（下键，等同手动 -）。
  /// 上/下键先本地调整滑杆，1 秒防抖后才下发一次最终值。
  final Future<void> Function(int direction) onAssistStep;

  /// 主键（home）按下：立即下发「停止助力」，不参与防抖。
  /// 可选参数，方便不接控制器的场景（如设备页单独调试闪控）保持兼容。
  final Future<void> Function()? onStopAssist;

  /// 已知键「按下」时的即时提示（toast）。参数是按键名，如 `▲ 上键`。
  /// 可选：widget 测试单独调试按键时无需挂全局 messenger。
  final void Function(String keyName)? onKeyPressed;
  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;
  bool _connecting = false;
  bool get isConnecting => _connecting;
  bool _connected = false;
  bool get isConnected => _connected;
  int? _battery;
  int? get battery => _battery;
  String? _message;
  String? get message => _message;
  String? _lastError;
  String? get lastError => _lastError;

  // 按键监视：与助力联动解耦，未连接控制器时也能看到按下了什么键
  Br80KeyEvent? _lastPressedKey;
  Br80KeyEvent? get lastPressedKey => _lastPressedKey;
  final List<Br80KeyEvent> _keyHistory = [];
  List<Br80KeyEvent> get keyHistory => List.unmodifiable(_keyHistory);
  int _pressCount = 0;
  int get pressCount => _pressCount;

  bool _disposed = false;
  int _generation = 0;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  final List<StreamSubscription<List<int>>> _subscriptions = [];

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void setMessage(String message) {
    if (!_connected) return;
    _message = message;
    _changed();
  }

  /// 清空按键监视记录（不影响连接和助力联动）。
  void clearKeyHistory() {
    _lastPressedKey = null;
    _keyHistory.clear();
    _pressCount = 0;
    _changed();
  }

  /// 处理一帧 A2A4 按键通知。公开以便 widget 测试直接喂帧，
  /// 也便于未来接入头盔转发链路。
  ///
  /// 上/下键只把方向（+1 / -1）交给 [onAssistStep]，由调度器做本地预览和
  /// 1 秒防抖；主键（home）交给 [onStopAssist] 实时下发停止助力。
  void handleKeyFrame(List<int> value, {DateTime? at}) {
    final event = Br80Protocol.parseKey(value, at: at);
    if (event == null) return;
    _keyHistory.insert(0, event);
    if (_keyHistory.length > 8) _keyHistory.removeLast();
    if (event.pressed && event.known) {
      _lastPressedKey = event;
      _pressCount++;
      // 按键反馈只走 toast，不再占用助力卡提示行。
      onKeyPressed?.call(event.name);
    }
    debugPrint('BR80 按键 ${event.display} ${event.hex}');
    _changed();

    // 停止优先且独占：不能与待发的调速指令并存。
    if (Br80Protocol.isStopKey(value)) {
      final stop = onStopAssist;
      if (stop != null) unawaited(stop());
      return;
    }
    final direction = Br80Protocol.assistDirection(value);
    if (direction != null) unawaited(onAssistStep(direction));
  }

  Future<bool> connect(BluetoothDevice device) async {
    if (_connecting || _connected) return false;
    final generation = ++_generation;
    _connecting = true;
    _device = device;
    _battery = null;
    _message = null;
    _lastError = null;
    clearKeyHistory();
    _changed();
    try {
      await device.connect(timeout: BleConstants.connectTimeout);
      if (generation != _generation) {
        await device.disconnect();
        return false;
      }
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            generation == _generation) {
          _clear();
        }
      });
      final services = await device.discoverServices();

      BluetoothCharacteristic? keys;
      BluetoothCharacteristic? activation;
      BluetoothCharacteristic? battery;
      final notifiable = <BluetoothCharacteristic>[];
      final writable = <BluetoothCharacteristic>[];
      for (final service in services) {
        final su = UuidUtil.normalize(service.serviceUuid);
        final parts = <String>[];
        for (final c in service.characteristics) {
          final cu = UuidUtil.normalize(c.characteristicUuid);
          parts.add('$cu[n=${c.properties.notify} i=${c.properties.indicate} '
              'w=${c.properties.write} wn=${c.properties.writeWithoutResponse} '
              'r=${c.properties.read}]');
          if (c.properties.notify || c.properties.indicate) {
            notifiable.add(c);
          }
          if (c.properties.write || c.properties.writeWithoutResponse) {
            writable.add(c);
          }
          if (su == Br80Protocol.serviceShortUuid && cu == 'a2a4') {
            keys = c;
          }
          if (su == Br80Protocol.serviceShortUuid && cu == 'a2a3') {
            activation = c;
          }
          if (cu == '2a19') {
            battery = c;
          }
        }
        debugPrint('BR80 服务 $su: ${parts.join(' ')}');
      }
      // H5 兜底：A2A3 缺失时取第一个可写特征
      activation ??= writable.isEmpty ? null : writable.first;
      if (keys == null ||
          !(keys.properties.notify || keys.properties.indicate)) {
        throw StateError('未找到可通知的 A2A4 按键特征');
      }
      if (activation == null) {
        throw StateError('未找到可写的 A2A3 激活特征');
      }
      final BluetoothCharacteristic writeChar = activation;

      // 1) 订阅所有可通知特征（含 180F/2A19 电量），失败逐个忽略
      for (final c in notifiable) {
        _subscriptions.add(c.onValueReceived
            .listen((value) => _onValue(c, value, generation)));
        try {
          await c.setNotifyValue(true);
          debugPrint('BR80 已订阅 ${UuidUtil.normalize(c.characteristicUuid)}');
        } catch (e) {
          debugPrint(
              'BR80 订阅 ${UuidUtil.normalize(c.characteristicUuid)} 失败（可忽略）: $e');
        }
      }

      // 2) A2A3 也开通知（文档 §2.4A / H5：失败一般正常，继续写 0xFF）
      if (!notifiable.contains(writeChar)) {
        try {
          _subscriptions.add(writeChar.onValueReceived
              .listen((value) => _onValue(writeChar, value, generation)));
          await writeChar.setNotifyValue(true);
          debugPrint('BR80 A2A3 已开通知');
        } catch (e) {
          debugPrint('BR80 A2A3 开通知失败（一般正常）: $e');
        }
      }

      // 3) 写 0xFF 激活：先带响应写，失败再试无响应写
      bool activated = false;
      try {
        await writeChar.write(const [0xff], withoutResponse: false);
        activated = true;
      } catch (e) {
        debugPrint('BR80 0xFF 带响应写失败: $e');
        try {
          await writeChar.write(const [0xff], withoutResponse: true);
          activated = true;
        } catch (e2) {
          debugPrint('BR80 0xFF 无响应写也失败: $e2');
        }
      }
      debugPrint('BR80 激活帧 0xFF ${activated ? '写入成功' : '写入失败'}');

      // 4) 等设备切换状态，再主动读一次（部分设备读后才推送）
      await Future.delayed(const Duration(milliseconds: 300));
      for (final c in notifiable) {
        if (!c.properties.read) continue;
        try {
          await c.read();
        } catch (_) {}
      }
      if (battery != null && battery.properties.read) {
        try {
          final level = Br80Protocol.batteryLevel(await battery.read());
          if (level != null && generation == _generation) _battery = level;
        } catch (_) {}
      }

      if (generation != _generation) return false;
      _connected = true;
      _connecting = false;
      _lastError = activated ? null : '激活帧 0xFF 写入失败，按键可能无响应';
      _message = _lastError;
      _changed();
      debugPrint('BR80 连接完成: connected=$_connected battery=$_battery');
      return true;
    } catch (e) {
      debugPrint('BR80 连接或激活失败: $e');
      if (generation == _generation) {
        _clear();
        _lastError = e.toString();
        try {
          await device.disconnect();
        } catch (_) {}
      }
      return false;
    }
  }

  /// 所有通知统一入口：A2A4 单字节按键、2A19 / A2A3 电量
  void _onValue(BluetoothCharacteristic c, List<int> value, int generation) {
    if (generation != _generation) return;
    final su = UuidUtil.normalize(c.serviceUuid);
    final cu = UuidUtil.normalize(c.characteristicUuid);
    final hex = value.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    debugPrint('BR80 通知 $su/$cu: $hex');

    if (su == Br80Protocol.serviceShortUuid && cu == 'a2a4') {
      handleKeyFrame(value);
      return;
    }
    final level = cu == '2a19'
        ? Br80Protocol.batteryLevel(value)
        : (cu == 'a2a3' ? Br80Protocol.batteryFromA2A3(value) : null);
    if (level != null) {
      _battery = level;
      _changed();
    }
  }

  void _clear() {
    _generation++;
    _connectionSub?.cancel();
    _connectionSub = null;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _device = null;
    _connected = false;
    _connecting = false;
    _battery = null;
    _message = null;
    _changed();
  }

  Future<void> disconnect() async {
    final device = _device;
    _lastError = null;
    _clear();
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}
