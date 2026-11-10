import 'package:bike_computer/models/assist_mode.dart';
import 'package:bike_computer/services/lvbu_mode.dart';
import 'package:bike_computer/services/lvbu_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imei = '123456789012345';
  List<int> bytes(String hex) => [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

  test('原厂 C4 模式映射和帧编码', () {
    expect(AssistMode.manual.code, 1);
    expect(AssistMode.leisure.code, 2);
    expect(AssistMode.exercise.code, 3);
    expect(AssistMode.commute.code, 4);
    expect(AssistMode.climbing.code, 5);
    expect(AssistMode.tryFromCode(99), isNull);
    for (final mode in AssistMode.values) {
      expect(LvbuProtocol.toHex(LvbuModeCommand.set(mode, imei)),
          'C4F$imei${mode.code.toString().padLeft(2, '0')}');
    }
    expect(() => LvbuModeCommand.set(AssistMode.manual, '123'), throwsArgumentError);
  });

  test('A5 百分比采用两位十进制编码并限制范围', () {
    for (final value in [0, 9, 10, 51, 99]) {
      expect(LvbuProtocol.toHex(LvbuAssistPercentCommand.set(value, imei)),
          'A5F$imei${value.toString().padLeft(2, '0')}');
    }
    expect(() => LvbuAssistPercentCommand.set(-1, imei), throwsRangeError);
    expect(() => LvbuAssistPercentCommand.set(100, imei), throwsRangeError);
    expect(() => LvbuAssistPercentCommand.set(51, '123'), throwsArgumentError);
  });

  test('A5 回包验证设备、分片、状态和百分比', () {
    final parser = LvbuAssistPercentReplyParser(imei);
    expect(parser.feed(bytes('A5F9999999999999990151')), isNull);
    final frame = bytes('A5F${imei}0151');
    expect(parser.feed(frame.sublist(0, 5)), isNull);
    final result = parser.feed(frame.sublist(5));
    expect(result?.status, 1);
    expect(result?.percent, 51);
    expect(parser.feed(bytes('A5F${imei}0251'))?.status, 2);
    expect(parser.feed(bytes('A5F${imei}01FF')), isNull);
    expect(parser.feed(bytes('A5F${imei}0199'))?.percent, 99);
  });

  test('C4 回包必须包含正确设备、完整状态和已知模式', () {
    final parser = LvbuModeReplyParser(imei);
    expect(parser.feed(bytes('C4F9999999999999990104')), isNull);
    final frame = bytes('C4F${imei}0104');
    expect(parser.feed(frame.sublist(0, 4)), isNull);
    final result = parser.feed(frame.sublist(4));
    expect(result?.status, 1);
    expect(result?.mode, AssistMode.commute);
    final rejected = parser.feed(bytes('C4F${imei}0204'));
    expect(rejected?.status, 2);
    expect(rejected?.mode, isNull);
    expect(parser.feed(bytes('C4F${imei}0199')), isNull);
    expect(parser.feed(bytes('C4F${imei}0101'))?.mode, AssistMode.manual);
  });
}
