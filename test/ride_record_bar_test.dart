import 'package:bike_computer/services/ride_recorder.dart';
import 'package:bike_computer/services/ride_repository.dart';
import 'package:bike_computer/theme/dashboard_theme.dart';
import 'package:bike_computer/widgets/ride_record_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeRecorder extends RideRecorder {
  _FakeRecorder({
    this.recording = true,
    this.slope,
    this.ascent = 12,
  }) : super(RideRepository());

  final bool recording;
  final double? slope;
  final double ascent;

  @override
  RideRecordState get state =>
      recording ? RideRecordState.recording : RideRecordState.paused;

  @override
  bool get isRecording => recording;

  @override
  bool get isPaused => !recording;

  @override
  double? get slopePercent => slope;

  @override
  double get ascentM => ascent;

  @override
  double get calories => 42;
}

Widget _wrap(RideRecorder recorder, {VoidCallback? onFinish}) =>
    ChangeNotifierProvider<RideRecorder>.value(
      value: recorder,
      child: MaterialApp(
        home: Scaffold(
          body: RideRecordBar(
            scale: 1,
            onStart: () {},
            onFinish: onFinish ?? () {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('记录卡片精简：无距离/均速/暂停继续按钮，保留坡度/爬升/千卡与结束',
      (tester) async {
    await tester.pumpWidget(_wrap(_FakeRecorder(slope: 6.5)));

    // 已移除
    expect(find.text('距离'), findsNothing);
    expect(find.text('均速'), findsNothing);
    expect(find.text('暂停'), findsNothing);
    expect(find.text('继续'), findsNothing);
    // 状态栏已有骑行时间，卡片不再显示时钟
    expect(find.text('00:00:00'), findsNothing);
    // 无红点（Pulsing dot 已移到状态栏）
    expect(find.byKey(const ValueKey('recording-indicator')), findsNothing);

    // 保留
    expect(find.text('记录中'), findsOneWidget);
    expect(find.text('坡度'), findsOneWidget);
    expect(find.text('+6.5'), findsOneWidget);
    expect(find.text('爬升'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('千卡'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('滑动结束骑行'), findsOneWidget);
  });

  testWidgets('坡度上坡红、下坡绿、平路蓝、无数据灰', (tester) async {
    Color slopeColor(double? slope) {
      final text = tester.widget<Text>(find.byKey(const ValueKey('record-slope')));
      return text.style!.color!;
    }

    await tester.pumpWidget(_wrap(_FakeRecorder(slope: 6.5)));
    expect(slopeColor(6.5), DashColors.red);

    await tester.pumpWidget(_wrap(_FakeRecorder(slope: -6.5)));
    await tester.pump();
    expect(slopeColor(-6.5), DashColors.green);

    await tester.pumpWidget(_wrap(_FakeRecorder(slope: 0)));
    await tester.pump();
    expect(slopeColor(0), DashColors.blue);

    await tester.pumpWidget(_wrap(_FakeRecorder(slope: null)));
    await tester.pump();
    expect(slopeColor(null), DashColors.muted2);
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('滑动到终点才触发结束回调', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
        _wrap(_FakeRecorder(recording: true, ascent: 20), onFinish: () => finished++));

    final thumb = find.byKey(const ValueKey('slide-thumb'));
    final thumbRect = tester.getRect(thumb);
    final start = thumbRect.center;

    // 只拖一小段后松手：不应触发（回弹）。
    await tester.dragFrom(start, const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(finished, 0);

    // 拖到最右（超过轨道宽度的大部分）后松手：触发结束。
    final trackRect = tester.getRect(find.byKey(const ValueKey('slide-track')));
    await tester.dragFrom(thumbRect.center, Offset(trackRect.width, 0));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('待记录态历史入口醒目且可点击', (tester) async {
    var opened = 0;
    // idle 态由 recorder.state 决定，用专门的 idle 假 recorder 验证历史入口。
    final idle = _IdleRecorder();
    await tester.pumpWidget(ChangeNotifierProvider<RideRecorder>.value(
      value: idle,
      child: MaterialApp(
        home: Scaffold(
          body: RideRecordBar(
            scale: 1,
            onStart: () {},
            onFinish: () {},
            onViewHistory: () => opened++,
          ),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('history-entry')), findsOneWidget);
    expect(find.text('骑行历史'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-entry')));
    await tester.pump();
    expect(opened, 1);
  });
}

/// 待记录态的假 recorder。
class _IdleRecorder extends RideRecorder {
  _IdleRecorder() : super(RideRepository());

  @override
  RideRecordState get state => RideRecordState.idle;
}
