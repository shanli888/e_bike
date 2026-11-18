import 'dart:async';

import 'package:bike_computer/models/assist_mode.dart';
import 'package:bike_computer/models/command_result.dart';
import 'package:bike_computer/services/assist_remote_scheduler.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只实现调速链路用到的字段，避免测试触发真实蓝牙插件。
class _FakeBle extends ChangeNotifier implements BleService {
  int _percent = 50;
  bool connected = true;
  AssistMode mode = AssistMode.manual;
  final List<int> sent = [];
  final List<bool> priorities = [];
  int stops = 0;

  @override
  int get assistPercent => _percent;

  @override
  bool get isConnected => connected;

  @override
  AssistMode get assistMode => mode;

  @override
  Future<CommandResult> setAssistPercent(int percent,
      {bool priority = false}) async {
    sent.add(percent);
    priorities.add(priority);
    _percent = percent;
    return CommandResult.ok;
  }

  @override
  Future<CommandResult> stopAssist() async {
    stops++;
    _percent = 0;
    return CommandResult.ok;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _cancelled = false;
  bool _fired = false;

  bool get isCancelled => _cancelled;
  bool get isFired => _fired;

  void fire() {
    if (_cancelled || _fired) return;
    _fired = true;
    callback();
  }

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled && !_fired;

  @override
  int get tick => 0;
}

class _ManualClock {
  final List<_ManualTimer> timers = [];

  Timer create(Duration duration, void Function() callback) {
    final timer = _ManualTimer(duration, callback);
    timers.add(timer);
    return timer;
  }

  /// 触发最近一个仍然存活的定时器（连续按键前的定时器都已被取消）。
  bool firePending() {
    for (var i = timers.length - 1; i >= 0; i--) {
      if (!timers[i].isCancelled && !timers[i].isFired) {
        timers[i].fire();
        return true;
      }
    }
    return false;
  }
}

void main() {
  late _FakeBle ble;
  late _ManualClock clock;
  late List<String> messages;
  late List<String> toasts;
  late AssistRemoteScheduler scheduler;

  setUp(() {
    ble = _FakeBle();
    clock = _ManualClock();
    messages = [];
    toasts = [];
    scheduler = AssistRemoteScheduler(
      ble: ble,
      stepOf: () => 5,
      onResult: messages.add,
      onToast: (message, {required bool error}) {
        toasts.add('${error ? '失败' : '成功'}|$message');
      },
      timerFactory: clock.create,
    );
  });

  test('单次按键立即给预览值，但不马上写设备', () {
    scheduler.step(1);
    expect(scheduler.previewPercent, 55);
    expect(scheduler.hasPendingStep, isTrue);
    expect(ble.sent, isEmpty);
    expect(clock.timers.single.duration, const Duration(seconds: 1));
  });

  test('防抖到期才下发，且只发一次', () async {
    scheduler.step(1);
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(ble.sent, [55]);
    expect(scheduler.previewPercent, isNull);
    expect(messages, ['助力已确认 55%']);
    expect(clock.firePending(), isFalse);
    expect(ble.sent, hasLength(1));
  });

  test('连续按键每次重置 1 秒窗口，最终只下发合并后的值', () async {
    scheduler.step(1); // 55
    scheduler.step(1); // 60
    scheduler.step(1); // 65
    expect(scheduler.previewPercent, 65);
    expect(ble.sent, isEmpty);

    // 前两个定时器被取消，只有最后一个会触发。
    expect(clock.timers[0].isCancelled, isTrue);
    expect(clock.timers[1].isCancelled, isTrue);
    expect(clock.timers[2].isCancelled, isFalse);
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(ble.sent, [65]);
  });

  test('上下键可混合连调，最终只下发一次合并值', () async {
    scheduler.step(1); // 55
    scheduler.step(1); // 60
    scheduler.step(-1); // 55
    expect(scheduler.previewPercent, 55);
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(ble.sent, [55]);
    expect(messages, ['助力已确认 55%']);
  });

  test('已在设备目标值时不再重复下发', () async {
    ble._percent = 99;
    scheduler.step(1);
    expect(scheduler.previewPercent, 99);
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(ble.sent, isEmpty);
    expect(messages, ['助力已达到 99%']);
  });

  test('到 0 / 99 边界时预览值被夹取', () {
    for (var i = 0; i < 12; i++) {
      scheduler.step(1);
    }
    expect(scheduler.previewPercent, 99);
    scheduler.cancel();
    for (var i = 0; i < 12; i++) {
      scheduler.step(-1);
    }
    expect(scheduler.previewPercent, 0);
  });

  test('主键停止实时生效，并取消待发的调速', () async {
    scheduler.step(1);
    expect(scheduler.previewPercent, 55);
    expect(clock.timers.single.isCancelled, isFalse);

    await scheduler.stop();
    expect(ble.stops, 1);
    expect(ble.sent, isEmpty);
    expect(scheduler.previewPercent, isNull);
    expect(clock.timers.single.isCancelled, isTrue);
    expect(clock.firePending(), isFalse, reason: '停止后不应再补发调速指令');
    expect(scheduler.resumePercent, 55);
    expect(messages, ['已停止助力，按上下键恢复 55%']);
  });

  test('停止助力后按上/下键恢复停止前的助力', () async {
    ble._percent = 45;
    await scheduler.stop();
    expect(ble.stops, 1);
    expect(ble.assistPercent, 0);
    expect(scheduler.resumePercent, 45);

    // 第一下按键直接恢复到 45%，而不是从 0 加一个步进。
    scheduler.step(1);
    expect(scheduler.previewPercent, 45);
    expect(scheduler.resumePercent, isNull, reason: '恢复值用完即清空');
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(ble.sent, [45]);
    // 恢复原助力属于安全动作：必须走优先级通道，不被写入冷却挡住。
    expect(ble.priorities, [true]);

    // 恢复之后继续按，回到正常步进累加。
    scheduler.step(1);
    expect(scheduler.previewPercent, 50);
  });

  test('停止后用下键同样恢复原助力，且用户手动操作会丢弃恢复值', () async {
    ble._percent = 60;
    await scheduler.stop();
    scheduler.step(-1);
    expect(scheduler.previewPercent, 60);
    await Future<void>.delayed(Duration.zero);

    // 手动拖动滑杆（cancel）后，恢复值失效，不再把用户设的值改回去。
    await scheduler.stop();
    expect(scheduler.resumePercent, 60);
    scheduler.cancel();
    expect(scheduler.resumePercent, isNull);
    expect(ble.assistPercent, 0);
    scheduler.step(1);
    expect(scheduler.previewPercent, 5, reason: '没有恢复值时从 0 加一个步进');
  });

  test('未连接或非手动模式时不下发调速，停止键也需先连接', () async {
    ble.connected = false;
    scheduler.step(1);
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(ble.sent, isEmpty);
    expect(messages.last, '请先连接控制器并确认手动模式');

    await scheduler.stop();
    expect(ble.stops, 0);
    expect(messages.last, '请先连接控制器');

    scheduler.cancel();
    ble.connected = true;
    ble.mode = AssistMode.commute;
    scheduler.step(1);
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(ble.sent, isEmpty);
  });

  test('用户手动操作可取消待发的闪控调速', () async {
    scheduler.step(1);
    scheduler.cancel();
    expect(scheduler.previewPercent, isNull);
    expect(clock.firePending(), isFalse);
    expect(ble.sent, isEmpty);
  });

  test('向电机下发调速成功后会 toast 提示', () async {
    scheduler.step(1);
    expect(toasts, isEmpty, reason: '按键阶段只有滑杆预览，还没有下发结果');
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(ble.sent, [55]);
    expect(toasts, ['成功|调速已下发 · 助力 55% 设备已确认']);
  });

  test('下发失败与停止助力结果同样会 toast 提示', () async {
    ble.connected = false;
    scheduler.step(1);
    expect(clock.firePending(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(toasts, ['失败|请先连接控制器并确认手动模式']);

    scheduler.cancel();
    ble.connected = true;
    await scheduler.stop();
    expect(toasts.last, '成功|已停止助力 · 设备已确认，按上下键恢复 50%');
  });

  test('dispose 会取消待发定时器，不再下发', () {
    scheduler.step(1);
    scheduler.dispose();
    expect(clock.timers.single.isCancelled, isTrue);
    expect(clock.firePending(), isFalse);
    expect(ble.sent, isEmpty);
  });

  test('闪控按键会点亮对应方向的面板按钮，按下态随后自动复原', () async {
    expect(scheduler.pressedDirection, isNull);
    scheduler.step(1);
    expect(scheduler.pressedDirection, 1, reason: '上键对应 +');
    scheduler.step(-1);
    expect(scheduler.pressedDirection, -1, reason: '下键对应 -');

    // 按下态约 0.35 秒后自动复原。
    await Future<void>.delayed(const Duration(milliseconds: 420));
    expect(scheduler.pressedDirection, isNull);
  });
}
