/// 腾讯位置服务 WebServiceAPI 的 SN 签名（sig）计算器。
///
/// 签名算法（官方 GET 规则，参数用未编码的原始值）：
///   1. 把除 sig 外的请求参数按参数名升序排序；
///   2. 拼成 `key1=value1&key2=value2&...`；
///   3. 计算 `md5(请求路径 + '?' + 排序参数 + SK)`，取小写十六进制；
///   4. 将得到的 sig 作为额外参数附到请求上。
///
/// 本类只负责「算 sig」和「拼 URL」，不发起任何网络请求，
/// 也不持有任何硬编码的 key / SK —— 全部由构造参数注入。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

class TencentMapSigner {
  const TencentMapSigner({
    required this.key,
    required this.secretKey,
  });

  /// 腾讯位置服务 API Key（形如 XXXXX-XXXXX-...）。
  final String key;

  /// Secret Key（SK），用于计算签名，仅存在于构建参数中。
  final String secretKey;

  /// WMTS 栅格瓦片服务的请求路径（签名时用，不含域名）。
  static const wmtsPath = '/maptile/base/wmts';

  /// 计算签名：md5(path?排序参数+SK)。
  ///
  /// [params] 为未编码的原始参数，方法内部会按参数名升序排序。
  String sign(String path, Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    final query = sortedKeys.map((k) => '$k=${params[k]}').join('&');
    final raw = '$path?$query$secretKey';
    return md5.convert(utf8.encode(raw)).toString();
  }

  /// 生成一张 WMTS 瓦片的完整带签名 URL。
  ///
  /// [z]/[x]/[y] 为 XYZ 瓦片坐标。腾讯 WMTS 使用 EPSG:3857，
  /// TILEMATRIX=z、TILECOL=x、TILEROW=y 与 XYZ 一一对应。
  String tileUrl(int z, int x, int y) {
    final params = <String, String>{
      'SERVICE': 'WMTS',
      'REQUEST': 'GetTile',
      'VERSION': '1.0.0',
      'LAYER': 'default',
      'STYLE': 'default',
      'FORMAT': 'image/png',
      'TILEMATRIXSET': 'EPSG:3857',
      'TILEMATRIX': '$z',
      'TILECOL': '$x',
      'TILEROW': '$y',
      'key': key,
    };
    final sig = sign(wmtsPath, params);
    final sortedKeys = params.keys.toList()..sort();
    final query = sortedKeys.map((k) => '$k=${params[k]}').join('&');
    return 'https://apis.map.qq.com$wmtsPath?$query&sig=$sig';
  }
}
