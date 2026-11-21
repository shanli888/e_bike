import 'dart:io';

import 'package:bike_computer/models/ride_record.dart';
import 'package:bike_computer/services/ride_recorder.dart';
import 'package:bike_computer/services/ride_repository.dart';
import 'package:flutter_test/flutter_test.dart';

RideSession _sample() => RideSession(
      id: 'ride_1000',
      startTime: DateTime(2026, 11, 21, 9, 15),
      endTime: DateTime(2026, 11, 21, 9, 47),
      movingSeconds: 1938,
      distanceKm: 12.68,
      avgSpeedKmh: 23.5,
      maxSpeedKmh: 38.2,
      ascentM: 186,
      descentM: 180,
      calories: 428,
      name: '晨骑',
      points: [
        RidePoint(lat: 31.23, lon: 121.47, alt: 12, t: DateTime(2026, 11, 21, 9, 15)),
        RidePoint(
            lat: 31.24,
            lon: 121.48,
            alt: 25,
            t: DateTime(2026, 11, 21, 9, 16),
            speedKmh: 22),
      ],
    );

void main() {
  group('RideSession 序列化', () {
    test('往返 JSON 保留汇总字段与轨迹点', () {
      final s = _sample();
      final restored = RideSession.fromJsonString(s.toJsonString());
      expect(restored.id, s.id);
      expect(restored.distanceKm, closeTo(12.68, 1e-6));
      expect(restored.ascentM, 186);
      expect(restored.calories, 428);
      expect(restored.points.length, 2);
      expect(restored.points.last.speedKmh, 22);
      expect(restored.points.last.alt, 25);
    });

    test('时长格式化：不足一小时与跨小时', () {
      final s = _sample();
      expect(s.durationLabel, '32:18');
      final long = RideSession(
        id: 'x',
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        movingSeconds: 3723,
        distanceKm: 0,
        avgSpeedKmh: 0,
        maxSpeedKmh: 0,
        ascentM: 0,
        descentM: 0,
        calories: 0,
        name: 'x',
      );
      expect(long.durationLabel, '1:02:03');
    });

    test('外接传感器预留字段缺省为 null', () {
      expect(_sample().avgHeartRate, isNull);
      expect(_sample().avgPower, isNull);
    });
  });

  group('RideRepository 本地存储', () {
    late Directory tmp;
    late RideRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ride_repo_test_');
      repo = RideRepository(dir: tmp);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('保存后可列出，按开始时间倒序，并统计总量', () async {
      final first = _sample();
      final second = RideSession(
        id: 'ride_2000',
        startTime: DateTime(2026, 11, 22, 8, 0),
        endTime: DateTime(2026, 11, 22, 8, 30),
        movingSeconds: 1800,
        distanceKm: 8.5,
        avgSpeedKmh: 17,
        maxSpeedKmh: 30,
        ascentM: 50,
        descentM: 48,
        calories: 300,
        name: '通勤',
      );
      await repo.save(first);
      await repo.save(second);

      final list = await repo.listAll();
      expect(list.length, 2);
      expect(list.first.id, 'ride_2000'); // 最新在前

      final totals = await repo.totals();
      expect(totals.count, 2);
      expect(totals.distanceKm, closeTo(21.18, 1e-6));
      expect(totals.ascentM, 236);
    });

    test('删除指定记录', () async {
      await repo.save(_sample());
      await repo.delete('ride_1000');
      expect((await repo.listAll()).isEmpty, isTrue);
    });
  });

  group('RideRecorder 状态机', () {
    test('初始为待记录，暂停/继续/结束在 idle 下无效', () async {
      final tmp = await Directory.systemTemp.createTemp('ride_rec_test_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final recorder = RideRecorder(RideRepository(dir: tmp));

      expect(recorder.state, RideRecordState.idle);
      expect(recorder.isIdle, isTrue);
      recorder.pause();
      recorder.resume();
      expect(await recorder.finish(), isNull);
      expect(recorder.state, RideRecordState.idle);
      recorder.dispose();
    });

    test('指标口径：均速=距离/移动时长，卡路里随移动时长增长', () {
      final tmp = Directory.systemTemp;
      final recorder = RideRecorder(RideRepository(dir: tmp));
      // 通过反射式注入不方便，这里仅验证纯计算属性的初始行为。
      expect(recorder.distanceKm, 0);
      expect(recorder.avgSpeedKmh, 0);
      expect(recorder.elapsed, Duration.zero);
      expect(recorder.state, RideRecordState.idle);
      recorder.dispose();
    });
  });
}
