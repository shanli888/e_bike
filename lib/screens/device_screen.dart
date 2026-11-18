import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/br80_protocol.dart';
import '../services/br80_service.dart';
import '../services/system_settings.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/remote_glyph.dart';

/// 设备扫描/连接页面
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  BleService? _ble;

  /// 闪控专用扫描：与码表扫描共用蓝牙扫描，但独立发起、独立连接
  bool _remoteScanPending = false;
  Timer? _remoteScanTimer;
  static const Duration _remoteScanWindow = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _ble = context.read<BleService>();
    _ble?.addListener(_onBleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startScan());
    });
  }

  @override
  void dispose() {
    _ble?.removeListener(_onBleChanged);
    _remoteScanTimer?.cancel();
    // 自动扫描独立于页面生命周期，切换页面时继续进行。
    super.dispose();
  }

  /// 扫描期间只挑名字命中的 BR80 闪控（列表已按信号强度降序）
  List<ScanResult> _remoteCandidates(BleService ble) {
    final hits = ble.devices
        .where((r) => Br80Protocol.matchesScan(
              name: r.device.platformName,
              advertisedUuids: r.advertisementData.serviceUuids,
            ))
        .toList();
    // 头盔也会广播 A2A0：名称命中的闪控优先，其次按信号强度
    hits.sort((a, b) {
      final an = Br80Protocol.matchesName(a.device.platformName) ? 0 : 1;
      final bn = Br80Protocol.matchesName(b.device.platformName) ? 0 : 1;
      return an != bn ? an.compareTo(bn) : b.rssi.compareTo(a.rssi);
    });
    return hits;
  }

  /// 闪控专用「扫描并连接」：发现第一个候选就立即连，不占用码表连接
  Future<void> _startRemoteScan() async {
    final ble = _ble;
    if (ble == null || _remoteScanPending) return;
    final remote = context.read<Br80Service>();
    if (remote.isConnected || remote.isConnecting) return;

    setState(() => _remoteScanPending = true);
    final started = await _startScan();
    if (!mounted) return;
    if (!started) {
      _finishRemoteScan();
      return;
    }

    // 复用已有扫描结果：若刚才那一轮已经看到闪控，立即连接
    final existing = _remoteCandidates(ble);
    if (existing.isNotEmpty) {
      _finishRemoteScan();
      await _connectRemote(remote, existing.first.device);
      return;
    }

    _onBleChanged();
    if (!_remoteScanPending) return;
    _remoteScanTimer = Timer(_remoteScanWindow, () {
      if (!mounted || !_remoteScanPending) return;
      _finishRemoteScan();
      unawaited(_showRemoteNotFoundDialog());
    });
  }

  void _onBleChanged() {
    if (!_remoteScanPending || !mounted) return;
    final ble = _ble;
    if (ble == null) return;
    final candidates = _remoteCandidates(ble);
    if (candidates.isEmpty) return;
    _finishRemoteScan();
    final remote = context.read<Br80Service>();
    if (remote.isConnected || remote.isConnecting) return;
    unawaited(_connectRemote(remote, candidates.first.device));
  }

  void _finishRemoteScan() {
    _remoteScanTimer?.cancel();
    _remoteScanTimer = null;
    if (!mounted) return;
    setState(() => _remoteScanPending = false);
  }

  Future<void> _showRemoteNotFoundDialog() async {
    await showAppDialog(
      context,
      title: '未找到闪控',
      message: '请按闪控任意键唤醒，靠近手机后重试；\n确认它没有被其他手机或头盔占用。',
      icon: Icons.gamepad,
      color: Colors.orange,
      primaryLabel: '重新扫描',
      onPrimary: _startRemoteScan,
    );
  }

  /// 开始扫描：蓝牙没开会弹窗引导去开启
  Future<bool> _startScan() async {
    final ble = _ble;
    if (ble == null) return false;

    // 启动瞬间缓存的适配器状态可能是 unknown，这里读系统实时状态
    var state = await ble.readAdapterState();
    if (state == BluetoothAdapterState.off) {
      if (!mounted) return false;
      await _showBluetoothOffDialog();
      if (!mounted) return false;
      state = await ble.readAdapterState();
      if (state == BluetoothAdapterState.off) return false;
    }

    final started = await ble.startScan();
    if (started || !mounted) return started;

    await showAppDialog(
      context,
      title: '无法开始扫描',
      message: '请确认手机蓝牙已开启，并允许本应用使用蓝牙/定位权限。',
      icon: Icons.error_outline,
      color: Colors.red,
      primaryLabel: '去系统设置',
      onPrimary: () async {
        await openAppSettings();
      },
    );
    return false;
  }

  /// 蓝牙未开启弹窗
  Future<void> _showBluetoothOffDialog() async {
    await showAppDialog(
      context,
      title: '蓝牙未开启',
      message: '扫描和连接控制器需要手机蓝牙，请先打开蓝牙。',
      icon: Icons.bluetooth_disabled,
      primaryLabel: '去开启',
      onPrimary: _enableBluetooth,
    );
  }

  /// 尝试打开蓝牙；系统不允许时引导去设置页
  Future<void> _enableBluetooth() async {
    final ble = _ble;
    if (ble == null) return;

    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {
      // 忽略，下面统一判断实际状态
    }
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    final state = await ble.readAdapterState();
    if (!mounted) return;

    if (state == BluetoothAdapterState.off) {
      await showAppDialog(
        context,
        title: '无法自动开启蓝牙',
        message: '部分手机（如华为/荣耀）不允许应用直接打开蓝牙，\n请在系统设置里手动开启后再回来扫描。',
        icon: Icons.settings_bluetooth,
        primaryLabel: '去设置',
        onPrimary: () => SystemSettings.openBluetoothSettings(),
      );
      return;
    }

    await _startScan();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BleService, Br80Service>(
      builder: (context, ble, remote, _) {
        final bluetoothOff = ble.adapterState == BluetoothAdapterState.off;

        return Container(
          color: const Color(0xFF1A1A2E),
          child: Column(
            children: [
              // 闪控独立连接入口（常驻，便于调试）
              _buildRemoteCard(remote),
              // 已连接设备信息
              if (ble.isConnected) _buildConnectedDevice(ble),
              if (!ble.isConnected && ble.lastDevice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: ListTile(
                    leading: const Icon(Icons.history, color: Colors.orange),
                    title: Text(ble.lastDevice!.name),
                    subtitle: Text('上次连接：${ble.lastDevice!.connectedAt.toLocal().toString().substring(0, 19)}'),
                  ),
                ),
              // 蓝牙未开启提示
              if (bluetoothOff) _buildBluetoothOff(ble),
              // 搜索栏
              _buildSearchBar(ble),
              // 设备列表
              Expanded(child: _buildDeviceList(ble)),
            ],
          ),
        );
      },
    );
  }

  /// 蓝牙未开启时的提示条
  Widget _buildBluetoothOff(BleService ble) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('手机蓝牙未开启',
                style: TextStyle(color: Colors.orange, fontSize: 13)),
          ),
          TextButton(
            onPressed: _enableBluetooth,
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('开启蓝牙'),
          ),
        ],
      ),
    );
  }

  /// 闪控（BR80）独立连接卡片：单独扫描/连接/断开，并显示最新按键反馈
  Widget _buildRemoteCard(Br80Service remote) {
    final connected = remote.isConnected;
    final busy = remote.isConnecting || _remoteScanPending;
    final accent = connected ? Colors.green : Colors.orange;
    final name = remote.device?.platformName ?? '';
    final String status;
    if (connected) {
      status = '已连接 · ${name.isEmpty ? 'BR80' : name}'
          ' · 电量 ${remote.battery == null ? '--' : '${remote.battery}%'}';
    } else if (remote.isConnecting) {
      status = '正在连接闪控…';
    } else if (_remoteScanPending) {
      status = '正在扫描闪控…请按任意键唤醒';
    } else {
      status = '未连接 · 可与码表同时连接';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 与设计稿一致的双态闪控图标（连接绿 / 未连接灰）。
              RemoteGlyph(connected: connected, size: 26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('闪控（BR80）',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(status, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          if (!connected && remote.lastError != null) ...[
            const SizedBox(height: 4),
            Text('上次失败：${remote.lastError}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (connected)
                TextButton(
                  onPressed: remote.disconnect,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('断开闪控'),
                )
              else
                ElevatedButton.icon(
                  onPressed: busy ? null : _startRemoteScan,
                  icon: const Icon(Icons.bluetooth_searching, size: 16),
                  label: const Text('扫描并连接'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedDevice(BleService ble) {
    final device = ble.connectedDevice!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.withValues(alpha: 0.2), Colors.green.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.2),
            ),
            child: const Icon(Icons.bluetooth_connected, color: Colors.green, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.platformName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '信号: ${ble.bikeData.rssi} dBm  |  电量: ${ble.bikeData.batteryLevel}%',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => ble.disconnect(),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('断开'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BleService ble) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.white.withValues(alpha: 0.4), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ble.isScanning ? '正在搜索设备...' : '${ble.devices.length} 个设备',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildScanButton(ble),
        ],
      ),
    );
  }

  Widget _buildScanButton(BleService ble) {
    if (ble.isScanning) {
      return SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.withValues(alpha: 0.8)),
        ),
      );
    }

    return GestureDetector(
      onTap: _startScan,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.refresh, color: Colors.orange, size: 22),
      ),
    );
  }

  Widget _buildDeviceList(BleService ble) {
    if (ble.devices.isEmpty) {
      final searching = ble.isScanning;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_searching,
                size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              searching ? '正在搜索附近的码表和闪控…' : '未发现设备',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? '保持设备开机，并将手机靠近设备'
                  : '请确保设备已开机、手机蓝牙已开启且在附近',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
            ),
            if (!searching && !ble.showAllDevices) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => ble.setShowAllDevices(true),
                child: const Text('显示全部蓝牙设备', style: TextStyle(color: Colors.orange)),
              ),
            ],
          ],
        ),
      );
    }

    // 过滤开关作为列表头部一起滚动，避免与列表项重叠
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _buildFilterRow(ble),
        for (final result in ble.devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildDeviceTile(ble, result),
          ),
      ],
    );
  }

  /// 名称过滤开关
  Widget _buildFilterRow(BleService ble) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Text(
            ble.showAllDevices ? '全部蓝牙设备' : '仅显示码表和闪控',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
          ),
          const Spacer(),
          Switch(
            value: ble.showAllDevices,
            activeThumbColor: Colors.orange,
            activeTrackColor: Colors.orange.withValues(alpha: 0.4),
            onChanged: (v) => ble.setShowAllDevices(v),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(BleService ble, ScanResult result) {
    final device = result.device;
    final rssi = result.rssi;
    final remote = context.read<Br80Service>();
    final isRemote = Br80Protocol.matchesScan(
      name: device.platformName,
      advertisedUuids: result.advertisementData.serviceUuids,
    );
    final isThisDevice = isRemote
        ? remote.device?.remoteId == device.remoteId && remote.isConnected
        : ble.connectedDevice?.remoteId == device.remoteId;

    return Container(
      decoration: BoxDecoration(
        color: isThisDevice
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: isThisDevice
            ? Border.all(color: Colors.green.withValues(alpha: 0.3))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isThisDevice
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.orange.withValues(alpha: 0.1),
          ),
          child: Icon(
            Icons.bluetooth,
            color: isThisDevice ? Colors.green : Colors.orange,
            size: 22,
          ),
        ),
        title: Text(
          device.platformName.isEmpty ? '闪控 (BR80)' : device.platformName,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            _buildSmallSignalBars(rssi),
            const SizedBox(width: 6),
            Text(
              '$rssi dBm',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
            ),
          ],
        ),
        trailing: (isRemote ? remote.isConnecting : ble.isConnecting)
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
              )
            : isThisDevice
                ? const Icon(Icons.check_circle, color: Colors.green, size: 24)
                : ElevatedButton(
                    onPressed: () => isRemote
                        ? _connectRemote(remote, device)
                        : _connect(ble, device),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('连接', style: TextStyle(fontSize: 13)),
                  ),
      ),
    );
  }

  Future<void> _connectRemote(Br80Service remote, BluetoothDevice device) async {
    if (remote.isConnected) {
      await showAppDialog(context, title: '闪控已连接', message: '请先断开当前闪控。');
      return;
    }
    final ok = await remote.connect(device);
    if (!mounted || ok) return;
    final reason = remote.lastError;
    await showAppDialog(
      context,
      title: '闪控连接失败',
      message: '${reason == null ? '' : '原因：$reason\n\n'}'
          '请按闪控任意键唤醒，确认它未被其他设备占用后重试。',
      icon: Icons.bluetooth_disabled,
      color: Colors.red,
      primaryLabel: '重试',
      onPrimary: () => _connectRemote(remote, device),
    );
  }

  /// 连接设备：失败时弹窗说明原因并给「重试」
  Future<void> _connect(BleService ble, BluetoothDevice device) async {
    if (ble.adapterState == BluetoothAdapterState.off) {
      await _showBluetoothOffDialog();
      return;
    }

    final name = device.platformName;
    final ok = await ble.connect(device);
    if (!mounted || ok) return;

    // 连接过程可能已被用户取消
    if (ble.isConnected) return;

    await showAppDialog(
      context,
      title: '连接失败',
      message: '无法连接到「$name」。\n请确认设备已开机、在手机附近，'
          '并且没有被其他手机/App 占用后重试。',
      icon: Icons.bluetooth_disabled,
      color: Colors.red,
      primaryLabel: '重试',
      onPrimary: () => _connect(ble, device),
    );
  }

  Widget _buildSmallSignalBars(int rssi) {
    final level = rssi > -65 ? 4 : rssi > -75 ? 3 : rssi > -85 ? 2 : rssi > -95 ? 1 : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        return Container(
          width: 3,
          height: 5.0 + i * 2.5,
          margin: const EdgeInsets.symmetric(horizontal: 0.5),
          decoration: BoxDecoration(
            color: i < level ? Colors.orange : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}