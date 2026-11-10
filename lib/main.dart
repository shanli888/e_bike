import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/gps_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/device_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/app_dialogs.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final bleService = BleService();
  bleService.init();

  final gpsService = GpsService();
  gpsService.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bleService),
        ChangeNotifierProvider.value(value: gpsService),
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
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: const ColorScheme.dark(
          primary: Colors.orange,
          secondary: Colors.orange,
          surface: Color(0xFF1A1A2E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16162A),
          elevation: 0,
          centerTitle: true,
          toolbarHeight: 46,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能码表'),
        actions: [
          Consumer<BleService>(
            builder: (context, ble, _) {
              if (!ble.isConnected) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bluetooth_connected,
                        color: Colors.green, size: 14),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        ble.connectedDevice?.platformName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: switch (_index) {
        0 => DashboardScreen(onOpenDevices: () => _goTo(1)),
        1 => const DeviceScreen(),
        _ => const SettingsScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        height: 62,
        backgroundColor: const Color(0xFF16162A),
        indicatorColor: Colors.orange.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed_outlined, color: Colors.white54),
            selectedIcon: Icon(Icons.speed, color: Colors.orange),
            label: '码表',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_outlined, color: Colors.white54),
            selectedIcon: Icon(Icons.bluetooth, color: Colors.orange),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: Colors.white54),
            selectedIcon: Icon(Icons.settings, color: Colors.orange),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
