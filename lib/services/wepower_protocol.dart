import 'dart:convert';

/// WePower JSON 帧协议候选实现（由原 App 的 libapp.so 汇编还原，见
/// docs/协议_帧格式_已确认.md）。
///
/// ```
/// 7F | len_lo | len_hi | JSON(ASCII) | crc_lo | crc_hi
/// ```
///
/// - `len` 为 JSON 字节数（小端）
/// - `crc` 为 CRC16/XMODEM（多项式 0x1021，初值 0），覆盖 7F、len 和 JSON，小端
/// - JSON 外壳：`{"M":1,"S":0,"F":<1设置|2查询>,"D":{...}}`
///
/// ⚠️ 帧结构来自汇编，尚未用真机抓包验证。
class WePowerProtocol {
  const WePowerProtocol._();

  static const int head = 0x7F;
  static const int maxLength = 512;

  static const int funcSet = 1;
  static const int funcInquire = 2;

  /// CRC16/XMODEM
  static int crc16(List<int> data) {
    var crc = 0;
    for (final b in data) {
      crc ^= (b & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc;
  }

  /// 按 ATT MTU 拆分载荷；每次写入最多为 MTU - 3 字节。
  static List<List<int>> splitForMtu(List<int> data, int mtu) {
    if (mtu < 23 || mtu > 517) {
      throw RangeError.range(mtu, 23, 517, 'mtu');
    }
    final size = mtu - 3;
    return [
      for (var offset = 0; offset < data.length; offset += size)
        data.sublist(offset, (offset + size).clamp(0, data.length)),
    ];
  }

  /// 把 JSON 对象封装成一帧
  static List<int> encode(Map<String, dynamic> json) {
    final body = ascii.encode(jsonEncode(json));
    final head3 = [head, body.length & 0xFF, (body.length >> 8) & 0xFF];
    final payload = [...head3, ...body];
    final crc = crc16(payload);
    return [...payload, crc & 0xFF, (crc >> 8) & 0xFF];
  }

  static Map<String, dynamic> _envelope(int func, Map<String, dynamic> d) =>
      {'M': 1, 'S': 0, 'F': func, 'D': d};

  /// 设置命令：`D = {key: value}`
  static List<int> setCommand(String key, Object? value) =>
      encode(_envelope(funcSet, {key: value}));

  /// 查询命令：`D = {key1: null, key2: null, ...}`
  static List<int> inquireCommand(List<String> keys) =>
      encode(_envelope(funcInquire, {for (final k in keys) k: null}));

  /// 文本控制命令：`@内容#`，如 `@NAME?#`、`@SRESET#`
  static List<int> controlCommand(String text) => ascii.encode('@$text#');
}

/// 回包解析结果
class WePowerFrame {
  const WePowerFrame(this.json);
  final Map<String, dynamic> json;
  @override
  String toString() => 'WePowerFrame($json)';
}

/// 流式解析器：BLE 通知可能分片，需缓存后按帧切分。
/// 逻辑对应原 App 的 `CommandJsonUtils.parsingBackCommand`。
class WePowerFrameParser {
  final List<int> _buf = [];

  /// 解析出的文本回包（以 `@` 开头），原样交给调用方
  final List<String> textReplies = [];

  /// 喂入一段通知数据，返回本次解析出的完整帧
  List<WePowerFrame> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <WePowerFrame>[];
    while (_buf.isNotEmpty) {
      if (_buf.first == 0x40) {
        // '@' 文本回包，直到 '#'
        final end = _buf.indexOf(0x23);
        if (end < 0) break;
        textReplies.add(ascii.decode(_buf.sublist(0, end + 1),
            allowInvalid: true));
        _buf.removeRange(0, end + 1);
        continue;
      }
      if (_buf.first != WePowerProtocol.head) {
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length <= 3) break;
      final len = _buf[1] | (_buf[2] << 8);
      if (len > WePowerProtocol.maxLength) {
        _buf.removeAt(0);
        continue;
      }
      final total = len + 5;
      if (_buf.length < total) break;
      final crcCalc = WePowerProtocol.crc16(_buf.sublist(0, len + 3));
      final crcRecv = _buf[len + 3] | (_buf[len + 4] << 8);
      if (crcCalc != crcRecv) {
        // CRC 错：丢掉这个帧头，找下一个 7F 继续
        _buf.removeAt(0);
        continue;
      }
      final text = ascii.decode(_buf.sublist(3, len + 3), allowInvalid: true);
      _buf.removeRange(0, total);
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) out.add(WePowerFrame(decoded));
      } catch (_) {
        // 非法 JSON：忽略
      }
    }
    return out;
  }

  void clear() {
    _buf.clear();
    textReplies.clear();
  }
}
