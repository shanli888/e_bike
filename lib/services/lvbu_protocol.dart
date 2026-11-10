/// 基于 wang.lvbu.mobile 3.4.0 的只读查询格式，尚待设备实测。
class LvbuProtocol {
  const LvbuProtocol._();

  /// 仅在本地构建时通过 --dart-define-from-file 提供，不存入公开源码。
  /// 编译进 APK 的标识仍可被提取，不应公开分享个人构建。
  static const String motorImei = String.fromEnvironment('LVBU_MOTOR_IMEI');

  static bool validImei(String imei) => RegExp(r'^\d{15}$').hasMatch(imei);

  /// 电压查询 C0 + F + 15 位电机 IMEI，按十六进制而非 ASCII 编码。
  static List<int> voltageQuery(String imei) {
    if (!validImei(imei)) throw ArgumentError('电机 IMEI 必须为 15 位数字');
    final hex = 'C0F$imei';
    return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }

  static List<int> gyroCalibration(String imei) {
    if (!validImei(imei)) throw ArgumentError('电机 IMEI 必须为 15 位数字');
    final hex = 'BEF$imei';
    return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }

  static String toHex(List<int> bytes) => bytes
      .map((byte) => (byte & 0xff).toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

class LvbuVoltageReply {
  const LvbuVoltageReply({required this.status, this.voltage});
  final int status;
  final double? voltage;
}

/// FFE1 通知可能分片；匹配完整的 C0 + F + IMEI + 状态 + 四位数值。
class LvbuVoltageReplyParser {
  LvbuVoltageReplyParser(String imei) : _prefix = 'C0F$imei' {
    if (!LvbuProtocol.validImei(imei)) throw ArgumentError('电机 IMEI 必须为 15 位数字');
  }

  final String _prefix;
  String _buffer = '';

  LvbuVoltageReply? feed(List<int> bytes) {
    _buffer += LvbuProtocol.toHex(bytes);
    final index = _buffer.indexOf(_prefix);
    if (index < 0) {
      if (_buffer.length > _prefix.length) {
        _buffer = _buffer.substring(_buffer.length - _prefix.length);
      }
      return null;
    }
    if (_buffer.length < index + 24) {
      _buffer = _buffer.substring(index);
      return null;
    }
    final frame = _buffer.substring(index, index + 24);
    _buffer = _buffer.substring(index + 24);
    final status = int.tryParse(frame.substring(18, 20), radix: 16);
    if (status == null) return null;
    if (status != 1) return LvbuVoltageReply(status: status);
    final value = frame.substring(20, 24);
    if (!RegExp(r'^\d{4}$').hasMatch(value)) return null;
    return LvbuVoltageReply(status: status, voltage: int.parse(value) / 10.0);
  }
}
