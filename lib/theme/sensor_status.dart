import 'package:flutter/material.dart';

import 'dashboard_theme.dart';

/// 电量档位（含边界归属）：
/// >80 充足 / 50~80 正常 / 20~50 偏低 / <20 低电。
enum BatteryBand { full, normal, low, critical, unknown }

/// 温度档位：<30 正常 / 30~50 偏热 / >50 过热。
enum TemperatureBand { cool, warm, hot, unknown }

/// 首页传感器卡的分级配色规则。
///
/// 纯函数，便于单测与复用；UI 只负责把这些颜色应用到
/// 百分比、进度条、电压/温度数值与卡片描边。
class SensorStatus {
  const SensorStatus._();

  static BatteryBand batteryBand(int? percent) {
    if (percent == null) return BatteryBand.unknown;
    if (percent > 80) return BatteryBand.full;
    if (percent >= 50) return BatteryBand.normal;
    if (percent >= 20) return BatteryBand.low;
    return BatteryBand.critical;
  }

  static Color batteryColor(int? percent) => switch (batteryBand(percent)) {
        BatteryBand.full => DashColors.green,
        BatteryBand.normal => DashColors.blue,
        BatteryBand.low => DashColors.orange,
        BatteryBand.critical => DashColors.red,
        BatteryBand.unknown => DashColors.muted2,
      };

  static String batteryBandLabel(int? percent) =>
      switch (batteryBand(percent)) {
        BatteryBand.full => '电量充足',
        BatteryBand.normal => '电量正常',
        BatteryBand.low => '电量偏低',
        BatteryBand.critical => '电量过低',
        BatteryBand.unknown => '电量未知',
      };

  /// 进度条填充比例 0~1；未知电量返回 0（只显示档位底色）。
  static double batteryProgress(int? percent) =>
      percent == null ? 0 : percent.clamp(0, 100) / 100.0;

  static TemperatureBand temperatureBand(double? celsius) {
    if (celsius == null || celsius.isNaN) return TemperatureBand.unknown;
    if (celsius < 30) return TemperatureBand.cool;
    if (celsius <= 50) return TemperatureBand.warm;
    return TemperatureBand.hot;
  }

  static Color temperatureColor(double? celsius) =>
      switch (temperatureBand(celsius)) {
        TemperatureBand.cool => DashColors.green,
        TemperatureBand.warm => DashColors.yellow,
        TemperatureBand.hot => DashColors.red,
        TemperatureBand.unknown => DashColors.muted2,
      };

  static String temperatureBandLabel(double? celsius) =>
      switch (temperatureBand(celsius)) {
        TemperatureBand.cool => '正常',
        TemperatureBand.warm => '偏热',
        TemperatureBand.hot => '过热',
        TemperatureBand.unknown => '--',
      };
}
