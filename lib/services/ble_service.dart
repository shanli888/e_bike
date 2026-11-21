import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/assist_mode.dart';
import '../models/bike_data.dart';
import '../models/command_result.dart';
import '../models/device_settings.dart';
import '../models/frame_log.dart';
import 'ble_commands.dart';
import 'ble_constants.dart';
import 'br80_protocol.dart';
import 'local_wheel_settings.dart';
import 'remembered_device.dart';
import 'lvbu_protocol.dart';
import 'lvbu_mode.dart';
import 'lvbu_read_only.dart';
import 'status_probe.dart';
import 'wepower_protocol.dart';

/// BLE 蓝牙管理器 - 核心服务
class BleService extends ChangeNotifier {
  // 单例
  static final BleService _instance = BleService._internal();
  bool _disposed = false;
  factory BleService() => _instance;
  BleService._internal();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // 蓝牙适配器状态
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  BluetoothAdapterState get adapterState => _adapterState;

  final RememberedDeviceStore _rememberedStore = RememberedDeviceStore();
  RememberedDevice? _lastDevice;
  RememberedDevice? get lastDevice => _lastDevice;
  AssistMode? _cachedAssistMode;
  AssistMode? get cachedAssistMode => _cachedAssistMode;
  bool _autoConnectPending = false;
  bool _initialScanPending = false;

  // 设备列表
  final List<ScanResult> _devices = [];
  List<ScanResult> get devices => List.unmodifiable(_devices);

  // 最近一次扫描的原始结果（用于切换过滤条件时立即重算）
  List<ScanResult> _lastScanResults = const [];

  // 当前连接的设备
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // 连接状态
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  // 是否显示全部蓝牙设备（默认只显示名称命中码表前缀的设备）
  bool _showAllDevices = false;
  bool get showAllDevices => _showAllDevices;

  /// 切换"显示全部设备"，并立即用已有扫描结果重新过滤
  void setShowAllDevices(bool value) {
    if (_showAllDevices == value) return;
    _showAllDevices = value;
    _filterScanResults(_lastScanResults);
  }

  // GATT 服务
  BluetoothService? _mainService;
  BluetoothService? _batteryService;
  BluetoothService? _deviceInfoService;
  BluetoothService? _cscService;
  final List<BluetoothService> _allServices = [];

  // 特征
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  BluetoothCharacteristic? _ctrlChar;

  // 私有服务里所有可通知的特征（用于监听观察设备实际推送）
  final List<BluetoothCharacteristic> _privateNotifyChars = [];
  final List<StreamSubscription<List<int>>> _privateNotifySubs = [];

  // 嗅探模式：订阅所有服务里的可通知特征，原始字节全部录制，不解析
  bool _sniffMode = false;
  bool get sniffMode => _sniffMode;
  final List<StreamSubscription<List<int>>> _sniffSubs = [];
  int _sniffSeq = 0;

  // 探测/回包关联：任意私有通知到来时喂给这个 completer
  Completer<List<int>>? _notifyProbe;
  bool _lvbuProbeRunning = false;
  DateTime? _modeRetryAfter;
  bool _modeOutcomeUncertain = false;
  bool _modeWriteStarted = false;
  bool _modeWriteRunning = false;
  bool _manualWriteRunning = false;
  bool _lvbuReplyGuard = false;
  Timer? _lvbuReplyGuardTimer;
  LvbuReadOnlyPoller? _lvbuPoller;
  final Map<LvbuReadCommand, DateTime> _lvbuLastSuccess = {};
  final Set<LvbuReadCommand> _lvbuFailures = {};

  /// 停止助力等「安全动作」正在抢占链路：只读轮询暂时让路。
  bool _assistPriorityWrite = false;

  /// A5 助力写入的冷却时间点：只用来挡住连续狂刷，不再长时间堵死链路。
  DateTime? _assistWriteCooldownAt;

  /// 停止助力最多等待链路空闲多久（只读查询 / 上一次写入结束后即可发送）。
  static const Duration _priorityWaitBudget = Duration(seconds: 8);
  static const Duration _assistWriteCooldown = Duration(milliseconds: 1500);

  bool get lvbuProbeRunning => _lvbuProbeRunning;
  bool _statusProbeRunning = false;
  bool _statusProbeCancelled = false;
  bool get statusProbeRunning => _statusProbeRunning;

  bool _protectLvbuIdentity(String source) =>
      _lvbuProbeRunning ||
      _lvbuReplyGuard ||
      (_isConnected && (source == 'ffe1' || source.endsWith('/ffe1')));

  /// 记录一条设备通知（供嗅探与探测共用）
  void _recordNotify(String sourceTag, List<int> data) {
    if (data.isEmpty) return;
    if (_protectLvbuIdentity(sourceTag)) return; // FFE1 回复可能分片并包含 IMEI。
    _sniffSeq++;
    _addLog(FrameLog(
      time: DateTime.now(),
      outgoing: false,
      data: List<int>.from(data),
      source: '嗅探#$_sniffSeq·$sourceTag (${data.length}字节)',
    ));
    // 若正在等待探测回包，投递给它
    final p = _notifyProbe;
    if (p != null && !p.isCompleted) p.complete(List<int>.from(data));
  }

  /// 连接后自动常驻嗅探（不需要手动开），确保任何回包都被记录
  Future<void> enableAlwaysOnSniff() async {
    if (_sniffMode) return;
    await setSniffMode(true);
  }

  /// 开启/关闭全特征嗅探。开启后任何 notify/indicate 都会原样记进日志。
  Future<void> setSniffMode(bool on) async {
    if (_sniffMode == on) return;
    _sniffMode = on;
    if (on) {
      await _startSniff();
    } else {
      await _stopSniff();
    }
    notifyListeners();
  }

  Future<void> _startSniff() async {
    for (final svc in _allServices) {
      final su = UuidUtil.normalize(svc.serviceUuid);
      for (final c in svc.characteristics) {
        if (!(c.properties.notify || c.properties.indicate)) continue;
        final cu = UuidUtil.normalize(c.characteristicUuid);
        try {
          await c.setNotifyValue(true);
          final sub = c.onValueReceived.listen((data) {
            _recordNotify('$su/$cu', data);
          });
          _sniffSubs.add(sub);
        } catch (_) {}
      }
    }
    debugPrint('嗅探模式已开启，订阅 ${_sniffSubs.length} 个通知特征');
  }

  Future<void> _stopSniff() async {
    for (final s in _sniffSubs) {
      s.cancel();
    }
    _sniffSubs.clear();
    debugPrint('嗅探模式已关闭');
  }

  /// 是否已发现主数据服务 FFE0
  bool get hasMainService => _mainService != null;

  /// 是否存在独立的控制命令通道 FFE2
  bool get hasCtrlChannel => _ctrlChar != null;

  /// 当前下发命令用的特征（短 UUID）
  String get writeCharLabel =>
      _shortUuid(_writeChar?.characteristicUuid.toString());

  /// 当前接收通知的特征（短 UUID）
  String get notifyCharLabel =>
      _shortUuid(_notifyChar?.characteristicUuid.toString());

  // 协议调试日志（最近 300 条）
  final List<FrameLog> _logs = [];
  List<FrameLog> get logs => List.unmodifiable(_logs);

  void _addLog(FrameLog entry) {
    _logs.add(entry);
    if (_logs.length > 300) {
      _logs.removeRange(0, _logs.length - 300);
    }
    notifyListeners();
  }

  /// 清空调试日志
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  // 骑行数据
  final BikeData _bikeData = BikeData();
  final Stopwatch _speedClock = Stopwatch()..start();
  static const Duration _lvbuVoltageFreshness = Duration(seconds: 45);

  void _clearLvbuVoltage() {
    _lvbuVoltageTimer?.cancel();
    _lvbuPoller?.stop();
    _lvbuPoller = null;
    _lvbuLastSuccess.clear();
    _lvbuFailures.clear();
    _lvbuReplyGuardTimer?.cancel();
    _lvbuReplyGuard = _lvbuProbeRunning;
    _bikeData.clearReadOnlyAvailability();
    // 助力控制默认按「手动」展示；每次重新连接仍回到这个本地默认值。
    _assistMode = AssistMode.manual;
    _assistModeConfirmed = false;
    _assistPercentConfirmed = false;
    _assistPercent = 51;
    // 连上后等电量与速度都读到，再下发一次手动模式，保证设备侧与界面一致。
    _manualModeSyncPending = true;
    if (_modeWriteRunning && _modeWriteStarted) _modeOutcomeUncertain = true;
  }

  BikeData get bikeData => _bikeData;

  // 设备设置
  final DeviceSettings _deviceSettings = DeviceSettings();
  DeviceSettings get deviceSettings => _deviceSettings;

  /// 本地 CSC 轮径设置，不下发电机。
  final LocalWheelSettings localWheel = LocalWheelSettings();

  // 助力状态只在收到匹配确认后更新。
  int _assistLevel = 0;
  int get assistLevel => _assistLevel;

  /// 本地默认按手动模式展示（设备无离线模式查询，未确认也先显示手动）。
  AssistMode _assistMode = AssistMode.manual;
  AssistMode get assistMode => _assistMode;
  bool _assistModeConfirmed = false;
  bool get assistModeConfirmed => _assistModeConfirmed;
  String get assistModeStatus => _assistModeConfirmed
      ? '${_assistMode.label} · 本次设置已确认'
      : '${_assistMode.label}（默认）';

  /// 连接成功后是否等待「读到电量 + 速度」再下发一次手动模式。
  bool _manualModeSyncPending = false;

  /// 默认位置仅供选择，不代表设备的当前百分比。
  int _assistPercent = 51;
  int get assistPercent => _assistPercent;
  bool _assistPercentConfirmed = false;
  bool get assistPercentConfirmed => _assistPercentConfirmed;

  // 信号强度历史
  final List<int> _rssiHistory = [];
  List<int> get rssiHistory => List.unmodifiable(_rssiHistory);

  // Stream 订阅
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<int>>? _cscSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  // 数据缓冲
  final List<int> _dataBuffer = [];

  // 等待设备回包的指令（命令字 -> Completer）
  final Map<int, Completer<bool>> _pending = {};

  // CSC 累计值（用于计算瞬时速度/里程）
  int? _lastWheelRevs;
  int? _lastWheelTime; // 1/1024 秒

  // 计时器
  Timer? _rssiTimer;
  Timer? _dataTimer;
  Timer? _lvbuVoltageTimer;
  Timer? _batteryPollTimer;
  StreamSubscription<List<int>>? _batteryNotifySub;

  /// 初始化蓝牙
  Future<void> init() async {
    unawaited(localWheel.load());
    // 监听适配器状态
    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (state == BluetoothAdapterState.off) {
        _clearLvbuVoltage();
        _isConnected = false;
        _connectedDevice = null;
      }
      notifyListeners();
      if (state == BluetoothAdapterState.on && _initialScanPending) {
        _initialScanPending = false;
        unawaited(startScan());
      }
    });

    // 扫描结果只订阅一次，避免每次 startScan 都叠加一个监听器
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);

    // 扫描状态（超时自动结束后 UI 也能正确复位）
    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (_isScanning != scanning) {
        _isScanning = scanning;
        notifyListeners();
      }
    });

    _lastDevice = await _rememberedStore.loadDevice();
    if (_lastDevice != null) {
      try {
        _cachedAssistMode = await _rememberedStore.loadMode(_lastDevice!.id);
      } catch (_) {}
    }
    if (_disposed) return;
    notifyListeners();
    // 首次启动自动扫描；仅自动连接扫描中出现的上次设备。
    _initialScanPending = true;
    _autoConnectPending = _lastDevice != null;
    if (await _requestPermissions()) {
      if (await readAdapterState() == BluetoothAdapterState.on) {
        _initialScanPending = false;
        await startScan();
      }
    }
  }

  /// 扫描结果更新
  void _onScanResults(List<ScanResult> results) {
    _filterScanResults(results);
    final last = _lastDevice;
    if (!_autoConnectPending || last == null || _isConnected || _isConnecting) {
      return;
    }
    for (final result in results) {
      if (result.device.remoteId.str == last.id) {
        _autoConnectPending = false;
        unawaited(() async {
          await stopScan();
          await connect(result.device);
        }());
        break;
      }
    }
  }

  /// 过滤扫描结果：只保留名称匹配的码表设备（可切换为显示全部）
  void _filterScanResults(List<ScanResult> results) {
    _lastScanResults = List<ScanResult>.unmodifiable(results);
    _devices.clear();
    final seen = <String>{};
    for (var r in results) {
      final name = r.device.platformName;
      // H5 用广播里的 A2A0 service UUID 发现闪控：广播名可能为空或不叫 BlingRemote
      final isRemote = Br80Protocol.matchesScan(
        name: name,
        advertisedUuids: r.advertisementData.serviceUuids,
      );
      if (name.isEmpty && !isRemote) continue;
      if (!_showAllDevices) {
        final upper = name.toUpperCase();
        final matched = BleConstants.deviceNamePrefixes
            .any((prefix) => upper.contains(prefix.toUpperCase()));
        if (!matched && !isRemote) continue;
      }
      if (seen.add(r.device.remoteId.str)) {
        _devices.add(r);
      }
    }
    // 信号强的排前面
    _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
    notifyListeners();
  }

  /// 请求蓝牙和位置权限
  ///
  /// Android 12+ 只需要 BLUETOOTH_SCAN / BLUETOOTH_CONNECT；
  /// Android 11 及以下扫描 BLE 还依赖定位权限，所以两种都请求，
  /// 只要满足其中一套就认为可以扫描。
  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) return true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scan = statuses[Permission.bluetoothScan];
    final connect = statuses[Permission.bluetoothConnect];
    final location = statuses[Permission.locationWhenInUse];

    final hasScan = scan?.isGranted ?? false;
    final hasConnect = connect?.isGranted ?? false;
    final hasLocation = location?.isGranted ?? false;

    debugPrint('权限: scan=$scan connect=$connect location=$location');

    // Android 12+: scan + connect；Android 11-: scan/connect 会自动授予，或退回定位权限
    return (hasScan && hasConnect) || hasLocation;
  }

  /// 读取系统实时蓝牙状态（缓存值在启动瞬间可能还是 unknown）
  Future<BluetoothAdapterState> readAdapterState() async {
    try {
      return await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 2), onTimeout: () => _adapterState);
    } catch (_) {
      return _adapterState;
    }
  }

  /// 开始扫描设备，返回是否成功启动
  Future<bool> startScan() async {
    if (_isScanning) return true;
    if (_lastDevice != null && !_isConnected && !_isConnecting) {
      _autoConnectPending = true;
    }

    final state = await readAdapterState();
    if (state == BluetoothAdapterState.off) {
      return false;
    }

    final granted = await _requestPermissions();
    if (!granted) {
      debugPrint('权限未授予');
      return false;
    }

    _devices.clear();
    _lastScanResults = const [];
    _isScanning = true;
    notifyListeners();

    try {
      await FlutterBluePlus.startScan(
        timeout: BleConstants.scanTimeout,
        androidUsesFineLocation: true,
      );
      return true;
    } catch (e) {
      debugPrint('扫描失败: $e');
      _isScanning = false;
      notifyListeners();
      return false;
    }
  }

  /// 停止扫描
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  /// 连接设备
  Future<bool> connect(BluetoothDevice device) async {
    if (_isConnecting || _isConnected) return false;

    _autoConnectPending = false;
    _clearLvbuVoltage();
    _isConnecting = true;
    notifyListeners();

    // 以下广播信息仅供诊断；此前 2A04 协议判断来自错误 APK。
    final matchingScans = _lastScanResults.where(
      (result) => result.device.remoteId == device.remoteId,
    );
    if (matchingScans.isEmpty) {
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: '广播协议线索: 未找到该设备的扫描数据，无法判断'));
    } else {
      final scan = matchingScans.first;
      final serviceKeys = scan.advertisementData.serviceData.keys
          .map(UuidUtil.normalize)
          .toList()
        ..sort();
      final marker = serviceKeys.contains('2a04');
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source:
              '广播 serviceData UUID: ${serviceKeys.isEmpty ? "无" : serviceKeys.join(", ")}'));
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source:
              '广播 2A04 标记: ${marker ? "存在" : "未发现"}；旧 APK 的协议判断已作废，不等同于 GATT 特征'));
    }

    try {
      await device.connect(timeout: BleConstants.connectTimeout);
      _connectedDevice = device;
      _isConnected = true;
      _isConnecting = false;

      // 监听连接状态
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _clearLvbuVoltage();
          _isConnected = false;
          _connectedDevice = null;
          notifyListeners();
        }
      });

      // 请求较大 MTU；设备可能仍只支持 23，长帧需要按实际 MTU 分片。
      try {
        final mtu = await device.requestMtu(517);
        debugPrint('MTU 协商结果: $mtu');
        _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: 'MTU 协商: $mtu',
        ));
      } catch (e) {
        debugPrint('MTU 协商失败: $e');
      }
      if (Platform.isAndroid) {
        try {
          await device.requestConnectionPriority(
              connectionPriorityRequest: ConnectionPriority.high);
        } catch (_) {}
      }

      // 发现服务
      await _discoverServices();

      // 订阅通知
      await _subscribeNotifications();

      // 连接后自动常驻嗅探，确保任何回包都被记录（便于协议探测）
      await enableAlwaysOnSniff();

      // 开始定期读取 RSSI
      _startRssiTimer();

      // 查询设备信息
      await _queryDeviceInfo();

      if (!_isConnected || _connectedDevice != device) return false;
      _lastDevice = RememberedDevice(
        id: device.remoteId.str,
        name: device.platformName.isEmpty ? '蓝牙设备' : device.platformName,
        connectedAt: DateTime.now(),
      );
      try {
        await _rememberedStore.saveDevice(_lastDevice!);
        _cachedAssistMode =
            await _rememberedStore.loadMode(device.remoteId.str);
      } catch (_) {}
      // 原厂源码中的只读命令串行轮询；除电压外仍待设备验证。
      _startLvbuReadOnlyPolling(device);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('连接失败: $e');
      _isConnecting = false;
      _isConnected = false;
      _connectedDevice = null;
      notifyListeners();
      return false;
    }
  }

  /// 重新发现 GATT 服务并选择通信特征（用于调试）
  Future<void> rediscoverServices() async {
    final device = _connectedDevice;
    if (device == null ||
        !_isConnected ||
        _lvbuProbeRunning ||
        _manualWriteRunning) {
      return;
    }
    _lvbuPoller?.stop();
    _manualWriteRunning = true;
    try {
      debugPrint('[调试] 重新发现服务...');
      await _discoverServices();
      await _subscribeNotifications();
      debugPrint('[调试] 服务发现完成');
    } finally {
      _manualWriteRunning = false;
      if (_isConnected && _connectedDevice == device) {
        _startLvbuReadOnlyPolling(device);
      }
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_statusProbeRunning) _statusProbeCancelled = true;
    _rssiTimer?.cancel();
    _dataTimer?.cancel();
    _clearLvbuVoltage();
    _batteryPollTimer?.cancel();
    _connectionSub?.cancel();
    _notifySub?.cancel();
    _cscSub?.cancel();
    _batteryNotifySub?.cancel();
    _notifySub = null;
    _cscSub = null;
    _batteryNotifySub = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
    }

    _isConnected = false;
    _connectedDevice = null;
    _mainService = null;
    _batteryService = null;
    _deviceInfoService = null;
    _cscService = null;
    _allServices.clear();
    _writeChar = null;
    _notifyChar = null;
    _ctrlChar = null;
    for (final s in _privateNotifySubs) {
      s.cancel();
    }
    _privateNotifySubs.clear();
    _privateNotifyChars.clear();
    for (final s in _sniffSubs) {
      s.cancel();
    }
    _sniffSubs.clear();
    _sniffMode = false;
    _dataBuffer.clear();
    _lastWheelRevs = null;
    _lastWheelTime = null;
    notifyListeners();
  }

  /// 发现 GATT 服务
  Future<void> _discoverServices() async {
    if (_connectedDevice == null) return;
    final services = await _connectedDevice!.discoverServices();
    _allServices
      ..clear()
      ..addAll(services);
    _mainService = null;
    _batteryService = null;
    _deviceInfoService = null;
    _cscService = null;
    _privateNotifyChars.clear();

    for (var svc in services) {
      final uuid = UuidUtil.normalize(svc.serviceUuid);
      debugPrint('发现服务: $uuid');

      if (uuid == 'ffe0') {
        _mainService = svc;
      } else if (uuid == '180f') {
        _batteryService = svc;
      } else if (uuid == '180a') {
        _deviceInfoService = svc;
      } else if (uuid == '1816') {
        _cscService = svc;
      }

      for (var char in svc.characteristics) {
        debugPrint(
            '  特征: ${UuidUtil.normalize(char.characteristicUuid)} (prop: ${char.properties})');
      }
    }

    _pickCharacteristics();
  }

  /// 选择用于通信的读写特征
  ///
  /// 按《蓝牙协议逆向文档》：
  /// - 数据通知走 FFE1（Notify）
  /// - 控制命令写入 FFE2（Write），设备不支持时退回 FFE1
  ///
  /// **关键**：只在自定义服务（FFE0/FFDx/WePower/Aux）里找特征，
  /// 跳过所有 SIG 标准服务（Battery/DeviceInfo/CSC/Power等），避免误选只读特征。
  void _pickCharacteristics() {
    BluetoothCharacteristic? write;
    BluetoothCharacteristic? notify;
    BluetoothCharacteristic? ctrl;

    // 自定义服务 UUID 白名单（全部归一化为短码，避免长/短格式不匹配）
    final customServiceUuids = {
      'ffe0',
      'ffe1',
      'ffe2',
      'ffe3',
      'ff00',
      'ff01',
      'ffd0',
      'ffd1',
      'ffd2',
      'ffd3',
      '3eb685db-65f9-4cf6-a03a-e3ef65729f3d',
      'fdd39ad0-238f-46af-adb4-6c85480369c7',
    };

    for (final svc in _allServices) {
      final su = UuidUtil.normalize(svc.serviceUuid);

      // 跳过 SIG 标准服务（用归一化短码比较，避免长/短格式不匹配）
      if (su == '180f' || su == '180a' || su == '1816' || su == '1818') {
        debugPrint('  [跳过标准服务] $su');
        continue;
      }

      final inWhitelist = customServiceUuids.contains(su);
      debugPrint(inWhitelist ? '  [自定义服务] $su' : '  [未知服务] $su');

      for (final c in svc.characteristics) {
        final cu = UuidUtil.normalize(c.characteristicUuid);
        final props = _describeProperties(c.properties);
        final canWrite =
            c.properties.write || c.properties.writeWithoutResponse;
        final canNotify = c.properties.notify || c.properties.indicate;

        debugPrint('    特征: $cu ($props)');

        // —— 精确匹配文档里的私有通道特征（归一化后比较）——
        if (canNotify && notify == null && cu == 'ffe1') {
          notify = c;
          debugPrint('      -> 选中为通知特征(FFE1)');
        }
        if (canWrite && ctrl == null && cu == 'ffe2') {
          ctrl = c;
          debugPrint('      -> 选中为控制特征(FFE2)');
        }
        if (canWrite && write == null && cu == 'ffe1') {
          write = c;
          debugPrint('      -> 选中为写入特征(FFE1)');
        }

        // 收集所有「私有服务里、可通知」的特征，用于监听观察设备实际推送
        if (inWhitelist && canNotify) {
          if (!_privateNotifyChars.contains(c)) _privateNotifyChars.add(c);
        }
      }
    }

    _ctrlChar = ctrl;
    // 默认优先 FFE1；写入可提交不代表设备已识别或执行命令。
    _writeChar = write ?? ctrl;
    _notifyChar = notify;

    if (_writeChar == null) {
      debugPrint('[警告] 未找到 FFE1/FFE2 私有写特征！该设备可能不使用此协议');
    }
    if (_notifyChar == null) {
      debugPrint('[警告] 未找到 FFE1 私有通知特征！');
    }

    debugPrint(
        '最终: 写=${_writeChar?.characteristicUuid}  通知=${_notifyChar?.characteristicUuid}');

    // 把完整 GATT 树写入调试日志，方便复制导出分析
    _dumpGattTreeToLog();
  }

  /// 特征属性的可读描述
  String _describeProperties(dynamic p) {
    final list = <String>[];
    if (p.read == true) list.add('read');
    if (p.write == true) list.add('write');
    if (p.writeWithoutResponse == true) list.add('writeNoRsp');
    if (p.notify == true) list.add('notify');
    if (p.indicate == true) list.add('indicate');
    return list.isEmpty ? '-' : list.join('/');
  }

  /// 将当前设备的完整 GATT 服务/特征树记录到调试日志（每行一条报文样式）
  void _dumpGattTreeToLog() {
    final now = DateTime.now();
    _addLog(FrameLog(
      time: now,
      outgoing: false,
      data: const [],
      source: '===== GATT 服务树开始 =====',
    ));
    for (final svc in _allServices) {
      final su = UuidUtil.normalize(svc.serviceUuid);
      _addLog(FrameLog(
        time: now,
        outgoing: false,
        data: const [],
        source: '服务 $su (${_isStandardService(su) ? "标准" : "私有"})',
      ));
      for (final c in svc.characteristics) {
        final cu = UuidUtil.normalize(c.characteristicUuid);
        _addLog(FrameLog(
          time: now,
          outgoing: false,
          data: const [],
          source: '  特征 $cu (${_describeProperties(c.properties)})',
        ));
      }
    }
    _addLog(FrameLog(
      time: now,
      outgoing: false,
      data: const [],
      source: '选定: 写=$writeCharLabel 通知=$notifyCharLabel',
    ));
    _addLog(FrameLog(
      time: now,
      outgoing: false,
      data: const [],
      source: '===== GATT 服务树结束 =====',
    ));
  }

  bool _isStandardService(String su) =>
      su == '180f' ||
      su == '180a' ||
      su == '1816' ||
      su == '1818' ||
      su == '1801' ||
      su == '1800';

  /// 订阅数据通知
  Future<void> _subscribeNotifications() async {
    if (_connectedDevice == null) return;

    await _notifySub?.cancel();
    _notifySub = null;
    for (final sub in _privateNotifySubs) {
      await sub.cancel();
    }
    _privateNotifySubs.clear();

    // 1) 厂商私有协议通知（精确匹配到的 FFE1）
    final notify = _notifyChar;
    if (notify != null) {
      try {
        _notifySub = notify.onValueReceived.listen(_handleNotification);
        await notify.setNotifyValue(true);
        _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: false,
            data: const [],
            source:
                '通知订阅成功: ${UuidUtil.normalize(notify.characteristicUuid)}'));
      } catch (e) {
        await _notifySub?.cancel();
        _notifySub = null;
        _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: false,
            data: const [],
            source: '通知订阅失败: $e'));
      }
    }

    // 1b) 监听观察：订阅所有私有服务里的可通知特征，
    //     即使主通道没匹配上，也能记录设备实际在哪个特征推送、推了什么。
    for (final c in _privateNotifyChars) {
      if (identical(c, notify)) continue; // 已单独订阅过
      final cu = UuidUtil.normalize(c.characteristicUuid);
      try {
        final sub = c.onValueReceived.listen((data) {
          _recordNotify(cu, data);
        });
        try {
          await c.setNotifyValue(true);
          _privateNotifySubs.add(sub);
          _addLog(FrameLog(
              time: DateTime.now(),
              outgoing: false,
              data: const [],
              source: '通知订阅成功: $cu'));
        } catch (e) {
          await sub.cancel();
          rethrow;
        }
      } catch (e) {
        _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: false,
            data: const [],
            source: '通知订阅失败 $cu: $e'));
      }
    }

    // 2) 标准 CSC 测量（速度/踏频），设备支持时使用
    for (final c
        in _cscService?.characteristics ?? const <BluetoothCharacteristic>[]) {
      if (UuidUtil.normalize(c.characteristicUuid) != '2a5b') {
        continue;
      }
      try {
        await c.setNotifyValue(true);
        _cscSub = c.onValueReceived.listen(_handleCscMeasurement);
        debugPrint('CSC 订阅成功');
      } catch (e) {
        debugPrint('CSC 订阅失败: $e');
      }
    }

    // 3) 电池电量：优先订阅 notify，同时启动 30s 轮询作为 fallback
    if (_batteryService != null) {
      for (final c in _batteryService!.characteristics) {
        if (UuidUtil.normalize(c.characteristicUuid) != '2a19') {
          continue;
        }
        // 先读一次当前电量
        try {
          final value = await c.read();
          if (value.isNotEmpty && value[0] <= 100) {
            _bikeData.batteryLevel = value[0] & 0xFF;
            _bikeData.batteryLevelAvailable = true;
            _bikeData.batteryLevelEstimated = false;
            debugPrint('初始电量: ${_bikeData.batteryLevel}%');
            _maybeSyncManualMode();
          }
        } catch (_) {}

        // 尝试订阅 notify
        if (c.properties.notify || c.properties.indicate) {
          try {
            await c.setNotifyValue(true);
            _batteryNotifySub = c.onValueReceived.listen((data) {
              if (data.isNotEmpty && data[0] <= 100) {
                _bikeData.batteryLevel = data[0] & 0xFF;
                _bikeData.batteryLevelAvailable = true;
                _bikeData.batteryLevelEstimated = false;
                debugPrint('电量推送: ${_bikeData.batteryLevel}%');
                notifyListeners();
                _maybeSyncManualMode();
              }
            });
            debugPrint('电池电量 notify 订阅成功');
          } catch (e) {
            debugPrint('电池电量 notify 订阅失败: $e');
          }
        }
      }

      // 30s 轮询 fallback（防止设备不支持 notify）
      _batteryPollTimer =
          Timer.periodic(const Duration(seconds: 30), (_) async {
        if (!_isConnected || _batteryService == null) return;
        for (final c in _batteryService!.characteristics) {
          if (UuidUtil.normalize(c.characteristicUuid) == '2a19') {
            try {
              final value = await c.read();
              if (value.isNotEmpty) {
                final level = value[0] & 0xFF;
                if (level <= 100 &&
                    (level != _bikeData.batteryLevel ||
                        !_bikeData.batteryLevelAvailable)) {
                  _bikeData.batteryLevel = level;
                  _bikeData.batteryLevelAvailable = true;
                  _bikeData.batteryLevelEstimated = false;
                  debugPrint('轮询电量: $level%');
                  notifyListeners();
                  _maybeSyncManualMode();
                }
              }
            } catch (_) {}
          }
        }
      });
    }
  }

  /// 处理设备通知数据
  void _handleNotification(List<int> data) {
    if (data.isEmpty || _protectLvbuIdentity('ffe1')) return;

    // 原始报文先入调试日志，方便按真机数据校准协议
    _addLog(FrameLog(
      time: DateTime.now(),
      outgoing: false,
      data: List<int>.from(data),
      source: 'FFE1',
    ));

    _dataBuffer.addAll(data);

    // 尝试解析数据帧（帧格式: 帧头 + 长度 + 命令 + 数据 + 校验）
    while (_dataBuffer.length >= 4) {
      // 查找帧头 (0xAA 0x55 或 0x5A)
      final headerIndex = _dataBuffer.indexWhere((b) => b == 0xAA || b == 0x5A);
      if (headerIndex < 0) break;
      if (headerIndex > 0) {
        _dataBuffer.removeRange(0, headerIndex);
      }

      if (_dataBuffer.length < 4) break;

      // 简单假设: [0xAA, 0x55, len, cmd, ...data..., checksum]
      if (_dataBuffer[0] == 0xAA && _dataBuffer.length > 2) {
        final len = _dataBuffer[2];
        if (_dataBuffer.length < len + 4) break; // 等待完整帧

        final frame = _dataBuffer.sublist(0, len + 4);
        _dataBuffer.removeRange(0, len + 4);

        // 先看是不是某条待确认指令的回包
        _resolvePending(frame);
        _parseDataFrame(frame);
      } else {
        _dataBuffer.removeAt(0); // 跳过无效字节
      }
    }
  }

  /// 解析数据帧并更新 BikeData
  void _parseDataFrame(List<int> frame) {
    if (frame.length < 4) return;

    final payload =
        frame.length > 4 ? frame.sublist(4, frame.length - 1) : <int>[];

    // CSC 测量数据 (Cycling Speed and Cadence)
    // 标准格式: flags(1) + wheel_rev(4) + last_wheel_event(2)
    // 简化: 假设数据直接按固定偏移解析
    try {
      // 根据常见协议解析（需根据实际硬件调整）
      if (payload.length >= 16) {
        _bikeData.batteryLevel = payload[15] & 0xFF; // %
        _bikeData.assistLevel = payload[16] & 0x07; // 0-5
        _assistLevel = _bikeData.assistLevel; // 同步 UI 状态
        _bikeData.assistPower = _bytesToUint16(payload, 17); // W
      }

      if (payload.length >= 21) {
        _bikeData.slope = _bytesToInt16(payload, 19) / 10.0; // 度
        _bikeData.motorPower = _bytesToUint16(payload, 21); // W
      }

      if (payload.length >= 25) {
        _bikeData.motorTemperature = payload[23] - 40; // °C (偏移40)
        _bikeData.controllerTemperature = payload[24] - 40;
      }

      // 电池电压：0.1V 为单位，例如 0x01E2 = 482 -> 48.2V
      // （偏移与单位均为推测，需按真机回包校准）
      if (payload.length >= 27) {
        final rawVoltage = _bytesToUint16(payload, 25);
        if (rawVoltage > 0) _bikeData.voltage = rawVoltage / 10.0;
      }

      // 更新 Rssi
      _bikeData.rssi = _rssiHistory.isNotEmpty ? _rssiHistory.last : -100;
    } catch (e) {
      debugPrint('数据解析错误: $e');
    }

    notifyListeners();
  }

  /// 解析标准 CSC 测量数据（0x2A5B），计算瞬时速度与里程
  ///
  /// flags(1)
  ///   bit0 = 1: 轮圈累计圈数(uint32) + 上次轮圈事件时间(uint16, 1/1024s)
  ///   bit1 = 1: 曲柄累计圈数(uint16) + 上次曲柄事件时间(uint16, 1/1024s)
  ///
  /// 本车没有踏频传感器，曲柄部分只跳过不解析。
  /// CSC 轮圈转数按用户选择的本地轮径乘 π 换算周长。
  void _handleCscMeasurement(List<int> data) {
    if (data.isEmpty) return;

    final flags = data[0];
    var i = 1;

    try {
      if ((flags & 0x01) != 0) {
        if (data.length < i + 6) return;
        final revs = _u32(data, i);
        final time = _u16(data, i + 4);
        i += 6;

        if (_lastWheelRevs != null && _lastWheelTime != null) {
          // 计数器回绕用掩码处理
          final dRev = (revs - _lastWheelRevs!) & 0xFFFFFFFF;
          final dTime = (time - _lastWheelTime!) & 0xFFFF;
          final circumferenceM = localWheel.circumferenceMeters;

          // 合理的两次采样间隔（1/1024s -> 0.1s~10s）
          if (dTime > 100 && dTime < 10240 && dRev < 500) {
            final seconds = dTime / 1024.0;
            final speedKmh = (dRev * circumferenceM) / seconds * 3.6;
            // 有有效的 LVBU 实时速度时，以该来源为准，避免重复累计。
            if (speedKmh >= 0 &&
                speedKmh < 150 &&
                !_lvbuLastSuccess.containsKey(LvbuReadCommand.speed)) {
              _bikeData.recordBluetoothSpeed(speedKmh, _speedClock.elapsed,
                  measurementInterval: Duration(
                      microseconds: (seconds * Duration.microsecondsPerSecond)
                          .round()));
            }
          }
        }

        _lastWheelRevs = revs;
        _lastWheelTime = time;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('CSC 解析错误: $e');
    }
  }

  /// 开始定期读取 RSSI
  void _startRssiTimer() {
    _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_connectedDevice != null && _isConnected) {
        try {
          final rssi = await _connectedDevice!.readRssi();
          _rssiHistory.add(rssi);
          if (_rssiHistory.length > 50) _rssiHistory.removeAt(0);
          _bikeData.rssi = rssi;
          notifyListeners();
        } catch (_) {}
      }
    });
  }

  /// 查询设备信息
  Future<void> _queryDeviceInfo() async {
    if (_deviceInfoService == null) return;

    try {
      for (var char in _deviceInfoService!.characteristics) {
        try {
          final value = await char.read();
          final str = String.fromCharCodes(value);
          debugPrint('设备信息: ${char.characteristicUuid} = $str');

          final uuid = UuidUtil.normalize(char.characteristicUuid);
          if (uuid == '2a29') {
            _deviceSettings.manufacturer = str;
          } else if (uuid == '2a24') {
            _deviceSettings.modelNumber = str;
          } else if (uuid == '2a27') {
            _deviceSettings.hardwareVersion = str;
          } else if (uuid == '2a28') {
            _deviceSettings.firmwareVersion = str;
          } else if (uuid == '2a25') {
            _deviceSettings.serialNumber = str;
          }
        } catch (_) {}
      }

      // 读取电量
      if (_batteryService != null) {
        for (var char in _batteryService!.characteristics) {
          if (UuidUtil.normalize(char.characteristicUuid) == '2a19') {
            try {
              final value = await char.read();
              if (value.isNotEmpty && value[0] <= 100) {
                _bikeData.batteryLevel = value[0];
                _bikeData.batteryLevelAvailable = true;
                _bikeData.batteryLevelEstimated = false;
              }
            } catch (_) {}
          }
        }
      }

      // 把读到的设备信息汇总进调试日志，方便对照
      final di = _deviceSettings;
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '设备信息: 厂商=${di.manufacturer} 型号=${di.modelNumber} '
            '固件=${di.firmwareVersion} 硬件=${di.hardwareVersion} 序列号=${di.serialNumber}',
      ));

      notifyListeners();
    } catch (e) {
      debugPrint('查询设备信息失败: $e');
    }
  }

  /// ========== 设置命令 ==========

  /// 发送原始命令
  Future<bool> sendCommand(List<int> command, {String source = '命令'}) async {
    final target = _writeChar;
    if (target == null) {
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: true,
        data: command,
        source: '$source（无写特征，未发送）',
      ));
      return false;
    }

    // 有些特征只支持「无响应写」，必须按属性选择，否则 Android 会报
    // "The WRITE property is not supported by this BLE characteristic"
    final withoutResponse =
        !target.properties.write && target.properties.writeWithoutResponse;

    try {
      await target.write(command, withoutResponse: withoutResponse);
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: true,
        data: command,
        source: source,
      ));
      return true;
    } catch (e) {
      debugPrint('发送命令失败: $e');
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: true,
        data: command,
        source: '$source（发送失败: $e）',
      ));
      return false;
    }
  }

  /// ===== 调试用：手动指定写入目标特征 / 填充长度 / 写模式 =====

  /// 找到某个短码 UUID 的特征（在已连接设备的所有服务里）
  BluetoothCharacteristic? findCharByShortUuid(String shortUuid) {
    final want = UuidUtil.normalize(shortUuid);
    for (final svc in _allServices) {
      for (final c in svc.characteristics) {
        if (UuidUtil.normalize(c.characteristicUuid) == want) return c;
      }
    }
    return null;
  }

  /// 私有可写特征候选（供调试页下拉选择）
  List<String> get writableCharCandidates {
    final out = <String>[];
    for (final svc in _allServices) {
      for (final c in svc.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          out.add(UuidUtil.normalize(c.characteristicUuid));
        }
      }
    }
    return out.toSet().toList()..sort();
  }

  /// 读取任意特征当前值并记录到日志（调试）
  Future<void> readCharToLog(String shortUuid) async {
    if (_manualWriteRunning || _lvbuProbeRunning) return;
    final c = findCharByShortUuid(shortUuid);
    if (c == null) {
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '读 $shortUuid：特征不存在',
      ));
      return;
    }
    try {
      final value = await c.read();
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: value,
        source: '读 $shortUuid (${value.length}字节)',
      ));
    } catch (e) {
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '读 $shortUuid 失败: $e',
      ));
    }
  }

  /// 高级手动发送：可指定目标特征、是否补零到定长、写模式。
  ///
  /// [charShort] 目标特征短码（如 ffe1/ffe2）；[padLen] >0 时把数据补零到该长度；
  /// [noRsp] 强制用 writeWithoutResponse。用于破解 GATT_INVALID_ATTRIBUTE_LENGTH。
  Future<String?> sendHexAdvanced({
    required String hexText,
    String? charShort,
    int padLen = 0,
    bool noRsp = false,
  }) async {
    if (_lvbuProbeRunning || _manualWriteRunning || _statusProbeRunning) {
      return '正在进行其他蓝牙操作，请稍后再试';
    }
    final cleaned = hexText.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.isEmpty || cleaned.length.isOdd) return '请输入偶数个十六进制字符';
    var bytes = <int>[
      for (var i = 0; i < cleaned.length; i += 2)
        int.parse(cleaned.substring(i, i + 2), radix: 16),
    ];

    if (padLen > 0 && bytes.length < padLen) {
      bytes = [...bytes, ...List<int>.filled(padLen - bytes.length, 0)];
    } else if (padLen > 0 && bytes.length > padLen) {
      return '数据($bytes.length)超过填充长度($padLen)';
    }

    final target =
        charShort != null ? findCharByShortUuid(charShort) : _writeChar;
    if (target == null) return '目标特征不存在或未选中写通道';

    final useNoRsp = noRsp ||
        (!target.properties.write && target.properties.writeWithoutResponse);

    final tag =
        '${charShort ?? writeCharLabel}${padLen > 0 ? '/补$padLen' : ''}${useNoRsp ? '/无应答' : ''}';
    _manualWriteRunning = true;
    try {
      await target.write(bytes, withoutResponse: useNoRsp);
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: true,
        data: bytes,
        source: '手动发送[$tag]',
      ));
      return null;
    } catch (e) {
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: true,
        data: bytes,
        source: '手动发送[$tag] 失败: $e',
      ));
      return '发送失败: $e';
    } finally {
      _manualWriteRunning = false;
    }
  }

  /// 自动扫描写入长度：对目标特征用「有应答写」依次试 4~20 字节的定长包，
  /// 记录每种长度的结果，用于确定设备要求的精确包长（破解 INVALID_ATTRIBUTE_LENGTH）。
  Future<void> scanWriteLength(String hexText, {String? charShort}) async {
    final cleaned = hexText.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.isEmpty || cleaned.length.isOdd) return;
    final base = <int>[
      for (var i = 0; i < cleaned.length; i += 2)
        int.parse(cleaned.substring(i, i + 2), radix: 16),
    ];
    final target =
        charShort != null ? findCharByShortUuid(charShort) : _writeChar;
    if (target == null) return;

    final useNoRsp =
        !target.properties.write && target.properties.writeWithoutResponse;
    bool anySuccess = false;
    _addLog(FrameLog(
      time: DateTime.now(),
      outgoing: false,
      data: const [],
      source:
          '===== 开始扫描写入长度 (${charShort ?? writeCharLabel}, ${useNoRsp ? "无应答" : "有应答"}) =====',
    ));

    for (var len = 4; len <= 20; len++) {
      if (base.length > len) continue; // 基础数据已超该长度则跳过
      final bytes = [...base, ...List<int>.filled(len - base.length, 0)];
      String result;
      try {
        await target.write(bytes, withoutResponse: useNoRsp);
        result = '✓ 成功';
        anySuccess = true;
      } catch (e) {
        final s = e.toString();
        if (s.contains('INVALID_ATTRIBUTE_LENGTH')) {
          result = '✗ 长度非法';
        } else if (s.contains('WRITE_NO_RESPONSE')) {
          result = '✗ 不支持无应答';
        } else {
          result = '✗ ${s.length > 40 ? s.substring(0, 40) : s}';
        }
      }
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: true,
        data: bytes,
        source: '扫描长度 $len -> $result',
      ));
      await Future.delayed(const Duration(milliseconds: 120));
    }

    _addLog(FrameLog(
      time: DateTime.now(),
      outgoing: false,
      data: const [],
      source: '===== 扫描结束 =====',
    ));

    // 若主通道全程「长度非法」，再对 FFE1（无应答写）扫一遍，覆盖另一种私有通道
    if (!anySuccess) {
      final ffe1 = findCharByShortUuid('ffe1');
      if (ffe1 != null && !identical(ffe1, target)) {
        _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: '===== FFE2 全失败，改试 FFE1(无应答) =====',
        ));
        for (var len = 4; len <= 20; len++) {
          if (base.length > len) continue;
          final bytes = [...base, ...List<int>.filled(len - base.length, 0)];
          String result;
          try {
            await ffe1.write(bytes, withoutResponse: true);
            result = '✓ 成功';
            anySuccess = true;
          } catch (e) {
            final s = e.toString();
            result = s.contains('INVALID_ATTRIBUTE_LENGTH')
                ? '✗ 长度非法'
                : '✗ ${s.length > 36 ? s.substring(0, 36) : s}';
          }
          _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: true,
            data: bytes,
            source: 'FFE1 长度 $len -> $result',
          ));
          await Future.delayed(const Duration(milliseconds: 120));
        }
      }
    }

    notifyListeners();
  }

  /// 自动轮询探测：把一批候选命令依次发到 FFE1，逐条等待设备是否回通知。
  ///
  /// 用于在没有 HCI 抓包时，主动"问"出哪条命令能被云轮正确响应。
  /// [candidates] 每项是十六进制字符串；每条发送后最多等 [replyTimeout] 看有无 notify。
  Future<void> autoProbeCommands(
    List<String> candidates, {
    String charShort = 'ffe1',
    Duration replyTimeout = const Duration(milliseconds: 800),
  }) async {
    final target = findCharByShortUuid(charShort);
    if (target == null) {
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '探测失败：找不到 $charShort',
      ));
      return;
    }
    await enableAlwaysOnSniff();

    final useNoRsp =
        !target.properties.write && target.properties.writeWithoutResponse;
    _addLog(FrameLog(
      time: DateTime.now(),
      outgoing: false,
      data: const [],
      source: '===== 开始自动轮询探测 ($charShort, ${candidates.length} 条) =====',
    ));

    for (var i = 0; i < candidates.length; i++) {
      final cleaned = candidates[i].replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (cleaned.isEmpty || cleaned.length.isOdd) continue;
      final bytes = <int>[
        for (var j = 0; j < cleaned.length; j += 2)
          int.parse(cleaned.substring(j, j + 2), radix: 16),
      ];

      // 注册一个回包 completer，发送后等待任意 notify
      _notifyProbe = Completer<List<int>>();
      String sent;
      try {
        await target.write(bytes, withoutResponse: useNoRsp);
        sent = '✓';
      } catch (e) {
        final s = e.toString();
        sent = s.contains('INVALID_ATTRIBUTE_LENGTH') ? '✗长度非法' : '✗写入失败';
      }
      _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: true,
        data: bytes,
        source: '探测[${i + 1}/${candidates.length}] 发送$sent',
      ));

      List<int>? reply;
      try {
        reply = await _notifyProbe!.future.timeout(replyTimeout);
      } catch (_) {
        reply = null;
      } finally {
        _notifyProbe = null;
      }

      if (reply != null) {
        _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: reply,
          source: '★ 探测[${i + 1}] 得到回复 (${reply.length}字节)',
        ));
      } else {
        _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: '探测[${i + 1}] 无回复',
        ));
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }

    _addLog(FrameLog(
      time: DateTime.now(),
      outgoing: false,
      data: const [],
      source: '===== 探测结束（标★的为有回复的命令）=====',
    ));
    notifyListeners();
  }

  /// 停止后不再发送下一片或下一条查询；正在进行的 BLE 写入可能仍会完成。
  void stopStatusProbe() {
    if (!_statusProbeRunning) return;
    _statusProbeCancelled = true;
    _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '状态专项测试: 已请求停止'));
  }

  /// 手动触发、有限次的候选只读查询；设备协议和响应关联仍待实机验证。
  Future<String> runStatusProbe() async {
    if (_statusProbeRunning || _lvbuProbeRunning || _manualWriteRunning) {
      return '已有操作正在运行';
    }
    final device = _connectedDevice;
    if (!_isConnected || device == null) return '请先连接设备';

    final targets = <BluetoothCharacteristic>[];
    for (final id in ['ffe1', 'ffe2']) {
      final target = findCharByShortUuid(id);
      if (target != null &&
          (target.properties.write || target.properties.writeWithoutResponse)) {
        targets.add(target);
      }
    }
    if (targets.isEmpty) return '没有找到 FFE1/FFE2 可写特征';

    _statusProbeRunning = true;
    _statusProbeCancelled = false;
    notifyListeners();
    void log(String message,
        {bool outgoing = false, List<int> data = const []}) {
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: outgoing,
          data: data,
          source: message));
    }

    final streams = <BluetoothCharacteristic>[];
    final subscriptions = <StreamSubscription<List<int>>>[];
    final matchers = <String, StatusResponseMatcher>{};
    Completer<String>? hit;
    try {
      log('===== 状态专项测试开始：仅候选查询，协议未验证 =====');
      for (final c in _privateNotifyChars) {
        if (!(c.properties.notify || c.properties.indicate)) continue;
        final tag =
            '${UuidUtil.normalize(c.serviceUuid)}/${UuidUtil.normalize(c.characteristicUuid)}';
        final sub = c.onValueReceived.listen((data) {
          final currentHit = hit;
          if (data.isEmpty || currentHit == null || currentHit.isCompleted) {
            return;
          }
          log('专项通知[$tag]', data: List<int>.from(data));
          final result = matchers[tag]?.feed(data);
          if (result != null && !currentHit.isCompleted) {
            currentHit.complete('$tag $result');
          }
        });
        subscriptions.add(sub);
        try {
          await c.setNotifyValue(true);
          streams.add(c);
          log('专项通知订阅成功: $tag');
        } catch (e) {
          await sub.cancel();
          subscriptions.remove(sub);
          log('专项通知订阅失败 $tag: $e');
        }
      }
      if (streams.isEmpty) {
        log('专项测试终止：没有成功订阅的私有通知通道');
        return '没有可用通知通道，请复制日志';
      }

      final mtu = device.mtuNow.clamp(23, 517);
      final queries = StatusProbe.queries();
      for (final query in queries) {
        for (final target in targets) {
          final modes = <bool>[
            if (target.properties.writeWithoutResponse) true,
            if (target.properties.write) false,
          ];
          for (final withoutResponse in modes) {
            if (_statusProbeCancelled ||
                !_isConnected ||
                _connectedDevice != device) {
              log('专项测试已停止或连接断开');
              return '测试已停止或设备断开';
            }
            final label =
                UuidUtil.normalize(target.characteristicUuid).toUpperCase();
            final mode = withoutResponse ? '无应答' : '有应答';
            matchers.clear();
            for (final c in streams) {
              final tag =
                  '${UuidUtil.normalize(c.serviceUuid)}/${UuidUtil.normalize(c.characteristicUuid)}';
              matchers[tag] = StatusResponseMatcher(query);
            }
            hit = Completer<String>();
            log('尝试 ${query.name} → $label/$mode，MTU=$mtu');
            try {
              final chunks = WePowerProtocol.splitForMtu(query.frame, mtu);
              for (var i = 0; i < chunks.length; i++) {
                if (_statusProbeCancelled ||
                    !_isConnected ||
                    _connectedDevice != device) {
                  break;
                }
                await target.write(chunks[i], withoutResponse: withoutResponse);
                log('专项写入[$label/$mode ${i + 1}/${chunks.length}]',
                    outgoing: true, data: chunks[i]);
                if (i + 1 < chunks.length) {
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                }
              }
              if (_statusProbeCancelled ||
                  !_isConnected ||
                  _connectedDevice != device) {
                log('专项测试已停止或连接断开');
                return '测试已停止或设备断开';
              }
              final deadline = DateTime.now().add(const Duration(seconds: 2));
              String? result;
              while (!_statusProbeCancelled &&
                  _isConnected &&
                  _connectedDevice == device &&
                  DateTime.now().isBefore(deadline)) {
                result = await Future.any<String?>([
                  hit.future,
                  Future<String?>.delayed(const Duration(milliseconds: 100)),
                ]);
                if (result != null) break;
              }
              if (result != null) {
                log('★ 候选回复 ${query.name} ← $result；尚不能证明与该次请求严格关联');
                return '收到候选数据，请复制日志核对';
              }
              if (_statusProbeCancelled ||
                  !_isConnected ||
                  _connectedDevice != device) {
                log('专项测试已停止或连接断开');
                return '测试已停止或设备断开';
              }
              log('无匹配回复: ${query.name} → $label/$mode');
            } catch (e) {
              log('专项写入失败 $label/$mode: $e');
            } finally {
              hit = null;
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
      }
      log('===== 状态专项测试结束：候选已试完，无匹配数据 =====');
      return '已试完候选，未收到匹配数据';
    } finally {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      _statusProbeRunning = false;
      _statusProbeCancelled = false;
      notifyListeners();
    }
  }

  void _startLvbuReadOnlyPolling(BluetoothDevice device) {
    _lvbuPoller?.stop();
    if (!LvbuProtocol.validImei(LvbuProtocol.motorImei)) {
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: '未配置有效的电机 IMEI，LVBU 查询已停用；请检查本地构建配置'));
      return;
    }
    _lvbuPoller = LvbuReadOnlyPoller(
      canRequest: () =>
          _isConnected &&
          _connectedDevice == device &&
          !_lvbuProbeRunning &&
          !_manualWriteRunning &&
          !_assistPriorityWrite &&
          !_statusProbeRunning,
      request: (command) => _requestLvbuRead(device, command),
      onReply: _applyLvbuReply,
      onFailure: (command, error) {
        if (!_isConnected ||
            _connectedDevice != device ||
            !_lvbuFailures.add(command)) {
          return;
        }
        _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: false,
            data: const [],
            source:
                '${command.code} 只读查询未确认${error is int ? "（状态 $error）" : ""}'));
      },
    )..start();
    _lvbuVoltageTimer?.cancel();
    _lvbuVoltageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isConnected || _connectedDevice != device || _manualWriteRunning) {
        return;
      }
      final now = DateTime.now();
      bool stale(LvbuReadCommand command, Duration limit) {
        final last = _lvbuLastSuccess[command];
        return last != null && now.difference(last) > limit;
      }

      var changed = false;
      if (stale(LvbuReadCommand.voltage, _lvbuVoltageFreshness)) {
        _lvbuLastSuccess.remove(LvbuReadCommand.voltage);
        _bikeData.voltage = 0;
        if (_bikeData.batteryLevelEstimated) {
          _bikeData.batteryLevelAvailable = false;
        }
        changed = true;
      }
      if (stale(LvbuReadCommand.speed, const Duration(seconds: 15))) {
        _lvbuLastSuccess.remove(LvbuReadCommand.speed);
        _bikeData.speedAvailable = false;
        changed = true;
      }
      for (final command in [
        LvbuReadCommand.temperature,
        LvbuReadCommand.gyro,
        LvbuReadCommand.climbing
      ]) {
        if (!stale(command, const Duration(seconds: 75))) continue;
        _lvbuLastSuccess.remove(command);
        switch (command) {
          case LvbuReadCommand.temperature:
            _bikeData.temperatureAvailable = false;
          case LvbuReadCommand.gyro:
            _bikeData.gyroAngleAvailable = false;
          case LvbuReadCommand.climbing:
            _bikeData.climbingAngle = null;
            _bikeData.climbingLevel = null;
          default:
            break;
        }
        changed = true;
      }
      if (changed) notifyListeners();
    });
  }

  Future<LvbuReadReply?> _requestLvbuRead(
      BluetoothDevice device, LvbuReadCommand command) async {
    if (_lvbuProbeRunning ||
        _manualWriteRunning ||
        _assistPriorityWrite ||
        _statusProbeRunning ||
        !_isConnected ||
        _connectedDevice != device) {
      return null;
    }
    BluetoothCharacteristic? target;
    for (final c
        in _mainService?.characteristics ?? const <BluetoothCharacteristic>[]) {
      if (UuidUtil.normalize(c.characteristicUuid) == 'ffe1') {
        target = c;
        break;
      }
    }
    if (target == null ||
        !(target.properties.write || target.properties.writeWithoutResponse) ||
        !(target.properties.notify || target.properties.indicate)) {
      return null;
    }
    _lvbuProbeRunning = true;
    final parser = LvbuReadReplyParser(command, LvbuProtocol.motorImei);
    final reply = Completer<LvbuReadReply>();
    final subscription = target.onValueReceived.listen((data) {
      try {
        final parsed = parser.feed(data);
        if (parsed != null && !reply.isCompleted) reply.complete(parsed);
      } catch (_) {
        // 异常或非法通知不应中断轮询，也不记录包含 IMEI 的数据。
      }
    });
    try {
      await FlutterBluePlus.setLogLevel(LogLevel.none);
      await target.setNotifyValue(true);
      if (_disposed || !_isConnected || _connectedDevice != device) return null;
      _lvbuReplyGuard = true;
      await target.write(LvbuReadOnly.request(command, LvbuProtocol.motorImei),
          withoutResponse: target.properties.writeWithoutResponse);
      try {
        final value = await reply.future.timeout(const Duration(seconds: 5));
        return !_disposed && _isConnected && _connectedDevice == device
            ? value
            : null;
      } on TimeoutException {
        // 留出迟到回包隔离时间，且仅在整条帧完成后才允许下一次请求。
        try {
          await reply.future.timeout(const Duration(seconds: 2));
        } on TimeoutException {/* 无迟到回复 */}
        return null;
      }
    } finally {
      await subscription.cancel();
      _lvbuProbeRunning = false;
      _lvbuReplyGuardTimer?.cancel();
      if (!_disposed && _isConnected && _connectedDevice == device) {
        _lvbuReplyGuardTimer =
            Timer(const Duration(seconds: 10), () => _lvbuReplyGuard = false);
      } else {
        _lvbuReplyGuard = false;
      }
    }
  }

  void _applyLvbuReply(LvbuReadReply reply) {
    final first = !_lvbuLastSuccess.containsKey(reply.command);
    final recovered = _lvbuFailures.remove(reply.command);
    _lvbuLastSuccess[reply.command] = DateTime.now();
    if (first || recovered) {
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: '${reply.command.code} 只读查询收到有效回复（设备标识已隐藏）'));
    }
    switch (reply.command) {
      case LvbuReadCommand.voltage:
        _bikeData.voltage = reply.value!;
        if (!_bikeData.batteryLevelAvailable ||
            _bikeData.batteryLevelEstimated) {
          _bikeData.batteryLevel =
              LvbuReadOnly.estimateBatteryPercent(reply.value!);
          _bikeData.batteryLevelAvailable = true;
          _bikeData.batteryLevelEstimated = true;
        }
      case LvbuReadCommand.speed:
        _bikeData.recordBluetoothSpeed(reply.value!, _speedClock.elapsed,
            measurementInterval: first ? Duration.zero : null);
      case LvbuReadCommand.temperature:
        _bikeData.controllerTemperature = reply.value!;
        _bikeData.temperatureAvailable = true;
      case LvbuReadCommand.trip:
        _bikeData.deviceTripDistance = reply.tripDistanceKm;
      case LvbuReadCommand.gyro:
        _bikeData.slope = reply.value!;
        _bikeData.gyroAngleAvailable = true;
      case LvbuReadCommand.climbing:
        _bikeData.climbingAngle = reply.climbingAngle;
        _bikeData.climbingLevel = reply.climbingLevel;
    }
    notifyListeners();
    _maybeSyncManualMode();
  }

  /// 连上设备后，等电量与码表速度都读到，再下发一次「手动模式」。
  ///
  /// 设备侧没有离线模式查询，只能靠主动下发来对齐；原厂也只在手动模式下
  /// 才接受 A5 助力指令，因此连接完成后先把设备切到手动更稳妥。
  void _maybeSyncManualMode() {
    if (!_manualModeSyncPending) return;
    final batteryReady = _bikeData.batteryLevelAvailable || _bikeData.voltage > 0;
    final speedReady = _bikeData.speedAvailable;
    if (!batteryReady || !speedReady) return;
    _manualModeSyncPending = false;
    unawaited(_syncManualModeOnce());
  }

  /// 下发一次手动模式并记录结果；失败不重试，界面会显示「未确认」。
  Future<void> _syncManualModeOnce() async {
    _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '已读到电量与速度，下发一次手动模式同步'));
    final result = await setAssistMode(AssistMode.manual, priority: true);
    _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '手动模式同步结果：${result.name}'));
  }

  Future<String> queryLvbuVoltage({bool silent = false}) async {
    final device = _connectedDevice;
    if (!_isConnected || device == null) return '请先连接设备';
    if (!LvbuProtocol.validImei(LvbuProtocol.motorImei)) {
      return '未配置有效的电机 IMEI，请检查本地构建配置';
    }
    if (_lvbuProbeRunning || _statusProbeRunning) return '正在读取其他数据，请稍后再试';
    try {
      final reply = await _requestLvbuRead(device, LvbuReadCommand.voltage);
      if (reply == null || reply.status != 1) return '电压查询未收到有效回复';
      _applyLvbuReply(reply);
      if (!silent) {
        _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: false,
            data: const [],
            source: 'C0 电压: ${reply.value!.toStringAsFixed(1)} V（IMEI 已隐藏）'));
      }
      return '收到电压 ${reply.value!.toStringAsFixed(1)} V';
    } catch (_) {
      return '电压查询失败，请检查连接';
    }
  }

  /// 手动触发的实验性只读查询；协议和设备响应仍需实机验证。
  Future<String?> runReadOnlyDiagnostic() async {
    final device = _connectedDevice;
    final target = _writeChar;
    if (!_isConnected || device == null || target == null) {
      return '设备未连接或没有可写通道';
    }

    final mtu = device.mtuNow.clamp(23, 517);
    final noResponse =
        !target.properties.write && target.properties.writeWithoutResponse;
    if (!target.properties.write && !noResponse) return '当前特征不支持写入';
    final label = UuidUtil.normalize(target.characteristicUuid);
    final frame = WePowerProtocol.inquireCommand(['34']);
    final chunks = WePowerProtocol.splitForMtu(frame, mtu);
    _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '实验性只读查询: key=34，写=$label，MTU=$mtu；回复通道和格式均待验证'));
    try {
      for (var i = 0; i < chunks.length; i++) {
        if (!_isConnected || _connectedDevice != device) return '连接已断开，诊断中止';
        await target.write(chunks[i], withoutResponse: noResponse);
        _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: true,
            data: chunks[i],
            source:
                '只读查询[$label ${i + 1}/${chunks.length}${noResponse ? "/无应答" : "/有应答"}]'));
        if (i + 1 < chunks.length) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: '查询写入已提交，不代表设备已接收或执行；请等待原始通知'));
      return null;
    } catch (e) {
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: '只读查询写入失败: $e'));
      return '查询写入失败: $e';
    }
  }

  /// 手动发送十六进制字符串，如 `AA 55 02 01 FE`
  Future<String?> sendHex(String text) async {
    final cleaned = text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.isEmpty || cleaned.length.isOdd) {
      return '请输入偶数个十六进制字符';
    }
    final bytes = <int>[
      for (var i = 0; i < cleaned.length; i += 2)
        int.parse(cleaned.substring(i, i + 2), radix: 16),
    ];
    if (bytes.length > 512) return '单次最多 512 字节';
    final result = await sendCommandAwait(bytes, source: '手动发送');
    return switch (result) {
      CommandResult.ok => null,
      CommandResult.noResponse => '已发送，但设备未回确认',
      CommandResult.notConnected => '未连接设备',
      CommandResult.bluetoothOff => '手机蓝牙未开启',
      _ => '发送失败',
    };
  }

  /// 旧控制指令已停用，避免向设备发送来自错误 APK 的推测命令。
  Future<CommandResult> sendCommandAwait(
    List<int> command, {
    String source = '命令',
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_adapterState == BluetoothAdapterState.off) {
      return CommandResult.bluetoothOff;
    }
    if (!_isConnected) {
      return CommandResult.notConnected;
    }
    // AA 55 控制协议来自错误的原厂包，禁止向车辆发送猜测的控制指令。
    _addLog(FrameLog(
        time: DateTime.now(),
        outgoing: false,
        data: const [],
        source: '$source：旧控制协议已停用，正确原厂协议尚待实机验证'));
    return CommandResult.writeFailed;
  }

  /// 设备回包 → 匹配等待中的指令
  void _resolvePending(List<int> frame) {
    if (frame.length < 4 || _pending.isEmpty) return;

    final cmd = frame[3] & 0xFF;
    final key = _pending.containsKey(cmd) ? cmd : (cmd & 0x7F);
    final completer = _pending.remove(key);
    if (completer == null || completer.isCompleted) return;

    final payload =
        frame.length > 5 ? frame.sublist(4, frame.length - 1) : const <int>[];
    final success =
        payload.isEmpty || payload.first == 0x00 || payload.first == 0x01;
    debugPrint('收到回包 cmd=0x${cmd.toRadixString(16)} success=$success');
    completer.complete(success);
  }

  /// 重启设备
  Future<CommandResult> restartDevice() =>
      sendCommandAwait(BleCommands.restart(), source: '重启设备');

  /// 设置轮胎尺寸
  Future<CommandResult> setTireSize(double inches) async {
    final result = await sendCommandAwait(
      BleCommands.tireSize(inches),
      source:
          '轮胎尺寸 ${inches == inches.roundToDouble() ? inches.toStringAsFixed(0) : inches}″',
    );
    if (result.isOk) {
      _deviceSettings.tireSize = inches;
      _deviceSettings.wheelDiameter = (inches * 25.4).round();
      notifyListeners();
    }
    return result;
  }

  /// 查询陀螺仪状态
  Future<CommandResult> queryGyroStatus() =>
      sendCommandAwait(BleCommands.gyroQuery(), source: '查询陀螺仪');

  /// 原厂 BE 校准；仅匹配设备标识和成功状态才视为确认。
  Future<CommandResult> calibrateGyro() async {
    final device = _connectedDevice;
    if (!_isConnected || device == null) return CommandResult.notConnected;
    if (_manualWriteRunning || _lvbuProbeRunning || _statusProbeRunning) {
      return CommandResult.busy;
    }
    BluetoothCharacteristic? target;
    for (final c
        in _mainService?.characteristics ?? const <BluetoothCharacteristic>[]) {
      if (UuidUtil.normalize(c.characteristicUuid) == 'ffe1') target = c;
    }
    if (target == null ||
        !(target.properties.write || target.properties.writeWithoutResponse) ||
        !(target.properties.notify || target.properties.indicate)) {
      return CommandResult.writeFailed;
    }
    _manualWriteRunning = true;
    final reply = Completer<int>();
    var buffer = '';
    const prefix = 'BEF${LvbuProtocol.motorImei}';
    final sub = target.onValueReceived.listen((data) {
      buffer += LvbuProtocol.toHex(data);
      final index = buffer.indexOf(prefix);
      if (index >= 0 && buffer.length >= index + 20 && !reply.isCompleted) {
        reply.complete(
            int.parse(buffer.substring(index + 18, index + 20), radix: 16));
      } else if (index < 0 && buffer.length > prefix.length) {
        buffer = buffer.substring(buffer.length - prefix.length);
      }
    });
    var started = false;
    try {
      await target.setNotifyValue(true);
      if (!_isConnected || _connectedDevice != device) {
        return CommandResult.notConnected;
      }
      _lvbuReplyGuard = true;
      started = true;
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: true,
          data: const [],
          source: 'BE 陀螺仪校准（设备标识已隐藏）'));
      await target.write(LvbuProtocol.gyroCalibration(LvbuProtocol.motorImei),
          withoutResponse: target.properties.writeWithoutResponse);
      final status = await reply.future.timeout(const Duration(seconds: 5));
      if (!_isConnected || _connectedDevice != device || _disposed) {
        return CommandResult.noResponse;
      }
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: status == 1 ? 'BE 校准收到确认' : 'BE 校准设备返回失败'));
      return status == 1 ? CommandResult.ok : CommandResult.deviceError;
    } on TimeoutException {
      return CommandResult.noResponse;
    } catch (_) {
      return started ? CommandResult.noResponse : CommandResult.writeFailed;
    } finally {
      await sub.cancel();
      if (started && _isConnected && _connectedDevice == device) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      _manualWriteRunning = false;
      _lvbuReplyGuardTimer?.cancel();
      if (!_disposed && _isConnected && _connectedDevice == device) {
        _lvbuReplyGuardTimer =
            Timer(const Duration(seconds: 10), () => _lvbuReplyGuard = false);
      } else {
        _lvbuReplyGuard = false;
      }
      notifyListeners();
    }
  }

  /// 原厂通过 FFE2 写 0x33；写入成功不代表已重启。
  Future<CommandResult> restartLvbuDevice() async {
    final device = _connectedDevice;
    if (!_isConnected || device == null) return CommandResult.notConnected;
    if (_manualWriteRunning || _lvbuProbeRunning || _statusProbeRunning) {
      return CommandResult.busy;
    }
    BluetoothCharacteristic? target;
    for (final c
        in _mainService?.characteristics ?? const <BluetoothCharacteristic>[]) {
      if (UuidUtil.normalize(c.characteristicUuid) == 'ffe2') target = c;
    }
    if (target == null ||
        !(target.properties.write || target.properties.writeWithoutResponse)) {
      return CommandResult.writeFailed;
    }
    _manualWriteRunning = true;
    try {
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: true,
          data: const [0x33],
          source: 'FFE2 重启请求'));
      await target
          .write(const [0x33], withoutResponse: !target.properties.write);
      return CommandResult.noResponse;
    } catch (_) {
      return CommandResult.writeFailed;
    } finally {
      _manualWriteRunning = false;
      notifyListeners();
    }
  }

  /// ========== 助力控制 ==========

  /// 设置助力等级（0 = 关闭助力，1~5 档）
  Future<CommandResult> setAssistLevel(int level) async {
    final target = level.clamp(0, 5);

    final result = await sendCommandAwait(
      BleCommands.assistLevel(target),
      source: '助力等级 $target',
    );
    if (result.isOk) {
      _assistLevel = target;
      _bikeData.assistLevel = target;
      notifyListeners();
    }
    return result;
  }

  /// 上/下一档助力
  Future<CommandResult> stepAssist(int delta) =>
      setAssistLevel(_assistLevel + delta);

  /// 原厂 C4 模式设置；仅状态 01 且返回模式与请求一致才标记已确认。
  /// 无独立蓝牙模式查询；断线或未确认时状态为未知。
  ///
  /// [priority] 为 true 时按「安全动作」处理：跳过冷却与「结果不确定」封锁，
  /// 链路忙时等待其空闲后再发（停止助力的兜底恢复会用到）。
  Future<CommandResult> setAssistMode(AssistMode mode,
      {bool priority = false}) async {
    if (_adapterState == BluetoothAdapterState.off) {
      return CommandResult.bluetoothOff;
    }
    final device = _connectedDevice;
    if (!_isConnected || device == null) return CommandResult.notConnected;
    if (!priority && _modeOutcomeUncertain) return CommandResult.modeUncertain;
    if (priority) {
      _assistPriorityWrite = true;
      if (!await _awaitLinkIdle()) {
        _assistPriorityWrite = false;
        return CommandResult.busy;
      }
    } else if (_lvbuProbeRunning ||
        _manualWriteRunning ||
        _statusProbeRunning ||
        (_modeRetryAfter != null &&
            DateTime.now().isBefore(_modeRetryAfter!))) {
      return CommandResult.busy;
    }
    BluetoothCharacteristic? target;
    for (final c
        in _mainService?.characteristics ?? const <BluetoothCharacteristic>[]) {
      if (UuidUtil.normalize(c.characteristicUuid) == 'ffe1') {
        target = c;
        break;
      }
    }
    if (target == null ||
        !(target.properties.write || target.properties.writeWithoutResponse) ||
        !(target.properties.notify || target.properties.indicate)) {
      return CommandResult.writeFailed;
    }

    // 获取独占写入权；读轮询只跳过该次尝试，不重启设备或自动重发。
    _manualWriteRunning = true;
    _modeWriteRunning = true;
    notifyListeners();
    final parser = LvbuModeReplyParser(LvbuProtocol.motorImei);
    final reply = Completer<LvbuModeReply>();
    final subscription = target.onValueReceived.listen((data) {
      try {
        final parsed = parser.feed(data);
        if (parsed != null && !reply.isCompleted) reply.complete(parsed);
      } catch (_) {
        // 丢弃异常通知，不记录含设备标识的原始数据。
      }
    });
    var writeStarted = false;
    try {
      await FlutterBluePlus.setLogLevel(LogLevel.none);
      await target.setNotifyValue(true);
      if (_disposed || !_isConnected || _connectedDevice != device) {
        return CommandResult.notConnected;
      }
      _lvbuReplyGuard = true;
      writeStarted = true;
      _modeWriteStarted = true;
      // 同一 C4 命令无事务 ID，冷却不能完全排除迟到回复。
      _modeRetryAfter = DateTime.now().add(const Duration(seconds: 5));
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: true,
          data: const [],
          source: 'C4 设置模式 ${mode.label}（设备标识已隐藏）'));
      await target.write(LvbuModeCommand.set(mode, LvbuProtocol.motorImei),
          withoutResponse: target.properties.writeWithoutResponse);
      final result = await reply.future.timeout(const Duration(seconds: 5));
      if (!_isConnected || _connectedDevice != device || _disposed) {
        _assistModeConfirmed = false;
        _modeOutcomeUncertain = true;
        return CommandResult.noResponse;
      }
      if (result.status != 1 || result.mode != mode) {
        _assistModeConfirmed = false;
        _modeOutcomeUncertain = true;
        _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: false,
            data: const [],
            source: 'C4 回复失败或模式不一致，当前模式未知'));
        return CommandResult.deviceError;
      }
      _assistMode = mode;
      _assistModeConfirmed = true;
      _cachedAssistMode = mode;
      try {
        await _rememberedStore.saveMode(device.remoteId.str, mode);
      } catch (_) {}
      _assistPercentConfirmed = false;
      _modeOutcomeUncertain = false;
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: 'C4 收到设备确认：${mode.label}'));
      return CommandResult.ok;
    } on TimeoutException {
      _assistModeConfirmed = false;
      _modeOutcomeUncertain = true;
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: 'C4 未收到确认，设备可能已执行；请勿连续重试'));
      return CommandResult.noResponse;
    } catch (_) {
      if (writeStarted) {
        _assistModeConfirmed = false;
        _modeOutcomeUncertain = true;
      }
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: 'C4 蓝牙写入失败或结果不确定'));
      return writeStarted
          ? CommandResult.noResponse
          : CommandResult.writeFailed;
    } finally {
      await subscription.cancel();
      // 先释放写锁，再等待迟到回复隔离期，避免把链路长时间堵死。
      _manualWriteRunning = false;
      _modeWriteRunning = false;
      _modeWriteStarted = false;
      _assistPriorityWrite = false;
      _lvbuReplyGuardTimer?.cancel();
      if (!_disposed && _isConnected && _connectedDevice == device) {
        _lvbuReplyGuardTimer =
            Timer(const Duration(seconds: 10), () => _lvbuReplyGuard = false);
      } else {
        _lvbuReplyGuard = false;
      }
      if (!_disposed) notifyListeners();
      if (writeStarted && _isConnected && _connectedDevice == device) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
  }

  /// 等待链路空闲：只读查询或上一次写入结束后才算空闲。
  Future<bool> _awaitLinkIdle() async {
    final deadline = DateTime.now().add(_priorityWaitBudget);
    while (_lvbuProbeRunning ||
        _manualWriteRunning ||
        _statusProbeRunning) {
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return true;
  }

  /// 停止助力。
  ///
  /// 原厂 LVBU 3.4.0 全量命令表里**没有独立的「停止助力」命令字**：
  /// 桌面小组件的「停止」（`WindowWidgetProvider.clickStopHelp` → `setHelpProgress(0)`）
  /// 与主 App 里把滑杆拖到 0，走的都是同一条 A5 手动助力通道 ——
  /// `A5F<电机IMEI>00`，即把手动助力百分比设为 0。
  /// 旧版 `BleCommands.assistStop()` 的 AA55 / 0x22 帧来自误用的 APK 推测，
  /// `sendCommandAwait` 已整体停用（只返回 writeFailed），不能再用于实车。
  ///
  /// 停止属于安全动作：按 [setAssistPercent] 的 priority 通道发送，
  /// 会跳过冷却、抢占只读轮询，并在链路忙时等待后重发。
  ///
  /// 原厂只在「手动模式」下才发送 A5，所以设备侧模式不是手动（或未确认）时，
  /// 先下发一次手动模式再发 0%；界面上的模式按钮与状态文案同步跟随。
  Future<CommandResult> stopAssist() async {
    var modeReady = _assistMode == AssistMode.manual && _assistModeConfirmed;
    if (!modeReady) {
      final mode = await setAssistMode(AssistMode.manual, priority: true);
      modeReady = mode.isOk;
    }
    var result = await setAssistPercent(0, priority: true);
    if (result == CommandResult.deviceError && !modeReady) {
      // 设备拒绝了 0%（多半不在手动模式）：再切一次手动后重发。
      final mode = await setAssistMode(AssistMode.manual, priority: true);
      if (mode.isOk) result = await setAssistPercent(0, priority: true);
    }
    if (result.isOk) {
      _assistLevel = 0;
      _bikeData.assistLevel = 0;
      notifyListeners();
    }
    return result;
  }

  /// 手动模式 A5：发送一次，只有状态和返回值都匹配才确认。
  ///
  /// [priority] 为 true 时按「安全动作」处理（停止助力、停止后恢复原助力）：
  /// - 跳过 1.5 秒写入冷却与「上次结果不确定」的封锁；
  /// - 期间暂停只读轮询，避免只读查询抢占链路；
  /// - 链路正忙（只读查询或上一次写入）时等待其结束再发送，
  ///   最多等 [_priorityWaitBudget]，而不是直接放弃。
  Future<CommandResult> setAssistPercent(int percent,
      {bool priority = false}) async {
    if (_adapterState == BluetoothAdapterState.off) {
      return CommandResult.bluetoothOff;
    }
    final device = _connectedDevice;
    if (!_isConnected || device == null) return CommandResult.notConnected;
    // 手动是本地默认模式：未收到 C4 设备确认也允许直接下发 A5，
    // 免去每次连接都要先点一次「手动」。结果不确定时仍然禁止发送。
    if (_assistMode != AssistMode.manual) return CommandResult.modeUncertain;
    if (!priority && _modeOutcomeUncertain) return CommandResult.modeUncertain;
    if (percent < 0 || percent > 99) return CommandResult.writeFailed;

    if (priority) {
      // 抢占链路：只读轮询在本次写入结束前不再发起新查询。
      _assistPriorityWrite = true;
      final deadline = DateTime.now().add(_priorityWaitBudget);
      while (_lvbuProbeRunning ||
          _manualWriteRunning ||
          _statusProbeRunning) {
        if (!DateTime.now().isBefore(deadline)) {
          _assistPriorityWrite = false;
          _addLog(FrameLog(
              time: DateTime.now(),
              outgoing: false,
              data: const [],
              source: '优先级指令等待链路空闲超时，本次未发送'));
          return CommandResult.busy;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } else if (_lvbuProbeRunning ||
        _manualWriteRunning ||
        _statusProbeRunning ||
        (_assistWriteCooldownAt != null &&
            DateTime.now().isBefore(_assistWriteCooldownAt!))) {
      return CommandResult.busy;
    }
    BluetoothCharacteristic? target;
    for (final c
        in _mainService?.characteristics ?? const <BluetoothCharacteristic>[]) {
      if (UuidUtil.normalize(c.characteristicUuid) == 'ffe1') {
        target = c;
        break;
      }
    }
    if (target == null ||
        !(target.properties.write || target.properties.writeWithoutResponse) ||
        !(target.properties.notify || target.properties.indicate)) {
      return CommandResult.writeFailed;
    }

    _manualWriteRunning = true;
    _modeWriteRunning = true;
    notifyListeners();
    final parser = LvbuAssistPercentReplyParser(LvbuProtocol.motorImei);
    final reply = Completer<LvbuAssistPercentReply>();
    final subscription = target.onValueReceived.listen((data) {
      try {
        final parsed = parser.feed(data);
        if (parsed != null && !reply.isCompleted) reply.complete(parsed);
      } catch (_) {}
    });
    var writeStarted = false;
    try {
      await FlutterBluePlus.setLogLevel(LogLevel.none);
      await target.setNotifyValue(true);
      if (_disposed || !_isConnected || _connectedDevice != device) {
        return CommandResult.notConnected;
      }
      _lvbuReplyGuard = true;
      writeStarted = true;
      _modeWriteStarted = true;
      // A5 只做 1.5 秒冷却：既挡住连点狂刷，又不会把停止助力堵在门外。
      // 注意：这 1.5 秒是软件自加的，原厂没有任何「写完要等几秒」的设备侧要求；
      // 设备侧唯一的硬性要求是「同一条命令在途时不要发第二条」。
      // 因此这里不再占用 _modeRetryAfter（那是 C4 模式设置的回包隔离窗口）。
      _assistWriteCooldownAt = DateTime.now().add(_assistWriteCooldown);
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: true,
          data: const [],
          source: 'A5 设置手动助力 $percent%（设备标识已隐藏）'));
      await target.write(
          LvbuAssistPercentCommand.set(percent, LvbuProtocol.motorImei),
          withoutResponse: target.properties.writeWithoutResponse);
      final result = await reply.future.timeout(const Duration(seconds: 5));
      if (!_isConnected || _connectedDevice != device || _disposed) {
        _assistPercentConfirmed = false;
        _modeOutcomeUncertain = true;
        return CommandResult.noResponse;
      }
      if (result.status != 1 || result.percent != percent) {
        _assistPercentConfirmed = false;
        if (result.status == 1 && result.percent != null) {
          // 设备回了成功但数值不同：以设备上报的数值为准。
          _assistPercent = result.percent!;
        }
        // 设备明确拒绝（状态 02）时结果已知，不必封锁后续指令；
        // 只有「没等到回复」才需要封锁。
        if (result.status != 2) _modeOutcomeUncertain = true;
        _addLog(FrameLog(
            time: DateTime.now(),
            outgoing: false,
            data: const [],
            source: 'A5 回复未生效（状态 ${result.status}，数值 ${result.percent ?? "--"}，期望 $percent%），当前百分比未知'));
        return CommandResult.deviceError;
      }
      _assistPercent = percent;
      _assistPercentConfirmed = true;
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: 'A5 收到设备确认：$percent%'));
      return CommandResult.ok;
    } on TimeoutException {
      _assistPercentConfirmed = false;
      _modeOutcomeUncertain = true;
      _addLog(FrameLog(
          time: DateTime.now(),
          outgoing: false,
          data: const [],
          source: 'A5 未收到确认，设备可能已执行；请勿连续重试'));
      return CommandResult.noResponse;
    } catch (_) {
      if (writeStarted) {
        _assistPercentConfirmed = false;
        _modeOutcomeUncertain = true;
      }
      return writeStarted
          ? CommandResult.noResponse
          : CommandResult.writeFailed;
    } finally {
      await subscription.cancel();
      // 先释放写锁，再做短暂的稳定等待：等待期间不再占用链路，
      // 后续指令（包括停止助力）可以立即排队发送。
      _manualWriteRunning = false;
      _modeWriteRunning = false;
      _modeWriteStarted = false;
      _assistPriorityWrite = false;
      _lvbuReplyGuardTimer?.cancel();
      if (!_disposed && _isConnected && _connectedDevice == device) {
        _lvbuReplyGuardTimer =
            Timer(const Duration(seconds: 10), () => _lvbuReplyGuard = false);
      } else {
        _lvbuReplyGuard = false;
      }
      if (!_disposed) notifyListeners();
      if (writeStarted && _isConnected && _connectedDevice == device) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
  }

  /// 手动模式下按步进调整百分比。
  ///
  /// 与停止助力一样按「安全动作」处理：用户直接操作不应被写入冷却挡回去，
  /// 链路忙时等待其空闲后照常下发。
  Future<CommandResult> stepAssistPercent(int delta) =>
      setAssistPercent((_assistPercent + delta).clamp(0, 99), priority: true);

  /// 获取设备信号强度
  Future<int> getRssi() async {
    if (_connectedDevice == null) return -100;
    try {
      return await _connectedDevice!.readRssi();
    } catch (_) {
      return -100;
    }
  }

  /// 启用电池电量通知
  Future<bool> enableBatteryNotify() async {
    if (_batteryService == null || _connectedDevice == null) return false;
    try {
      for (var char in _batteryService!.characteristics) {
        if (char.properties.notify) {
          await char.setNotifyValue(true);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _adapterStateSub?.cancel();
    _isScanningSub?.cancel();
    _scanSub?.cancel();
    _notifySub?.cancel();
    _cscSub?.cancel();
    _connectionSub?.cancel();
    _rssiTimer?.cancel();
    _dataTimer?.cancel();
    _lvbuVoltageTimer?.cancel();
    _lvbuReplyGuardTimer?.cancel();
    _lvbuPoller?.stop();
    localWheel.dispose();
    disconnect();
    super.dispose();
  }
}

// ===== 字节解析辅助函数 =====

/// 完整 UUID 取第一段作为短标识，例如 `0000ffe2-...` -> `FFE2`
String _shortUuid(String? uuid) {
  if (uuid == null || uuid.isEmpty) return '--';
  return uuid.split('-').first.toUpperCase();
}

int _u16(List<int> bytes, int offset) {
  if (offset + 1 >= bytes.length) return 0;
  return (bytes[offset] & 0xFF) | ((bytes[offset + 1] & 0xFF) << 8);
}

int _u32(List<int> bytes, int offset) {
  if (offset + 3 >= bytes.length) return 0;
  return (bytes[offset] & 0xFF) |
      ((bytes[offset + 1] & 0xFF) << 8) |
      ((bytes[offset + 2] & 0xFF) << 16) |
      ((bytes[offset + 3] & 0xFF) << 24);
}

int _bytesToUint16(List<int> bytes, int offset) => _u16(bytes, offset);


int _bytesToInt16(List<int> bytes, int offset) {
  var val = _u16(bytes, offset);
  if (val >= 0x8000) val -= 0x10000;
  return val;
}
