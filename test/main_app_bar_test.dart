import 'package:bike_computer/main.dart';
import 'package:bike_computer/models/assist_mode.dart';
import 'package:bike_computer/models/bike_data.dart';
import 'package:bike_computer/services/assist_remote_scheduler.dart';
import 'package:bike_computer/services/assist_step_settings.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/br80_service.dart';
import 'package:bike_computer/services/demo_mode_settings.dart';
import 'package:bike_computer/services/gps_service.dart';
import 'package:bike_computer/services/ride_time_service.dart';
import 'package:bike_computer/theme/dashboard_theme.dart';
import 'package:bike_computer/widgets/remote_glyph.dart';
import 'package:bike_computer/widgets/segment_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只替换连接状态，其余只读数据仍用真实 BleService 的默认值。
class _FakeBle extends ChangeNotifier implements BleService {
  _FakeBle(this.delegate, {required this.connected});

  final BleService delegate;
  final bool connected;

  @override
  bool get isConnected => connected;

  @override
  BluetoothDevice? get connectedDevice => null;

  @override
  BikeData get bikeData => delegate.bikeData;

  @override
  BluetoothAdapterState get adapterState => delegate.adapterState;

  @override
  int get assistLevel => delegate.assistLevel;

  @override
  AssistMode get assistMode => delegate.assistMode;

  @override
  bool get assistModeConfirmed => delegate.assistModeConfirmed;

  @override
  String get assistModeStatus => delegate.assistModeStatus;

  @override
  int get assistPercent => delegate.assistPercent;

  @override
  bool get assistPercentConfirmed => delegate.assistPercentConfirmed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(BleService ble,
        {Br80Service? remote, DemoModeSettings? demo, RideTimeService? rideTime}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: ble),
        if (remote != null)
          ChangeNotifierProvider<Br80Service>.value(value: remote)
        else
          ChangeNotifierProvider<Br80Service>(
              create: (_) => Br80Service(onAssistStep: (direction) async {})),
        ChangeNotifierProvider<AssistRemoteScheduler>(
            create: (_) => AssistRemoteScheduler(
                ble: ble, stepOf: () => 5, onResult: (_) {})),
        ChangeNotifierProvider<GpsService>.value(value: GpsService()),
        ChangeNotifierProvider<AssistStepSettings>(
            create: (_) => AssistStepSettings()),
        if (demo != null)
          ChangeNotifierProvider<DemoModeSettings>.value(value: demo)
        else
          ChangeNotifierProvider<DemoModeSettings>(
              create: (_) => DemoModeSettings()),
        if (rideTime != null)
          ChangeNotifierProvider<RideTimeService>.value(value: rideTime)
        else
          ChangeNotifierProvider<RideTimeService>(
              create: (ctx) =>
                  RideTimeService.fromServices(ble, ctx.read<GpsService>())),
      ],
      child: const BikeComputerApp(),
    );

/// 状态栏里闪控图标的绘制颜色（新设计稿为纯色双态，无独立 LED 点）。
Color _remoteGlyphColor(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(
      of: find.byKey(const ValueKey('remote-glyph')),
      matching: find.byType(CustomPaint)));
  return (paint.painter! as RemoteGlyphPainter).color;
}

/// 状态栏里的骑行时间（数码管）。
SegmentClock _appBarClock(WidgetTester tester) => tester
    .widget<SegmentClock>(find.byKey(const ValueKey('appbar-ride-time')));

void main() {
  testWidgets('连接控制器时信号变绿、蓝牙图标统一蓝色，且不显示状态标签', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final delegate = BleService();
    delegate.bikeData.rssi = -62;
    final ble = _FakeBle(delegate, connected: true);
    await tester.pumpWidget(_app(ble));
    await tester.pump();

    expect(find.text('已连接'), findsNothing);
    expect(find.text('未连接'), findsNothing);
    // 连接设备的名称标签已去掉。
    expect(find.text('未连接设备'), findsNothing);
    expect(find.text('蓝牙设备'), findsNothing);

    final appBar = find.byType(AppBar);
    // 连接成功时蓝牙图标换成 bluetooth_connected。
    final bluetooth = tester.widget<Icon>(find.descendant(
        of: appBar, matching: find.byIcon(Icons.bluetooth_connected)));
    expect(bluetooth.color, DashColors.sourceBluetooth);
    expect(
        find.descendant(of: appBar, matching: find.byIcon(Icons.bluetooth)),
        findsNothing);
    // 信号图标紧挨蓝牙图标，连接时转绿；dBm 数值已删除。
    final signal = tester.widget<Icon>(
        find.descendant(
            of: appBar, matching: find.byIcon(Icons.signal_cellular_alt)));
    expect(signal.color, DashColors.green);
    expect(find.textContaining('dBm'), findsNothing);
    // 右上角没有实际功能的电源按钮已移除。
    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未连接时状态图标保持灰色，同样不显示状态标签', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final delegate = BleService();
    final ble = _FakeBle(delegate, connected: false);
    await tester.pumpWidget(_app(ble));
    await tester.pump();

    expect(find.text('已连接'), findsNothing);
    expect(find.text('未连接'), findsNothing);
    // 未连接时也不再显示设备名称标签。
    expect(find.text('未连接设备'), findsNothing);
    expect(find.text('蓝牙设备'), findsNothing);

    final appBar = find.byType(AppBar);
    final bluetooth = tester.widget<Icon>(
        find.descendant(of: appBar, matching: find.byIcon(Icons.bluetooth)));
    // 未连接用普通蓝牙图标，颜色与首页来源图标统一为蓝色。
    expect(bluetooth.color, DashColors.sourceBluetooth);
    expect(
        find.descendant(
            of: appBar, matching: find.byIcon(Icons.bluetooth_connected)),
        findsNothing);
    final signal = tester.widget<Icon>(
        find.descendant(
            of: appBar, matching: find.byIcon(Icons.signal_cellular_alt)));
    expect(signal.color, DashColors.muted);
    expect(find.textContaining('dBm'), findsNothing);
    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('状态栏显示骑行时间数码管，字号比首页那一行小一号',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ble = _FakeBle(BleService(), connected: true);
    await tester.pumpWidget(_app(ble));
    await tester.pump();

    final clock = _appBarClock(tester);
    expect(clock.text, '00:00');
    expect(clock.height, 18, reason: '状态栏里的骑行时间比首页小一号');
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    // 首页不再重复显示骑行时间。
    expect(find.byKey(const ValueKey('ride-time')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('计时服务按速度启停，状态栏骑行时间随之更新', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var speed = 20.0;
    final rideTime =
        RideTimeService(isConnected: () => false, speedKmh: () => speed);
    final ble = _FakeBle(BleService(), connected: true);
    await tester.pumpWidget(_app(ble, rideTime: rideTime));
    await tester.pump();
    expect(_appBarClock(tester).text, '00:00');

    final t0 = DateTime(2026, 11, 16, 10);
    rideTime.tick(t0);
    for (var i = 1; i <= 65; i++) {
      rideTime.tick(t0.add(Duration(seconds: i)));
    }
    await tester.pump();
    expect(_appBarClock(tester).text, '00:01');

    // 速度归零后自动暂停
    speed = 0;
    for (var i = 66; i <= 130; i++) {
      rideTime.tick(t0.add(Duration(seconds: i)));
    }
    await tester.pump();
    expect(_appBarClock(tester).text, '00:01');

    rideTime.dispose();
  });

  testWidgets('演示模式下状态栏显示绿色连接信号与连接态蓝牙图标', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final demo = DemoModeSettings();
    await demo.setEnabled(true);
    final ble = _FakeBle(BleService(), connected: false);
    await tester.pumpWidget(_app(ble, demo: demo));
    await tester.pump();

    // 设备名称标签已去掉，演示态也不再显示「演示设备」。
    expect(find.text('演示设备'), findsNothing);
    expect(find.text('未连接设备'), findsNothing);
    final appBar = find.byType(AppBar);
    expect(
        find.descendant(
            of: appBar, matching: find.byIcon(Icons.bluetooth_connected)),
        findsOneWidget,
        reason: '演示态按连接成功显示蓝牙图标');
    final signal = tester.widget<Icon>(find.byIcon(Icons.signal_cellular_alt));
    expect(signal.color, DashColors.green, reason: '演示模式也显示连接信号');
    // 演示时显示固定的演示时长。
    expect(_appBarClock(tester).text, '01:24');
    expect(tester.takeException(), isNull);
  });

  testWidgets('闪控连接状态灯显示在状态栏', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ble = _FakeBle(BleService(), connected: true);
    await tester.pumpWidget(_app(ble));
    await tester.pump();
    expect(_remoteGlyphColor(tester), RemoteGlyph.disconnectedColor);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(ble,
        remote: _FakeRemote(connected: true)));
    await tester.pump();
    expect(_remoteGlyphColor(tester), RemoteGlyph.connectedColor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('闪控图标靠状态栏左侧，排在骑行时间与设置按钮之前', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ble = _FakeBle(BleService(), connected: false);
    await tester.pumpWidget(_app(ble));
    await tester.pump();

    final appBar = find.byType(AppBar);
    final bluetooth = find.descendant(
        of: appBar, matching: find.byIcon(Icons.bluetooth));
    final glyph = find.byKey(const ValueKey('remote-glyph'));
    final clock = find.byKey(const ValueKey('appbar-ride-time'));
    final settings = find.descendant(
        of: appBar, matching: find.byIcon(Icons.settings_outlined));
    expect(bluetooth, findsOneWidget);
    expect(glyph, findsOneWidget);
    expect(clock, findsOneWidget);
    expect(settings, findsOneWidget);
    expect(tester.getCenter(bluetooth).dx, lessThan(tester.getCenter(glyph).dx));
    expect(tester.getCenter(glyph).dx, lessThan(tester.getCenter(clock).dx));
    expect(tester.getCenter(clock).dx, lessThan(tester.getCenter(settings).dx));
    expect(tester.takeException(), isNull);
  });
}

/// 只控制连接状态的闪控服务。
class _FakeRemote extends ChangeNotifier implements Br80Service {
  _FakeRemote({required this.connected});

  final bool connected;

  @override
  bool get isConnected => connected;

  @override
  String? get message => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
