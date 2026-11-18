import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/assist_mode.dart';
import '../models/command_result.dart';
import 'assist_step_settings.dart';
import 'ble_service.dart';

/// 创建定时器的工厂，便于单测用可控时钟替换真实 Timer。
typedef AssistTimerFactory = Timer Function(
    Duration duration, void Function() callback);

/// BR80 闪控上/下键的助力调速调度器。
///
/// 骑行时连续按键很常见，若每按一次就写一条 BLE 指令，既会刷屏又容易撞上
/// 设备「等待回包」的忙碌状态。这里把「调整数值」与「下发指令」拆开：
///
/// - 每次按键立刻更新 [previewPercent]，首页滑杆随之移动（纯本地，不写 BLE）；
/// - 每次按键重置 1 秒防抖定时器，最后一次按键 1 秒后才把**最终值**下发一次；
/// - 主键（home）走 [stop]，取消所有待发调速并**立即**下发停止助力命令。
///
/// 设备直接上报的 [BleService.assistPercent] 仍是唯一权威值，预览值只在
/// 待发期间覆盖滑杆显示；命令返回后自动让位给设备确认值。
class AssistRemoteScheduler extends ChangeNotifier {
  AssistRemoteScheduler({
    required this.ble,
    required this.stepOf,
    required this.onResult,
    this.onToast,
    this.debounce = const Duration(seconds: 1),
    AssistTimerFactory? timerFactory,
  }) : _timerFactory =
            timerFactory ?? ((duration, callback) => Timer(duration, callback));

  final BleService ble;

  /// 读取设置页的「加减步进」，与手动 +/- 按钮共用同一份设置。
  final int Function() stepOf;

  /// 命令结果反馈（闪控已连接时显示在助力卡提示行）。
  final void Function(String message) onResult;

  /// 命令结果的 toast 反馈：向电机下发调速 / 停止助力后都提示一次，
  /// `error` 区分成功与失败。可选，widget 测试可直接忽略。
  final void Function(String message, {required bool error})? onToast;

  /// 连续按键的合并窗口。
  final Duration debounce;

  final AssistTimerFactory _timerFactory;

  Timer? _timer;
  int? _previewPercent;
  bool _inFlight = false;
  bool _disposed = false;

  /// 停止助力前（或最近一次非零助力）的百分比，用于停止后按上/下键恢复。
  int? _resumePercent;

  /// 最近一次闪控上/下键的方向（1 = 上键/+，-1 = 下键/-），
  /// 用于让控制面板的加减按钮显示「按下」效果。
  int? _pressedDirection;
  int? get pressedDirection => _pressedDirection;
  Timer? _pressTimer;

  /// 待下发值是否属于「停止后恢复原助力」：这类写入按安全动作抢占链路。
  bool _pendingPriority = false;

  /// 待下发期间滑杆应显示的百分比；null 表示没有待发调速。
  int? get previewPercent => _previewPercent;

  /// 停止助力后暂存的「原助力」，恢复后清空；null 表示没有可恢复的值。
  int? get resumePercent => _resumePercent;

  bool get hasPendingStep => _previewPercent != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _toast(String message, {bool error = false}) =>
      onToast?.call(message, error: error);

  /// 上/下键：立即移动滑杆并重新开始 1 秒倒计时。
  /// 连续按键会以「当前预览值」为基准继续累加，最终只下发一次。
  ///
  /// 停止助力（home）把助力降到 0 后，下一次按上/下键不再从 0 开始加，
  /// 而是**恢复停止前的原助力值**，避免每停一次都要从 5% 一路按回去。
  void step(int direction) {
    final magnitude = AssistStepSettings.clampStep(stepOf());
    _flashPress(direction);

    // 刚停过助力且设备仍为 0%：本次按键直接恢复原值。
    final resume = _resumePercent;
    if (_previewPercent == null &&
        resume != null &&
        resume > 0 &&
        ble.assistPercent == 0) {
      _resumePercent = null;
      _previewPercent = resume;
      // 恢复原助力属于安全动作，不受写入冷却限制，避免按了没反应。
      _pendingPriority = true;
      _notify();
      _scheduleFlush();
      return;
    }

    final base = _previewPercent ?? ble.assistPercent;
    _previewPercent = assistStepTarget(base, direction, magnitude);
    _notify();
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _timer?.cancel();
    _timer = _timerFactory(debounce, () => unawaited(flush()));
  }

  /// 闪控按键与面板按钮联动：按下上/下键时让对应按钮显示按下效果，
  /// 约 0.35 秒后自动复原（与手指点按的视觉时长接近）。
  void _flashPress(int direction) {
    _pressedDirection = direction;
    _pressTimer?.cancel();
    _pressTimer = Timer(const Duration(milliseconds: 350), () {
      _pressTimer = null;
      if (_pressedDirection == direction) {
        _pressedDirection = null;
        _notify();
      }
    });
    _notify();
  }

  /// 防抖到期后提交最终值。若上一条指令还在等设备确认，保留预览并重新排队，
  /// 避免两条写指令并发。
  Future<void> flush() async {
    _timer = null;
    if (_inFlight || _previewPercent == null) return;
    final target = _previewPercent!;
    _inFlight = true;
    try {
      if (!ble.isConnected || ble.assistMode != AssistMode.manual) {
        const message = '请先连接控制器并确认手动模式';
        onResult(message);
        _toast(message, error: true);
        _pendingPriority = false;
      } else if (target == ble.assistPercent) {
        final message = '助力已达到 $target%';
        onResult(message);
        _toast(message);
        _pendingPriority = false;
      } else {
        final result = await ble.setAssistPercent(target, priority: _pendingPriority);
        _pendingPriority = false;
        if (result.isOk) {
          onResult('助力已确认 $target%');
          _toast('调速已下发 · 助力 $target% 设备已确认');
        } else {
          onResult(result.message);
          _toast('调速下发失败 · ${result.message}', error: true);
        }
      }
      // 期间又有新按键时预览值已变化，保留它等待下一次下发。
      if (_previewPercent == target) {
        _previewPercent = null;
        _notify();
      }
    } finally {
      _inFlight = false;
      if (_previewPercent != null && _timer == null) _scheduleFlush();
    }
  }

  /// 主键（home）：不做任何防抖，取消待发调速并实时下发停止助力。
  /// 停止前记住当前助力百分比，下次按上/下键恢复到这个值。
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _pendingPriority = false;
    // 待发值优先（用户刚调到 45% 还没下发就按了 home），否则用设备当前值。
    final before = _previewPercent ?? ble.assistPercent;
    if (_previewPercent != null) {
      _previewPercent = null;
      _notify();
    }
    if (!ble.isConnected) {
      const message = '请先连接控制器';
      onResult(message);
      _toast(message, error: true);
      return;
    }
    final result = await ble.stopAssist();
    if (result.isOk) {
      if (before > 0) _resumePercent = before;
      final suffix = _resumePercent == null ? '' : '，按上下键恢复 $_resumePercent%';
      onResult('已停止助力$suffix');
      _toast('已停止助力 · 设备已确认$suffix');
    } else {
      onResult(result.message);
      _toast('停止助力失败 · ${result.message}', error: true);
    }
  }

  /// 用户在首页手动拖滑杆或点 +/- 时调用：丢弃待发的闪控调速，
  /// 让手动操作优先，避免 1 秒后的闪控指令覆盖用户刚设的值。
  /// 同时清掉停止助力的「恢复值」，避免之后按闪控键把用户手动设的值改回去。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _resumePercent = null;
    _pendingPriority = false;
    if (_previewPercent != null) {
      _previewPercent = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pressTimer?.cancel();
    _pressTimer = null;
    super.dispose();
  }
}
