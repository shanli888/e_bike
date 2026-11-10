import 'package:flutter/material.dart';

/// LVBU 3.4.0 原厂 App 的 C4 模式码；设置功能仍需实车验证。
enum AssistMode {
  commute('通勤', 0x04, Icons.directions_bike),
  exercise('运动', 0x03, Icons.fitness_center),
  climbing('爬坡', 0x05, Icons.terrain),
  leisure('休闲', 0x02, Icons.park),
  manual('手动', 0x01, Icons.tune);

  const AssistMode(this.label, this.code, this.icon);

  /// 中文名
  final String label;

  /// 原厂 C4 命令中的模式码。
  final int code;

  /// 图标
  final IconData icon;

  static AssistMode? tryFromCode(int code) {
    for (final mode in AssistMode.values) {
      if (mode.code == code) return mode;
    }
    return null;
  }

  static AssistMode fromCode(int code) => AssistMode.values.firstWhere(
        (m) => m.code == code,
        orElse: () => AssistMode.commute,
      );
}
