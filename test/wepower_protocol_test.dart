import 'dart:convert';

import 'package:bike_computer/services/wepower_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WePowerProtocol', () {
    test('CRC16/XMODEM 标准校验值', () {
      expect(WePowerProtocol.crc16(ascii.encode('123456789')), 0x31C3);
    });

    test('帧结构：7F + 小端长度 + JSON + 小端 CRC', () {
      final f = WePowerProtocol.setCommand('7', 1);
      final json = ascii.decode(f.sublist(3, f.length - 2));
      expect(json, '{"M":1,"S":0,"F":1,"D":{"7":1}}');
      expect(f[0], 0x7F);
      expect(f[1] | (f[2] << 8), json.length);
      final crc = WePowerProtocol.crc16(f.sublist(0, f.length - 2));
      expect(f[f.length - 2], crc & 0xFF);
      expect(f[f.length - 1], crc >> 8);
    });

    test('查询命令携带多个 key', () {
      final f = WePowerProtocol.inquireCommand(['16', '17']);
      expect(ascii.decode(f.sublist(3, f.length - 2)),
          '{"M":1,"S":0,"F":2,"D":{"16":null,"17":null}}');
    });

    test('按 MTU 分片且可无损重组', () {
      final frame = WePowerProtocol.inquireCommand(['34']);
      final chunks = WePowerProtocol.splitForMtu(frame, 23);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.length <= 20), isTrue);
      expect(chunks.expand((chunk) => chunk).toList(), frame);
      expect(WePowerProtocol.splitForMtu(frame, 517), [frame]);
      expect(() => WePowerProtocol.splitForMtu(frame, 22), throwsRangeError);
    });

    test('文本控制命令', () {
      expect(ascii.decode(WePowerProtocol.controlCommand('NAME?')), '@NAME?#');
    });
  });

  group('WePowerFrameParser', () {
    test('编码后可解析回来', () {
      final p = WePowerFrameParser();
      final frames = p.feed(WePowerProtocol.setCommand('9', 30));
      expect(frames.length, 1);
      expect(frames.first.json['D'], {'9': 30});
    });

    test('分片到达也能拼成一帧', () {
      final f = WePowerProtocol.inquireCommand(['34']);
      final p = WePowerFrameParser();
      expect(p.feed(f.sublist(0, 5)), isEmpty);
      expect(p.feed(f.sublist(5, 12)), isEmpty);
      expect(p.feed(f.sublist(12)).length, 1);
    });

    test('粘包：两帧连在一起', () {
      final a = WePowerProtocol.setCommand('7', 1);
      final b = WePowerProtocol.setCommand('10', 2);
      final frames = WePowerFrameParser().feed([...a, ...b]);
      expect(frames.map((e) => e.json['D']).toList(), [
        {'7': 1},
        {'10': 2},
      ]);
    });

    test('CRC 错误的帧被丢弃，后面的好帧仍可解析', () {
      final bad = WePowerProtocol.setCommand('7', 1);
      bad[bad.length - 1] ^= 0xFF;
      final good = WePowerProtocol.setCommand('8', 3);
      final frames = WePowerFrameParser().feed([...bad, ...good]);
      expect(frames.length, 1);
      expect(frames.first.json['D'], {'8': 3});
    });

    test('开头有垃圾字节会被跳过', () {
      final good = WePowerProtocol.setCommand('7', 1);
      expect(WePowerFrameParser().feed([0x00, 0x11, ...good]).length, 1);
    });

    test('文本回包 @OK# 单独收集', () {
      final p = WePowerFrameParser();
      p.feed(ascii.encode('@OK+NAME=abc#'));
      expect(p.textReplies, ['@OK+NAME=abc#']);
    });
  });
}
