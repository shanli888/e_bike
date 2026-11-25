import 'package:bike_computer/services/tencent_map_tiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TencentMapConfig 底图模式选择', () {
    test('URL 模板始终包含 XYZ 占位符', () {
      expect(TencentMapConfig.tileUrl, contains('{z}'));
      expect(TencentMapConfig.tileUrl, contains('{x}'));
      expect(TencentMapConfig.tileUrl, contains('{y}'));
    });

    test('默认模式使用腾讯公开瓦片、无签名 provider', () {
      // 无 dart-define 注入时为公开瓦片模式
      if (TencentMapConfig.isPublic) {
        expect(TencentMapConfig.tileUrl, contains('map.gtimg.com'));
        expect(TencentMapConfig.subdomains, ['0', '1', '2', '3']);
        expect(TencentMapConfig.buildProvider().runtimeType.toString(),
            isNot(contains('Signed')));
      }
    });

    test('版权归属为腾讯地图', () {
      expect(TencentMapConfig.attribution, '© 腾讯地图');
    });
  });
}
