import 'package:wakelock_plus/wakelock_plus.dart';

/// 屏幕常亮控制。
///
/// 连接控制器或 BR80 闪控时保持亮屏，全部断开后恢复系统自动熄屏。
/// [setConnected] 会在状态真正变化时才调用平台接口：BLE 服务在一次连接过程中
/// 会频繁 `notifyListeners`，直接逐次调用会造成大量无意义的方法通道通信。
class ScreenWakeLock {
  ScreenWakeLock({Future<void> Function(bool enable)? apply})
      : _apply = apply ?? _defaultApply;

  final Future<void> Function(bool enable) _apply;

  /// 平台上一次下发的状态。App 启动时系统默认按自动熄屏处理。
  bool _applied = false;

  /// 期望状态（由最新的连接情况决定）。
  bool _desired = false;
  bool _running = false;
  bool _lastApplyFailed = false;

  bool get isEnabled => _desired;

  static Future<void> _defaultApply(bool enable) =>
      WakelockPlus.toggle(enable: enable);

  /// 同步连接状态。并发调用时以最后一次的 [connected] 为最终结果。
  Future<void> setConnected(bool connected) async {
    _desired = connected;
    if (_running) return;
    _running = true;
    try {
      while (_applied != _desired) {
        final target = _desired;
        try {
          await _apply(target);
          _lastApplyFailed = false;
        } catch (_) {
          // 桌面/测试环境、或 App 在后台时 Activity 已解绑都会抛错；
          // 不阻塞连接流程，也不在当前循环里反复重试。
          _lastApplyFailed = true;
        }
        _applied = target;
      }
    } finally {
      _running = false;
    }
  }

  /// App 回到前台时重新下发一次窗口标志。
  ///
  /// 后台期间 Activity 可能 detach，导致平台调用失败；且系统重建窗口后
  /// 之前设置的 `FLAG_KEEP_SCREEN_ON` 也会丢失。
  Future<void> refresh() async {
    if (!_desired && !_lastApplyFailed) return;
    _applied = !_desired; // 强制下一轮重新下发当前状态
    await setConnected(_desired);
  }
}
