import 'package:bike_computer/services/gps_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认不启用 GPS 对比，蓝牙主速度不会请求定位', () async {
    SharedPreferences.setMockInitialValues({});
    final gps = GpsService();
    await gps.load();
    expect(gps.source, SpeedSource.bluetooth);
    expect(gps.comparisonEnabled, isFalse);
    expect(gps.gpsRequested, isFalse);
    expect(gps.speedKmh, isNull);
    expect(await gps.retry(), isFalse);
    gps.dispose();
  });

  test('关闭对比可持久化且主来源仍为蓝牙', () async {
    SharedPreferences.setMockInitialValues({});
    final gps = GpsService();
    await gps.load();
    expect(await gps.setComparisonEnabled(false), isTrue);
    expect(gps.source, SpeedSource.bluetooth);
    expect(gps.gpsRequested, isFalse);
    gps.dispose();
  });
}
