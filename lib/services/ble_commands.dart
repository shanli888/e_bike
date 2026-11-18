/// 命令帧构造
///
/// 依据《蓝牙协议逆向文档》3.3 节推测的帧格式：
///
/// ```
/// [帧头 AA 55] [长度 len] [命令字 cmd] [数据 data...] [校验 checksum]
/// ```
///
/// - `len` = 1（命令字）+ 数据长度
/// - `checksum` = 前面所有字节求和的低 8 位取反（即 `0xFF - (sum & 0xFF)`）
///
/// ⚠️ 命令字与校验方式都是逆向推测值，**必须用真实码表抓包核对**。
/// 拿到设备实际回包后，只需要改这一个文件即可整体切换协议。
class BleCommands {
  const BleCommands._();

  static const int head0 = 0xAA;
  static const int head1 = 0x55;

  // ===== 命令字（推测） =====
  static const int cmdRestart = 0x01;
  static const int cmdTireSize = 0x02;

  static const int cmdGyroQuery = 0x10;
  static const int cmdGyroCalibrate = 0x11;

  /// 助力等级 0~5（0 = 关闭助力）
  static const int cmdAssistLevel = 0x20;

  /// 助力/骑行模式（通勤/运动/爬坡/休闲/手动）
  static const int cmdAssistMode = 0x21;

  /// 停止助力（旧 AA55 推测码，已停用；实车请用 `BleService.stopAssist()`）
  static const int cmdAssistStop = 0x22;

  /// 手动模式下的助力百分比 0~100
  static const int cmdAssistPercent = 0x23;

  /// 限速
  static const int cmdSpeedLimit = 0x30;

  /// 头灯
  static const int cmdHeadLamp = 0x31;

  /// 组装一帧命令
  static List<int> frame(int cmd, [List<int> data = const []]) {
    final length = 1 + data.length;
    final body = <int>[head0, head1, length & 0xFF, cmd & 0xFF, ...data];
    var sum = 0;
    for (final b in body) {
      sum += b & 0xFF;
    }
    final checksum = (0xFF - (sum & 0xFF)) & 0xFF;
    return [...body, checksum];
  }

  /// 重启设备
  static List<int> restart() => frame(cmdRestart);

  /// 设置轮胎尺寸：英寸 + 轮径(mm) 高低字节
  static List<int> tireSize(double inches) {
    final inchByte = inches.round() & 0xFF;
    final wheelDiameterMm = (inches * 25.4).round();
    return frame(cmdTireSize, [
      inchByte,
      (wheelDiameterMm >> 8) & 0xFF,
      wheelDiameterMm & 0xFF,
    ]);
  }

  static List<int> gyroQuery() => frame(cmdGyroQuery);

  static List<int> gyroCalibrate() => frame(cmdGyroCalibrate);

  /// 设置助力等级 0~5
  static List<int> assistLevel(int level) =>
      frame(cmdAssistLevel, [level.clamp(0, 5) & 0x07]);

  /// 设置助力模式
  static List<int> assistMode(int modeCode) =>
      frame(cmdAssistMode, [modeCode & 0xFF]);

  /// 停止助力。⚠️ 仅保留给旧协议单测，不要用于实车：
  /// 原厂 LVBU 3.4.0 的停止助力是 `A5F<IMEI>00`，见 `BleService.stopAssist()`。
  static List<int> assistStop() => frame(cmdAssistStop, [0x00]);

  /// 手动模式的助力百分比（0~100%）
  static List<int> assistPercent(int percent) =>
      frame(cmdAssistPercent, [percent.clamp(0, 100) & 0xFF]);

  /// 设置限速 (km/h)
  static List<int> speedLimit(int kmh) =>
      frame(cmdSpeedLimit, [kmh.clamp(0, 99) & 0xFF]);

  /// 头灯开关
  static List<int> headLamp(bool on) => frame(cmdHeadLamp, [on ? 0x01 : 0x00]);
}
