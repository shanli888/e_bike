import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/gps_service.dart';
import 'package:bike_computer/services/ride_recorder.dart';
import 'package:bike_computer/services/ride_time_service.dart';
import 'package:flutter_test/flutter_test.dart';

RideTimeService _service({
  required bool Function() connected,
  required double? Function() speed,
}) {
  return RideTimeService(isConnected: connected, speedKmh: speed);
}

/// 逐秒推进，模拟真实 Timer.periodic 每秒调用一次
void _advance(RideTimeService service, DateTime base, int from, int seconds) {
  for (var i = from + 1; i <= from + seconds; i++) {
    service.tick(base.add(Duration(seconds: i)));
  }
}

void main() {
  final base = DateTime(2026, 11, 13, 10);

  test('初始为 00:00，速度为 0 不计时', () {
    var speed = 0.0;
    final s = _service(connected: () => true, speed: () => speed);
    s.tick(base);
    _advance(s, base, 0, 120);
    expect(s.display, '00:00');
    expect(s.running, isFalse);
    s.dispose();
  });

  test('有速度开始计时，速度归零自动暂停，恢复后继续累计', () {
    var speed = 0.0;
    final s = _service(connected: () => true, speed: () => speed);
    // 首次 tick 因「新连接」清零，之后第 2 秒起才开始累计
    s.tick(base);
    speed = 18.2;
    _advance(s, base, 0, 65);
    expect(s.display, '00:01');
    expect(s.running, isTrue);

    speed = 0;
    _advance(s, base, 65, 65);
    expect(s.display, '00:01');
    expect(s.running, isFalse);

    speed = 20;
    _advance(s, base, 130, 65);
    expect(s.display, '00:02');
    s.dispose();
  });

  test('格式为 HH:MM，小时按累计值显示', () {
    final s = _service(connected: () => true, speed: () => 25);
    s.tick(base);
    _advance(s, base, 0, 3725); // 约 1 小时 2 分
    expect(s.display, '01:02');
    s.dispose();
  });

  test('重新连接控制器自动清零，之后重新累计', () {
    var connected = false;
    final s = _service(connected: () => connected, speed: () => 15);
    s.tick(base);
    _advance(s, base, 0, 65);
    expect(s.display, '00:01');

    connected = true;
    _advance(s, base, 65, 3); // false → true 触发新的一次骑行
    expect(s.display, '00:00');

    _advance(s, base, 68, 65);
    expect(s.display, '00:01');
    s.dispose();
  });

  test('App 挂起造成的超长间隔不补算', () {
    final s = _service(connected: () => false, speed: () => 20);
    s.tick(base);
    _advance(s, base, 0, 65);
    expect(s.display, '00:01');

    s.tick(base.add(const Duration(minutes: 5)));
    expect(s.display, '00:01');
    expect(s.running, isFalse);
    s.dispose();
  });

  test('手动 reset 清零', () {
    final s = _service(connected: () => false, speed: () => 12);
    s.tick(base);
    _advance(s, base, 0, 130);
    expect(s.display, '00:02');
    s.reset();
    expect(s.display, '00:00');
    expect(s.running, isFalse);
    s.dispose();
  });

  test('工厂方法在 GPS 主来源时按 GPS 速度计时', () {
    final s = RideTimeService.fromServices(BleService(), _GpsPrimary());
    s.tick(base);
    _advance(s, base, 0, 65);
    expect(s.display, '00:01');
    s.dispose();
  });

  group('跟随骑行记录状态（点开始即计时）', () {
    late RideRecordState state;
    late RideTimeService s;

    setUp(() {
      state = RideRecordState.idle;
      s = RideTimeService(
        isConnected: () => false,
        speedKmh: () => 0, // 速度为 0：证明不再依赖速度
        recordState: () => state,
      );
      s.tick(base);
    });

    tearDown(() => s.dispose());

    test('idle 时归零不走字', () {
      _advance(s, base, 0, 90);
      expect(s.display, '00:00');
      expect(s.running, isFalse);
    });

    test('点开始（recording）即使速度为 0 也走字', () {
      state = RideRecordState.recording;
      _advance(s, base, 0, 125); // 首 tick 已消耗 base，累计约 124s
      expect(s.display, isNot('00:00'));
      expect(s.running, isTrue);
    });

    test('暂停停走但保留时长，结束后归零', () {
      state = RideRecordState.recording;
      _advance(s, base, 0, 70);
      final atPause = s.display;
      expect(atPause, isNot('00:00'));

      state = RideRecordState.paused;
      _advance(s, base, 70, 60);
      expect(s.display, atPause, reason: '暂停期间时长不变');
      expect(s.running, isFalse);

      state = RideRecordState.idle;
      s.tick(base.add(const Duration(seconds: 131)));
      expect(s.display, '00:00', reason: '结束后归零待命');
    });
  });
}

/// 模拟 GPS 已成为主速度来源，避免触发真实定位
class _GpsPrimary extends GpsService {
  @override
  SpeedSource get source => SpeedSource.gps;

  @override
  double? get speedKmh => 25;
}
