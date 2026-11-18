import 'package:bike_computer/services/screen_wake_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('初始未连接不下发，连接后开启、断开后关闭，重复状态不重复调用', () async {
    final calls = <bool>[];
    final lock = ScreenWakeLock(apply: (value) async => calls.add(value));

    await lock.setConnected(false);
    expect(calls, isEmpty);
    expect(lock.isEnabled, isFalse);

    await lock.setConnected(true);
    expect(calls, [true]);
    expect(lock.isEnabled, isTrue);

    // BLE 服务连接过程中会反复 notifyListeners，不能重复调用平台接口。
    await lock.setConnected(true);
    await lock.setConnected(true);
    expect(calls, [true]);

    await lock.setConnected(false);
    expect(calls, [true, false]);
    expect(lock.isEnabled, isFalse);
    await lock.setConnected(false);
    expect(calls, [true, false]);
  });

  test('连接状态快速切换时以最后一次为准，且会补发中间状态', () async {
    final calls = <bool>[];
    final lock = ScreenWakeLock(apply: (value) async {
      calls.add(value);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });

    final first = lock.setConnected(true);
    final second = lock.setConnected(false); // 上一次还没下发完成
    await Future.wait([first, second]);

    expect(calls, [true, false]);
    expect(lock.isEnabled, isFalse);
  });

  test('连接后立刻断开，最终平台状态是熄屏', () async {
    final calls = <bool>[];
    final lock = ScreenWakeLock(apply: (value) async {
      calls.add(value);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });

    final first = lock.setConnected(false);
    final second = lock.setConnected(false);
    await Future.wait([first, second]);
    expect(calls, isEmpty);

    final connect = lock.setConnected(true);
    final disconnect = lock.setConnected(false);
    await Future.wait([connect, disconnect]);
    expect(calls, [true, false]);
  });

  test('平台接口抛异常时不影响连接流程，也不反复重试', () async {
    final calls = <bool>[];
    final lock = ScreenWakeLock(apply: (value) async {
      calls.add(value);
      throw StateError('MissingPluginException');
    });

    await expectLater(lock.setConnected(true), completes);
    expect(calls, [true]);
    expect(lock.isEnabled, isTrue);

    await expectLater(lock.setConnected(false), completes);
    expect(calls, [true, false]);
    expect(lock.isEnabled, isFalse);
  });

  test('回到前台 refresh 会补发当前状态，未连接且无失败时不打扰平台', () async {
    final calls = <bool>[];
    final lock = ScreenWakeLock(apply: (value) async => calls.add(value));

    await lock.refresh();
    expect(calls, isEmpty);

    await lock.setConnected(true);
    expect(calls, [true]);
    await lock.refresh();
    expect(calls, [true, true]);

    await lock.setConnected(false);
    expect(calls, [true, true, false]);
    await lock.refresh();
    expect(calls, [true, true, false]);
  });

  test('后台期间平台调用失败，回到前台 refresh 后重新下发成功', () async {
    final calls = <bool>[];
    var fail = true;
    final lock = ScreenWakeLock(apply: (value) async {
      calls.add(value);
      if (fail) throw StateError('NoActivityException');
    });

    await lock.setConnected(true); // 后台：失败
    expect(calls, [true]);
    fail = false;
    await lock.refresh(); // 前台：补齐
    expect(calls, [true, true]);
    expect(lock.isEnabled, isTrue);
  });
}
