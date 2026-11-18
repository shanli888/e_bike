/// 36V（10S 锂电）电池的空载电压 ↔ 电量对照曲线。
///
/// 标称 36V、**满电 42.0V**，控制器低压保护约 30.0V。旧曲线以 24V 为 0%、
/// 41.8V 为 100%，是另一套电池的参数，套在 36V 电池上会让电量百分比失真。
///
/// 这是一条估算曲线，不是 BMS 上报的真实 SOC：33~42V 平台区近似线性
/// （每 1V ≈ 10%），30~33V 为放电末段的快速下跌区。
/// 设备直接上报的百分比优先，本曲线只在读不到上报值时兜底；演示数据也用
/// 它的逆向插值反推电压，保证首页「百分比 / 进度条 / 电压」三者自洽。
class BatteryCurve {
  const BatteryCurve._();

  static const double emptyVoltage = 30.0;
  static const double fullVoltage = 42.0;

  /// (电压 V, 电量比例 0~1)，必须按电压与比例同时升序。
  static const List<(double, double)> points = [
    (30.0, 0),
    (32.0, .05),
    (33.0, .10),
    (34.0, .20),
    (35.0, .30),
    (36.0, .40),
    (37.0, .50),
    (38.0, .60),
    (39.0, .70),
    (40.0, .80),
    (41.0, .90),
    (42.0, 1.0),
  ];

  /// 电压 → 电量百分比。段内线性插值，不再用相邻两点的平均值造成阶梯。
  static int percentFromVoltage(double voltage) {
    if (!voltage.isFinite) throw ArgumentError('无效电压');
    if (voltage <= points.first.$1) return 0;
    if (voltage >= points.last.$1) return 100;
    for (var i = 1; i < points.length; i++) {
      final (v0, p0) = points[i - 1];
      final (v1, p1) = points[i];
      if (voltage <= v1) {
        final t = (voltage - v0) / (v1 - v0);
        return ((p0 + (p1 - p0) * t) * 100).round();
      }
    }
    return 100;
  }

  /// 电量百分比 → 电压，[percentFromVoltage] 的逆向插值。
  static double voltageFromPercent(int percent) {
    final p = percent.clamp(0, 100) / 100.0;
    if (p <= points.first.$2) return points.first.$1;
    if (p >= points.last.$2) return points.last.$1;
    for (var i = 1; i < points.length; i++) {
      final (v0, p0) = points[i - 1];
      final (v1, p1) = points[i];
      if (p <= p1) {
        final t = (p - p0) / (p1 - p0);
        return v0 + (v1 - v0) * t;
      }
    }
    return points.last.$1;
  }
}
