import 'package:bike_computer/models/ride_record.dart';
import 'package:bike_computer/screens/ride_history_screen.dart';
import 'package:bike_computer/services/ride_repository.dart';
import 'package:bike_computer/theme/dashboard_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 纯内存仓库，避免测试里的文件 IO（那会让 pump 卡住）。
class _FakeRepo extends RideRepository {
  _FakeRepo(this.ride);

  final RideSession ride;
  bool deleted = false;

  @override
  Future<List<RideSession>> listAll() async => deleted ? [] : [ride];

  @override
  Future<({int count, double distanceKm, double ascentM})> totals() async => (
        count: deleted ? 0 : 1,
        distanceKm: deleted ? 0.0 : ride.distanceKm,
        ascentM: deleted ? 0.0 : ride.ascentM,
      );

  @override
  Future<void> delete(String id) async {
    if (id == ride.id) deleted = true;
  }
}

RideSession _ride() => RideSession(
      id: 'r1',
      startTime: DateTime(2026, 11, 21, 17, 14),
      endTime: DateTime(2026, 11, 21, 18, 14),
      movingSeconds: 1938,
      distanceKm: 12.68,
      avgSpeedKmh: 23.5,
      maxSpeedKmh: 38.2,
      ascentM: 186,
      descentM: 180,
      calories: 428,
      name: '午后骑行',
      points: [
        RidePoint(
            lat: 31.23, lon: 121.47, alt: 12, t: DateTime(2026, 11, 21, 17, 14)),
        RidePoint(
            lat: 31.24,
            lon: 121.48,
            alt: 30,
            t: DateTime(2026, 11, 21, 17, 15),
            speedKmh: 22),
      ],
    );

void main() {
  testWidgets('历史列表数值与单位使用不同字体，数字完整不截断', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RideHistoryScreen(repository: _FakeRepo(_ride())),
    ));
    await tester.pump();

    // 纯数值用 DSEG7 显示，单位用普通字体放在标签行，避免数字字体渲染字母变形。
    expect(find.text('12.68'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    // 186 同时出现在汇总条（总爬升）与列表卡片，共两处。
    expect(find.text('186'), findsNWidgets(2));
    expect(find.text('m'), findsOneWidget);
    expect(find.text('23.5'), findsOneWidget);
    // 不再有把单位混进数字字体的整串。
    expect(find.text('12.68 km'), findsNothing);
    expect(find.text('186 m'), findsNothing);

    // 数字字体与单位字体确实不同族。
    final numberStyle = tester.widget<Text>(find.text('12.68')).style!;
    final unitStyle = tester.widget<Text>(find.text('km')).style!;
    expect(numberStyle.fontFamily, DashFonts.segClassic);
    expect(unitStyle.fontFamily, isNot(DashFonts.segClassic));

    expect(tester.takeException(), isNull);
  });

  testWidgets('历史卡片四列的数值、单位、标签分别同高对齐', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RideHistoryScreen(repository: _FakeRepo(_ride())),
    ));
    await tester.pump();

    // 时长/均速没有单位，不能让它们的标签比距离/爬升高一行。
    final labels = ['距离', '时长', '均速', '爬升']
        .map((text) => tester.getCenter(find.text(text)).dy)
        .toList();
    for (final dy in labels.skip(1)) {
      expect(dy, closeTo(labels.first, 0.5), reason: '四个标签必须在同一水平线');
    }

    final values = [
      tester.getCenter(find.text('12.68')).dy,
      tester.getCenter(find.text(_ride().durationLabel)).dy,
      tester.getCenter(find.text('23.5')).dy,
      tester.getCenter(find.text('186').last).dy,
    ];
    for (final dy in values.skip(1)) {
      expect(dy, closeTo(values.first, 0.5), reason: '四个数值必须在同一水平线');
    }

    expect(tester.getCenter(find.text('km')).dy,
        closeTo(tester.getCenter(find.text('m')).dy, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史卡片保持紧凑：日期与标题同行、单位为标签后缀', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RideHistoryScreen(repository: _FakeRepo(_ride())),
    ));
    await tester.pump();

    // 日期已并入标题行，不再单独占一行；卡片整体高度控制在紧凑范围。
    final title = tester.getCenter(find.text('午后骑行'));
    final date = tester.getCenter(find.text('11/21 17:14'));
    expect(date.dy, closeTo(title.dy, 2), reason: '日期应与标题在同一行');

    final cardHeight =
        tester.getSize(find.byKey(const ValueKey('ride-card-r1'))).height;
    expect(cardHeight, lessThan(88), reason: '单张卡片不应超过 88 逻辑像素');

    // 单位仍与普通标签共用一行，不额外占用数值行的高度。
    expect(find.text('km'), findsOneWidget);
    expect(tester.getCenter(find.text('km')).dy,
        closeTo(tester.getCenter(find.text('距离')).dy, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除骑行记录：二次确认后删除并刷新为空态', (tester) async {
    final repo = _FakeRepo(_ride());
    await tester.pumpWidget(MaterialApp(
      home: RideHistoryScreen(repository: repo),
    ));
    await tester.pump();

    // 点删除按钮，弹出确认框
    await tester.tap(find.byKey(const ValueKey('delete-r1')));
    await tester.pump();
    expect(find.text('删除骑行记录'), findsOneWidget);
    expect(repo.deleted, isFalse, reason: '确认前不应删除');

    // 取消：不删除
    await tester.tap(find.byKey(const ValueKey('delete-cancel')));
    await tester.pump();
    expect(repo.deleted, isFalse);

    // 再次点删除并确认
    await tester.tap(find.byKey(const ValueKey('delete-r1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pump();
    await tester.pump();

    expect(repo.deleted, isTrue);
    expect(find.text('还没有骑行记录'), findsOneWidget, reason: '删除后刷新为空态');
    expect(find.byKey(const ValueKey('delete-r1')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
