import 'package:bike_computer/screens/settings_screen.dart';
import 'package:bike_computer/services/assist_step_settings.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/demo_mode_settings.dart';
import 'package:bike_computer/services/gps_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(AssistStepSettings steps,
        {BleService? ble, DemoModeSettings? demo}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: ble ?? BleService()),
        ChangeNotifierProvider<GpsService>(create: (_) => GpsService()),
        ChangeNotifierProvider<AssistStepSettings>.value(value: steps),
        ChangeNotifierProvider<DemoModeSettings>(
            create: (_) => demo ?? DemoModeSettings()),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    );

void main() {
  testWidgets('本地轮径可选择并保存，重启和校准保持禁用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ble = BleService();
    await ble.localWheel.load();
    final steps = AssistStepSettings();
    await steps.load();
    await tester.pumpWidget(_wrap(steps, ble: ble));
    await tester.scrollUntilVisible(find.text('本地 CSC 轮径'), 200);
    expect(find.textContaining('不会写入电机'), findsOneWidget);
    // 显示设置与加减步进已移到首页右上角的显示设置弹层，大设置页不再出现。
    expect(find.text('速度来源', skipOffstage: false), findsNothing);
    expect(find.text('GPS 副速度对比', skipOffstage: false), findsNothing);
    expect(find.text('加减步进', skipOffstage: false), findsNothing);
    expect(find.text('陀螺仪角度', skipOffstage: false), findsOneWidget);
    await tester.ensureVisible(find.text('27.5"'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('27.5"'));
    await tester.pumpAndSettle();
    expect(ble.localWheel.diameterMm, 699);
    expect(find.text('699 mm'), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance())
            .getInt('local_csc_wheel_diameter_mm'),
        699);
    await tester.ensureVisible(find.text('重启设备', skipOffstage: false));
    await tester.pumpAndSettle();
    final restart = find
        .ancestor(of: find.text('重启设备'), matching: find.byType(GestureDetector))
        .first;
    expect(tester.widget<GestureDetector>(restart).onTap, isNull);
    await tester.scrollUntilVisible(find.text('校准陀螺仪'), 200);
    final calibrate = find
        .ancestor(
            of: find.text('校准陀螺仪'), matching: find.byType(GestureDetector))
        .first;
    expect(tester.widget<GestureDetector>(calibrate).onTap, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('大设置页不再包含加减步进与逐格微调控件', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final steps = AssistStepSettings();
    await steps.load();
    await tester.pumpWidget(_wrap(steps));

    expect(find.text('加减步进'), findsNothing);
    expect(find.byKey(const ValueKey('assist-step-value')), findsNothing);
    expect(find.byKey(const ValueKey('assist-step-plus')), findsNothing);
    expect(find.byKey(const ValueKey('assist-step-minus')), findsNothing);
    expect(find.text('1%'), findsNothing);
    expect(find.text('20%'), findsNothing);
    // 步进设置本体仍在（显示设置弹层负责配置）。
    expect(steps.step, AssistStepSettings.defaultStep);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('大设置页不再显示演示数据开关（快捷开关在显示设置弹层）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final steps = AssistStepSettings();
    await steps.load();
    await tester.pumpWidget(_wrap(steps));

    expect(find.text('断开连接时显示演示数据'), findsNothing);
    expect(find.text('演示数据'), findsNothing);
    expect(find.byKey(const ValueKey('demo-mode-tile')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('关于页面显示版本号和本次更新', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: '智能码表',
      packageName: 'com.wepower.bike_computer',
      version: '1.6.57',
      buildNumber: '68',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(_wrap(AssistStepSettings()));

    final about = find.text('应用简介、版本与更新信息');
    await tester.scrollUntilVisible(about, 300);
    await tester.ensureVisible(about);
    await tester.pumpAndSettle();
    await tester.tap(about);
    await tester.pumpAndSettle();

    expect(find.text('1.6.57 (68)'), findsOneWidget);
    expect(find.text('2026-11-16'), findsOneWidget);
    expect(find.text('本次更新'), findsOneWidget);
    // 本次更新文案随版本变化，断言只锁定该段独有的关键词。
    expect(find.textContaining('裁剪掉设计稿的空白边框'), findsOneWidget);
    expect(find.textContaining('toast 反馈'), findsOneWidget);
    expect(find.textContaining('电源按钮'), findsOneWidget);
    expect(find.textContaining('数显管'), findsOneWidget);
    expect(find.textContaining('连续调速'), findsOneWidget);
    expect(find.textContaining('36V 电池重新标定'), findsOneWidget);
    expect(find.textContaining('正红 #FF0000'), findsOneWidget);
    expect(find.textContaining('24 秒一轮'), findsOneWidget);
    expect(find.textContaining('单一连续填充条'), findsOneWidget);
    expect(find.textContaining('屏幕常亮'), findsOneWidget);
    expect(find.textContaining('来源图标上移'), findsOneWidget);
    expect(find.textContaining('分级多色'), findsOneWidget);
    expect(find.textContaining('偏热 / 过热'), findsOneWidget);
    expect(find.textContaining('50~80% 蓝'), findsOneWidget);
    expect(find.textContaining('DSEG7'), findsOneWidget);
    expect(find.textContaining('熄灭段底纹'), findsOneWidget);
    expect(find.textContaining('位数恒定'), findsOneWidget);
    expect(find.textContaining('连接真实设备自动切回真实数据'), findsOneWidget);
    expect(find.textContaining('闪控联动'), findsOneWidget);
  });
}
