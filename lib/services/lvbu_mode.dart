import '../models/assist_mode.dart';
import 'lvbu_protocol.dart';

/// 原厂 LVBU 3.4.0 C4 模式设置帧；没有推测性的蓝牙模式查询命令。
class LvbuModeCommand {
  const LvbuModeCommand._();

  static List<int> set(AssistMode mode, String imei) {
    if (!LvbuProtocol.validImei(imei)) throw ArgumentError('无效的电机 IMEI');
    final hex = 'C4F$imei${mode.code.toString().padLeft(2, '0')}';
    return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }
}

class LvbuModeReply {
  const LvbuModeReply({required this.status, this.mode});
  final int status;
  final AssistMode? mode;
}

/// 匹配设备标识及完整 C4 回复；确认码 01 后仍须核对实际返回模式。
///
/// 只有 01（成功）与 02（设备明确失败）算有效回复；
/// 其它状态码（例如写入被回显的半截帧）会被跳过，继续找真正的回复。
class LvbuModeReplyParser {
  LvbuModeReplyParser(String imei) : _prefix = 'C4F$imei' {
    if (!LvbuProtocol.validImei(imei)) throw ArgumentError('无效的电机 IMEI');
  }
  final String _prefix;
  String _buffer = '';

  LvbuModeReply? feed(List<int> bytes) {
    _buffer += LvbuProtocol.toHex(bytes);
    while (true) {
      final index = _buffer.indexOf(_prefix);
      if (index < 0) {
        if (_buffer.length > _prefix.length) _buffer = _buffer.substring(_buffer.length - _prefix.length);
        return null;
      }
      if (index > 0) _buffer = _buffer.substring(index);
      if (_buffer.length < 22) return null;
      final frame = _buffer.substring(0, 22);
      final parsedStatus = int.tryParse(frame.substring(18, 20), radix: 16);
      final status = parsedStatus ?? 0;
      if (status == 1) {
        final code = int.tryParse(frame.substring(20, 22));
        final mode = code == null ? null : AssistMode.tryFromCode(code);
        if (mode == null) {
          // 未知模式码：跳过这一帧继续找真正的回复。
          _buffer = _buffer.substring(1);
          continue;
        }
        _buffer = _buffer.substring(22);
        return LvbuModeReply(status: status, mode: mode);
      }
      if (status == 2) {
        _buffer = _buffer.substring(22);
        return LvbuModeReply(status: status);
      }
      // 无效帧：跳过一个字符继续搜索，避免把回显帧当成失败回复。
      _buffer = _buffer.substring(1);
    }
  }
}

/// 原厂 A5 手动助力百分比使用两位十进制数；100 的编码尚未确认。
class LvbuAssistPercentCommand {
  const LvbuAssistPercentCommand._();

  static List<int> set(int percent, String imei) {
    if (!LvbuProtocol.validImei(imei)) throw ArgumentError('无效的电机 IMEI');
    if (percent < 0 || percent > 99) throw RangeError.range(percent, 0, 99, 'percent');
    final hex = 'A5F$imei${percent.toString().padLeft(2, '0')}';
    return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }
}

class LvbuAssistPercentReply {
  const LvbuAssistPercentReply({required this.status, this.percent});
  final int status;
  final int? percent;
}

/// A5 回复格式与 C4 一样为 22 个十六进制字符，末尾是十进制百分比。
///
/// 只有 01（成功）与 02（设备明确失败）算有效回复；
/// 其它状态码（例如写入被回显的半截帧）会被跳过，继续找真正的回复，
/// 避免把「回显帧」误判成设备拒绝。
class LvbuAssistPercentReplyParser {
  LvbuAssistPercentReplyParser(String imei) : _prefix = 'A5F$imei' {
    if (!LvbuProtocol.validImei(imei)) throw ArgumentError('无效的电机 IMEI');
  }
  final String _prefix;
  String _buffer = '';

  LvbuAssistPercentReply? feed(List<int> bytes) {
    _buffer += LvbuProtocol.toHex(bytes);
    while (true) {
      final index = _buffer.indexOf(_prefix);
      if (index < 0) {
        if (_buffer.length > _prefix.length) _buffer = _buffer.substring(_buffer.length - _prefix.length);
        return null;
      }
      if (index > 0) _buffer = _buffer.substring(index);
      if (_buffer.length < 22) return null;
      final frame = _buffer.substring(0, 22);
      final parsedStatus = int.tryParse(frame.substring(18, 20), radix: 16);
      final status = parsedStatus ?? 0;
      if (status == 1) {
        final digits = frame.substring(20, 22);
        if (!RegExp(r'^\d{2}$').hasMatch(digits)) {
          // 非十进制数值：跳过这一帧继续找（例如写入回显帧）。
          _buffer = _buffer.substring(1);
          continue;
        }
        _buffer = _buffer.substring(22);
        return LvbuAssistPercentReply(status: status, percent: int.parse(digits));
      }
      if (status == 2) {
        _buffer = _buffer.substring(22);
        return LvbuAssistPercentReply(status: status);
      }
      // 无效帧：跳过一个字符继续搜索，避免把回显帧当成失败回复。
      _buffer = _buffer.substring(1);
    }
  }
}

