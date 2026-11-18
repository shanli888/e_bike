import 'package:bike_computer/theme/dashboard_theme.dart';
import 'package:bike_computer/theme/sensor_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('电量分级配色', () {
    test('>80 绿 / 50~80 蓝 / 20~50 橙 / <20 红', () {
      expect(SensorStatus.batteryBand(100), BatteryBand.full);
      expect(SensorStatus.batteryColor(100), DashColors.green);
      expect(SensorStatus.batteryBand(81), BatteryBand.full);
      expect(SensorStatus.batteryColor(81), DashColors.green);

      expect(SensorStatus.batteryBand(80), BatteryBand.normal);
      expect(SensorStatus.batteryColor(80), DashColors.blue);
      expect(SensorStatus.batteryBand(50), BatteryBand.normal);
      expect(SensorStatus.batteryColor(50), DashColors.blue);

      expect(SensorStatus.batteryBand(49), BatteryBand.low);
      expect(SensorStatus.batteryColor(49), DashColors.orange);
      expect(SensorStatus.batteryBand(20), BatteryBand.low);
      expect(SensorStatus.batteryColor(20), DashColors.orange);

      expect(SensorStatus.batteryBand(19), BatteryBand.critical);
      expect(SensorStatus.batteryColor(19), DashColors.red);
      expect(SensorStatus.batteryColor(0), DashColors.red);
    });

    test('边界归属与标签：80/50 为蓝，20 为橙，19 为红', () {
      expect(SensorStatus.batteryBandLabel(80), '电量正常');
      expect(SensorStatus.batteryBandLabel(50), '电量正常');
      expect(SensorStatus.batteryBandLabel(20), '电量偏低');
      expect(SensorStatus.batteryBandLabel(19), '电量过低');
      expect(SensorStatus.batteryBandLabel(81), '电量充足');
    });

    test('未知电量用中性色，进度为 0', () {
      expect(SensorStatus.batteryBand(null), BatteryBand.unknown);
      expect(SensorStatus.batteryColor(null), DashColors.muted2);
      expect(SensorStatus.batteryBandLabel(null), '电量未知');
      expect(SensorStatus.batteryProgress(null), 0);
    });

    test('进度比例按百分比换算并夹在 0~1', () {
      expect(SensorStatus.batteryProgress(78), 0.78);
      expect(SensorStatus.batteryProgress(100), 1.0);
      expect(SensorStatus.batteryProgress(0), 0.0);
      expect(SensorStatus.batteryProgress(-5), 0.0);
      expect(SensorStatus.batteryProgress(130), 1.0);
    });
  });

  group('温度分级配色', () {
    test('<30 绿 / 30~50 黄 / >50 红', () {
      expect(SensorStatus.temperatureBand(-5), TemperatureBand.cool);
      expect(SensorStatus.temperatureColor(-5), DashColors.green);
      expect(SensorStatus.temperatureColor(29.9), DashColors.green);

      expect(SensorStatus.temperatureBand(30), TemperatureBand.warm);
      expect(SensorStatus.temperatureColor(30), DashColors.yellow);
      expect(SensorStatus.temperatureColor(50), DashColors.yellow);

      expect(SensorStatus.temperatureBand(50.1), TemperatureBand.hot);
      expect(SensorStatus.temperatureColor(50.1), DashColors.red);
      expect(SensorStatus.temperatureColor(80), DashColors.red);
    });

    test('标签与未知值', () {
      expect(SensorStatus.temperatureBandLabel(26.5), '正常');
      expect(SensorStatus.temperatureBandLabel(32.4), '偏热');
      expect(SensorStatus.temperatureBandLabel(55), '过热');
      expect(SensorStatus.temperatureBand(null), TemperatureBand.unknown);
      expect(SensorStatus.temperatureBand(double.nan), TemperatureBand.unknown);
      expect(SensorStatus.temperatureColor(null), DashColors.muted2);
      expect(SensorStatus.temperatureBandLabel(null), '--');
    });
  });
}
