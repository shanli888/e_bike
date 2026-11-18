import 'ble_constants.dart';

/// 一次 A2A4 按键通知。§6.2A.1 实机对照：
/// 按下 `0x05`–`0x09`，抬起为 `+0x20`（`0x25`–`0x29`）。
class Br80KeyEvent {
  const Br80KeyEvent({
    required this.code,
    required this.name,
    required this.pressed,
    required this.known,
    required this.at,
  });

  final int code;
  final String name;
  final bool pressed;
  final bool known;
  final DateTime at;

  String get hex => '0x${code.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  String get action => known ? (pressed ? '按下' : '抬起') : '未知事件';

  String get display => known ? '$name $action' : '未知键 $hex';

  String get timeLabel => [
        at.hour,
        at.minute,
        at.second,
      ].map((v) => v.toString().padLeft(2, '0')).join(':');
}

/// BR80 直连协议，依据《BR80闪控_蓝牙协议逆向.md》§6.2A / §8，
/// 并与 H5 客户端 `lvbu-ble/js/remote.js` 的实机验证逻辑对齐。
class Br80Protocol {
  /// A2A0 数据服务。H5 用 `filters: [{ services: [A2A0] }]` 发现闪控，
  /// 因为部分 BR80 广播名不叫 BlingRemote / BR80，甚至为空。
  static const String serviceShortUuid = 'a2a0';

  /// 名称过滤：与 H5 的 namePrefix 列表保持一致
  static bool matchesName(String name) {
    final upper = name.toUpperCase();
    return upper.contains('BLINGREMOTE') ||
        upper.contains('BR80') ||
        upper.contains('LIVALL') ||
        upper.startsWith('BR');
  }

  /// 广播里的 service UUID 命中 A2A0 也算闪控（H5 的主要发现方式）
  static bool matchesService(Iterable<Object?> advertisedUuids) =>
      advertisedUuids
          .any((uuid) => UuidUtil.normalize(uuid) == serviceShortUuid);

  /// 扫描结果判定：名称或广播服务任一命中即可
  static bool matchesScan({
    required String name,
    required Iterable<Object?> advertisedUuids,
  }) =>
      matchesName(name) || matchesService(advertisedUuids);

  /// 把一帧 A2A4 通知解析成可读按键事件，供界面显示（不依赖电机连接）。
  /// 未知字节也保留为「未知事件」，方便调试时看到原始码。
  static Br80KeyEvent? parseKey(List<int> value, {DateTime? at}) {
    if (value.length != 1) return null;
    final code = value.single & 0xff;
    const names = <int, String>{
      0x05: '▼ 下键',
      0x06: '▲ 上键',
      0x07: '◀ 左键',
      0x08: '▶ 右键',
      0x09: '● 主键',
    };
    final pressed = code >= 0x05 && code <= 0x09;
    final released = code >= 0x25 && code <= 0x29;
    final base = released ? code - 0x20 : code;
    final name = names[base];
    return Br80KeyEvent(
      code: code,
      name: name ?? '未知键',
      pressed: pressed,
      known: name != null,
      at: at ?? DateTime.now(),
    );
  }

  /// 主键（home，0x09 按下）= 停止助力。只在按下时触发，抬起 0x29 忽略。
  /// 与 [assistDirection] 互斥，调用方应先判停止再判方向，避免一条帧同时
  /// 触发「调速」和「停止」两条命令。
  static bool isStopKey(List<int> value) =>
      value.length == 1 && (value.single & 0xff) == 0x09;

  /// 只有上/下按下键调整助力（0x06=上，0x05=下）。
  /// 返回方向而不是固定步进：+1 等同手动模式的「+」，-1 等同「-」。
  /// 抬起键 0x25~0x29 和其它按键忽略。
  static int? assistDirection(List<int> value) {
    if (value.length != 1) return null;
    return switch (value.single) {
      0x06 => 1,
      0x05 => -1,
      _ => null,
    };
  }

  /// 按给定步进换算成实际增量；[step] 来自设置页的「加减步进」。
  /// 保留默认 5%，便于协议层单独验证与兼容旧调用。
  static int? assistDelta(List<int> value, {int step = 5}) {
    if (value.length != 1) return null;
    final direction = assistDirection(value);
    return direction == null ? null : direction * step;
  }

  /// 标准电池服务 180F/2A19：单字节百分比
  static int? batteryLevel(List<int> value) =>
      value.length == 1 && value.single >= 0 && value.single <= 100
          ? value.single
          : null;

  /// A2A3 通知里的电量（文档 §6.2B / H5 remote.js）：
  /// 取通知十六进制串末 2 位按 16 进制解析，0x88 是「电量充足」标志。
  static int? batteryFromA2A3(List<int> value) {
    if (value.isEmpty) return null;
    final last = value.last & 0xff;
    if (last == 0x88) return 100;
    return last <= 100 ? last : null;
  }
}
