import 'package:bike_computer/services/tencent_map_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TencentMapSigner.sign SN 签名算法', () {
    test('与腾讯官方逆地址解析示例的结果一致', () {
      // 官方文档示例：
      // path = /ws/geocoder/v1
      // params（排序后）= key=...&location=28.7033487,115.8660847
      // SK = SWvT26ypwq5Nwb5RvS8cLi6NSoH8HlJX
      // 期望 sig = 90da272bfa19122547298e2b0bcc0e50
      const signer = TencentMapSigner(
        key: '5Q5BZ-5EVWJ-SN5F3-K6QBZ-B3FAO-RVBWM',
        secretKey: 'SWvT26ypwq5Nwb5RvS8cLi6NSoH8HlJX',
      );
      const path = '/ws/geocoder/v1';
      final params = <String, String>{
        'location': '28.7033487,115.8660847',
        'key': '5Q5BZ-5EVWJ-SN5F3-K6QBZ-B3FAO-RVBWM',
      };
      final sig = signer.sign(path, params);
      expect(sig, '90da272bfa19122547298e2b0bcc0e50');
    });

    test('签名与 SK 绑定：换 SK 结果不同', () {
      const a = TencentMapSigner(key: 'k', secretKey: 'sk-a');
      const b = TencentMapSigner(key: 'k', secretKey: 'sk-b');
      const params = <String, String>{'z': '10', 'x': '1'};
      expect(a.sign('/p', params), isNot(b.sign('/p', params)));
    });

    test('参数顺序不影响签名（内部按名排序）', () {
      const signer = TencentMapSigner(key: 'k', secretKey: 'sk');
      final p1 = <String, String>{'a': '1', 'b': '2', 'c': '3'};
      final p2 = <String, String>{'c': '3', 'a': '1', 'b': '2'};
      expect(signer.sign('/p', p1), signer.sign('/p', p2));
    });

    test('签名是 32 位小写十六进制', () {
      const signer = TencentMapSigner(key: 'k', secretKey: 'sk');
      final sig = signer.sign('/p', {'a': '1'});
      expect(sig, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('TencentMapSigner.tileUrl WMTS 瓦片 URL', () {
    test('包含全部 WMTS 参数、key 与 sig，且坐标正确映射', () {
      const signer = TencentMapSigner(key: 'MYKEY', secretKey: 'MYSECRET');
      final url = signer.tileUrl(12, 3371, 1624);
      final uri = Uri.parse(url);
      expect(uri.host, 'apis.map.qq.com');
      expect(uri.path, '/maptile/base/wmts');
      expect(uri.queryParameters['SERVICE'], 'WMTS');
      expect(uri.queryParameters['REQUEST'], 'GetTile');
      expect(uri.queryParameters['TILEMATRIX'], '12');
      expect(uri.queryParameters['TILECOL'], '3371');
      expect(uri.queryParameters['TILEROW'], '1624');
      expect(uri.queryParameters['TILEMATRIXSET'], 'EPSG:3857');
      expect(uri.queryParameters['key'], 'MYKEY');
      expect(uri.queryParameters['sig'], isNotNull);
      expect(uri.queryParameters['sig'], matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('相同 key/SK/坐标得到稳定 URL（便于瓦片缓存）', () {
      const signer = TencentMapSigner(key: 'MYKEY', secretKey: 'MYSECRET');
      expect(signer.tileUrl(10, 843, 388), signer.tileUrl(10, 843, 388));
    });

    test('不同坐标得到不同 sig', () {
      const signer = TencentMapSigner(key: 'MYKEY', secretKey: 'MYSECRET');
      expect(signer.tileUrl(10, 843, 388), isNot(signer.tileUrl(10, 844, 388)));
    });
  });
}
