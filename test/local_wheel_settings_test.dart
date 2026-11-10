import 'dart:math' as math;

import 'package:bike_computer/services/local_wheel_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('本地轮径默认值和周长换算', () async {
    final wheel = LocalWheelSettings();
    await wheel.load();
    expect(wheel.loaded, isTrue);
    expect(wheel.diameterMm, 660);
    expect(wheel.circumferenceMeters, closeTo(0.66 * math.pi, 1e-10));
    expect(LocalWheelSettings.diameterFromInches(27.5), 699);
    expect(() => LocalWheelSettings.diameterFromInches(double.nan), throwsArgumentError);
    expect(() => LocalWheelSettings.diameterFromInches(0), throwsArgumentError);
    wheel.dispose();
  });

  test('选择轮径后持久化，重新读取可恢复', () async {
    final first = LocalWheelSettings();
    await first.load();
    expect(await first.setDiameterMm(699), isTrue);
    expect(first.diameterMm, 699);
    final second = LocalWheelSettings();
    await second.load();
    expect(second.diameterMm, 699);
    expect(second.circumferenceMeters, closeTo(0.699 * math.pi, 1e-10));
    first.dispose();
    second.dispose();
  });

  test('非法或损坏设置不会覆盖有效值', () async {
    SharedPreferences.setMockInitialValues({'local_csc_wheel_diameter_mm': 5000});
    final wheel = LocalWheelSettings();
    await wheel.load();
    expect(wheel.diameterMm, 660);
    expect(await wheel.setDiameterMm(100), isFalse);
    expect(await wheel.setDiameterMm(1001), isFalse);
    expect(wheel.diameterMm, 660);
    wheel.dispose();
  });
}
