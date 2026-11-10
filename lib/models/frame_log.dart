/// 一条蓝牙收发记录，用于协议调试/抓包校准
class FrameLog {
  FrameLog({
    required this.time,
    required this.outgoing,
    required this.data,
    this.source = '',
  });

  /// 记录时间
  final DateTime time;

  /// true = App 发给设备；false = 设备发来的
  final bool outgoing;

  /// 原始字节
  final List<int> data;

  /// 来源说明（特征 UUID 或命令名）
  final String source;

  /// 十六进制文本，如 `AA 55 04 02 1A 94 02 F5`
  String get hex => data
      .map((b) => (b & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0'))
      .join(' ');

  /// `15:04:05.123`
  String get timeText {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}
