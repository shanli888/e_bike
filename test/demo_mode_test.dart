import 'dart:math' as math;

import 'package:bike_computer/models/battery_curve.dart';
import 'package:bike_computer/models/demo_ride_data.dart';
import 'package:bike_computer/services/demo_mode_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认关闭，任何连接状态下都不激活演示', () {
    final settings = DemoModeSettings();
    expect(settings.enabled, DemoModeSettings.defaultEnabled);
    expect(settings.isActive(false), isFalse);
    expect(settings.isActive(true), isFalse);
    settings.dispose();
  });

  test('开启后只在未连接时激活，且写入本机并可读回', () async {
    final settings = DemoModeSettings();
    await settings.load();
    var notifications = 0;
    settings.addListener(() => notifications++);

    expect(await settings.setEnabled(true), isTrue);
    expect(notifications, 1);
    expect(settings.enabled, isTrue);
    expect(settings.isActive(false), isTrue);
    expect(settings.isActive(true), isFalse);
    expect(
        (await SharedPreferences.getInstance())
            .getBool(DemoModeSettings.preferenceKey),
        isTrue);

    final restored = DemoModeSettings();
    await restored.load();
    expect(restored.enabled, isTrue);
    expect(restored.isActive(false), isTrue);

    settings.dispose();
    restored.dispose();
  });

  test('重复设置同一值不重复通知，关闭后恢复真实数据', () async {
    final settings = DemoModeSettings();
    await settings.load();
    var notifications = 0;
    settings.addListener(() => notifications++);

    expect(await settings.setEnabled(true), isTrue);
    expect(await settings.setEnabled(true), isTrue);
    expect(notifications, 1);

    expect(await settings.setEnabled(false), isTrue);
    expect(notifications, 2);
    expect(settings.isActive(false), isFalse);
    expect(
        (await SharedPreferences.getInstance())
            .getBool(DemoModeSettings.preferenceKey),
        isFalse);

    settings.dispose();
  });

  test('读取到已保存的开启值时直接生效', () async {
    SharedPreferences.setMockInitialValues(
        {DemoModeSettings.preferenceKey: true});
    final settings = DemoModeSettings();
    await settings.load();
    expect(settings.enabled, isTrue);
    expect(settings.isActive(false), isTrue);
    settings.dispose();
  });

  test('演示数据生成独立 BikeData，各分区都有值且不写回真实服务', () {
    final t = DateTime(2026, 11, 15, 10);
    final data = DemoRideData.bikeData(t);
    final other = DemoRideData.bikeData(t);

    expect(identical(data, other), isFalse);
    expect(data.speedAvailable, isTrue);
    expect(data.speed, greaterThan(21.0));
    expect(data.speed, lessThan(27.0));
    expect(data.tripAvailable, isTrue);
    expect(data.tripDistance, DemoRideData.tripKm);
    expect(data.avgSpeed, DemoRideData.avgSpeedKmh);
    expect(data.maxSpeed, DemoRideData.maxSpeedKmh);
    expect(data.batteryLevelAvailable, isTrue);
    expect(data.batteryLevel, DemoRideData.batteryAt(t));
    expect(data.voltage, DemoRideData.voltageAt(t));
    expect(data.temperatureAvailable, isTrue);
    expect(data.controllerTemperature, DemoRideData.temperatureAt(t));
    expect(data.gyroAngleAvailable, isTrue);
    expect(data.slope, DemoRideData.slopeAt(t));

    // 主速度与电量/温度/坡度都随时间变化，便于观察刷新与档位配色。
    final later = DemoRideData.bikeData(t.add(const Duration(seconds: 2)));
    expect(later.speed, isNot(data.speed));
    expect(later.batteryLevel, isNot(data.batteryLevel));
    expect(later.voltage, isNot(data.voltage));
    expect(later.controllerTemperature, isNot(data.controllerTemperature));
    expect(later.slope, isNot(data.slope));
  });

  test('电量/电压/温度按周期循环，覆盖全部档位且首尾相接', () {
    final t0 = DateTime(2026, 11, 15, 10);
    const cycle = DemoRideData.sensorCycleSeconds;
    final cycleLater = t0.add(const Duration(seconds: cycle));
    expect(DemoRideData.batteryAt(cycleLater), DemoRideData.batteryAt(t0));
    expect(DemoRideData.voltageAt(cycleLater), DemoRideData.voltageAt(t0));
    expect(
        DemoRideData.temperatureAt(cycleLater), DemoRideData.temperatureAt(t0));

    final batteries = <int>{};
    final temps = <double>{};
    for (var sec = 0; sec < cycle; sec++) {
      final t = t0.add(Duration(seconds: sec));
      final battery = DemoRideData.batteryAt(t);
      final temp = DemoRideData.temperatureAt(t);
      final voltage = DemoRideData.voltageAt(t);
      expect(battery >= 0 && battery <= 100, isTrue, reason: '第 $sec 秒电量越界');
      expect(temp >= 20.0 && temp <= 60.0, isTrue, reason: '第 $sec 秒温度越界');
      expect(
          voltage >= DemoRideData.minVoltage &&
              voltage <= DemoRideData.maxVoltage,
          isTrue,
          reason: '第 $sec 秒电压越界（36V 电池 30~42V）');
      batteries.add(battery);
      temps.add(temp);
    }

    // 电量四档 (>80 / 50~80 / 20~50 / <20) 在一轮内都能出现。
    expect(batteries.where((v) => v > 80), isNotEmpty);
    expect(batteries.where((v) => v >= 50 && v <= 80), isNotEmpty);
    expect(batteries.where((v) => v >= 20 && v < 50), isNotEmpty);
    expect(batteries.where((v) => v < 20), isNotEmpty);
    // 温度三档 (<30 / 30~50 / >50) 在一轮内都能出现。
    expect(temps.where((v) => v < 30), isNotEmpty);
    expect(temps.where((v) => v >= 30 && v <= 50), isNotEmpty);
    expect(temps.where((v) => v > 50), isNotEmpty);
  });

  test('演示坡度在 ±25° 间循环，覆盖下坡/平路/上坡三态且首尾相接', () {
    final t0 = DateTime(2026, 11, 15, 10);
    const cycle = DemoRideData.sensorCycleSeconds;
    // 一个周期后回到同一值。
    expect(DemoRideData.slopeAt(t0.add(const Duration(seconds: cycle))),
        closeTo(DemoRideData.slopeAt(t0), 1e-9));

    final slopes = <double>[];
    for (var sec = 0; sec < cycle; sec++) {
      final slope = DemoRideData.slopeAt(t0.add(Duration(seconds: sec)));
      expect(slope.abs() <= DemoRideData.slopeAmplitude + 1e-9, isTrue,
          reason: '第 $sec 秒坡度越界');
      slopes.add(slope);
    }
    // 三角波扫过两端（受采样秒点限制，最值允许有 1 步误差）。
    expect(slopes.reduce(math.min), lessThan(-DemoRideData.slopeAmplitude + 3));
    expect(slopes.reduce(math.max), greaterThan(DemoRideData.slopeAmplitude - 3));
    // 下坡（负）、平路（0 附近）、上坡（正）在一轮内都能出现。
    expect(slopes.where((v) => v < -2.5), isNotEmpty);
    expect(slopes.where((v) => v.abs() < 2.5), isNotEmpty);
    expect(slopes.where((v) => v > 2.5), isNotEmpty);
  });

  test('电压始终与当前电量对应，温度与电量错开相位', () {
    final t0 = DateTime(2026, 11, 15, 10);
    final combos = <String>{};
    for (var sec = 0; sec < DemoRideData.sensorCycleSeconds; sec++) {
      final t = t0.add(Duration(seconds: sec));
      final battery = DemoRideData.batteryAt(t);
      expect(
        DemoRideData.voltageAt(t),
        closeTo(BatteryCurve.voltageFromPercent(battery), 1e-9),
      );
      combos.add('${battery > 80}-'
          '${DemoRideData.temperatureAt(t) > 50}');
    }
    // 相位错开，一轮里能看到高电量 / 低电量 与 高温 / 低温 的多种组合。
    expect(combos.length, greaterThan(2));
  });
}
