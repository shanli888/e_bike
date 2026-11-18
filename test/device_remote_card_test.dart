import 'package:bike_computer/screens/device_screen.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/br80_service.dart';
import 'package:bike_computer/services/remembered_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 只覆盖设备页读取的字段，避免测试里触发真实蓝牙插件
class _FakeBle extends ChangeNotifier implements BleService {
  @override
  BluetoothAdapterState get adapterState => BluetoothAdapterState.on;

  @override
  Future<BluetoothAdapterState> readAdapterState() async => BluetoothAdapterState.on;

  @override
  Future<bool> startScan() async => true;

  @override
  List<ScanResult> get devices => const [];

  @override
  bool get isConnected => false;

  @override
  bool get isScanning => false;

  @override
  bool get showAllDevices => false;

  @override
  RememberedDevice? get lastDevice => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('设备页常驻闪控入口，可单独发起扫描连接', (tester) async {
    final ble = _FakeBle();
    final remote = Br80Service(onAssistStep: (delta) async {});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BleService>.value(value: ble),
          ChangeNotifierProvider<Br80Service>.value(value: remote),
        ],
        child: const MaterialApp(home: Scaffold(body: DeviceScreen())),
      ),
    );
    await tester.pump();

    expect(find.text('闪控（BR80）'), findsOneWidget);
    expect(find.text('未连接 · 可与码表同时连接'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '扫描并连接'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, '扫描并连接'));
    await tester.pump();

    expect(find.textContaining('正在扫描闪控'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    ble.dispose();
    remote.dispose();
  });

}
