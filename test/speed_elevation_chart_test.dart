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

    testWidgets('标题与图例保留，图例在图表上方且海拔为亮蓝色', (tester) async {
      await tester.pumpWidget(wrap(_points()));
      expect(find.text('速度与海拔'), findsOneWidget);
      expect(find.text('速度'), findsOneWidget);
      expect(find.text('海拔'), findsOneWidget); // 图例
      // 面板精简：顶部两个大数字已移除
      expect(find.text('最大速度'), findsNothing);
      expect(find.text('最高海拔'), findsNothing);
      expect(find.byKey(const ValueKey('chart-max-speed')), findsNothing);
      expect(find.byKey(const ValueKey('chart-max-altitude')), findsNothing);
      expect(find.byKey(const ValueKey('chart-painter-distance')), findsOneWidget);

      // 图例移到标题行：图例文字中心应高于图表绘制区中心。
      final legendCenter = tester.getCenter(find.text('速度')).dy;
      final chartCenter =
          tester.getCenter(find.byKey(const ValueKey('chart-painter-distance'))).dy;
      expect(legendCenter, lessThan(chartCenter), reason: '图例应在图表上方');

      // 海拔图例色块用亮蓝色，不再是灰色 muted2。
      final legendBox = tester.widget<Container>(
          find.byKey(const ValueKey('legend-swatch-海拔')));
      final legendDeco = legendBox.decoration! as BoxDecoration;
      // 色块带半透明（面积图例 alpha 0.35），只校验 RGB 与亮蓝一致。
      expect(legendDeco.color!.r, DashColors.blue.r);
      expect(legendDeco.color!.g, DashColors.blue.g);
      expect(legendDeco.color!.b, DashColors.blue.b);
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

    testWidgets('默认高度收紧、左右贴紧边框，卡片不过高', (tester) async {
      await tester.pumpWidget(wrap(_points()));
      final card = find.byKey(const ValueKey('speed-elevation-chart'));
      final cardHeight = tester.getSize(card).height;
      // 图区默认 150 + 标题/图例与内边距 ≈ 220；旧版（含大数字）约 375。
      expect(cardHeight, lessThan(250),
          reason: '速度与海拔面板应比旧版（约 375）明显更矮');

      // 图表渲染宽度应接近卡片宽度：左右 padding 仅 6（旧版 14）。
      final cardWidth = tester.getSize(card).width;
      final painterWidth =
          tester.getSize(find.byKey(const ValueKey('chart-painter-distance'))).width;
      expect(painterWidth / cardWidth, greaterThan(0.92),
          reason: '图表应贴紧卡片左右边框');
    });
  });
}
