import 'package:bike_computer/models/assist_mode.dart';
import 'package:bike_computer/models/bike_data.dart';
import 'package:bike_computer/models/command_result.dart';
import 'package:bike_computer/screens/dashboard_screen.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/gps_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _ConnectedBleService extends ChangeNotifier implements BleService {
  _ConnectedBleService(this.delegate);
  final BleService delegate;
  final List<AssistMode> requestedModes = [];
  final List<int> requestedPercents = [];
  bool manual = false;
  bool percentConfirmed = false;

  @override
  Future<CommandResult> setAssistPercent(int percent) async {
    requestedPercents.add(percent);
    return CommandResult.ok;
  }

  @override
  Future<CommandResult> setAssistMode(AssistMode mode) async {
    requestedModes.add(mode);
    return CommandResult.ok;
  }

  @override
  bool get isConnected => true;

  @override
  BikeData get bikeData => delegate.bikeData;

  @override
  BluetoothAdapterState get adapterState => delegate.adapterState;

  @override
  int get assistLevel => delegate.assistLevel;

  @override
  AssistMode get assistMode => manual ? AssistMode.manual : delegate.assistMode;

  @override
  bool get assistModeConfirmed => manual || delegate.assistModeConfirmed;

  @override
  String get assistModeStatus => delegate.assistModeStatus;

  @override
  int get assistPercent => delegate.assistPercent;

  @override
  bool get assistPercentConfirmed => percentConfirmed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('控制按钮禁用，设备未报告的数据保持未知', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 12.3;
    ble.bikeData.speedAvailable = true;
    ble.bikeData.voltage = 38.5;
    ble.bikeData.batteryLevel = 77;
    ble.bikeData.batteryLevelAvailable = true;
    ble.bikeData.batteryLevelEstimated = true;
    ble.bikeData.controllerTemperature = 0;
    ble.bikeData.temperatureAvailable = true;
    ble.bikeData.slope = -1.2;
    ble.bikeData.gyroAngleAvailable = true;
    ble.bikeData.climbingAngle = 1.2;
    ble.bikeData.climbingLevel = 25;
    ble.bikeData.tripDistance = 1.5;
    ble.bikeData.tripAvailable = true;
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: connected),
        ChangeNotifierProvider<GpsService>(create: (_) => GpsService()),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    ));
    expect(find.text('12.3'), findsOneWidget);
    final voltage = tester.widget<Text>(find.text('38.5 V'));
    final percent = tester.widget<Text>(find.text('77% · 估算'));
    expect(voltage.style!.fontSize, greaterThan(percent.style!.fontSize!));
    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('坡度信息'), findsOneWidget);
    expect(find.text('-1.2°'), findsOneWidget);
    expect(find.text('蓝牙车体倾角'), findsOneWidget);
    expect(find.text('爬坡设定'), findsNothing);
    expect(find.text('助力 25%'), findsNothing);
    expect(find.text('陀螺仪'), findsNothing);
    expect(find.text('助力设置仅限停车测试；请使用车辆原有控制装置'), findsNothing);
    expect(find.text('助力功率'), findsNothing);
    expect(find.text('电机功率'), findsNothing);
    expect(find.text('总里程'), findsNothing);
    expect(find.text('模式未知（无离线查询）'), findsOneWidget);
    expect(find.text('停止'), findsNothing);
    await tester.tap(find.text('通勤'));
    await tester.pumpAndSettle();
    expect(connected.requestedModes, [AssistMode.commute]);
    expect(find.text('确认切换助力模式'), findsNothing);
    expect(find.text('未确认车辆静止'), findsNothing);
    expect(find.text('模式未知（无离线查询）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('手动滑块默认位置不发送，松手后发送所选百分比', (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble)..manual = true;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: connected),
        ChangeNotifierProvider<GpsService>(create: (_) => GpsService()),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    ));
    expect(find.text('百分比未知（默认位置 51%）'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 51);
    expect(slider.max, 99);
    expect(connected.requestedPercents, isEmpty);
    slider.onChanged!(35);
    await tester.pump();
    expect(connected.requestedPercents, isEmpty);
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(35);
    await tester.pump();
    expect(connected.requestedPercents, [35]);
    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('副速度显示另一来源，未启用 GPS 时明确提示', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: connected),
        ChangeNotifierProvider<GpsService>(create: (_) => GpsService()),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    ));
    expect(find.text('18.2'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('secondary-speed'))).data, '--');
    expect(find.text('GPS'), findsOneWidget);
    expect(find.text('对比未开启'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('连接后电压可见，未取得百分比时不误报 0%', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.voltage = 38.5;
    ble.bikeData.batteryLevel = 0;
    ble.bikeData.batteryLevelAvailable = false;
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BleService>.value(value: connected),
          ChangeNotifierProvider<GpsService>(create: (_) => GpsService()),
        ],
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    expect(find.text('38.5 V'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text('电量 --'), findsOneWidget);
    expect(find.text('尚未读取'), findsOneWidget);
    expect(find.text('蓝牙车体倾角'), findsNothing);
    expect(find.text('--'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.voltage = 0;
  });
}
