import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'screens/dashboard_screen.dart';
import 'screens/device_screen.dart';
import 'screens/ride_history_screen.dart';
import 'screens/settings_screen.dart';
import 'models/demo_ride_data.dart';
import 'services/assist_remote_scheduler.dart';
import 'services/assist_step_settings.dart';
import 'services/ble_service.dart';
import 'services/br80_service.dart';
import 'services/demo_mode_settings.dart';
import 'services/display_mode_settings.dart';
import 'services/gps_service.dart';
import 'services/ride_recorder.dart';
import 'services/ride_repository.dart';
import 'services/ride_time_service.dart';
import 'services/screen_wake_lock.dart';
import 'theme/dashboard_theme.dart';
import 'widgets/app_dialogs.dart';
import 'widgets/display_settings_sheet.dart';
import 'widgets/ride_summary_sheet.dart';
import 'widgets/remote_glyph.dart';
import 'widgets/segment_display.dart';

/// App 回到前台时重新下发屏幕常亮状态，补齐后台期间可能失败的窗口标志。
class _WakeLockLifecycleObserver extends WidgetsBindingObserver {
  _WakeLockLifecycleObserver(this.wakeLock);

  final ScreenWakeLock wakeLock;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(wakeLock.refresh());
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bleService = BleService();
  bleService.init();

  final stepSettings = AssistStepSettings();
  await stepSettings.load();

  final demoSettings = DemoModeSettings();
  await demoSettings.load();

  late final Br80Service remote;
  // 闪控上/下键先本地移动滑杆，1 秒防抖后只下发一次最终值；
  // 主键（home）不参与防抖，立即下发停止助力。
  final assistScheduler = AssistRemoteScheduler(
    ble: bleService,
    stepOf: () => stepSettings.step,
    onResult: (message) => remote.setMessage(message),
    // 调速 / 停止助力命令下发后，不论成功失败都弹一次 toast。
    onToast: (message, {required bool error}) =>
        showGlobalToast(message, error: error),
  );
  remote = Br80Service(
    onAssistStep: (direction) async => assistScheduler.step(direction),
    onStopAssist: () => assistScheduler.stop(),
    // 按键不再弹 toast：闪控上/下键直接映射到首页控制面板的加减按钮，
    // 按下时对应按钮显示按下效果。
  );

  final gpsService = GpsService();
  gpsService.load();

  // 骑行记录：本地文件仓库 + 记录状态机 + 显示形态设置
  final rideRepository = RideRepository();
  final rideRecorder = RideRecorder(rideRepository);
  final displayMode = DisplayModeSettings();
  await displayMode.load();

  // 连接控制器或 BR80 闪控后保持屏幕常亮，全部断开后恢复系统自动熄屏。
  // 两个服务都是 ChangeNotifier，连接/掉线都会通知；setConnected 内部去重。
  final screenWakeLock = ScreenWakeLock();
  void syncWakeLock() => unawaited(screenWakeLock.setConnected(
        bleService.isConnected || remote.isConnected,
      ));
  bleService.addListener(syncWakeLock);
  remote.addListener(syncWakeLock);
  WidgetsBinding.instance
      .addObserver(_WakeLockLifecycleObserver(screenWakeLock));
  syncWakeLock();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bleService),
        ChangeNotifierProvider.value(value: remote),
        ChangeNotifierProvider<AssistRemoteScheduler>.value(
            value: assistScheduler),
        ChangeNotifierProvider.value(value: gpsService),
        ChangeNotifierProvider<AssistStepSettings>.value(value: stepSettings),
        ChangeNotifierProvider<DemoModeSettings>.value(value: demoSettings),
        ChangeNotifierProvider<DisplayModeSettings>.value(value: displayMode),
        Provider<RideRepository>.value(value: rideRepository),
        ChangeNotifierProvider<RideRecorder>.value(value: rideRecorder),
        ChangeNotifierProvider<RideTimeService>(
          create: (ctx) => RideTimeService.fromServices(
            ctx.read<BleService>(),
            ctx.read<GpsService>(),
          ),
        ),
      ],
      child: const BikeComputerApp(),
    ),
  );
}

class BikeComputerApp extends StatelessWidget {
  const BikeComputerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智能码表',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: DashColors.orange,
        scaffoldBackgroundColor: DashColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: DashColors.orange,
          secondary: DashColors.orange,
          surface: DashColors.card,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0C1120),
          elevation: 0,
          centerTitle: false,
          toolbarHeight: 55,
          titleSpacing: 20,
          titleTextStyle: TextStyle(
            color: DashColors.txt,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

/// 三个页面用底部导航切换，把顶部空间留给内容
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;
  bool _showStartupSweep = true;

  /// 状态栏骑行时间数码管的数字高度：比首页那一行小一号，与状态栏字号相称。
  static const double _appBarSegmentHeight = 18.0;

  BleService? _ble;
  bool _wasConnected = false;
  bool? _wasAdapterOff;
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    _ble = context.read<BleService>();
    _ble!.addListener(_onBleChanged);
  }

  @override
  void dispose() {
    _ble?.removeListener(_onBleChanged);
    super.dispose();
  }

  /// 蓝牙被关掉、或已连接的设备掉线时弹窗提醒
  void _onBleChanged() {
    final ble = _ble;
    if (ble == null) return;

    final adapterOff = ble.adapterState == BluetoothAdapterState.off;
    final connected = ble.isConnected;

    if (!_dialogShowing) {
      if (_wasAdapterOff == false && adapterOff && _wasConnected) {
        _alert('蓝牙已关闭', '手机蓝牙被关闭，与设备的连接已断开。\n重新打开蓝牙后请回到「设备」页连接。');
      } else if (_wasConnected && !connected && !adapterOff) {
        _alert('连接已断开', '控制器连接丢失。\n请确认设备已开机且电量充足，靠近后重新连接。');
      }
    }

    _wasConnected = connected;
    _wasAdapterOff = adapterOff;
  }

  void _alert(String title, String message) {
    if (!mounted) return;
    _dialogShowing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _dialogShowing = false;
        return;
      }
      await showAppDialog(
        context,
        title: title,
        message: message,
        icon: Icons.bluetooth_disabled,
        color: Colors.red,
        primaryLabel: '去设备页',
        onPrimary: () => _goTo(1),
      );
      _dialogShowing = false;
    });
  }

  void _goTo(int index) {
    if (index == _index) return;
    setState(() {
      if (_index == 0) _showStartupSweep = false;
      _index = index;
    });
  }

  /// 打开骑行历史（作为独立页面 pushed，不占用底部导航）
  void _openHistory() {
    final repo = context.read<RideRepository>();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RideHistoryScreen(repository: repo)),
    );
  }

  /// 结束骑行：落库后弹汇总层，可从汇总直接进入历史。
  Future<void> _finishRide() async {
    final recorder = context.read<RideRecorder>();
    final ride = await recorder.finish();
    if (ride == null || !mounted) return;
    await showRideSummary(
      context,
      ride: ride,
      onDone: () => Navigator.of(context).pop(),
      onViewHistory: () {
        Navigator.of(context).pop();
        _openHistory();
      },
    );
  }

  /// 开始骑行：失败时用 toast 告知（如未开定位/无权限）
  Future<void> _startRide() async {
    final ok = await context.read<RideRecorder>().start();
    if (!mounted) return;
    final status = context.read<RideRecorder>().status;
    if (!ok) showGlobalToast(status, error: true);
  }

  /// 规格 §2.2：单行标题栏，左侧「连接状态」，右侧「骑行时间／设置」。
  /// 蓝牙图标连接成功时换成 bluetooth_connected，信号图标紧挨其右
  /// （连接绿色、未连接灰色），不再显示 dBm 数值与设备名称标签；
  /// 闪控图标靠左显示，紧跟在信号图标之后。
  /// 演示模式（未连接 + 演示开关打开）按「数据正常」显示绿灯与连接态蓝牙图标。
  Widget _buildAppBarTitle(BleService ble, {required bool demo}) {
    final online = ble.isConnected;
    final signalColor = (online || demo) ? DashColors.green : DashColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          (online || demo) ? Icons.bluetooth_connected : Icons.bluetooth,
          size: 17,
          color: DashColors.sourceBluetooth,
        ),
        const SizedBox(width: 5),
        Icon(Icons.signal_cellular_alt, size: 17, color: signalColor),
        const SizedBox(width: 8),
        // 闪控连接状态图标靠左显示，与蓝牙、信号图标同一组。
        Consumer<Br80Service>(
          builder: (context, remote, _) =>
              RemoteGlyph(connected: remote.isConnected, size: 17),
        ),
      ],
    );
  }

  /// 状态栏右侧的骑行时间：小一号数码管，字号与状态栏其它内容相称。
  Widget _buildRideTimeIndicator(bool demo) {
    final clock = demo
        ? const SegmentClock(
            key: ValueKey('appbar-ride-time'),
            text: DemoRideData.rideTime,
            height: _appBarSegmentHeight,
          )
        : Selector<RideTimeService, (String, bool)>(
            selector: (context, service) => (
              service.display,
              !service.running ||
                  MediaQuery.disableAnimationsOf(context) ||
                  service.elapsed.inSeconds.isOdd,
            ),
            builder: (_, clockState, __) => SegmentClock(
              key: const ValueKey('appbar-ride-time'),
              text: clockState.$1,
              colonLit: clockState.$2,
              height: _appBarSegmentHeight,
            ),
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer_outlined, size: 13, color: DashColors.muted2),
        const SizedBox(width: 4),
        clock,
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onTap,
    Color? background,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        ),
        child: Icon(icon, size: size * 0.55, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Consumer2<BleService, DemoModeSettings>(
            builder: (context, ble, demoSettings, _) {
          final demo = demoSettings.isActive(ble.isConnected);
          return _buildAppBarTitle(ble, demo: demo);
        }),
        actions: [
          Consumer2<BleService, DemoModeSettings>(
            builder: (context, ble, demoSettings, _) {
              final demo = demoSettings.isActive(ble.isConnected);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRideTimeIndicator(demo),
                  const SizedBox(width: 14),
                  _buildCircleButton(
                    icon: Icons.settings_outlined,
                    color: DashColors.muted2,
                    size: 30,
                    onTap: () => showDisplaySettingsSheet(context),
                  ),
                  const SizedBox(width: 20),
                ],
              );
            },
          ),
        ],
      ),
      body: switch (_index) {
        0 => DashboardScreen(
            onOpenDevices: () => _goTo(1),
            onOpenHistory: _openHistory,
            onStartRide: _startRide,
            onFinishRide: _finishRide,
            showStartupSweep: _showStartupSweep,
          ),
        1 => const DeviceScreen(),
        _ => const SettingsScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        height: 66,
        backgroundColor: DashColors.nav,
        indicatorColor: DashColors.orange.withValues(alpha: 0.17),
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed_outlined, color: DashColors.muted, size: 21),
            selectedIcon: Icon(Icons.speed, color: DashColors.orange, size: 21),
            label: '码表',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_outlined,
                color: DashColors.muted, size: 21),
            selectedIcon:
                Icon(Icons.bluetooth, color: DashColors.orange, size: 21),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined,
                color: DashColors.muted, size: 21),
            selectedIcon:
                Icon(Icons.settings, color: DashColors.orange, size: 21),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
