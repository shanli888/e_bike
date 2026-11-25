import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ride_record.dart';
import '../theme/dashboard_theme.dart';
import 'coordinate_transform.dart';
import 'tencent_map_signer.dart';

class TencentStaticMap {
  static const _key = String.fromEnvironment('RIDE_MAP_TILE_KEY');
  static const _secret = String.fromEnvironment('RIDE_MAP_SECRET_KEY');
  static const _path = '/ws/staticmap/v2/';
  static const attribution = '© 腾讯地图';

  static Uri forRide(List<RidePoint> points,
      {String key = _key,
      String secret = _secret,
      int width = 640,
      int height = 360}) {
    // Keep the URL bounded and retain both endpoints on long rides.
    final count = points.length > 70 ? 70 : points.length;
    final track = List.generate(count, (i) {
      final point = points[
          count == 1 ? 0 : (i * (points.length - 1) / (count - 1)).round()];
      final coordinate = wgs84ToGcj02(point.lat, point.lon);
      return '${coordinate.lat.toStringAsFixed(5)},${coordinate.lon.toStringAsFixed(5)}';
    });
    final routeColor = (DashColors.green.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    final parameters = <String, String>{
      'format': 'png',
      'key': key,
      'size': '$width*$height',
      'labels': track.first == track.last
          ? '起|${track.first}'
          : '起|${track.first}|终|${track.last}',
      if (track.length > 1)
        'path': 'color:0x$routeColor|weight:5|${track.join('|')}',
      if (track.toSet().length == 1) ...{
        'center': track.first,
        'zoom': '16',
      },
    };
    if (secret.isNotEmpty) {
      parameters['sig'] =
          TencentMapSigner(key: key, secretKey: secret).sign(_path, parameters);
    }
    return Uri.https('apis.map.qq.com', _path, parameters);
  }
}

class TencentStaticMapCache {
  TencentStaticMapCache({
    Future<Directory> Function()? cacheDirectory,
    Future<Uint8List> Function(Uri)? download,
  })  : _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory,
        _download = download ?? _downloadImage;

  static final shared = TencentStaticMapCache();

  final Future<Directory> Function() _cacheDirectory;
  final Future<Uint8List> Function(Uri) _download;
  final _pending = <String, Future<Uint8List>>{};

  Future<Uint8List> load(Uri uri) {
    final parameters = Map.of(uri.queryParameters)
      ..remove('key')
      ..remove('sig');
    final imageUri = uri.replace(queryParameters: parameters);
    final cacheKey =
        sha256.convert(utf8.encode(imageUri.toString())).toString();
    return _pending.putIfAbsent(
      cacheKey,
      () => _load(uri, cacheKey).whenComplete(() {
        _pending.remove(cacheKey);
      }),
    );
  }

  Future<Uint8List> _load(Uri uri, String cacheKey) async {
    File? file;
    try {
      final base = await _cacheDirectory();
      final separator = Platform.pathSeparator;
      file = File('${base.path}${separator}ride_maps$separator$cacheKey.png');
      final bytes = await file.readAsBytes();
      await _validateImage(bytes);
      return bytes;
    } on Exception {
      // A missing or damaged entry can be replaced by a fresh image.
    }

    final bytes = await _download(uri);
    await _validateImage(bytes);
    if (file != null) {
      try {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
      } on FileSystemException {
        // A cache write failure should not prevent displaying the image.
      }
    }
    return bytes;
  }

  static Future<void> _validateImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }

  static Future<Uint8List> _downloadImage(Uri uri) async {
    final client = HttpClient();
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Map request returned ${response.statusCode}');
        }
        return consolidateHttpClientResponseBytes(response);
      })()
          .timeout(const Duration(seconds: 12));
    } finally {
      client.close(force: true);
    }
  }
}
