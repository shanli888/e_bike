import 'dart:async';

import '../models/battery_curve.dart';
import 'lvbu_protocol.dart';

/// 原厂源码中明确用于读取的命令白名单，不包含控制或校准。
enum LvbuReadCommand {
  voltage('C0', '', 24, Duration(seconds: 20)),
  speed('BF', '', 24, Duration(seconds: 2)),
  temperature('C1', '', 24, Duration(seconds: 30)),
  trip('B1', '', 0, Duration(seconds: 10)),
  gyro('BD', '', 26, Duration(seconds: 30)),
  climbing('C6', '030000', 26, Duration(seconds: 30));

  const LvbuReadCommand(this.code, this.suffix, this.hexLength, this.interval);
  final String code;
  final String suffix;
  final int hexLength;
  final Duration interval;
}

class LvbuReadReply {
  const LvbuReadReply(
      {required this.command,
      required this.status,
      this.value,
      this.tripDistanceKm,
      this.tripTimeSeconds,
      this.tripMaxSpeed,
      this.climbingAngle,
      this.climbingLevel});
  final LvbuReadCommand command;
  final int status;
  final double? value;
  final double? tripDistanceKm;
  final int? tripTimeSeconds;
  final double? tripMaxSpeed;
  final double? climbingAngle;
  final int? climbingLevel;
}

class LvbuReadOnly {
  const LvbuReadOnly._();

  static List<int> request(LvbuReadCommand command, String imei) {
    if (!LvbuProtocol.validImei(imei)) throw ArgumentError('无效的电机 IMEI');
    final hex = '${command.code}F$imei${command.suffix}';
    return [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16)
    ];
  }

  /// 按 36V 电池（满电 42.0V / 空电 30.0V）的曲线估算，见 [BatteryCurve]。
  ///
  /// 这是基于空载电压的估算，并非 BMS 上报的真实荷电状态；设备直接上报的
  /// 百分比优先，本函数只在读不到上报值时兜底。
  static int estimateBatteryPercent(double voltage) =>
      BatteryCurve.percentFromVoltage(voltage);
}

/// 每条请求独立组帧，隔离分片、错误设备与其他命令的迟到回复。
class LvbuReadReplyParser {
  LvbuReadReplyParser(this.command, String imei)
      : _prefix = '${command.code}F$imei' {
    if (!LvbuProtocol.validImei(imei)) throw ArgumentError('无效的电机 IMEI');
  }
  final LvbuReadCommand command;
  final String _prefix;
  String _buffer = '';

  LvbuReadReply? feed(List<int> bytes) {
    _buffer += LvbuProtocol.toHex(bytes);
    while (true) {
      final index = _buffer.indexOf(_prefix);
      if (index < 0) {
        if (_buffer.length > _prefix.length) {
          _buffer = _buffer.substring(_buffer.length - _prefix.length);
        }
        return null;
      }
      if (index > 0) _buffer = _buffer.substring(index);
      if (_buffer.length < 20) return null;
      final status = int.parse(_buffer.substring(18, 20), radix: 16);
      var length = command.hexLength;
      if (command == LvbuReadCommand.trip) {
        if (_buffer.length < 30) return null;
        final lengths = _buffer
            .substring(24, 30)
            .split('')
            .map((s) => int.parse(s, radix: 16));
        length = 30 + lengths.fold<int>(0, (sum, n) => sum + n);
        if (length.isOdd || length > 120) {
          _buffer = _buffer.substring(_prefix.length);
          continue;
        }
      }
      if (_buffer.length < length) return null;
      final frame = _buffer.substring(0, length);
      _buffer = _buffer.substring(length);
      if (status != 1) return LvbuReadReply(command: command, status: status);
      final parsed = _parse(frame, status);
      if (parsed != null) return parsed;
    }
  }

  LvbuReadReply? _parse(String frame, int status) {
    int? decimal(String s) =>
        RegExp(r'^\d+$').hasMatch(s) ? int.tryParse(s) : null;
    if (command == LvbuReadCommand.voltage ||
        command == LvbuReadCommand.speed ||
        command == LvbuReadCommand.temperature) {
      final n = decimal(frame.substring(20, 24));
      if (n == null) return null;
      var value = n / 10.0;
      if (command == LvbuReadCommand.temperature && value >= 100) {
        value = 100 - value;
      }
      return LvbuReadReply(command: command, status: status, value: value);
    }
    if (command == LvbuReadCommand.gyro) {
      var n = decimal(frame.substring(20, 26));
      if (n == null) return null;
      if (n >= 100000) n = 100000 - n;
      return LvbuReadReply(command: command, status: status, value: n / 1000.0);
    }
    if (command == LvbuReadCommand.climbing) {
      if (frame.substring(20, 22) != '03') return null;
      final angle = decimal(frame.substring(22, 24));
      final level = decimal(frame.substring(24, 26));
      if (angle == null || level == null) return null;
      return LvbuReadReply(
          command: command,
          status: status,
          climbingAngle: angle / 10.0,
          climbingLevel: level);
    }
    final maxSpeed = decimal(frame.substring(20, 24));
    if (maxSpeed == null) return null;
    final sizes = frame
        .substring(24, 30)
        .split('')
        .map((s) => int.parse(s, radix: 16))
        .toList();
    var offset = 30;
    final fields = <int>[];
    for (final size in sizes) {
      final part = frame.substring(offset, offset + size);
      final value = size == 0 ? 0 : int.tryParse(part, radix: 16);
      if (value == null) return null;
      fields.add(value);
      offset += size;
    }
    return LvbuReadReply(
        command: command,
        status: status,
        tripDistanceKm: fields[0] / 1000.0,
        tripTimeSeconds: fields[2],
        tripMaxSpeed: maxSpeed / 10.0);
  }
}

/// 可注入时钟和传输层的串行轮询器；前一条结束后才发送下一条。
class LvbuReadOnlyPoller {
  LvbuReadOnlyPoller(
      {required this.request,
      required this.onReply,
      required this.onFailure,
      bool Function()? canRequest,
      DateTime Function()? now})
      : _canRequest = canRequest ?? _alwaysReady,
        _now = now ?? DateTime.now;
  static bool _alwaysReady() => true;
  final bool Function() _canRequest;
  final Future<LvbuReadReply?> Function(LvbuReadCommand) request;
  final void Function(LvbuReadReply) onReply;
  final void Function(LvbuReadCommand, Object?) onFailure;
  final DateTime Function() _now;
  final Map<LvbuReadCommand, DateTime> _lastAttempt = {};
  Timer? _timer;
  bool _busy = false;
  int _generation = 0;

  void start() {
    stop();
    _lastAttempt.clear();
    final generation = _generation;
    unawaited(_tick(generation));
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => unawaited(_tick(generation)));
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(int generation) async {
    if (_busy || generation != _generation || !_canRequest()) return;
    final now = _now();
    final pending = LvbuReadCommand.values.where((command) {
      final last = _lastAttempt[command];
      return last == null || now.difference(last) >= command.interval;
    }).toList()
      ..sort((a, b) {
        final x = _lastAttempt[a];
        final y = _lastAttempt[b];
        if (x == null) return y == null ? a.index.compareTo(b.index) : -1;
        if (y == null) return 1;
        return x.add(a.interval).compareTo(y.add(b.interval));
      });
    for (final command in pending) {
      _busy = true;
      _lastAttempt[command] = now;
      try {
        final reply = await request(command);
        if (generation != _generation) return;
        if (reply != null && reply.status == 1) {
          onReply(reply);
        } else {
          onFailure(command, reply?.status);
        }
      } catch (e) {
        if (generation == _generation) onFailure(command, e);
      } finally {
        _busy = false;
      }
      break;
    }
  }
}
