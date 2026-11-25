import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bike_computer/services/tencent_static_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('并发加载只请求一次，重新创建缓存实例仍可离线读取', () async {
    final directory = await Directory.systemTemp.createTemp('ride_map_test');
    addTearDown(() => directory.delete(recursive: true));
    final uri = Uri.https('apis.map.qq.com', '/ws/staticmap/v2/', {
      'center': '22.3,114.2',
      'key': 'test',
    });
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC',
    );
    var downloads = 0;
    final cache = TencentStaticMapCache(
      cacheDirectory: () async => directory,
      download: (_) async {
        downloads++;
        return png;
      },
    );
    expect(await Future.wait([cache.load(uri), cache.load(uri)]), [png, png]);
    expect(downloads, 1);

    final offlineCache = TencentStaticMapCache(
      cacheDirectory: () async => directory,
      download: (_) async => throw StateError('Unexpected network request'),
    );
    expect(await offlineCache.load(uri), png);
  });

  test('无效响应不会写入缓存，下一次仍可尝试下载', () async {
    final directory = await Directory.systemTemp.createTemp('ride_map_test');
    addTearDown(() => directory.delete(recursive: true));
    final uri = Uri.https('apis.map.qq.com', '/ws/staticmap/v2/');
    var downloads = 0;
    final cache = TencentStaticMapCache(
      cacheDirectory: () async => directory,
      download: (_) async {
        downloads++;
        return Uint8List.fromList(utf8.encode('{"status": 1}'));
      },
    );

    await expectLater(cache.load(uri), throwsException);
    await expectLater(cache.load(uri), throwsException);
    expect(downloads, 2);
    expect(await directory.list().toList(), isEmpty);
  });
}
