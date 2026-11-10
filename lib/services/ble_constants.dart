/// LVBU/WePower 蓝牙 GATT 协议常量
///
/// 依据《蓝牙协议逆向文档》：主数据服务 FFE0 下，FFE1 负责数据通知（Notify），
/// FFE2 负责控制命令写入（Write），FFE3 上报设备状态。
class BleConstants {
  // ===== 自定义服务 UUID (主通信) =====
  static const String serviceMain = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String serviceNotify = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String serviceCommand = '0000ffe2-0000-1000-8000-00805f9b34fb';
  static const String serviceStatus = '0000ffe3-0000-1000-8000-00805f9b34fb';

  // ===== 自定义数据通道 =====
  static const String serviceData0 = '0000ff00-0000-1000-8000-00805f9b34fb';
  static const String charData0 = '0000ff01-0000-1000-8000-00805f9b34fb';

  // ===== 固件升级服务 =====
  static const String serviceDfu0 = '0000ffd0-0000-1000-8000-00805f9b34fb';
  static const String serviceDfu1 = '0000ffd1-0000-1000-8000-00805f9b34fb';
  static const String serviceDfu2 = '0000ffd2-0000-1000-8000-00805f9b34fb';
  static const String serviceDfu3 = '0000ffd3-0000-1000-8000-00805f9b34fb';

  // ===== 标准服务 =====
  static const String serviceBattery = '0000180f-0000-1000-8000-00805f9b34fb';
  static const String serviceDeviceInfo = '0000180a-0000-1000-8000-00805f9b34fb';
  static const String serviceCsc = '00001816-0000-1000-8000-00805f9b34fb';
  static const String serviceCyclingPower = '00001818-0000-1000-8000-00805f9b34fb';

  // ===== 标准 Characteristic =====
  static const String charBatteryLevel = '00002a19-0000-1000-8000-00805f9b34fb';
  static const String charCscMeasurement = '00002a5b-0000-1000-8000-00805f9b34fb';
  static const String charCyclingPowerMeasurement = '00002a63-0000-1000-8000-00805f9b34fb';
  static const String charCyclingPowerFeature = '00002abe-0000-1000-8000-00805f9b34fb';
  static const String charManufacturerName = '00002a29-0000-1000-8000-00805f9b34fb';
  static const String charHardwareRevision = '00002a27-0000-1000-8000-00805f9b34fb';
  static const String charSerialNumber = '00002a25-0000-1000-8000-00805f9b34fb';
  static const String charSoftwareRevision = '00002a28-0000-1000-8000-00805f9b34fb';
  static const String charModelNumber = '00002a24-0000-1000-8000-00805f9b34fb';
  static const String charCccConfig = '00002902-0000-1000-8000-00805f9b34fb';

  // ===== WePower / 白标私有服务 =====
  static const String serviceWePower = '3eb685db-65f9-4cf6-a03a-e3ef65729f3d';
  static const String serviceAux = 'fdd39ad0-238f-46af-adb4-6c85480369c7';

  // ===== 自定义特征 =====
  /// 数据通知（设备 → App）
  static const String charNotifyData = '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// 控制命令写入（App → 设备）
  static const String charCtrlCommand = '0000ffe2-0000-1000-8000-00805f9b34fb';

  /// 设备状态上报
  static const String charDeviceStatus = '0000ffe3-0000-1000-8000-00805f9b34fb';

  /// 兼容旧代码：FFE1 同时具备写属性时也可作为下发通道
  static const String charWriteData = charNotifyData;

  // ===== 设备名称前缀（文档中列出的白标品牌） =====
  static const List<String> deviceNamePrefixes = [
    'LVBU', 'WEPOWER', 'VIRVOLT', 'EASIFIT', 'HIGHWING', 'EGREEN',
    'VER TTIRE', 'VERTTIRE', 'GEROAD', 'DSBIKE', 'EASYCYC', 'KARAA',
    'RACER', 'ZEBRA', 'ZEUS', 'ZOOMY', 'BT-', 'EB-', 'BIKE-',
  ];

  // ===== 扫描超时 =====
  static const Duration scanTimeout = Duration(seconds: 30);
  static const Duration connectTimeout = Duration(seconds: 15);
}

/// UUID 归一化工具。
///
/// flutter_blue_plus 在不同平台/设备上，同一个 UUID 可能被规范化成
/// 短格式（`ffe1`）或长格式（`0000ffe1-0000-1000-8000-00805f9b34fb`），
/// 直接字符串比较会不相等——这正是之前 FFE1/FFE2 匹配不上的根因。
/// 统一用 [normalize] 转成小写短码后再比较。
class UuidUtil {
  const UuidUtil._();

  /// 把任意 Guid 或其字符串表示归一化为小写短码：
  /// - `0000ffe1-0000-1000-8000-00805f9b34fb` -> `ffe1`
  /// - `ffe1` / `FFE1` -> `ffe1`
  /// - 非蓝牙基础 UUID（如 3EB685DB-…）保持完整小写
  static String normalize(Object? g) {
    var s = (g?.toString() ?? '').toLowerCase();
    if (s.isEmpty) return '';
    if (RegExp(r'^[0-9a-f]{4}$').hasMatch(s)) return s;
    if (s.startsWith('0000') && s.endsWith('-0000-1000-8000-00805f9b34fb')) {
      return s.substring(4, 8);
    }
    return s;
  }
}
