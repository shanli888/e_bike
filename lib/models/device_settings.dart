/// 设备设置模型
class DeviceSettings {
  /// 轮胎尺寸 (英寸, 支持 27.5 这类小数)
  double tireSize;

  /// 旧设备设置的轮径占位值 (mm)；CSC 使用 LocalWheelSettings 的本地轮径。
  int wheelDiameter;

  /// 速度限制 (km/h)
  int speedLimit;

  /// 超速报警 (bool)
  bool overSpeedAlarm;

  /// 陀螺仪已校准
  bool gyroCalibrated;

  /// 陀螺仪角度偏移
  double gyroAngleOffset;

  /// 载重 (kg)
  double loadWeight;

  /// 电机型号
  String motorType;

  /// 型号 (Device Info 0x2A24)
  String modelNumber;

  /// 厂商 (Device Info 0x2A29)
  String manufacturer;

  /// 固件版本
  String firmwareVersion;

  /// 硬件版本
  String hardwareVersion;

  /// 设备序列号
  String serialNumber;

  DeviceSettings({
    this.tireSize = 26,
    this.wheelDiameter = 660,
    this.speedLimit = 25,
    this.overSpeedAlarm = false,
    this.gyroCalibrated = false,
    this.gyroAngleOffset = 0,
    this.loadWeight = 75,
    this.motorType = '',
    this.modelNumber = '',
    this.manufacturer = '',
    this.firmwareVersion = '',
    this.hardwareVersion = '',
    this.serialNumber = '',
  });
}
