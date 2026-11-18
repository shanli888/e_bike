import 'package:bike_computer/models/command_result.dart';
import 'package:bike_computer/services/assist_step_action.dart';
import 'package:bike_computer/services/assist_step_settings.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/br80_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只实现步进链路用到的字段，避免测试触发真实蓝牙插件。
class _FakeBle extends ChangeNotifier implements BleService {
  int _percent = 51;
  final List<int> steps = [];

  @override
  int get assistPercent => _percent;

  @override
  Future<CommandResult> stepAssistPercent(int delta) async {
    steps.add(delta);
    _percent = (_percent + delta).clamp(0, 99);
    return CommandResult.ok;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('步进设置默认 5%，范围 1~50%，可持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AssistStepSettings();
    await settings.load();
    expect(settings.step, AssistStepSettings.defaultStep);

    expect(await settings.setStep(10), isTrue);
    expect(settings.step, 10);
    expect(
        (await SharedPreferences.getInstance())
            .getInt(AssistStepSettings.preferenceKey),
        10);

    expect(await settings.setStep(999), isTrue);
    expect(settings.step, AssistStepSettings.maxStep);
    expect(await settings.setStep(-3), isTrue);
    expect(settings.step, AssistStepSettings.minStep);

    final restored = AssistStepSettings();
    await restored.load();
    expect(restored.step, AssistStepSettings.minStep);

    SharedPreferences.setMockInitialValues(
        {AssistStepSettings.preferenceKey: 999});
    final invalid = AssistStepSettings();
    await invalid.load();
    expect(invalid.step, AssistStepSettings.maxStep);
  });

  test('步进目标限制在 0~99', () {
    expect(assistStepTarget(51, 1, 5), 56);
    expect(assistStepTarget(51, -1, 5), 46);
    expect(assistStepTarget(97, 1, 10), 99);
    expect(assistStepTarget(2, -1, 10), 0);
    expect(assistStepTarget(51, 1, 999), 99);
  });

  test('到边界不下发命令，返回 atLimit', () async {
    final ble = _FakeBle().._percent = 99;
    expect(await applyAssistStep(ble, 1, 5), CommandResult.atLimit);
    expect(ble.steps, isEmpty);

    ble._percent = 0;
    expect(await applyAssistStep(ble, -1, 5), CommandResult.atLimit);
    expect(ble.steps, isEmpty);
  });

  test('闪控上/下键与手动加/减按钮走同一个动作和步进', () async {
    SharedPreferences.setMockInitialValues(
        {AssistStepSettings.preferenceKey: 10});
    final settings = AssistStepSettings();
    await settings.load();
    final ble = _FakeBle();
    final results = <CommandResult>[];

    // 与 main.dart 中闪控回调一致的接法
    final remote = Br80Service(onAssistStep: (direction) async {
      results.add(await applyAssistStep(ble, direction, settings.step));
    });

    remote.handleKeyFrame([0x06]); // 上键 = 手动 +
    await Future<void>.delayed(Duration.zero);
    expect(ble.steps, [10]);
    expect(results, [CommandResult.ok]);

    remote.handleKeyFrame([0x05]); // 下键 = 手动 -
    await Future<void>.delayed(Duration.zero);
    expect(ble.steps, [10, -10]);

    // 首页手动加按钮走的是同一个函数
    expect(await applyAssistStep(ble, 1, settings.step), CommandResult.ok);
    expect(ble.steps, [10, -10, 10]);

    // 抬起键、左右键、主键都不调整助力
    for (final code in [0x25, 0x26, 0x07, 0x08, 0x09]) {
      remote.handleKeyFrame([code]);
    }
    await Future<void>.delayed(Duration.zero);
    expect(ble.steps, hasLength(3));

    // 修改步进后两条入口同时生效
    await settings.setStep(3);
    remote.handleKeyFrame([0x06]);
    await Future<void>.delayed(Duration.zero);
    expect(await applyAssistStep(ble, -1, settings.step), CommandResult.ok);
    expect(ble.steps, [10, -10, 10, 3, -3]);

    remote.dispose();
  });

  test('闪控主键走独立的停止助力回调，抬起与左右键不触发', () async {
    final directions = <int>[];
    var stops = 0;
    final remote = Br80Service(
      onAssistStep: (direction) async => directions.add(direction),
      onStopAssist: () async => stops++,
    );

    remote.handleKeyFrame(const [0x09]); // 主键按下 = 停止助力
    remote.handleKeyFrame(const [0x29]); // 主键抬起
    remote.handleKeyFrame(const [0x07]); // 左键
    remote.handleKeyFrame(const [0x08]); // 右键
    remote.handleKeyFrame(const [0x06]); // 上键仍走调速
    await Future<void>.delayed(Duration.zero);

    expect(stops, 1);
    expect(directions, [1]);
    remote.dispose();
  });

  test('闪控按键按下时触发按键事件回调，抬起与未知键不触发', () async {
    final pressed = <String>[];
    final remote = Br80Service(
      onAssistStep: (direction) async {},
      onKeyPressed: pressed.add,
    );

    remote.handleKeyFrame(const [0x06]); // ▲ 上键按下
    remote.handleKeyFrame(const [0x26]); // 抬起
    remote.handleKeyFrame(const [0x09]); // ● 主键按下
    remote.handleKeyFrame(const [0x29]); // 抬起
    remote.handleKeyFrame(const [0x05]); // ▼ 下键按下
    remote.handleKeyFrame(const [0xff]); // 未知帧
    await Future<void>.delayed(Duration.zero);

    expect(pressed, ['▲ 上键', '● 主键', '▼ 下键']);
    remote.dispose();
  });
}
