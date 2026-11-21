/// 骑行数据模型
class BikeData {
  /// 当前速度 (km/h)
  double speed;
  bool speedAvailable;

  /// 平均速度 (km/h)
  double avgSpeed;

  /// 最大速度 (km/h)
  double maxSpeed;

  /// 陀螺仪角度（度）；并不一定等同于当前路面坡度。
  double slope;

  /// 助力等级 (0-5, 0=无助力)
  int assistLevel;

  /// 助力功率 (W)
  int assistPower;

  /// 总里程 (km)
  double totalDistance;

  /// 手机根据蓝牙实时速度计算的本次骑行里程 (km)。
  double tripDistance;
  bool tripAvailable;
  /// 设备只读行程查询返回的里程 (km)，供设置页查看。
  double? deviceTripDistance;
  Duration? _lastSpeedSample;
  double _movingHours = 0;
  bool totalDistanceAvailable;
  bool gyroAngleAvailable;
  bool temperatureAvailable;
  bool batteryLevelEstimated;
  double? climbingAngle;
  int? climbingLevel;

  /// 电池电量 (0-100%)；是否已经实际读到或估算另见 [batteryLevelAvailable]。
  int batteryLevel;

  /// 区分未知电量与真实的 0%。
  bool batteryLevelAvailable;

  /// 电池电压 (V)，0 表示设备尚未上报
  double voltage;

  /// 温度 (°C)
  double temperature;

  /// 电机温度 (°C)
  double motorTemperature;

  /// 控制器温度 (°C)
  double controllerTemperature;

  /// 设备信号强度 (dBm)
  int rssi;

  /// 电机功率 (W)
  int motorPower;

  /// 骑行时间 (秒)
  int rideTime;

  /// 胎压 (PSI, 如果有传感器)
  double tirePressure;

  BikeData({
    this.speed = 0,
    this.speedAvailable = false,
    this.avgSpeed = 0,
    this.maxSpeed = 0,
    this.slope = 0,
    this.assistLevel = 0,
    this.assistPower = 0,
    this.totalDistance = 0,
    this.tripDistance = 0,
    this.tripAvailable = false,
    this.deviceTripDistance,
    this.totalDistanceAvailable = false,
    this.gyroAngleAvailable = false,
    this.temperatureAvailable = false,
    this.batteryLevelEstimated = false,
    this.climbingAngle,
    this.climbingLevel,
    this.batteryLevel = 0,
    this.batteryLevelAvailable = false,
    this.voltage = 0,
    this.temperature = 0,
    this.motorTemperature = 0,
    this.controllerTemperature = 0,
    this.rssi = -100,
    this.motorPower = 0,
    this.rideTime = 0,
    this.tirePressure = 0,
  });

  /// 从设备原始数据帧解析
  factory BikeData.fromRawData(Map<String, dynamic> data) {
    return BikeData(
      speed: (data['speed'] ?? 0).toDouble(),
      speedAvailable: data['speedAvailable'] as bool? ?? false,
      avgSpeed: (data['avgSpeed'] ?? 0).toDouble(),
      maxSpeed: (data['maxSpeed'] ?? 0).toDouble(),
      slope: (data['slope'] ?? 0).toDouble(),
      assistLevel: (data['assistLevel'] ?? 0) as int,
      assistPower: (data['assistPower'] ?? 0) as int,
      totalDistance: (data['totalDistance'] ?? 0).toDouble(),
      tripDistance: (data['tripDistance'] ?? 0).toDouble(),
      tripAvailable: data['tripAvailable'] as bool? ?? false,
      deviceTripDistance: (data['deviceTripDistance'] as num?)?.toDouble(),
      totalDistanceAvailable: data['totalDistanceAvailable'] as bool? ?? false,
      gyroAngleAvailable: data['gyroAngleAvailable'] as bool? ?? false,
      temperatureAvailable: data['temperatureAvailable'] as bool? ?? false,
      batteryLevelEstimated: data['batteryLevelEstimated'] as bool? ?? false,
      climbingAngle: (data['climbingAngle'] as num?)?.toDouble(),
      climbingLevel: data['climbingLevel'] as int?,
      batteryLevel: (data['batteryLevel'] ?? 0) as int,
      batteryLevelAvailable: data['batteryLevelAvailable'] as bool? ?? false,
      voltage: (data['voltage'] ?? 0).toDouble(),
      temperature: (data['temperature'] ?? 0).toDouble(),
      motorTemperature: (data['motorTemperature'] ?? 0).toDouble(),
      controllerTemperature: (data['controllerTemperature'] ?? 0).toDouble(),
      rssi: (data['rssi'] ?? -100) as int,
      motorPower: (data['motorPower'] ?? 0) as int,
      rideTime: (data['rideTime'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'speed': speed,
    'speedAvailable': speedAvailable,
    'avgSpeed': avgSpeed,
    'maxSpeed': maxSpeed,
    'slope': slope,
    'assistLevel': assistLevel,
    'assistPower': assistPower,
    'totalDistance': totalDistance,
    'tripDistance': tripDistance,
    'tripAvailable': tripAvailable,
    'deviceTripDistance': deviceTripDistance,
    'totalDistanceAvailable': totalDistanceAvailable,
    'gyroAngleAvailable': gyroAngleAvailable,
    'temperatureAvailable': temperatureAvailable,
    'batteryLevelEstimated': batteryLevelEstimated,
    'climbingAngle': climbingAngle,
    'climbingLevel': climbingLevel,
    'batteryLevel': batteryLevel,
    'batteryLevelAvailable': batteryLevelAvailable,
    'voltage': voltage,
    'temperature': temperature,
    'motorTemperature': motorTemperature,
    'controllerTemperature': controllerTemperature,
    'rssi': rssi,
    'motorPower': motorPower,
    'rideTime': rideTime,
  };

  /// 仅在收到新的速度样本时更新行程，忽略断流期间的距离。
  void recordBluetoothSpeed(double kmh, Duration timestamp,
      {Duration? measurementInterval}) {
    if (!kmh.isFinite || kmh < 0) return;
    final previous = _lastSpeedSample;
    final interval = measurementInterval ??
        (previous == null ? Duration.zero : timestamp - previous);
    final intervalSpeed = measurementInterval == null ? (speed + kmh) / 2 : kmh;
    if (interval > Duration.zero &&
        interval < const Duration(seconds: 10) &&
        intervalSpeed > 0) {
      final hours = interval.inMicroseconds / Duration.microsecondsPerHour;
      _movingHours += hours;
      tripDistance += intervalSpeed * hours;
      avgSpeed = tripDistance / _movingHours;
    }
    _lastSpeedSample = timestamp;
    speed = kmh;
    speedAvailable = true;
    tripAvailable = true;
    if (kmh > maxSpeed) maxSpeed = kmh;
  }

  /// 清除 BLE 数据有效标记，避免重连后显示上一台设备的值。
  void clearReadOnlyAvailability() {
    voltage = 0;
    batteryLevelAvailable = false;
    batteryLevelEstimated = false;
    speedAvailable = false;
    _lastSpeedSample = null;
    _movingHours = 0;
    avgSpeed = 0;
    maxSpeed = 0;
    tripDistance = 0;
    tripAvailable = false;
    deviceTripDistance = null;
    totalDistanceAvailable = false;
    temperatureAvailable = false;
    gyroAngleAvailable = false;
    climbingAngle = null;
    climbingLevel = null;
  }
}
