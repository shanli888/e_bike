import 'package:bike_computer/models/assist_mode.dart';
import 'package:bike_computer/services/ble_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BleCommands 帧格式', () {
    test('帧头、长度、命令字', () {
      final frame = BleCommands.assistLevel(3);
      expect(frame[0], 0xAA);
      expect(frame[1], 0x55);
      expect(frame[2], 2); // cmd + 1 字节数据
      expect(frame[3], BleCommands.cmdAssistLevel);
      expect(frame[4], 3);
      expect(frame.length, 6); // 2 头 + len + cmd + data + 校验
    });

    test('校验和是前面所有字节求和的低 8 位取反', () {
      final frame = BleCommands.assistLevel(3);
      var sum = 0;
      for (final b in frame.sublist(0, frame.length - 1)) {
        sum += b;
      }
      expect(frame.last, (0xFF - (sum & 0xFF)) & 0xFF);
    });

    test('助力等级被限制在 0~5', () {
      expect(BleCommands.assistLevel(9)[4], 5);
      expect(BleCommands.assistLevel(-3)[4], 0);
    });

    test('轮胎尺寸命令带轮径高低字节', () {
      final frame = BleCommands.tireSize(27.5);
      final mm = (27.5 * 25.4).round(); // 699
      expect(frame[3], BleCommands.cmdTireSize);
      expect(frame[4], 28); // round(27.5) = 28
      expect(frame[5], (mm >> 8) & 0xFF);
      expect(frame[6], mm & 0xFF);
    });

    test('停止助力 / 重启帧', () {
      expect(BleCommands.assistStop()[3], BleCommands.cmdAssistStop);
      expect(BleCommands.restart().sublist(0, 4), [0xAA, 0x55, 0x01, 0x01]);
    });

    test('README 里列出的示例帧与实际构造一致', () {
      expect(BleCommands.restart(), [0xAA, 0x55, 0x01, 0x01, 0xFE]);
      expect(BleCommands.gyroQuery(), [0xAA, 0x55, 0x01, 0x10, 0xEF]);
      expect(BleCommands.gyroCalibrate(), [0xAA, 0x55, 0x01, 0x11, 0xEE]);
      expect(BleCommands.assistLevel(3), [0xAA, 0x55, 0x02, 0x20, 0x03, 0xDB]);
      expect(BleCommands.assistMode(3), [0xAA, 0x55, 0x02, 0x21, 0x03, 0xDA]);
      expect(BleCommands.assistStop(), [0xAA, 0x55, 0x02, 0x22, 0x00, 0xDC]);
      expect(BleCommands.assistPercent(35), [0xAA, 0x55, 0x02, 0x23, 0x23, 0xB8]);
      expect(BleCommands.tireSize(27.5),
          [0xAA, 0x55, 0x04, 0x02, 0x1C, 0x02, 0xBB, 0x21]);
    });

    test('手动百分比限制在 0~100', () {
      expect(BleCommands.assistPercent(120)[4], 100);
      expect(BleCommands.assistPercent(-5)[4], 0);
    });
  });

  group('AssistMode', () {
    test('模式码可往返', () {
      for (final mode in AssistMode.values) {
        expect(AssistMode.fromCode(mode.code), mode);
      }
      expect(AssistMode.fromCode(0x99), AssistMode.commute);
    });
  });
}
