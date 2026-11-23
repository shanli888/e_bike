import 'package:bike_computer/models/assist_mode.dart';
import 'package:bike_computer/models/bike_data.dart';
import 'package:bike_computer/models/command_result.dart';
import 'package:bike_computer/models/demo_ride_data.dart';
import 'package:bike_computer/screens/dashboard_screen.dart';
import 'package:bike_computer/services/assist_remote_scheduler.dart';
import 'package:bike_computer/services/assist_step_settings.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/br80_protocol.dart';
import 'package:bike_computer/services/br80_service.dart';
import 'package:bike_computer/services/demo_mode_settings.dart';
import 'package:bike_computer/services/display_mode_settings.dart';
import 'package:bike_computer/services/gps_service.dart';
import 'package:bike_computer/services/ride_recorder.dart';
import 'package:bike_computer/services/ride_repository.dart';
import 'package:bike_computer/services/ride_time_service.dart';
import 'package:bike_computer/theme/dashboard_theme.dart';
import 'package:bike_computer/theme/sensor_status.dart';
import 'package:bike_computer/widgets/needle_speedometer.dart';
import 'package:bike_computer/widgets/segment_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只替换与助力指令相关的 getter，其余仍用真实 BleService 的只读数据。
class _ConnectedBleService extends ChangeNotifier implements BleService {
  _ConnectedBleService(this.delegate);
  final BleService delegate;
  final List<AssistMode> requestedModes = [];
  final List<int> requestedPercents = [];
  final List<int> requestedSteps = [];
  int stopCalls = 0;
  bool manual = false;
  bool percentConfirmed = false;
  int _percent = 51;

  @override
  Future<CommandResult> setAssistPercent(int percent,
      {bool priority = false}) async {
    requestedPercents.add(percent);
    _percent = percent;
    return CommandResult.ok;
  }

  @override
  Future<CommandResult> stepAssistPercent(int delta) async {
    requestedSteps.add(delta);
    return setAssistPercent((_percent + delta).clamp(0, 99));
  }

  @override
  Future<CommandResult> setAssistMode(AssistMode mode,
      {bool priority = false}) async {
    requestedModes.add(mode);
    return CommandResult.ok;
  }

  @override
  Future<CommandResult> stopAssist() async {
    stopCalls++;
    _percent = 0;
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
  int get assistPercent => _percent;

  @override
  bool get assistPercentConfirmed => percentConfirmed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 测试用 GPS 服务：可直接控制「副速度对比」开关，避免触发真实定位。
class _TestGpsService extends GpsService {
  bool _compare = false;
  SpeedSource _source = SpeedSource.bluetooth;
  double? _speed;

  @override
  bool get comparisonEnabled => _compare;
  @override
  SpeedSource get source => _source;
  @override
  double? get speedKmh => _speed;

  void setCompare(bool value) {
    _compare = value;
    notifyListeners();
  }

  /// 首页点副速度切换来源时走这里，测试里不触发真实定位插件。
  @override
  Future<bool> setSource(SpeedSource source) async {
    if (_source == source) return true;
    _source = source;
    notifyListeners();
    return true;
  }

  /// 模拟 GPS 作为主速度来源
  void useGpsPrimary(double speed) {
    _source = SpeedSource.gps;
    _speed = speed;
    notifyListeners();
  }
}

/// 测试用闪控服务：只控制连接状态，不触碰真实 BLE。
class _FakeRemote extends ChangeNotifier implements Br80Service {
  _FakeRemote({required this.connected});

  bool connected;

  @override
  bool get isConnected => connected;

  @override
  String? get message => null;

  @override
  Br80KeyEvent? get lastPressedKey => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 统一提供首页所需的 Provider（独立计时服务、闪控、助力步进设置）。
Widget _wrap(
  Widget child,
  BleService ble,
  GpsService gps, {
  AssistStepSettings? steps,
  Br80Service? remote,
  DemoModeSettings? demo,
  AssistRemoteScheduler? scheduler,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<BleService>.value(value: ble),
      ChangeNotifierProvider<GpsService>.value(value: gps),
      ChangeNotifierProvider<Br80Service>.value(
          value: remote ?? Br80Service(onAssistStep: (direction) async {})),
      if (scheduler != null)
        ChangeNotifierProvider<AssistRemoteScheduler>.value(value: scheduler)
      else
        ChangeNotifierProvider<AssistRemoteScheduler>(
          create: (_) => AssistRemoteScheduler(
            ble: ble,
            stepOf: () => steps?.step ?? AssistStepSettings.defaultStep,
            onResult: (_) {},
          ),
        ),
      ChangeNotifierProvider<RideTimeService>(
          create: (_) => RideTimeService.fromServices(ble, gps)),
      ChangeNotifierProvider<AssistStepSettings>(
          create: (_) => steps ?? AssistStepSettings()),
      ChangeNotifierProvider<DemoModeSettings>(
          create: (_) => demo ?? DemoModeSettings()),
      ChangeNotifierProvider<DisplayModeSettings>(
          create: (_) => DisplayModeSettings()),
      Provider<RideRepository>(create: (_) => RideRepository()),
      ChangeNotifierProvider<RideRecorder>(
          create: (ctx) => RideRecorder(ctx.read<RideRepository>())),
    ],
    child: child,
  );
}

Widget _screen({VoidCallback? onOpenDevices, DateTime Function()? demoClock}) =>
    MaterialApp(
      home: Scaffold(
          body: DashboardScreen(
              onOpenDevices: onOpenDevices, demoClock: demoClock)),
    );

SegmentNumber _segment(WidgetTester tester, String key) =>
    tester.widget<SegmentNumber>(find.byKey(ValueKey(key)));

Finder _key(String key) => find.byKey(ValueKey(key));

Color _textColor(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).style!.color!;

Color _cardBorderColor(WidgetTester tester, String key) {
  final decoration =
      tester.widget<Container>(_key(key)).decoration! as BoxDecoration;
  return (decoration.border as Border).top.color;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('新视觉分区齐全：七段主速度、三列副表、助力卡与传感器卡', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 12.3;
    ble.bikeData.speedAvailable = true;
    ble.bikeData.voltage = 38.5;
    ble.bikeData.batteryLevel = 77;
    ble.bikeData.batteryLevelAvailable = true;
    ble.bikeData.controllerTemperature = 26.5;
    ble.bikeData.temperatureAvailable = true;
    ble.bikeData.slope = -1.2;
    ble.bikeData.gyroAngleAvailable = true;
    ble.bikeData.tripDistance = 1.5;
    ble.bikeData.tripAvailable = true;
    ble.bikeData.avgSpeed = 8.4;
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    // 主速度用七段控件绘制，不再有可 find.text 的纯文本数字。
    expect(_segment(tester, 'primary-speed').text, '12.3');
    expect(_segment(tester, 'primary-speed').integerDigits, 2);
    expect(_segment(tester, 'primary-speed').fractionDigits, 1);
    expect(_key('primary-icon-bluetooth'), findsOneWidget);

    // 三列副表 AVG / MAX / km，里程的 km 语义仍在。
    for (final tag in ['AVG', 'MAX', 'km']) {
      expect(_key('sub-tag-$tag'), findsOneWidget);
      expect(_key('sub-value-$tag'), findsOneWidget);
    }
    expect(_segment(tester, 'sub-value-AVG').text, '8.4');
    expect(_segment(tester, 'sub-value-MAX').text, '0.0');
    expect(_segment(tester, 'sub-value-km').text, '1.5');
    expect(_segment(tester, 'sub-value-km').semanticsLabel, '1.5 km');
    expect(
        find.descendant(
          of: _key('speed-number-page'),
          matching: find.textContaining('km/h'),
        ),
        findsNothing,
      );

    // 助力卡与电量/温度两张传感器卡按新稿命名；坡度改由 GPS 指示，陀螺仪已移除。
    expect(find.text('助力控制'), findsOneWidget);
    expect(find.text('电量'), findsOneWidget);
    expect(find.text('温度'), findsOneWidget);
    expect(find.text('陀螺仪'), findsNothing);
    expect(find.text('77%'), findsOneWidget);
    expect(find.text('38.5'), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
    expect(find.text('26.5'), findsOneWidget);
    expect(find.text('-1.2'), findsNothing);

    // 电量 77% 属 50~80 蓝色档，温度 26.5℃ 属 <30 绿色档；
    expect(_textColor(tester, 'battery-percent'), DashColors.blue);
    expect(_textColor(tester, 'battery-voltage'), DashColors.blue);
    expect(_cardBorderColor(tester, 'battery-card'), DashColors.line);
    expect(_textColor(tester, 'temperature-value'), DashColors.green);
    expect(find.text('正常'), findsOneWidget);
    expect(_key('battery-bar'), findsOneWidget);
    expect(
      tester
          .widget<FractionallySizedBox>(find.descendant(
            of: _key('battery-bar'),
            matching: find.byType(FractionallySizedBox),
          ))
          .widthFactor,
      0.77,
    );
    // 进度条必须是一条连续填充：底轨只有一块、填充不透明，
    // 不能再出现分区淡底 / 常亮四色带把进度条切成几段。
    expect(_key('battery-track'), findsOneWidget);
    expect(_key('battery-fill'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('battery-bar'),
        matching: find.byType(ColoredBox),
      ),
      findsOneWidget,
    );
    final fillDecoration = tester
        .widget<DecoratedBox>(_key('battery-fill'))
        .decoration as BoxDecoration;
    final fillColors = (fillDecoration.gradient! as LinearGradient).colors;
    for (final color in fillColors) {
      expect(color.a, 1.0, reason: '填充色不透明，底轨分区线不会透出来');
    }
    // 填充宽度与百分比一致，是完整的一块而非分段拼凑。
    final barWidth = tester.getSize(_key('battery-bar')).width;
    expect(tester.getSize(_key('battery-fill')).width / barWidth,
        closeTo(0.77, 0.02));

    // 旧版文案与部件已移除。
    expect(find.text('手动（默认）'), findsNothing);
    expect(find.text('坡度信息'), findsNothing);
    expect(find.text('总里程'), findsNothing);
    expect(find.text('停止'), findsNothing);

    // 骑行时间保留，但去掉「骑行时间」文字，只留 icon + HH:MM 数码管。
    expect(find.text('骑行时间'), findsNothing);
    expect(_key('ride-time'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('电量四档与温度三档在首页同步切换配色', (tester) async {
    final cases = [
      (
        battery: 95,
        temp: 25.0,
        batteryColor: DashColors.green,
        tempColor: DashColors.green,
        label: '正常'
      ),
      (
        battery: 81,
        temp: 30.0,
        batteryColor: DashColors.green,
        tempColor: DashColors.yellow,
        label: '偏热'
      ),
      (
        battery: 80,
        temp: 50.0,
        batteryColor: DashColors.blue,
        tempColor: DashColors.yellow,
        label: '偏热'
      ),
      (
        battery: 50,
        temp: 50.1,
        batteryColor: DashColors.blue,
        tempColor: DashColors.red,
        label: '过热'
      ),
      (
        battery: 49,
        temp: 18.0,
        batteryColor: DashColors.orange,
        tempColor: DashColors.green,
        label: '正常'
      ),
      (
        battery: 20,
        temp: 62.0,
        batteryColor: DashColors.orange,
        tempColor: DashColors.red,
        label: '过热'
      ),
      (
        battery: 19,
        temp: 0.0,
        batteryColor: DashColors.red,
        tempColor: DashColors.green,
        label: '正常'
      ),
      (
        battery: 0,
        temp: 55.0,
        batteryColor: DashColors.red,
        tempColor: DashColors.red,
        label: '过热'
      ),
    ];

    for (final c in cases) {
      final ble = BleService();
      ble.bikeData.clearReadOnlyAvailability();
      ble.bikeData.voltage = 40.0;
      ble.bikeData.batteryLevel = c.battery;
      ble.bikeData.batteryLevelAvailable = true;
      ble.bikeData.controllerTemperature = c.temp;
      ble.bikeData.temperatureAvailable = true;
      final connected = _ConnectedBleService(ble);
      await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

      expect(tester.widget<Text>(_key('battery-percent')).data, '${c.battery}%',
          reason: '电量 ${c.battery}%');
      expect(_textColor(tester, 'battery-percent'), c.batteryColor,
          reason: '电量 ${c.battery}% 的百分比配色');
      expect(_textColor(tester, 'battery-voltage'), c.batteryColor,
          reason: '电量 ${c.battery}% 的电压配色');
      expect(_cardBorderColor(tester, 'battery-card'), DashColors.line,
          reason: '电量 ${c.battery}% 的卡片描边');
      expect(
        tester
            .widget<FractionallySizedBox>(find.descendant(
              of: _key('battery-bar'),
              matching: find.byType(FractionallySizedBox),
            ))
            .widthFactor,
        c.battery / 100,
        reason: '电量 ${c.battery}% 的进度条填充',
      );
      final fillColors = ((tester
                  .widget<DecoratedBox>(_key('battery-fill'))
                  .decoration as BoxDecoration)
              .gradient! as LinearGradient)
          .colors;
      expect(fillColors.last, c.batteryColor,
          reason: '电量 ${c.battery}% 的进度条填充配色');

      expect(_textColor(tester, 'temperature-value'), c.tempColor,
          reason: '温度 ${c.temp}℃ 的配色');
      expect(_cardBorderColor(tester, 'temperature-card'), DashColors.line,
          reason: '温度 ${c.temp}℃ 的卡片描边');
      expect(find.text(c.label), findsOneWidget, reason: '温度 ${c.temp}℃ 的档位标签');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      connected.dispose();
    }
  });

  testWidgets('电量/温度无数据时用中性色且进度条不填充', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    expect(tester.widget<Text>(_key('battery-percent')).data, '--');
    expect(_textColor(tester, 'battery-percent'), DashColors.muted2);
    expect(_textColor(tester, 'battery-voltage'), DashColors.muted2);
    expect(_textColor(tester, 'temperature-value'), DashColors.muted2);
    expect(
      find.descendant(
        of: _key('battery-bar'),
        matching: find.byType(FractionallySizedBox),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('主速度来源图标与小数位拉开间距，仍在数字区域内', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    final frac = tester.getRect(find.descendant(
      of: _key('primary-speed'),
      matching: find.byKey(const ValueKey('segment-on-frac')),
    ));
    final icon = tester.getRect(_key('primary-icon-bluetooth'));
    // 原先 9px 间距（约 8 逻辑像素）太贴字，上移后应明显拉开。
    expect(frac.top - icon.bottom, greaterThan(11));
    expect(icon.top, greaterThan(tester.getRect(_key('primary-speed')).top));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('副速度对比关闭时隐藏副速度，实时速度仍居中显示', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    final gps = _TestGpsService();
    await tester.pumpWidget(_wrap(_screen(), connected, gps));

    expect(gps.comparisonEnabled, isFalse);
    expect(_key('secondary-speed'), findsNothing);
    expect(_segment(tester, 'primary-speed').text, '18.2');

    final screenWidth =
        MediaQuery.sizeOf(tester.element(find.byType(DashboardScreen))).width;
    final primary = tester.getCenter(_key('primary-speed'));
    expect((primary.dx - screenWidth / 2).abs(), lessThan(60));

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('副速度对比开启时在右上角单行显示来源图标，且不与主速度重叠', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    final gps = _TestGpsService()..setCompare(true);
    await tester.pumpWidget(_wrap(_screen(), connected, gps));

    expect(gps.comparisonEnabled, isTrue);
    expect(_key('secondary-speed'), findsOneWidget);
    // 蓝牙为主来源时，右上角副速度是 GPS；主速度角标是蓝牙。
    expect(_key('source-icon-gps'), findsOneWidget);
    expect(_key('primary-icon-bluetooth'), findsOneWidget);
    expect(find.text('GPS'), findsNothing);
    expect(find.text('蓝牙'), findsNothing);

    final iconCenter = tester.getCenter(_key('source-icon-gps'));
    final valueCenter = tester.getCenter(_key('secondary-speed'));
    expect((iconCenter.dy - valueCenter.dy).abs(), lessThan(2));

    final screenWidth =
        MediaQuery.sizeOf(tester.element(find.byType(DashboardScreen))).width;
    final primaryCenter = tester.getCenter(_key('primary-speed'));
    expect(iconCenter.dx, greaterThan(screenWidth * 0.7));
    expect(iconCenter.dy, lessThan(60));
    expect(iconCenter.dx, greaterThan(primaryCenter.dx + 80));
    expect((primaryCenter.dx - screenWidth / 2).abs(), lessThan(60));
    expect(
        find.descendant(
          of: _key('speed-number-page'),
          matching: find.textContaining('km/h'),
        ),
        findsNothing,
      );

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('骑行时间移到顶部状态栏后，首页只保留右上角副速度数码管',
      (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    final gps = _TestGpsService()..setCompare(true);
    await tester.pumpWidget(_wrap(_screen(), connected, gps));

    // 首页不再显示骑行时间（已移到顶部状态栏）。
    expect(_key('ride-time'), findsNothing);
    expect(find.text('骑行时间'), findsNothing);

    // 副速度仍是 DSEG7 数码管。
    final secondary = _segment(tester, 'secondary-speed');
    expect(secondary.fontFamily, DashFonts.segClassic);
    expect(secondary.text, isNull, reason: '蓝牙主来源、GPS 未定位时只留熄灭底纹');
    final secondaryCenter = tester.getCenter(_key('secondary-speed'));
    expect(secondaryCenter.dx, greaterThan(200), reason: '副速度靠右');

    // 速度来源图标：蓝牙蓝、GPS 绿。
    expect(tester.widget<Icon>(_key('primary-icon-bluetooth')).color,
        DashColors.sourceBluetooth);
    expect(tester.widget<Icon>(_key('source-icon-gps')).color,
        DashColors.sourceGps);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('单击右上角副速度区域交替切换蓝牙 / GPS 主速度来源', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    final gps = _TestGpsService()..setCompare(true);
    await tester.pumpWidget(_wrap(_screen(), connected, gps));

    expect(gps.source, SpeedSource.bluetooth);
    expect(_key('compare-speed-pill'), findsOneWidget);

    await tester.tap(_key('compare-speed-pill'));
    await tester.pump();
    expect(gps.source, SpeedSource.gps);
    expect(_key('primary-icon-gps'), findsOneWidget);
    expect(_key('source-icon-bluetooth'), findsOneWidget);

    await tester.tap(_key('compare-speed-pill'));
    await tester.pump();
    expect(gps.source, SpeedSource.bluetooth);
    expect(_key('primary-icon-bluetooth'), findsOneWidget);
    expect(_key('source-icon-gps'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('手动模式标题后实时显示助力百分比，含闪控本地预览值',
      (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble)..manual = true;
    final scheduler = AssistRemoteScheduler(
      ble: connected,
      stepOf: () => 5,
      onResult: (_) {},
      onToast: (message, {required bool error}) {},
    );
    await tester.pumpWidget(
        _wrap(_screen(), connected, GpsService(), scheduler: scheduler));

    expect(tester.widget<Text>(_key('assist-percent')).data, '51%');
    scheduler.step(1);
    await tester.pump();
    expect(tester.widget<Text>(_key('assist-percent')).data, '56%');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    scheduler.dispose();
    connected.dispose();
  });

  testWidgets('GPS 主来源时主速度取 GPS、角标切换为定位图标', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    final gps = _TestGpsService()..useGpsPrimary(20);
    await tester.pumpWidget(_wrap(_screen(), connected, gps));

    expect(_segment(tester, 'primary-speed').text, '20.0');
    expect(_key('primary-icon-gps'), findsOneWidget);
    expect(_segment(tester, 'sub-value-km').text, '0.0');
    expect(find.text('骑行时间'), findsNothing);
    expect(_key('ride-time'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('无数据时七段只留熄灭底纹，骑行时间为 00:00', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    expect(_segment(tester, 'primary-speed').text, isNull);
    expect(_segment(tester, 'sub-value-km').text, isNull);
    expect(_segment(tester, 'sub-value-km').semanticsLabel, 'km 无数据');
    expect(_key('ride-time'), findsNothing);
    expect(find.text('--'), findsWidgets);
    expect(tester.widget<Text>(_key('gauge-speed-readout')).data, '--');
    expect(
        find.descendant(
          of: _key('speed-number-page'),
          matching: find.textContaining('km/h'),
        ),
        findsNothing,
      );

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('骑行时间 HH:MM 且忽略设备上报的行程时长', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    ble.bikeData.tripDistance = 12.3;
    ble.bikeData.tripAvailable = true;
    ble.bikeData.rideTime = 5025; // 旧逻辑会显示 01:23:45，现在必须忽略
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    expect(find.text('骑行时间'), findsNothing);
    expect(_key('ride-time'), findsNothing);
    expect(find.text('01:23:45'), findsNothing);
    expect(_segment(tester, 'sub-value-km').text, '12.3');
    expect(_segment(tester, 'sub-value-km').semanticsLabel, '12.3 km');
    expect(
        find.descendant(
          of: _key('speed-number-page'),
          matching: find.textContaining('km/h'),
        ),
        findsNothing,
      );

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('默认手动模式：滑块、加减按钮与模式按钮均可用', (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    expect(_key('mode-manual'), findsOneWidget); // 当前模式的触发按钮
    expect(find.byType(Slider), findsOneWidget);
    expect(_key('assist-plus'), findsOneWidget);
    expect(_key('assist-minus'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);

    // 模式按钮已改为径向弹出菜单：点触发按钮展开，再点通勤项。
    await tester.tap(_key('mode-manual'));
    await tester.pumpAndSettle();
    expect(_key('mode-menu-commute'), findsOneWidget);
    await tester.tap(_key('mode-menu-commute'));
    await tester.pumpAndSettle();
    expect(connected.requestedModes, [AssistMode.commute]);
    expect(find.text('确认切换助力模式'), findsNothing);
    expect(find.text('未确认车辆静止'), findsNothing);

    // 选择后菜单自动收起。
    expect(_key('mode-menu-commute'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('径向模式菜单：点触发按钮展开 5 项，点空白处收起', (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    // 默认收起：菜单项不在树中，当前模式触发按钮在树中。
    expect(_key('mode-menu-manual'), findsNothing);
    expect(_key('mode-manual'), findsOneWidget);

    // 展开：5 个模式项全部出现。
    await tester.tap(_key('mode-manual'));
    await tester.pumpAndSettle();
    for (final mode in AssistMode.values) {
      expect(_key('mode-menu-${mode.name}'), findsOneWidget,
          reason: '径向菜单应包含 ${mode.label}');
    }

    // 点空白处（菜单遮罩）收起。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(_key('mode-menu-manual'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('手动滑块默认位置不发送，松手后发送所选百分比', (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble)..manual = true;
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    final slider = tester.widget<Slider>(_key('assist-slider'));
    expect(slider.value, 51);
    expect(slider.max, 99);
    expect(connected.requestedPercents, isEmpty);
    slider.onChanged!(35);
    await tester.pump();
    expect(connected.requestedPercents, isEmpty);
    tester.widget<Slider>(_key('assist-slider')).onChangeEnd!(35);
    await tester.pump();
    expect(connected.requestedPercents, [35]);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('手动加减按钮使用设置页步进值，修改后立即生效', (tester) async {
    SharedPreferences.setMockInitialValues(
        {AssistStepSettings.preferenceKey: 12});
    final steps = AssistStepSettings();
    await steps.load();
    final ble = BleService();
    final connected = _ConnectedBleService(ble)..manual = true;
    await tester
        .pumpWidget(_wrap(_screen(), connected, GpsService(), steps: steps));

    await tester.tap(_key('assist-plus'));
    await tester.pump();
    expect(connected.requestedSteps, [12]);

    await tester.tap(_key('assist-minus'));
    await tester.pump();
    expect(connected.requestedSteps, [12, -12]);

    await steps.setStep(3);
    await tester.pump();
    await tester.tap(_key('assist-plus'));
    await tester.pump();
    expect(connected.requestedSteps, [12, -12, 3]);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('助力卡不再显示闪控按键调试信息', (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble);
    final remote = Br80Service(onAssistStep: (direction) async {});
    await tester
        .pumpWidget(_wrap(_screen(), connected, GpsService(), remote: remote));

    expect(find.textContaining('闪控按键'), findsNothing);
    remote.handleKeyFrame(const [0x06]); // ▲ 上键按下
    await tester.pump();
    expect(find.textContaining('闪控按键'), findsNothing);
    expect(find.textContaining('0x06'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    remote.dispose();
  });

  testWidgets('闪控连续调速先移动滑杆，1 秒后只下发一次最终值', (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble)..manual = true;
    final scheduler = AssistRemoteScheduler(
      ble: connected,
      stepOf: () => 5,
      onResult: (_) {},
    );
    await tester.pumpWidget(
        _wrap(_screen(), connected, GpsService(), scheduler: scheduler));
    expect(tester.widget<Slider>(_key('assist-slider')).value, 51);

    scheduler.step(1);
    scheduler.step(1);
    await tester.pump(const Duration(milliseconds: 600));
    scheduler.step(1); // 重置 1 秒窗口，三次按键合并为一次
    await tester.pump();
    expect(tester.widget<Slider>(_key('assist-slider')).value, 66);
    expect(connected.requestedPercents, isEmpty, reason: '防抖窗口内不应下发任何指令');

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(connected.requestedPercents, [66]);
    expect(scheduler.previewPercent, isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    scheduler.dispose();
    connected.dispose();
  });

  testWidgets('闪控主键取消待发调速并立即停止助力', (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble)..manual = true;
    final scheduler = AssistRemoteScheduler(
      ble: connected,
      stepOf: () => 5,
      onResult: (_) {},
    );
    await tester.pumpWidget(
        _wrap(_screen(), connected, GpsService(), scheduler: scheduler));

    scheduler.step(1);
    await tester.pump();
    expect(scheduler.previewPercent, 56);

    await scheduler.stop();
    await tester.pump();
    expect(connected.stopCalls, 1);
    expect(connected.requestedPercents, isEmpty);
    expect(scheduler.previewPercent, isNull);

    await tester.pump(const Duration(seconds: 2));
    expect(connected.requestedPercents, isEmpty, reason: '停止后不应再补发调速指令');
    expect(tester.widget<Slider>(_key('assist-slider')).value, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    scheduler.dispose();
    connected.dispose();
  });

  testWidgets('未连接时进入纯码表模式，隐藏助力卡并显示连接助力器入口', (tester) async {
    var opened = 0;
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    await tester.pumpWidget(_wrap(
      _screen(onOpenDevices: () => opened++),
      ble,
      GpsService(),
    ));

    // 分水岭：未连接 → 纯码表模式，助力卡与传感器行隐藏。
    expect(find.text('未连接控制器'), findsNothing);
    expect(find.text('去连接'), findsNothing);
    expect(_key('demo-badge'), findsNothing);
    // 记录主场与轻量连接入口可见
    expect(find.text('开始骑行'), findsOneWidget);
    expect(find.text('连接助力器'), findsOneWidget);
    await tester.tap(find.text('连接助力器'));
    await tester.pump();
    expect(opened, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏 360×560 不溢出，三列副表同行且大里程不截断', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 18.2;
    ble.bikeData.speedAvailable = true;
    ble.bikeData.tripDistance = 123.4;
    ble.bikeData.tripAvailable = true;
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 360, height: 560, child: DashboardScreen()),
          ),
        ),
      ),
      connected,
      GpsService(),
    ));

    expect(tester.takeException(), isNull);
    // 表盘页极简模式已收起 AVG/MAX/km 一排；左滑切到数字页再验证三列副表布局。
    await tester.drag(find.byKey(const ValueKey('speed-gauge-page')),
        const Offset(-160, 0));
    await tester.pumpAndSettle();
    final avgY = tester.getCenter(_key('sub-tag-AVG')).dy;
    for (final tag in ['MAX', 'km']) {
      expect((tester.getCenter(_key('sub-tag-$tag')).dy - avgY).abs(),
          lessThan(2));
    }
    // 123.4 必须扩展为 3 位整数，不能被截成 23.4。
    expect(_segment(tester, 'sub-value-km').text, '123.4');
    expect(_segment(tester, 'sub-value-km').integerDigits, 3);
    expect(_segment(tester, 'sub-value-km').semanticsLabel, '123.4 km');
    expect(find.text('骑行时间'), findsNothing);
    expect(_key('ride-time'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('演示模式开启且未连接时，首页各分区填充循环演示数据', (tester) async {
    final demo = DemoModeSettings();
    await demo.setEnabled(true);
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    // 注入可推进的时钟，让循环数据在一屏内稳定复现并可验证档位切换。
    var now = DateTime(2026, 11, 15, 10);
    await tester.pumpWidget(
        _wrap(_screen(demoClock: () => now), ble, GpsService(), demo: demo));

    expect(_key('demo-badge'), findsNothing);
    expect(find.text('演示数据'), findsNothing);

    final speed = double.parse(_segment(tester, 'primary-speed').text!);
    expect(tester.widget<Text>(_key('gauge-speed-readout')).data,
        speed.toStringAsFixed(1));
    expect(speed, greaterThan(21.0));
    expect(speed, lessThan(27.0));
    expect(_segment(tester, 'sub-value-AVG').text, '18.6');
    expect(_segment(tester, 'sub-value-MAX').text, '36.8');
    expect(_segment(tester, 'sub-value-km').text, '12.7');
    expect(_segment(tester, 'sub-value-km').semanticsLabel, '12.7 km');
    // 演示骑行时间已移到顶部状态栏，首页不再显示。
    expect(_key('ride-time'), findsNothing);
    // 坡度改由手机 GPS 指示，演示模式下首页也不再展示陀螺仪卡与坡度值。
    expect(_key('gyro-card'), findsNothing);
    expect(find.byKey(const ValueKey('slope-bar')), findsNothing);

    // 电量 / 电压 / 温度取当前时刻的循环值，并按同一档位规则上色。
    void expectSensorsAt(DateTime t) {
      final battery = DemoRideData.batteryAt(t);
      final temp = DemoRideData.temperatureAt(t);
      expect(find.text('$battery%'), findsOneWidget,
          reason: '${t.second} 秒的电量');
      expect(find.text(DemoRideData.voltageAt(t).toStringAsFixed(1)),
          findsOneWidget);
      expect(find.text(temp.toStringAsFixed(1)), findsOneWidget);
      expect(_textColor(tester, 'battery-percent'),
          SensorStatus.batteryColor(battery));
      expect(_textColor(tester, 'battery-voltage'),
          SensorStatus.batteryColor(battery));
      expect(_textColor(tester, 'temperature-value'),
          SensorStatus.temperatureColor(temp));
      expect(
          find.text(SensorStatus.temperatureBandLabel(temp)), findsOneWidget);
      expect(
        tester
            .widget<FractionallySizedBox>(find.descendant(
              of: _key('battery-bar'),
              matching: find.byType(FractionallySizedBox),
            ))
            .widthFactor,
        battery / 100,
      );
    }

    expectSensorsAt(now);

    // 时间推进后电量和温度同步变化，配色与进度条跟着切换（循环预览效果）。
    now = now.add(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
        DemoRideData.batteryAt(now),
        isNot(
            DemoRideData.batteryAt(now.subtract(const Duration(seconds: 6)))));
    expectSensorsAt(now);

    expect(find.text('助力控制'), findsOneWidget);
    expect(find.text('未连接控制器'), findsNothing);
    expect(_key('assist-slider'), findsOneWidget);
    expect(find.textContaining('不会下发指令'), findsOneWidget);
    expect(
        find.descendant(
          of: _key('speed-number-page'),
          matching: find.textContaining('km/h'),
        ),
        findsNothing,
      );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('运行中切换演示开关，首页即时在真实与演示数据间切换', (tester) async {
    final demo = DemoModeSettings();
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    await tester.pumpWidget(_wrap(_screen(), ble, GpsService(), demo: demo));

    expect(_key('demo-badge'), findsNothing);
    expect(_segment(tester, 'primary-speed').text, isNull);

    await demo.setEnabled(true);
    await tester.pump();
    expect(_key('demo-badge'), findsNothing);
    expect(_segment(tester, 'primary-speed').text, isNotNull);

    await demo.setEnabled(false);
    await tester.pump();
    expect(_key('demo-badge'), findsNothing);
    expect(_segment(tester, 'primary-speed').text, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('演示开关开启但已连接控制器时，仍显示真实数据', (tester) async {
    final demo = DemoModeSettings();
    await demo.setEnabled(true);
    final ble = BleService();
    ble.bikeData.speed = 12.3;
    ble.bikeData.speedAvailable = true;
    ble.bikeData.tripDistance = 1.5;
    ble.bikeData.tripAvailable = true;
    final connected = _ConnectedBleService(ble);
    await tester
        .pumpWidget(_wrap(_screen(), connected, GpsService(), demo: demo));

    expect(_key('demo-badge'), findsNothing);
    expect(_segment(tester, 'primary-speed').text, '12.3');
    expect(_segment(tester, 'sub-value-km').text, '1.5');
    expect(_key('ride-time'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
    ble.bikeData.clearReadOnlyAvailability();
  });

  testWidgets('演示模式下助力加减只改本地数值，不下发任何指令', (tester) async {
    final demo = DemoModeSettings();
    await demo.setEnabled(true);
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    await tester.pumpWidget(_wrap(_screen(), ble, GpsService(), demo: demo));

    expect(tester.widget<Slider>(_key('assist-slider')).value,
        DemoRideData.assistPercent.toDouble());
    await tester.tap(_key('assist-plus'));
    await tester.pump();
    expect(tester.widget<Slider>(_key('assist-slider')).value,
        (DemoRideData.assistPercent + 5).toDouble());
    await tester.tap(_key('assist-minus'));
    await tester.pump();
    expect(tester.widget<Slider>(_key('assist-slider')).value,
        DemoRideData.assistPercent.toDouble());
    expect(find.text('未连接设备'), findsNothing);
    expect(find.text('去连接'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('未连接设备（含演示模式）时副码表隐藏，切换开关不生效', (tester) async {
    final demo = DemoModeSettings();
    await demo.setEnabled(true);
    final gps = _TestGpsService();
    await tester.pumpWidget(_wrap(_screen(), BleService(), gps, demo: demo));

    // 演示模式设备未连接：副码表强制隐藏，即便「副速度对比」开关打开。
    expect(_key('secondary-speed'), findsNothing);
    gps.setCompare(true);
    await tester.pump();
    expect(_key('secondary-speed'), findsNothing);
    // 主速度仍为 GPS 来源图标（未连接强制 GPS），不显示蓝牙来源图标。
    expect(_key('primary-icon-gps'), findsOneWidget);
    expect(_key('primary-icon-bluetooth'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('未连接设备时主速度强制取 GPS，副码表隐藏且切换入口不可用',
      (tester) async {
    final ble = BleService();
    final gps = _TestGpsService()..setCompare(true);
    // 设备未连接，即使服务来源设为蓝牙、且有蓝牙速度数据。
    ble.bikeData.speed = 33.3;
    ble.bikeData.speedAvailable = true;
    gps.useGpsPrimary(12.5);
    await tester.pumpWidget(_wrap(_screen(), ble, gps));
    await tester.pump();

    // 主速度取自 GPS（12.5），而非蓝牙的 33.3。
    expect(_segment(tester, 'primary-speed').text, '12.5');
    // 来源角标为 GPS，副码表隐藏，来源切换入口也不存在。
    expect(_key('primary-icon-gps'), findsOneWidget);
    expect(_key('secondary-speed'), findsNothing);
    expect(_key('compare-speed-pill'), findsNothing);
    expect(gps.source, SpeedSource.gps);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('未连控制器时不再重复显示闪控状态（已移到顶部状态栏）', (tester) async {
    await tester.pumpWidget(_wrap(
      _screen(),
      BleService(),
      GpsService(),
      remote: _FakeRemote(connected: true),
    ));
    expect(find.text('闪控已连接'), findsNothing);
    expect(_key('remote-status-prompt'), findsNothing);
    expect(_key('remote-glyph'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('闪控上/下键会让控制面板对应的加减按钮显示按下效果', (tester) async {
    final ble = BleService();
    final connected = _ConnectedBleService(ble);
    final scheduler = AssistRemoteScheduler(
      ble: connected,
      stepOf: () => 5,
      onResult: (_) {},
    );
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService(),
        scheduler: scheduler));

    Color buttonColor(String key) {
      final box = tester.widget<AnimatedContainer>(find
          .descendant(
              of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedContainer))
          .first);
      return (box.decoration! as BoxDecoration).color!;
    }

    final normal = buttonColor('assist-plus');
    expect(normal, isNot(DashColors.orange));

    // 闪控上键 → 加号按钮高亮。
    scheduler.step(1);
    await tester.pump();
    expect(buttonColor('assist-plus'), DashColors.orange.withValues(alpha: 0.9));
    expect(buttonColor('assist-minus'), isNot(DashColors.orange));

    // 闪控下键 → 减号按钮高亮。
    scheduler.step(-1);
    await tester.pump();
    expect(buttonColor('assist-minus'), DashColors.orange.withValues(alpha: 0.9));
    expect(buttonColor('assist-plus'), isNot(DashColors.orange));

    scheduler.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('传感器区只保留电量/温度两卡，陀螺仪坡度条已移除', (tester) async {
    // 即便设备上报了陀螺仪数据，首页也不再展示坡度条与陀螺仪卡。
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.slope = -12;
    ble.bikeData.gyroAngleAvailable = true;
    await tester.pumpWidget(
        _wrap(_screen(), _ConnectedBleService(ble), GpsService()));

    expect(_key('battery-card'), findsOneWidget);
    expect(_key('temperature-card'), findsOneWidget);
    expect(_key('gyro-card'), findsNothing);
    expect(find.byKey(const ValueKey('slope-bar')), findsNothing);
    expect(find.text('陀螺仪'), findsNothing);
    expect(find.text('-12.0'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('速度区默认显示扇形指针表盘，来源由语义标签表达', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 42.0;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    // 默认表盘页不透明、数字页透明，但两者都在树中（旧测试/key 不受影响）。
    expect(find.byKey(const ValueKey('speed-gauge-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('speed-number-page')), findsOneWidget);
    final gaugeOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('speed-gauge-page')));
    final numberOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('speed-number-page')));
    expect(gaugeOpacity.opacity, 1.0);
    expect(numberOpacity.opacity, 0.0);

    // 设计稿已去掉盘面中心来源图标；来源改由语义标签表达。
    expect(find.byKey(const ValueKey('needle-speedometer')), findsOneWidget);
    Semantics gaugeSemantics = tester.widget<Semantics>(
        find.ancestor(of: find.byKey(const ValueKey('needle-speedometer')),
            matching: find.byType(Semantics)).first);
    expect(gaugeSemantics.properties.label, contains('来源蓝牙'));

    // 表盘页极简模式：副速度 pill 淡出、AVG/MAX/km 一排收起（高度 0）。
    final gps = _TestGpsService()..setCompare(true);
    await tester.pumpWidget(_wrap(_screen(), connected, gps));
    final pillOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
            of: _key('compare-speed-pill'),
            matching: find.byType(AnimatedOpacity)).first);
    expect(pillOpacity.opacity, 0.0);
    expect(tester.getSize(_key('sub-table-row')).height, 0.0);

    // 左滑切到数字页：pill 恢复、AVG/MAX/km 一排恢复原高度。
    await tester.drag(
        find.byKey(const ValueKey('speed-gauge-page')), const Offset(-160, 0));
    await tester.pumpAndSettle();
    final pillOpacityNum = tester.widget<AnimatedOpacity>(
        find.ancestor(
            of: _key('compare-speed-pill'),
            matching: find.byType(AnimatedOpacity)).first);
    expect(pillOpacityNum.opacity, 1.0);
    expect(tester.getSize(_key('sub-table-row')).height, greaterThan(0));

    // 数字页点 pill 切换为 GPS 后，表盘语义标签同步为 GPS。
    await tester.tap(_key('compare-speed-pill'));
    await tester.pumpAndSettle();
    expect(gps.source, SpeedSource.gps);
    Semantics gpsSemantics = tester.widget<Semantics>(
        find.ancestor(of: find.byKey(const ValueKey('needle-speedometer')),
            matching: find.byType(Semantics)).first);
    expect(gpsSemantics.properties.label, contains('来源GPS'));

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  test('指针动画进度在低速演示区间仍为正值且角度各不相同', () {
    // 演示速度约 22~27 km/h：曾因混入 -135° 偏移得到负进度，指针卡在正上方。
    for (final v in [0.0, 22.0, 24.0, 27.0, 60.0]) {
      final p = NeedleSpeedometer.progressFor(v);
      expect(p, greaterThanOrEqualTo(0.0));
      expect(p, lessThanOrEqualTo(1.0));
    }
    // 演示波动必须映射到不同角度，指针才会随之扫动。
    expect(NeedleSpeedometer.radiansFor(NeedleSpeedometer.progressFor(22.0)),
        isNot(closeTo(NeedleSpeedometer.radiansFor(
            NeedleSpeedometer.progressFor(27.0)), 0.01)));
    // 端点：-135° 与 +135°。
    expect(NeedleSpeedometer.radiansFor(0.0), closeTo(-135 * 3.141592653589793 / 180, 1e-6));
    expect(NeedleSpeedometer.radiansFor(1.0), closeTo(135 * 3.141592653589793 / 180, 1e-6));
  });

  test('路纹滚动速率跟随车速：0 速为 0，越快越急', () {
    // 速度为 0（进度 0）时路面完全静止。
    expect(NeedleSpeedometer.roadCyclesPerSec(0.0), 0.0);
    // 满速约 0.9 圈/秒。
    expect(NeedleSpeedometer.roadCyclesPerSec(1.0), closeTo(0.9, 1e-9));
    // 随速度单调递增。
    expect(
      NeedleSpeedometer.roadCyclesPerSec(0.5),
      greaterThan(NeedleSpeedometer.roadCyclesPerSec(0.25)),
    );
    // 用 0 速换算仍是 0：里程/速度都为 0 时不会误动。
    expect(
      NeedleSpeedometer.roadCyclesPerSec(
          NeedleSpeedometer.progressFor(0.0)),
      0.0,
    );
  });

  test('AVG/MAX 标线进度会夹到量程且忽略 0 / 空值', () {
    expect(NeedleSpeedometer.markerProgress(null), isNull);
    expect(NeedleSpeedometer.markerProgress(0), isNull);
    expect(NeedleSpeedometer.markerProgress(-5), isNull);
    expect(NeedleSpeedometer.markerProgress(72), closeTo(1.0, 1e-6));
    expect(NeedleSpeedometer.markerProgress(18.6), closeTo(18.6 / 60, 1e-6));
  });

  testWidgets('表盘 AVG/MAX 标线值写入语义标签，无效值不写入', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: NeedleSpeedometer(
            speed: 24,
            useGps: false,
            avgSpeed: 18.6,
            peakSpeed: 36.8,
          ),
        ),
      ),
    ));
    Semantics sem = tester.widget<Semantics>(find.ancestor(
        of: find.byKey(const ValueKey('needle-speedometer')),
        matching: find.byType(Semantics)).first);
    expect(sem.properties.label, contains('来源蓝牙'));
    expect(sem.properties.label, contains('平均速度18.6'));
    expect(sem.properties.label, contains('最高速度36.8'));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: NeedleSpeedometer(
            speed: 24,
            useGps: true,
            avgSpeed: 0,
            peakSpeed: null,
          ),
        ),
      ),
    ));
    sem = tester.widget<Semantics>(find.ancestor(
        of: find.byKey(const ValueKey('needle-speedometer')),
        matching: find.byType(Semantics)).first);
    expect(sem.properties.label, contains('来源GPS'));
    expect(sem.properties.label, isNot(contains('平均速度')));
    expect(sem.properties.label, isNot(contains('最高速度')));
  });

  testWidgets('速度区左右滑动在表盘与数字视图间切换', (tester) async {
    final ble = BleService();
    ble.bikeData.clearReadOnlyAvailability();
    ble.bikeData.speed = 30.0;
    ble.bikeData.speedAvailable = true;
    final connected = _ConnectedBleService(ble);
    await tester.pumpWidget(_wrap(_screen(), connected, GpsService()));

    final gauge = find.byKey(const ValueKey('speed-gauge-page'));
    expect(tester.widget<AnimatedOpacity>(gauge).opacity, 1.0);

    // 向左滑：切到数字视图
    await tester.drag(gauge, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(gauge).opacity, 0.0);
    expect(
        tester
            .widget<AnimatedOpacity>(
                find.byKey(const ValueKey('speed-number-page')))
            .opacity,
        1.0);

    // 连续向左滑也能绕回表盘。
    await tester.drag(gauge, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(gauge).opacity, 1.0);

    await tester.drag(gauge, const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(gauge).opacity, 0.0);

    await tester.drag(gauge, const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(gauge).opacity, 1.0);

    await tester.pumpWidget(const SizedBox.shrink());
    connected.dispose();
  });

  testWidgets('闪控左右键按下循环切换码表，抬起不翻页', (tester) async {
    final remote = Br80Service(onAssistStep: (_) async {});
    await tester.pumpWidget(
        _wrap(_screen(), BleService(), GpsService(), remote: remote));

    final gauge = find.byKey(const ValueKey('speed-gauge-page'));
    double opacity() => tester.widget<AnimatedOpacity>(gauge).opacity;
    expect(opacity(), 1);

    for (final code in [0x07, 0x08]) {
      remote.handleKeyFrame([code]);
      await tester.pump();
      expect(opacity(), 0);
      remote.handleKeyFrame([code + 0x20]);
      await tester.pump();
      expect(opacity(), 0);
      remote.handleKeyFrame([code]);
      await tester.pump();
      expect(opacity(), 1);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    remote.dispose();
  });
}
