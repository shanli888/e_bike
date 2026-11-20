import 'package:bike_computer/models/battery_curve.dart';
import 'package:bike_computer/models/demo_ride_data.dart';
import 'package:bike_computer/services/lvbu_read_only.dart';
import 'package:bike_computer/theme/dashboard_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('36V 电池参数：30V 空电、42V 满电，曲线严格单调', () {
    expect(BatteryCurve.emptyVoltage, 30.0);
    expect(BatteryCurve.fullVoltage, 42.0);
    for (var i = 1; i < BatteryCurve.points.length; i++) {
      expect(BatteryCurve.points[i].$1,
          greaterThan(BatteryCurve.points[i - 1].$1));
      expect(BatteryCurve.points[i].$2,
          greaterThan(BatteryCurve.points[i - 1].$2));
    }
    expect(BatteryCurve.percentFromVoltage(30), 0);
    expect(BatteryCurve.percentFromVoltage(42), 100);
  });

  test('电压到电量：平台区线性插值，越界钳位，非法值抛错', () {
    expect(BatteryCurve.percentFromVoltage(24), 0);
    expect(BatteryCurve.percentFromVoltage(43), 100);
    expect(BatteryCurve.percentFromVoltage(33), 10);
    expect(BatteryCurve.percentFromVoltage(37), 50);
    expect(BatteryCurve.percentFromVoltage(38.5), 65);
    expect(BatteryCurve.percentFromVoltage(40), 80);
    expect(BatteryCurve.percentFromVoltage(41), 90);
    expect(BatteryCurve.percentFromVoltage(41.5), 95);
    expect(
        () => BatteryCurve.percentFromVoltage(double.nan), throwsArgumentError);
    expect(() => BatteryCurve.percentFromVoltage(double.infinity),
        throwsArgumentError);
  });

  test('电量到电压：与电压到电量双向自洽', () {
    expect(BatteryCurve.voltageFromPercent(0), 30.0);
    expect(BatteryCurve.voltageFromPercent(50), 37.0);
    expect(BatteryCurve.voltageFromPercent(100), 42.0);
    expect(BatteryCurve.voltageFromPercent(-10), 30.0);
    expect(BatteryCurve.voltageFromPercent(120), 42.0);
    for (var percent = 0; percent <= 100; percent++) {
      final voltage = BatteryCurve.voltageFromPercent(percent);
      expect(BatteryCurve.percentFromVoltage(voltage), closeTo(percent, 1),
          reason: '$percent% 反推电压 $voltage V 后应回到同一百分比');
    }
  });

  test('真实估算与演示电压共用同一条曲线', () {
    expect(LvbuReadOnly.estimateBatteryPercent(42), 100);
    expect(LvbuReadOnly.estimateBatteryPercent(37), 50);
    expect(DemoRideData.minVoltage, BatteryCurve.emptyVoltage);
    expect(DemoRideData.maxVoltage, BatteryCurve.fullVoltage);

    final t = DateTime(2026, 11, 15, 10);
    for (var sec = 0; sec < DemoRideData.sensorCycleSeconds; sec++) {
      final now = t.add(Duration(seconds: sec));
      final percent = DemoRideData.batteryAt(now);
      expect(DemoRideData.voltageAt(now),
          closeTo(BatteryCurve.voltageFromPercent(percent), 1e-9));
      // 电压反算回百分比，与卡片上显示的百分比一致。
      expect(BatteryCurve.percentFromVoltage(DemoRideData.voltageAt(now)),
          closeTo(percent, 1));
    }
  });

  test('Critical telemetry uses muted coral', () {
    expect(DashColors.red, const Color(0xFFE58D80));
  });
}
