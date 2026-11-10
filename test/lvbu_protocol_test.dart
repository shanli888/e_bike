import 'package:bike_computer/services/lvbu_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('陀螺仪校准使用原厂 BE 帧', () {
    expect(LvbuProtocol.toHex(LvbuProtocol.gyroCalibration('123456789012345')), 'BEF123456789012345');
    expect(() => LvbuProtocol.gyroCalibration('invalid'), throwsArgumentError);
  });
  const imei = '123456789012345'; // 测试用虚构号码
  test('电机标识可生成查询并匹配回复', () {
    final query = LvbuProtocol.voltageQuery(imei);
    expect(LvbuProtocol.toHex(query), 'C0F$imei');
    final parser = LvbuVoltageReplyParser(imei);
    final reply = parser.feed([...query, 0x01, 0x03, 0x85]);
    expect(reply?.status, 1);
    expect(reply?.voltage, 38.5);
  });

  test('原厂 C0 请求按十六进制编码，IMEI 位于命令内', () {
    expect(LvbuProtocol.voltageQuery(imei),
        [0xc0, 0xf1, 0x23, 0x45, 0x67, 0x89, 0x01, 0x23, 0x45]);
    expect(() => LvbuProtocol.voltageQuery('123'), throwsArgumentError);
    expect(() => LvbuProtocol.voltageQuery('12345678901234A'), throwsArgumentError);
  });

  test('分片回包按原厂规则匹配设备和十进制电压', () {
    final parser = LvbuVoltageReplyParser(imei);
    final frame = [0xc0, 0xf1, 0x23, 0x45, 0x67, 0x89, 0x01, 0x23, 0x45, 0x01, 0x04, 0x82];
    expect(parser.feed(frame.sublist(0, 5)), isNull);
    final reply = parser.feed(frame.sublist(5));
    expect(reply?.status, 1);
    expect(reply?.voltage, 48.2);
  });

  test('原厂日志脱敏 C0 样本可解析为 38.5 V', () {
    // 标识替换为虚构值，尾部保留实机日志中的状态和电压。
    final parser = LvbuVoltageReplyParser(imei);
    final reply = parser.feed([0xc0, 0xf1, 0x23, 0x45, 0x67, 0x89, 0x01, 0x23, 0x45, 0x01, 0x03, 0x85]);
    expect(reply?.status, 1);
    expect(reply?.voltage, 38.5);
  });

  test('错误设备或非法数值不能被当成有效电压', () {
    final parser = LvbuVoltageReplyParser(imei);
    expect(parser.feed([0xc0, 0xf9, 0x23, 0x45, 0x67, 0x89, 0x01, 0x23, 0x45, 1, 4, 0x82]), isNull);
    expect(parser.feed([0xc0, 0xf1, 0x23, 0x45, 0x67, 0x89, 0x01, 0x23, 0x45, 1, 0x0a, 0x82]), isNull);
    final reply = parser.feed([0xc0, 0xf1, 0x23, 0x45, 0x67, 0x89, 0x01, 0x23, 0x45, 2, 0, 0]);
    expect(reply?.status, 2);
    expect(reply?.voltage, isNull);
  });
}
