import 'dart:convert';

/// 一次骑行记录的数据模型（纯手机 GPS 能力，外接传感器字段预留）。
///
/// 设计取舍：
/// - 轨迹点用经纬度 + 高程 + 时间戳，坐标统一为 geolocator 返回的 WGS-84；
///   自绘网格和 OpenStreetMap 底图都直接使用该坐标，无需转为 GCJ-02。
/// - 汇总指标（距离/爬升/卡路里等）在记录结束时落盘，避免每次打开都重算整条轨迹。
/// - 心率/踏频/功率等外接字段以可选形式预留，当前恒为 null，不影响序列化兼容。
class RidePoint {
  final double lat;
  final double lon;
  final double alt;
  final DateTime t;
  final double speedKmh;
  final double accuracy;

  const RidePoint({
    required this.lat,
    required this.lon,
    required this.alt,
    required this.t,
    this.speedKmh = 0,
    this.accuracy = 0,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'alt': alt,
        't': t.millisecondsSinceEpoch,
        's': speedKmh,
        'ac': accuracy,
      };

  factory RidePoint.fromJson(Map<String, dynamic> j) => RidePoint(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        alt: (j['alt'] as num?)?.toDouble() ?? 0,
        t: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        speedKmh: (j['s'] as num?)?.toDouble() ?? 0,
        accuracy: (j['ac'] as num?)?.toDouble() ?? 0,
      );
}

/// 一次完整骑行的汇总与轨迹。
class RideSession {
  final String id;
  final DateTime startTime;
  final DateTime endTime;

  /// 移动时长（扣除暂停，秒）
  final int movingSeconds;

  /// 距离 km
  final double distanceKm;

  /// 平均 / 最高速度 km/h
  final double avgSpeedKmh;
  final double maxSpeedKmh;

  /// 累计爬升 / 下降（米，高程差分 + 阈值滤波）
  final double ascentM;
  final double descentM;

  /// 估算消耗卡路里（MET 模型）
  final int calories;

  /// 用户命名 / 自动命名
  final String name;

  /// 轨迹点（按时间有序）
  final List<RidePoint> points;

  // --- 外接传感器预留字段（本期恒 null） ---
  final double? avgHeartRate;
  final double? avgCadence;
  final double? avgPower;

  RideSession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.movingSeconds,
    required this.distanceKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.ascentM,
    required this.descentM,
    required this.calories,
    required this.name,
    List<RidePoint>? points,
    this.avgHeartRate,
    this.avgCadence,
    this.avgPower,
  }) : points = points ?? const [];

  /// 历史列表用的简短副标题
  String get durationLabel {
    final h = movingSeconds ~/ 3600;
    final m = (movingSeconds % 3600) ~/ 60;
    final s = movingSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': startTime.millisecondsSinceEpoch,
        'end': endTime.millisecondsSinceEpoch,
        'moving': movingSeconds,
        'dist': distanceKm,
        'avg': avgSpeedKmh,
        'max': maxSpeedKmh,
        'asc': ascentM,
        'desc': descentM,
        'kcal': calories,
        'name': name,
        'pts': points.map((p) => p.toJson()).toList(),
        'hr': avgHeartRate,
        'cad': avgCadence,
        'pw': avgPower,
      };

  factory RideSession.fromJson(Map<String, dynamic> j) => RideSession(
        id: j['id'] as String,
        startTime: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        endTime: DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        movingSeconds: (j['moving'] as num?)?.toInt() ?? 0,
        distanceKm: (j['dist'] as num?)?.toDouble() ?? 0,
        avgSpeedKmh: (j['avg'] as num?)?.toDouble() ?? 0,
        maxSpeedKmh: (j['max'] as num?)?.toDouble() ?? 0,
        ascentM: (j['asc'] as num?)?.toDouble() ?? 0,
        descentM: (j['desc'] as num?)?.toDouble() ?? 0,
        calories: (j['kcal'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?) ?? '骑行',
        points: (j['pts'] as List?)
                ?.map((e) => RidePoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        avgHeartRate: (j['hr'] as num?)?.toDouble(),
        avgCadence: (j['cad'] as num?)?.toDouble(),
        avgPower: (j['pw'] as num?)?.toDouble(),
      );

  /// 编码为单行 JSON（写入单个记录文件）
  String toJsonString() => jsonEncode(toJson());

  factory RideSession.fromJsonString(String s) =>
      RideSession.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
