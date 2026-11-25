import 'dart:math' as math;

import 'package:bike_computer/services/coordinate_transform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wgs84ToGcj02 坐标基准转换', () {
    test('国内坐标产生符合预期的 GCJ-02 偏移', () {
      // 以eviltransform的标准样例为参照：北京 WGS-84 大致偏移 +0.0016 纬度、
      // +0.0065 经度。这里用宽松区间校验方向与量级，避免与实现细节强耦合。
      final c = wgs84ToGcj02(39.9042, 116.4074);
      expect(c.lat, greaterThan(39.9042));
      expect(c.lat, lessThan(39.9070));
      expect(c.lon, greaterThan(116.4074));
      expect(c.lon, lessThan(116.4150));
    });

    test('转换量级在数百米，能把轨迹与国内底图对齐', () {
      const lat = 31.2304;
      const lon = 121.4737; // 上海
      final c = wgs84ToGcj02(lat, lon);
      final dLatM = (c.lat - lat) * 111320;
      final dLonM = (c.lon - lon) * 111320 * math.cos(lat * math.pi / 180);
      final offsetM = math.sqrt(dLatM * dLatM + dLonM * dLonM);
      expect(offsetM, greaterThan(50), reason: '国内坐标必须有约数百米偏移');
      expect(offsetM, lessThan(1000), reason: '偏移不应超过约 1 公里');
    });

    test('境外坐标原样返回，不做偏移', () {
      final tokyo = wgs84ToGcj02(35.6895, 139.6917);
      expect(tokyo.lat, 35.6895);
      expect(tokyo.lon, 139.6917);

      final ny = wgs84ToGcj02(40.7128, -74.0060);
      expect(ny.lat, 40.7128);
      expect(ny.lon, -74.0060);
    });

    test('边界外纬度同样原样返回', () {
      final c = wgs84ToGcj02(0.5, 116.0); // 低于中国纬度下界
      expect(c.lat, 0.5);
      expect(c.lon, 116.0);
    });

    test('GcjPoint 可打印，便于调试', () {
      expect(wgs84ToGcj02(35.6895, 139.6917).toString(), contains('GcjPoint'));
    });
  });
}
