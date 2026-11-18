import 'package:bike_computer/services/assist_step_settings.dart';
import 'package:bike_computer/services/demo_mode_settings.dart';
import 'package:bike_computer/services/gps_service.dart';
import 'package:bike_computer/widgets/display_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 避免触发 geolocator 插件（测试环境无平台实现）。
class _FakeGpsService extends GpsService {
  bool _compare = false;
  SpeedSource _source = SpeedSource.bluetooth;

  @override
  bool get comparisonEnabled => _compare;

  @override
  SpeedSource get source => _source;

  @override
  Future<bool> setSource(SpeedSource source) async {
    _source = source;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> setComparisonEnabled(bool enabled) async {
    _compare = enabled;
    notifyListeners();
    return true;
  }
}

void main() {
  late _FakeGpsService gps;
  late AssistStepSettings steps;
  late DemoModeSettings demo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gps = _FakeGpsService();
    steps = AssistStepSettings();
    demo = DemoModeSettings();
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<GpsService>.value(value: gps),
        ChangeNotifierProvider<AssistStepSettings>.value(value: steps),
        ChangeNotifierProvider<DemoModeSettings>.value(value: demo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(builder: (context) {
              return ElevatedButton(
                onPressed: () => showDisplaySettingsSheet(context),
                child: const Text('打开显示设置'),
              );
            }),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开显示设置'));
    await tester.pumpAndSettle();
  }

  testWidgets('面板集中展示速度来源、副速度对比与加减步进', (tester) async {
    await openSheet(tester);

    expect(find.text('显示设置'), findsOneWidget);
    expect(find.text('速度来源'), findsOneWidget);
    expect(find.text('GPS 副速度对比'), findsOneWidget);
    expect(find.text('演示数据'), findsOneWidget);
    expect(find.text('加减步进'), findsOneWidget);
    expect(find.textContaining('闪控上/下键共用此数值'), findsOneWidget);
    expect(find.byType(SegmentedButton<SpeedSource>), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(2));
    for (final preset in ['1%', '5%', '10%', '20%']) {
      expect(find.text(preset), findsOneWidget);
    }
    // 2% 档位已去掉；选中样式不显示对钩，只做高亮。
    expect(find.text('2%'), findsNothing);
    final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '10%'));
    expect(chip.showCheckmark, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换速度来源与副速度对比开关会写回服务', (tester) async {
    await openSheet(tester);
    expect(gps.source, SpeedSource.bluetooth);
    expect(gps.comparisonEnabled, isFalse);

    await tester.tap(find.text('GPS'));
    await tester.pumpAndSettle();
    expect(gps.source, SpeedSource.gps);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();
    expect(gps.comparisonEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('演示数据快捷开关写回 DemoModeSettings 并持久化', (tester) async {
    await openSheet(tester);
    expect(demo.enabled, isFalse);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(demo.enabled, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DemoModeSettings.preferenceKey), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('步进预设写入 AssistStepSettings 并持久化', (tester) async {
    await openSheet(tester);
    expect(steps.step, AssistStepSettings.defaultStep);

    await tester.tap(find.text('10%'));
    await tester.pumpAndSettle();
    expect(steps.step, 10);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(AssistStepSettings.preferenceKey), 10);
    expect(tester.takeException(), isNull);
  });
}
