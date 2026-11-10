import 'package:bike_computer/screens/settings_screen.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/gps_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('本地轮径可选择并保存，重启和校准保持禁用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ble = BleService();
    await ble.localWheel.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: ble),
        ChangeNotifierProvider<GpsService>(create: (_) => GpsService()),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await tester.scrollUntilVisible(find.text('本地 CSC 轮径'), 200);
    expect(find.textContaining('不会写入电机'), findsOneWidget);
    expect(find.text('GPS 副速度对比', skipOffstage: false), findsOneWidget);
    expect(find.text('陀螺仪角度', skipOffstage: false), findsOneWidget);
    await tester.ensureVisible(find.text('27.5"'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('27.5"'));
    await tester.pumpAndSettle();
    expect(ble.localWheel.diameterMm, 699);
    expect(find.text('699 mm'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getInt('local_csc_wheel_diameter_mm'), 699);
    await tester.ensureVisible(find.text('重启设备', skipOffstage: false));
    await tester.pumpAndSettle();
    final restart = find.ancestor(of: find.text('重启设备'), matching: find.byType(GestureDetector)).first;
    expect(tester.widget<GestureDetector>(restart).onTap, isNull);
    await tester.scrollUntilVisible(find.text('校准陀螺仪'), 200);
    final calibrate = find.ancestor(of: find.text('校准陀螺仪'), matching: find.byType(GestureDetector)).first;
    expect(tester.widget<GestureDetector>(calibrate).onTap, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('关于页面显示版本号和本次更新', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: '智能码表',
      packageName: 'com.wepower.bike_computer',
      version: '1.6.29',
      buildNumber: '39',
      buildSignature: '',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BleService>.value(value: BleService()),
          ChangeNotifierProvider<GpsService>(create: (_) => GpsService()),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );

    final about = find.text('应用简介、版本与更新信息');
    await tester.scrollUntilVisible(about, 300);
    await tester.ensureVisible(about);
    await tester.pumpAndSettle();
    await tester.tap(about);
    await tester.pumpAndSettle();

    expect(find.text('1.6.29 (39)'), findsOneWidget);
    expect(find.text('2026-11-10'), findsOneWidget);
    expect(find.text('本次更新'), findsOneWidget);
    expect(find.textContaining('首页显示蓝牙车体倾角'), findsOneWidget);
  });
}
