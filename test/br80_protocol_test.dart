import 'package:bike_computer/services/br80_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognises remote names without changing motor matching', () {
    expect(Br80Protocol.matchesName('BlingRemote BR80'), isTrue);
    expect(Br80Protocol.matchesName('br80'), isTrue);
    expect(Br80Protocol.matchesName('LIVALL BH60'), isTrue);
    expect(Br80Protocol.matchesName('BR-remote'), isTrue);
    expect(Br80Protocol.matchesName('LVBU'), isFalse);
    expect(Br80Protocol.matchesName('njcuk.fitting.ad1204'), isFalse);
  });

  test(
      'matches A2A0 advertised service even when the name is empty (H5 filter)',
      () {
    expect(
        Br80Protocol.matchesService(['0000a2a0-0000-1000-8000-00805f9b34fb']),
        isTrue);
    expect(Br80Protocol.matchesService(['a2a0']), isTrue);
    expect(
        Br80Protocol.matchesService(['0000ffe0-0000-1000-8000-00805f9b34fb']),
        isFalse);
    expect(
      Br80Protocol.matchesScan(
        name: '',
        advertisedUuids: ['0000a2a0-0000-1000-8000-00805f9b34fb'],
      ),
      isTrue,
    );
    expect(
        Br80Protocol.matchesScan(name: '', advertisedUuids: const []), isFalse);
  });

  test('only up and down key presses change assist', () {
    expect(Br80Protocol.assistDelta([0x06]), 5);
    expect(Br80Protocol.assistDelta([0x05]), -5);
    for (final value in [0x25, 0x26, 0x07, 0x08, 0x09]) {
      expect(Br80Protocol.assistDelta([value]), isNull);
    }
    expect(Br80Protocol.assistDelta([]), isNull);
    expect(Br80Protocol.assistDelta([0x06, 0x05]), isNull);
  });

  test('上下键只上报方向，步进由设置页决定', () {
    expect(Br80Protocol.assistDirection([0x06]), 1);
    expect(Br80Protocol.assistDirection([0x05]), -1);
    for (final value in [0x25, 0x26, 0x07, 0x08, 0x09]) {
      expect(Br80Protocol.assistDirection([value]), isNull);
    }
    expect(Br80Protocol.assistDelta([0x06], step: 10), 10);
    expect(Br80Protocol.assistDelta([0x05], step: 10), -10);
    expect(Br80Protocol.assistDelta([0x07], step: 10), isNull);
    expect(Br80Protocol.assistDelta([0x06]), 5); // 默认步进
  });

  test('主键 0x09 是停止助力键，抬起与其它键都不触发', () {
    expect(Br80Protocol.isStopKey([0x09]), isTrue);
    for (final value in [0x29, 0x25, 0x05, 0x06, 0x07, 0x08, 0x10]) {
      expect(Br80Protocol.isStopKey([value]), isFalse,
          reason: '0x${value.toRadixString(16)} 不应触发停止');
    }
    expect(Br80Protocol.isStopKey([0x09, 0x09]), isFalse);
    expect(Br80Protocol.isStopKey([]), isFalse);
    // 停止键与调速方向互斥，避免一帧触发两条命令。
    expect(Br80Protocol.assistDirection([0x09]), isNull);
  });

  test('parses A2A4 single-byte frames into readable key events', () {
    final at = DateTime(2026, 11, 13, 13, 45, 21);
    final up = Br80Protocol.parseKey([0x06], at: at)!;
    expect(up.name, '▲ 上键');
    expect(up.pressed, isTrue);
    expect(up.display, '▲ 上键 按下');
    expect(up.hex, '0x06');
    expect(up.timeLabel, '13:45:21');

    expect(Br80Protocol.parseKey([0x05], at: at)!.name, '▼ 下键');
    expect(Br80Protocol.parseKey([0x07], at: at)!.name, '◀ 左键');
    expect(Br80Protocol.parseKey([0x08], at: at)!.name, '▶ 右键');
    expect(Br80Protocol.parseKey([0x09], at: at)!.name, '● 主键');

    final released = Br80Protocol.parseKey([0x26], at: at)!;
    expect(released.pressed, isFalse);
    expect(released.action, '抬起');
    expect(released.known, isTrue);

    final unknown = Br80Protocol.parseKey([0x10], at: at)!;
    expect(unknown.known, isFalse);
    expect(unknown.action, '未知事件');
    expect(unknown.display, '未知键 0x10');

    expect(Br80Protocol.parseKey([0x06, 0x05]), isNull);
    expect(Br80Protocol.parseKey([]), isNull);
  });

  test('battery is a single percentage byte, including zero', () {
    expect(Br80Protocol.batteryLevel([0]), 0);
    expect(Br80Protocol.batteryLevel([100]), 100);
    expect(Br80Protocol.batteryLevel([101]), isNull);
    expect(Br80Protocol.batteryLevel([]), isNull);
    expect(Br80Protocol.batteryLevel([1, 2]), isNull);
  });

  test('A2A3 battery uses the last hex byte, 0x88 means full (doc 6.2B)', () {
    expect(Br80Protocol.batteryFromA2A3([0x88]), 100);
    expect(Br80Protocol.batteryFromA2A3([0x2d]), 45);
    expect(Br80Protocol.batteryFromA2A3([0x10, 0x32]), 50);
    expect(Br80Protocol.batteryFromA2A3([0x65]), isNull); // 101 > 100
    expect(Br80Protocol.batteryFromA2A3([]), isNull);
  });
}
