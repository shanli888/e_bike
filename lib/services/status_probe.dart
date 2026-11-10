import 'dart:convert';

import 'wepower_protocol.dart';

/// 固定的实验性只读查询；没有设置、重启或助力指令。
class StatusQuery {
  const StatusQuery(this.name, this.protocol, this.keys, this.frame);

  final String name;
  final StatusProtocol protocol;
  final Set<int> keys;
  final List<int> frame;
}

enum StatusProtocol { legacy, json }

class StatusProbe {
  const StatusProbe._();

  static const legacyKeys = <int>{0xbb, 0xc4, 0xa0, 0xa5, 0xd2, 0xd3, 0xb1};
  static const jsonKeys = <int>{16, 17, 37, 38, 54, 30, 31, 39, 7, 8, 9, 10};

  /// 原厂旧版 getInquireCommand：7E + 长度 + 0C + 键 + 大端 CRC。
  static List<int> legacyInquiry(List<int> keys) {
    if (keys.isEmpty || keys.length > 252 || keys.any((k) => k < 0 || k > 255)) {
      throw ArgumentError('旧版查询键必须为 1~252 个字节');
    }
    final body = <int>[keys.length + 3, 0x0c, ...keys];
    final crc = WePowerProtocol.crc16(body);
    return [0x7e, ...body, crc >> 8, crc & 0xff];
  }

  static List<StatusQuery> queries() => [
        StatusQuery('旧版固件查询', StatusProtocol.legacy, {0xbb}, legacyInquiry([0xbb])),
        StatusQuery('旧版主页状态', StatusProtocol.legacy, legacyKeys, legacyInquiry(legacyKeys.toList())),
        StatusQuery('JSON 固件查询', StatusProtocol.json, {34}, WePowerProtocol.inquireCommand(['34'])),
        StatusQuery('JSON 主页状态', StatusProtocol.json, jsonKeys,
            WePowerProtocol.inquireCommand(jsonKeys.map((key) => '$key').toList())),
      ];
}

/// 单个通知特征、单次尝试独立使用，避免不同通道和尝试的分片混合。
class StatusResponseMatcher {
  StatusResponseMatcher(this.query);

  final StatusQuery query;
  final List<int> _legacyBuffer = [];
  final WePowerFrameParser _jsonParser = WePowerFrameParser();

  /// 返回已校验且包含查询键、非空值的候选数据；不能证明响应与本次写入严格对应。
  String? feed(List<int> chunk) {
    if (query.protocol == StatusProtocol.json) {
      for (final frame in _jsonParser.feed(chunk)) {
        final data = frame.json['D'];
        if (data is! Map) continue;
        final matching = <String, Object?>{};
        for (final key in query.keys) {
          final value = data['$key'];
          if (value != null) matching['$key'] = value;
        }
        if (matching.isNotEmpty) return jsonEncode(matching);
      }
      return null;
    }

    _legacyBuffer.addAll(chunk);
    while (_legacyBuffer.isNotEmpty) {
      if (_legacyBuffer.first != 0x7e) {
        _legacyBuffer.removeAt(0);
        continue;
      }
      if (_legacyBuffer.length < 2) break;
      // 原厂接收队列使用第二字节 + 2 计算完整帧长。
      final total = _legacyBuffer[1] + 2;
      if (total < 8 || total > 257) {
        _legacyBuffer.removeAt(0);
        continue;
      }
      if (_legacyBuffer.length < total) break;
      final frame = _legacyBuffer.sublist(0, total);
      _legacyBuffer.removeRange(0, total);
      final crc = WePowerProtocol.crc16(frame.sublist(1, total - 2));
      if (frame[total - 2] != crc >> 8 || frame[total - 1] != (crc & 0xff)) continue;
      // 原厂 getBackCommandIsSuccess 要求状态字节为 1；数据从偏移 4 开始。
      if (frame[3] != 1) continue;
      var offset = 4;
      final values = <String, String>{};
      var valid = true;
      while (offset < total - 2) {
        if (offset + 2 > total - 2) {
          valid = false;
          break;
        }
        final key = frame[offset++];
        final length = frame[offset++];
        if (offset + length > total - 2) {
          valid = false;
          break;
        }
        if (query.keys.contains(key) && length > 0) {
          values[key.toRadixString(16).toUpperCase().padLeft(2, '0')] =
              frame.sublist(offset, offset + length)
                  .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
                  .join(' ');
        }
        offset += length;
      }
      if (valid && values.isNotEmpty) return jsonEncode(values);
    }
    return null;
  }
}
