import 'package:bike_computer/models/ride_record.dart';
import 'package:bike_computer/theme/dashboard_theme.dart';
import 'package:bike_computer/widgets/speed_elevation_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<RidePoint> _points() {
  final base = DateTime(2026, 11, 21, 9, 0);
  return [
    RidePoint(
        lat: 31.2304,
        lon: 121.4737,
        alt: 10,
        t: base,
        speedKmh: 0),
    RidePoint(
        lat: 31.2314,
        lon: 121.4747,
        alt: 15,
        t: base.add(const Duration(minutes: 1)),
        speedKmh: 20),
    RidePoint(
        lat: 31.2324,
        lon: 121.4757,
        alt: 25,
        t: base.add(const Duration(minutes: 2)),
        speedKmh: 32),
    RidePoint(
        lat: 31.2334,
        lon: 121.4767,
        alt: 8,
        t: base.add(const Duration(minutes: 3)),
        speedKmh: 12),
  ];
}

void main() {
  group('RideChartData 纯数据', () {
    test('空轨迹返回空采样', () {
      expect(RideChartData.samples(const []), isEmpty);
      expect(RideChartData.maxAltitude(const []), 0);
      expect(RideChartData.maxSpeed(const []), 0);
    });

    test('采样保留海拔/速度并累计距离与时间', () {
      final s = RideChartData.samples(_points());
      expect(s.length, 4);
      expect(s.first.distanceKm, 0);
      expect(s.first.minutes, 0);
      expect(s.last.minutes, closeTo(3, 1e-6));
      // 每两点约 150m，累计约 0.45km（忽略滤波，验证单调递增）
      for (var i = 1; i < s.length; i++) {
        expect(s[i].distanceKm, greaterThan(s[i - 1].distanceKm));
      }
      expect(s[2].altitudeM, 25);
      expect(s[2].speedKmh, 32);
    });

    test('忽略 >200m 的跳点，不虚增累计距离', () {
      final base = DateTime(2026, 11, 21, 9, 0);
      final pts = [
        RidePoint(lat: 31.23, lon: 121.47, alt: 1, t: base),
        // 约 1km 之外的跳点
        RidePoint(
            lat: 31.24, lon: 121.47, alt: 1, t: base.add(const Duration(seconds: 1))),
      ];
      final s = RideChartData.samples(pts);
      expect(s.last.distanceKm, 0);
    });

    test('极值与海拔计算正确', () {
      expect(RideChartData.maxAltitude(_points()), 25);
      expect(RideChartData.maxSpeed(_points()), 32);
    });

    test('haversine 已知距离合理（赤道 1 度经度 ≈ 111km）', () {
      final m = RideChartData.haversineMeters(0, 0, 0, 1);
      expect(m, closeTo(111195, 200));
    });
  });

  group('SpeedElevationChart widget', () {
    Widget wrap(List<RidePoint> pts) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpeedElevationChart(points: pts, maxSpeedKmh: 35.2),
            ),
          ),
        );

    testWidgets('标题、图例、双轴大数字与极速一致', (tester) async {
      await tester.pumpWidget(wrap(_points()));
      expect(find.text('速度与海拔'), findsOneWidget);
      expect(find.text('速度'), findsOneWidget);
      expect(find.text('海拔'), findsOneWidget); // 图例
      expect(find.text('最大速度'), findsOneWidget);
      expect(find.text('最高海拔'), findsOneWidget);
      // 极速取 max(轨迹 32, 汇总 35.2)
      expect(find.byKey(const ValueKey('chart-max-speed')), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('chart-max-speed')))
              .data,
          '35.2');
      // 最高海拔 25
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('chart-max-altitude')))
              .data,
          '25');
      expect(find.byKey(const ValueKey('chart-painter-distance')), findsOneWidget);
    });

    testWidgets('距离/时间切换重建 painter', (tester) async {
      await tester.pumpWidget(wrap(_points()));
      expect(find.byKey(const ValueKey('chart-painter-distance')), findsOneWidget);
      expect(find.byKey(const ValueKey('chart-axis-distance')), findsOneWidget);
      expect(find.byKey(const ValueKey('chart-axis-time')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chart-axis-time')));
      await tester.pump();
      expect(find.byKey(const ValueKey('chart-painter-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('chart-painter-distance')), findsNothing);
    });

    testWidgets('轨迹点不足时显示降级提示，不绘制图表', (tester) async {
      await tester.pumpWidget(wrap(_points().take(1).toList()));
      expect(find.byKey(const ValueKey('chart-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('chart-painter-distance')), findsNothing);
    });

    testWidgets('图表卡片与速度色一致', (tester) async {
      await tester.pumpWidget(wrap(_points()));
      final card = tester.widget<Container>(find.byKey(const ValueKey('speed-elevation-chart')));
      final box = card.decoration! as BoxDecoration;
      expect(box.color, DashColors.card);
    });
  });
}
