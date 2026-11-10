import 'package:bike_computer/models/bike_data.dart';
import 'package:bike_computer/models/command_result.dart';
import 'package:bike_computer/models/device_settings.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BikeData', () {
    test('默认值', () {
      final data = BikeData();
      expect(data.speed, 0);
      expect(data.assistLevel, 0);
      expect(data.batteryLevel, 0);
      expect(data.batteryLevelAvailable, isFalse);
      expect(data.voltage, 0);
      expect(data.rssi, -100);
    });

    test('toJson / fromRawData 往返', () {
      final data = BikeData(
        speed: 23.5,
        batteryLevel: 74,
        batteryLevelAvailable: true,
        voltage: 48.2,
        assistLevel: 3,
        motorPower: 210,
        totalDistance: 12.4,
      );

      final copy = BikeData.fromRawData(data.toJson());

      expect(copy.speed, 23.5);
      expect(copy.batteryLevel, 74);
      expect(copy.batteryLevelAvailable, isTrue);
      expect(copy.voltage, 48.2);
      expect(copy.assistLevel, 3);
      expect(copy.motorPower, 210);
      expect(copy.totalDistance, 12.4);
    });

    test('断连清除只读数据有效性，保留数值但不再显示旧数据', () {
      final data = BikeData(speed: 12, speedAvailable: true, voltage: 38.5,
          batteryLevelAvailable: true, batteryLevelEstimated: true,
          tripAvailable: true, totalDistanceAvailable: true,
          temperatureAvailable: true, gyroAngleAvailable: true,
          climbingAngle: 1.2, climbingLevel: 3);
      data.clearReadOnlyAvailability();
      expect(data.voltage, 0);
      expect(data.speedAvailable, isFalse);
      expect(data.tripAvailable, isFalse);
      expect(data.totalDistanceAvailable, isFalse);
      expect(data.temperatureAvailable, isFalse);
      expect(data.gyroAngleAvailable, isFalse);
      expect(data.batteryLevelAvailable, isFalse);
      expect(data.climbingAngle, isNull);
      expect(data.climbingLevel, isNull);
    });

    test('fromRawData 缺失字段时使用默认值', () {
      final data = BikeData.fromRawData(<String, dynamic>{});
      expect(data.speed, 0);
      expect(data.rssi, -100);
    });
  });

  test('未连接时模式和百分比不会被当作设备已确认状态', () {
    final ble = BleService();
    expect(ble.assistModeConfirmed, isFalse);
    expect(ble.assistModeStatus, contains('未知'));
  });

  group('DeviceSettings', () {
    test('默认值', () {
      final settings = DeviceSettings();
      expect(settings.tireSize, 26);
      expect(settings.wheelDiameter, 660);
      expect(settings.speedLimit, 25);
      expect(settings.gyroCalibrated, isFalse);
    });

    test('支持小数胎宽', () {
      final settings = DeviceSettings(tireSize: 27.5);
      expect(settings.tireSize, 27.5);
    });
  });

  group('CommandResult', () {
    test('只有确认和未回包算「已发出」', () {
      expect(CommandResult.ok.isSent, isTrue);
      expect(CommandResult.noResponse.isSent, isTrue);
      expect(CommandResult.writeFailed.isSent, isFalse);
      expect(CommandResult.busy.isSent, isFalse);
      expect(CommandResult.modeUncertain.isSent, isFalse);
      expect(CommandResult.notStationary.isSent, isFalse);
      expect(CommandResult.notConnected.isSent, isFalse);
      expect(CommandResult.bluetoothOff.isSent, isFalse);
      expect(CommandResult.deviceError.isSent, isFalse);
    });

    test('需要弹窗的只有硬性错误', () {
      expect(CommandResult.writeFailed.isError, isTrue);
      expect(CommandResult.busy.isError, isTrue);
      expect(CommandResult.modeUncertain.isError, isTrue);
      expect(CommandResult.notStationary.isError, isTrue);
      expect(CommandResult.notConnected.isError, isTrue);
      expect(CommandResult.bluetoothOff.isError, isTrue);
      expect(CommandResult.noResponse.isError, isFalse);
      expect(CommandResult.deviceError.isError, isFalse);
      expect(CommandResult.ok.isError, isFalse);
    });

    test('每种结果都有标题和说明', () {
      for (final result in CommandResult.values) {
        expect(result.title, isNotEmpty);
        expect(result.message, isNotEmpty);
      }
    });
  });
}
