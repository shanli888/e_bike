import 'dart:async';

import 'package:bike_computer/services/lvbu_protocol.dart';
import 'package:bike_computer/services/lvbu_read_only.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imei = '123456789012345';
  List<int> bytes(String hex) => [
    for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  String header(String code) => '${code}F$imei';

  test('只读白名单使用原厂请求，C6 只允许查询参数', () {
    expect(LvbuReadCommand.values.map((c) => c.code).toSet(), {'C0', 'BF', 'C1', 'B1', 'BD', 'C6'});
    for (final c in LvbuReadCommand.values) {
      expect(LvbuProtocol.toHex(LvbuReadOnly.request(c, imei)), '${header(c.code)}${c.suffix}');
    }
    expect(LvbuReadCommand.climbing.suffix, '030000');
    expect(() => LvbuReadOnly.request(LvbuReadCommand.voltage, '12'), throwsArgumentError);
  });

  test('速度、电压、负温度和陀螺仪按原厂十进制规则解析', () {
    LvbuReadReply? parse(LvbuReadCommand cmd, String tail) =>
        LvbuReadReplyParser(cmd, imei).feed(bytes('${header(cmd.code)}$tail'));
    expect(parse(LvbuReadCommand.voltage, '010385')?.value, 38.5);
    expect(parse(LvbuReadCommand.speed, '010123')?.value, 12.3);
    expect(parse(LvbuReadCommand.temperature, '011025')?.value, -2.5);
    expect(parse(LvbuReadCommand.gyro, '01113844')?.value, -13.844);
    expect(parse(LvbuReadCommand.voltage, '020000')?.status, 2);
    expect(parse(LvbuReadCommand.speed, '010A23'), isNull);
  });

  test('分片、错误设备、其他命令和 C6 子命令不会误判', () {
    final parser = LvbuReadReplyParser(LvbuReadCommand.climbing, imei);
    expect(parser.feed(bytes('${header('BF')}010123')), isNull);
    expect(parser.feed(bytes('C6F99999999999999901031004')), isNull);
    expect(parser.feed(bytes('${header('C6')}01011004')), isNull);
    final frame = bytes('${header('C6')}01031204');
    expect(parser.feed(frame.sublist(0, 4)), isNull);
    final reply = parser.feed(frame.sublist(4));
    expect(reply?.climbingAngle, 1.2);
    expect(reply?.climbingLevel, 4);
  });

  test('B1 可变长度记录解析距离、时间和最高速度', () {
    final parser = LvbuReadReplyParser(LvbuReadCommand.trip, imei);
    // 最大速度 12.3，六段长度 4/0/4/0/0/0，距离 1000m，时间 600s。
    final frame = bytes('${header('B1')}01012340400003E80258');
    expect(parser.feed(frame.sublist(0, 8)), isNull);
    final reply = parser.feed(frame.sublist(8));
    expect(reply?.tripDistanceKm, 1);
    expect(reply?.tripTimeSeconds, 600);
    expect(reply?.tripMaxSpeed, 12.3);
  });

  test('错误回复分片、粘包和无法解析的 B1 不抛异常', () {
    final parser = LvbuReadReplyParser(LvbuReadCommand.speed, imei);
    final failed = bytes('${header('BF')}020000');
    expect(parser.feed(failed.sublist(0, 10)), isNull);
    expect(parser.feed(failed.sublist(10))?.status, 2);
    final frame = bytes('${header('BF')}010123');
    expect(parser.feed([...bytes('${header('C0')}010385'), ...frame])?.value, 12.3);
    final tripParser = LvbuReadReplyParser(LvbuReadCommand.trip, imei);
    // 累计帧长超出上限的 B1 必须安全丢弃。
    final oversized = bytes('${header('B1')}010000FFFFFF');
    expect(tripParser.feed(oversized), isNull);
  });

  test('电量曲线是原厂估算，边界和中间区间可复现', () {
    expect(LvbuReadOnly.estimateBatteryPercent(24), 0);
    expect(LvbuReadOnly.estimateBatteryPercent(41.8), 100);
    expect(LvbuReadOnly.estimateBatteryPercent(38.45), 75);
    expect(LvbuReadOnly.estimateBatteryPercent(38.5), 77);
    expect(() => LvbuReadOnly.estimateBatteryPercent(double.nan), throwsArgumentError);
  });

  testWidgets('单条超时不会饿死低频查询，也不会并发', (tester) async {
    final requests = <LvbuReadCommand>[];
    var active = 0;
    var maxActive = 0;
    final poller = LvbuReadOnlyPoller(
      now: tester.binding.clock.now,
      request: (command) async {
        requests.add(command);
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(seconds: 3));
        active--;
        return null;
      },
      onReply: (_) {},
      onFailure: (_, __) {},
    );
    poller.start();
    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    poller.stop();
    await tester.pump(const Duration(seconds: 4));
    expect(maxActive, 1);
    expect(requests.toSet(), containsAll(LvbuReadCommand.values));
  });

  testWidgets('设置占用蓝牙时暂停轮询，不误记失败且恢复后立即查询', (tester) async {
    var ready = false;
    var failures = 0;
    final requests = <LvbuReadCommand>[];
    final poller = LvbuReadOnlyPoller(
      canRequest: () => ready,
      request: (command) async {
        requests.add(command);
        return LvbuReadReply(command: command, status: 1, value: 38.5);
      },
      onReply: (_) {},
      onFailure: (_, __) => failures++,
    );
    poller.start();
    await tester.pump(const Duration(seconds: 5));
    expect(requests, isEmpty);
    expect(failures, 0);
    ready = true;
    await tester.pump(const Duration(seconds: 1));
    expect(requests, [LvbuReadCommand.voltage]);
    expect(failures, 0);
    poller.stop();
  });

  testWidgets('轮询串行、停止后不应用迟到回复', (tester) async {
    final requests = <LvbuReadCommand>[];
    final completions = <Completer<LvbuReadReply?>>[];
    final replies = <LvbuReadReply>[];
    final poller = LvbuReadOnlyPoller(
      request: (command) {
        requests.add(command);
        final c = Completer<LvbuReadReply?>();
        completions.add(c);
        return c.future;
      },
      onReply: replies.add,
      onFailure: (_, __) {},
    );
    poller.start();
    await tester.pump(const Duration(seconds: 3));
    expect(requests, [LvbuReadCommand.voltage]);
    completions.first.complete(const LvbuReadReply(command: LvbuReadCommand.voltage, status: 1, value: 38.5));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(requests, [LvbuReadCommand.voltage, LvbuReadCommand.speed]);
    poller.stop();
    completions.last.complete(const LvbuReadReply(command: LvbuReadCommand.speed, status: 1, value: 2));
    await tester.pump();
    expect(replies.length, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(requests.length, 2);
  });
}
