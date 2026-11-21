import 'package:bike_computer/models/assist_mode.dart';
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

    test('蓝牙行程按实时速度积分，设备里程独立保存', () {
      final data = BikeData(deviceTripDistance: 99);
      data.recordBluetoothSpeed(18, Duration.zero);
      data.recordBluetoothSpeed(36, const Duration(seconds: 2));
      data.recordBluetoothSpeed(0, const Duration(seconds: 4));
      data.recordBluetoothSpeed(0, const Duration(seconds: 6));
      data.recordBluetoothSpeed(25, const Duration(seconds: 30));

      expect(data.speed, 25);
      expect(data.maxSpeed, 36);
      expect(data.avgSpeed, closeTo(22.5, 0.00001));
      expect(data.tripDistance, closeTo(0.025, 0.00001));
      expect(data.deviceTripDistance, 99);
      expect(data.tripAvailable, isTrue);
      expect(BikeData.fromRawData(data.toJson()).deviceTripDistance, 99);

      data.clearReadOnlyAvailability();
      data.recordBluetoothSpeed(10, const Duration(seconds: 31));
      expect(data.avgSpeed, 0);
      expect(data.maxSpeed, 10);
      expect(data.tripDistance, 0);
      expect(data.deviceTripDistance, isNull);
    });

    test('CSC 使用轮圈事件的实际采样间隔计算里程', () {
      final data = BikeData();
      data.recordBluetoothSpeed(36, const Duration(seconds: 3),
          measurementInterval: const Duration(seconds: 2));
      expect(data.avgSpeed, closeTo(36, 0.00001));
      expect(data.tripDistance, closeTo(0.02, 0.00001));
      expect(data.deviceTripDistance, isNull);
    });
  });

  test('未连接时默认显示手动模式，但不会被当作设备已确认状态', () {
    final ble = BleService();
    expect(ble.assistMode, AssistMode.manual);
    expect(ble.assistModeConfirmed, isFalse);
    expect(ble.assistModeStatus, contains('手动'));
    expect(ble.assistModeStatus, contains('默认'));
    expect(ble.assistModeStatus, isNot(contains('已确认')));
    expect(ble.assistPercentConfirmed, isFalse);
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
      expect(CommandResult.atLimit.isSent, isFalse);
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
      expect(CommandResult.atLimit.isError, isFalse);
    });

    test('每种结果都有标题和说明', () {
      for (final result in CommandResult.values) {
        expect(result.title, isNotEmpty);
        expect(result.message, isNotEmpty);
      }
    });
  });
}
