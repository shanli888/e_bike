import 'package:bike_computer/services/ride_recorder.dart';
import 'package:bike_computer/services/ride_repository.dart';
import 'package:bike_computer/widgets/recording_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 仅用于测试：可指定状态的假记录器。
class FakeRecorder extends RideRecorder {
  FakeRecorder(this._state) : super(RideRepository());
  final RideRecordState _state;

  @override
  RideRecordState get state => _state;

  @override
  bool get isIdle => _state == RideRecordState.idle;

  @override
  bool get isRecording => _state == RideRecordState.recording;

  @override
  bool get isPaused => _state == RideRecordState.paused;

  @override
  bool get isActive => _state != RideRecordState.idle;
}

Widget _wrap(RideRecorder recorder) => ChangeNotifierProvider<RideRecorder>.value(
      value: recorder,
      child: const MaterialApp(home: Scaffold(body: RecordingIndicator())),
    );

void main() {
  testWidgets('待记录时状态栏红点不占位', (tester) async {
    await tester.pumpWidget(_wrap(FakeRecorder(RideRecordState.idle)));
    expect(find.byKey(const ValueKey('recording-indicator')), findsOneWidget);
    final box = tester.widget<SizedBox>(
        find.byKey(const ValueKey('recording-indicator')));
    expect(box.width, 0);
    expect(find.text('记录中'), findsNothing);
    expect(find.text('已暂停'), findsNothing);
  });

  testWidgets('记录中/已暂停时显示脉动点与状态文字', (tester) async {
    await tester.pumpWidget(_wrap(FakeRecorder(RideRecordState.recording)));
    expect(find.text('记录中'), findsOneWidget);
    expect(find.text('已暂停'), findsNothing);

    await tester.pumpWidget(_wrap(FakeRecorder(RideRecordState.paused)));
    await tester.pump();
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('记录中'), findsNothing);
  });
}
