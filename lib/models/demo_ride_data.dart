import 'dart:math' as math;

import 'battery_curve.dart';
import 'bike_data.dart';

/// 断开控制器时用于预览界面的演示数据。
///
/// 全部是纯展示值，通过 [bikeData] 生成一个临时 [BikeData]，绝不写回
/// `BleService.bikeData`，也不会触发任何 BLE 命令或 GPS 定位。
///
/// 速度、电量、电压、温度都随时间循环变化：电量扫过
/// >80 / 50~80 / 20~50 / <20 四档，温度扫过 <30 / 30~50 / >50 三档；
/// 坡度在 −25°~+25° 间匀速往返，依次呈现下坡绿、平路蓝、上坡红，
/// 便于在一屏上直接查看分级配色、进度条与双向坡度条的完整效果。
class DemoRideData {
  const DemoRideData._();

  static const String label = '演示数据';

  /// 主速度围绕 24.0 km/h 缓慢波动，方便观察七段数码管的刷新与跳变。
  static double speedAt(DateTime now) {
    final t = now.millisecondsSinceEpoch / 1000.0;
    return 24.0 + 1.8 * math.sin(t / 3.1) + 0.6 * math.sin(t / 1.3);
  }

  static const double secondarySpeedKmh = 23.4;
  static const double avgSpeedKmh = 18.6;
  static const double maxSpeedKmh = 36.8;
  static const double tripKm = 12.7;

  /// 演示坡度在 ±[slopeAmplitude] 度之间循环，覆盖下坡／平路／上坡三态。
  static const double slopeAmplitude = 25.0;

  static const int assistPercent = 45;
  static const int assistLevel = 3;
  static const String rideTime = '01:24';

  /// 传感器循环周期（秒）：一轮走完 电量 0→100→0 与 温度 20→60→20℃。
  static const int sensorCycleSeconds = 24;

  /// 演示电压与 36V 电池曲线同源：30.0 V 空电、42.0 V 满电。
  static const double minVoltage = BatteryCurve.emptyVoltage;
  static const double maxVoltage = BatteryCurve.fullVoltage;
  static const double minTemperature = 20.0;
  static const double maxTemperature = 60.0;

  /// 当前在周期内的位置 0~1，[offsetSeconds] 用于让多条曲线错开相位。
  static double _phase(DateTime now, double offsetSeconds) {
    final seconds = now.millisecondsSinceEpoch / 1000.0 + offsetSeconds;
    return (seconds % sensorCycleSeconds) / sensorCycleSeconds;
  }

  /// 0 → 1 → 0 的三角波；变化速度恒定，每个档位的停留时间正比于区间宽度。
  static double _triangle(double phase) =>
      phase < 0.5 ? phase * 2 : (1 - phase) * 2;

  /// 电量 0~100% 循环，覆盖四档配色与进度条全空 / 全满两端。
  static int batteryAt(DateTime now) =>
      (100 * _triangle(_phase(now, 0))).round();

  /// 电压由 36V 电池曲线反推（30.0~42.0 V），与百分比严格自洽：
  /// 100% → 42.0 V，50% → 37.0 V，0% → 30.0 V。
  static double voltageAt(DateTime now) =>
      BatteryCurve.voltageFromPercent(batteryAt(now));

  /// 温度 20~60℃ 循环，覆盖 <30 绿 / 30~50 黄 / >50 红 三档。
  /// 与电量错开 1/4 周期，能同时看到不同档位组合。
  static double temperatureAt(DateTime now) =>
      minTemperature +
      (maxTemperature - minTemperature) *
          _triangle(_phase(now, sensorCycleSeconds / 4));

  /// 坡度 −25°→+25°→−25° 匀速往返，与电量同周期但错开 1/2 相位。
  ///
  /// 一个循环内依次经过下坡满格绿、平路中心蓝、上坡满格红，
  /// 便于在 500ms 刷新下直接看到双向条的三种配色与填充方向。
  static double slopeAt(DateTime now) =>
      -slopeAmplitude +
      2 * slopeAmplitude * _triangle(_phase(now, sensorCycleSeconds / 2));

  /// 生成一份与真实上报结构完全一致的临时数据，让首页各分区无需分支即可渲染。
  static BikeData bikeData([DateTime? now]) {
    final t = now ?? DateTime.now();
    return BikeData(
      speed: speedAt(t),
      speedAvailable: true,
      avgSpeed: avgSpeedKmh,
      maxSpeed: maxSpeedKmh,
      tripDistance: tripKm,
      tripAvailable: true,
      batteryLevel: batteryAt(t),
      batteryLevelAvailable: true,
      voltage: voltageAt(t),
      controllerTemperature: temperatureAt(t),
      temperatureAvailable: true,
      slope: slopeAt(t),
      gyroAngleAvailable: true,
    );
  }
}
