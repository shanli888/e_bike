/// WGS-84 与 GCJ-02（火星坐标）之间的坐标转换。
///
/// 背景：手机 GPS 记录的是 WGS-84 坐标，而国内地图底图（腾讯/高德/百度）
/// 使用的是 GCJ-02 加密坐标。若把 WGS-84 轨迹直接画到腾讯底图上，
/// 整条轨迹会有约 300~600 米的系统性偏移，因此展示前必须转换。
///
/// 算法来自公开的 eviltransform 实现（WGS-84 -> GCJ-02），
/// 仅做坐标基准转换，不涉及任何地图 SDK / key / 网络请求。
library;

import 'dart:math' as math;

const double _pi = 3.1415926535897932384626;
const double _a = 6378245.0; // 克拉索夫斯基椭球长半轴
const double _ee = 0.00669342162296594323; // 椭球扁率

/// 一个 GCJ-02 坐标点（纬度、经度，单位：度）。
class GcjPoint {
  const GcjPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  String toString() => 'GcjPoint(lat: $lat, lon: $lon)';
}

/// 将 WGS-84 坐标转换为 GCJ-02。
///
/// 境外坐标（中国大陆范围之外）不做偏移，原样返回，与主流实现一致。
GcjPoint wgs84ToGcj02(double lat, double lon) {
  if (_outOfChina(lat, lon)) return GcjPoint(lat, lon);

  double dLat = _transformLat(lon - 105.0, lat - 35.0);
  double dLon = _transformLon(lon - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * _pi;
  var magic = math.sin(radLat);
  magic = 1 - _ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180.0) /
      ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi);
  dLon = (dLon * 180.0) / (_a / sqrtMagic * math.cos(radLat) * _pi);
  return GcjPoint(lat + dLat, lon + dLon);
}

/// 粗略判断是否在中国大陆范围（含台湾、海南），境外不做 GCJ-02 偏移。
bool _outOfChina(double lat, double lon) {
  if (lon < 72.004 || lon > 137.8347) return true;
  if (lat < 0.8293 || lat > 55.8271) return true;
  return false;
}

double _transformLat(double x, double y) {
  var ret = -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * _pi) +
          20.0 * math.sin(2.0 * x * _pi)) *
      2.0 /
      3.0;
  ret +=
      (20.0 * math.sin(y * _pi) + 40.0 * math.sin(y / 3.0 * _pi)) * 2.0 / 3.0;
  ret += (160.0 * math.sin(y / 12.0 * _pi) +
          320 * math.sin(y * _pi / 30.0)) *
      2.0 /
      3.0;
  return ret;
}

double _transformLon(double x, double y) {
  var ret = 300.0 +
      x +
      2.0 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * _pi) +
          20.0 * math.sin(2.0 * x * _pi)) *
      2.0 /
      3.0;
  ret +=
      (20.0 * math.sin(x * _pi) + 40.0 * math.sin(x / 3.0 * _pi)) * 2.0 / 3.0;
  ret += (150.0 * math.sin(x / 12.0 * _pi) +
          300.0 * math.sin(x / 30.0 * _pi)) *
      2.0 /
      3.0;
  return ret;
}
