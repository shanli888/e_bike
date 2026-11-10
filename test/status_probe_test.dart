import 'package:bike_computer/services/status_probe.dart';
import 'package:bike_computer/services/wepower_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('旧版固件查询帧长度和大端 CRC 与独立计算结果一致', () {
    expect(StatusProbe.legacyInquiry([0xbb]), [0x7e, 0x04, 0x0c, 0xbb, 0x8f, 0x1d]);
    expect(() => StatusProbe.legacyInquiry([]), throwsArgumentError);
    expect(() => StatusProbe.legacyInquiry([256]), throwsArgumentError);
  });

  test('候选只包含四种原厂读取查询', () {
    final queries = StatusProbe.queries();
    expect(queries.length, 4);
    expect(queries.take(2).every((q) => q.frame[0] == 0x7e && q.frame[2] == 0x0c), isTrue);
    expect(queries.skip(2).every((q) => q.frame[0] == 0x7f), isTrue);
  });

  test('JSON 分片回复必须 CRC 正确且包含本次查询键的非空数据', () {
    final query = StatusProbe.queries()[2];
    final matcher = StatusResponseMatcher(query);
    expect(matcher.feed(WePowerProtocol.setCommand('7', 1)), isNull);
    expect(matcher.feed(WePowerProtocol.inquireCommand(['34'])), isNull);
    final bad = WePowerProtocol.setCommand('34', 12);
    bad[bad.length - 1] ^= 1;
    expect(matcher.feed(bad), isNull);
    final good = WePowerProtocol.setCommand('34', 12);
    expect(matcher.feed(good.sublist(0, 7)), isNull);
    expect(matcher.feed(good.sublist(7)), '{"34":12}');
  });

  test('旧版回复需完整、CRC 正确、状态成功且包含查询键', () {
    final matcher = StatusResponseMatcher(StatusProbe.queries()[0]);
    List<int> reply(int status, int key) {
      final body = [7, 0x0c, status, key, 1, 42];
      final crc = WePowerProtocol.crc16(body);
      return [0x7e, ...body, crc >> 8, crc & 0xff];
    }

    final bad = reply(1, 0xbb);
    bad[bad.length - 1] ^= 1;
    expect(matcher.feed(bad), isNull);
    expect(matcher.feed(reply(0, 0xbb)), isNull);
    expect(matcher.feed(reply(1, 0xc4)), isNull);
    final good = reply(1, 0xbb);
    expect(matcher.feed(good.sublist(0, 3)), isNull);
    expect(matcher.feed(good.sublist(3)), '{"BB":"2A"}');
  });
}
