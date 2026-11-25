/// 骑行详情页在线底图的配置与瓦片提供器。
///
/// key / SK / 自定义模板全部通过 --dart-define 注入，源码不含任何凭据。
/// 三种运行模式（优先级从高到低）：
///   1. 自定义模板：RIDE_MAP_TILE_URL 非空，直接用它（需含 {z}/{x}/{y}）；
///   2. 签名 WMTS：RIDE_MAP_TILE_KEY + RIDE_MAP_SECRET_KEY 同时非空，
///      走腾讯官方 WMTS 并对每张瓦片动态计算 sig（SN 校验模式）；
///   3. 公开瓦片：默认，使用腾讯网页端公开瓦片，无需 key，开箱即用。
library;

import 'package:flutter_map/flutter_map.dart';

import 'tencent_map_signer.dart';

class TencentMapConfig {
  static const _key = String.fromEnvironment('RIDE_MAP_TILE_KEY');
  static const _secret = String.fromEnvironment('RIDE_MAP_SECRET_KEY');
  static const _customUrl = String.fromEnvironment('RIDE_MAP_TILE_URL');

  /// 是否启用带签名的官方 WMTS 通道。
  static bool get isSigned => _key.isNotEmpty && _secret.isNotEmpty;

  /// 是否为无需 key 的公开瓦片模式。
  static bool get isPublic => _customUrl.isEmpty && !isSigned && _key.isEmpty;

  /// 传给 TileLayer 的 URL 模板占位。
  /// 签名模式下真实 URL 由 [SignedTileProvider] 按坐标动态生成，
  /// 这里给一个结构完整的模板供 TileLayer/测试读取。
  static String get tileUrl {
    if (_customUrl.isNotEmpty) return _customUrl;
    if (_key.isNotEmpty) {
      return 'https://apis.map.qq.com${TencentMapSigner.wmtsPath}'
          '?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
          '&LAYER=default&STYLE=default&FORMAT=image/png'
          '&TILEMATRIXSET=EPSG:3857'
          '&TILEMATRIX={z}&TILECOL={x}&TILEROW={y}'
          '&key=$_key';
    }
    return publicTileUrl;
  }

  /// 腾讯地图网页端公开瓦片模板（无需 key）。
  static const publicTileUrl = 'https://rt{s}.map.gtimg.com/tile'
      '?z={z}&x={x}&y={y}&type=vector&styleid=1';

  /// 瓦片子域：公开瓦片用 {s} 轮换 0~3；其它模式 URL 不含 {s}，
  /// 但 flutter_map 内部按长度取模，故给非空占位值避免除零。
  static List<String> get subdomains =>
      _customUrl.isEmpty && _key.isEmpty ? const ['0', '1', '2', '3'] : const ['a'];

  /// 版权归属文案。
  static const attribution = '© 腾讯地图';

  /// 构造瓦片提供器：签名模式用 [SignedTileProvider]，其余用标准网络提供器。
  static TileProvider buildProvider() {
    if (isSigned) {
      return SignedTileProvider(
        const TencentMapSigner(key: _key, secretKey: _secret),
      );
    }
    return NetworkTileProvider(attemptDecodeOfHttpErrorResponses: false);
  }
}

/// 带 SN 签名的瓦片提供器：按 z/x/y 动态计算 sig 并生成完整 URL。
///
/// 继承 [NetworkTileProvider] 只重写 URL 生成，沿用其网络请求、缓存、
/// 取消加载与错误回调等全部能力。
class SignedTileProvider extends NetworkTileProvider {
  SignedTileProvider(this.signer)
      : super(attemptDecodeOfHttpErrorResponses: false);

  final TencentMapSigner signer;

  @override
  String getTileUrl(coordinates, options) =>
      signer.tileUrl(coordinates.z, coordinates.x, coordinates.y);
}
