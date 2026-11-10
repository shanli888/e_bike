import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../models/assist_mode.dart';
import '../models/bike_data.dart';
import '../models/command_result.dart';
import '../services/ble_service.dart';
import '../services/gps_service.dart';
import '../widgets/app_dialogs.dart';

/// 主界面 - 码表显示
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onOpenDevices});

  /// 未连接时点「连接设备」跳到设备页（由外层底部导航切换）
  final VoidCallback? onOpenDevices;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _refreshTimer;

  /// 正在等待设备确认的指令说明（非空时禁用助力按钮）
  String? _pendingCommand;
  double? _percentDraft;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BleService, GpsService>(
      builder: (context, ble, gps, _) {
        final data = ble.bikeData;

        return Container(
          color: const Color(0xFF1A1A2E),
          child: SafeArea(
            child: Column(
              children: [
                // 顶部状态栏
                _buildTopBar(ble, data),
                // 速度显示
                _buildSpeedDisplay(ble, gps, data),
                if (ble.isConnected) ...[
                  // 助力控制（模式 / 等级 / 停止）
                  _buildAssistControl(ble, data),
                  // 信息卡片
                  Expanded(child: _buildInfoGrid(data)),
                ] else
                  // 未连接时不显示无意义的四宫格，整屏放连接引导
                  Expanded(child: _buildConnectPrompt(ble)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 顶部状态栏
  Widget _buildTopBar(BleService ble, BikeData data) {
    final bluetoothOff = ble.adapterState == BluetoothAdapterState.off;
    final statusColor = ble.isConnected
        ? Colors.green
        : (bluetoothOff ? Colors.orange : Colors.red);
    final statusText = ble.isConnected
        ? '已连接'
        : (bluetoothOff ? '蓝牙未开启' : '未连接');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 连接状态
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: ble.isConnected
                      ? [BoxShadow(color: Colors.green.withValues(alpha: 0.5), blurRadius: 6)]
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          // 信号强度
          if (ble.isConnected) ...[
            Row(
              children: [
                _buildSignalBars(data.rssi),
                const SizedBox(width: 4),
                Text(
                  '${data.rssi} dBm',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 信号强度指示器
  Widget _buildSignalBars(int rssi) {
    final signalLevel = rssi > -65 ? 4 : rssi > -75 ? 3 : rssi > -85 ? 2 : rssi > -95 ? 1 : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final active = i < signalLevel;
        final color = active
            ? (rssi > -75 ? Colors.green : Colors.orange)
            : Colors.white.withValues(alpha: 0.2);
        return Container(
          width: 5,
          height: 8.0 + i * 4.0,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  /// 速度显示区（速度来源可选：蓝牙 / GPS）
  Widget _buildSpeedDisplay(BleService ble, GpsService gps, BikeData data) {
    final useGps = gps.source == SpeedSource.gps;
    final speedText = useGps
        ? (gps.speedKmh?.toStringAsFixed(1) ?? '--')
        : (data.speedAvailable ? data.speed.toStringAsFixed(1) : '--');
    final avg = useGps ? gps.avgSpeedKmh : data.avgSpeed;
    final max = useGps ? gps.maxSpeedKmh : data.maxSpeed;
    final trip = useGps ? gps.tripKm : data.tripDistance;
    final tripAvailable = useGps || data.tripAvailable;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          // 大字速度：数字居中，单位 + 角标紧贴数字右下角（GPS 在上、km/h 在下）
          SizedBox(
            height: 104,
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                      speedText,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 84,
                        fontWeight: FontWeight.w200,
                        height: 1,
                        letterSpacing: -2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: useGps
                              ? Colors.blue.withValues(alpha: 0.25)
                              : Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          useGps ? 'GPS' : '蓝牙',
                          style: TextStyle(
                            color: useGps ? Colors.lightBlueAccent : Colors.orange,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      const Text(
                        'km/h',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(useGps ? '蓝牙' : 'GPS',
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(
                        useGps
                            ? (data.speedAvailable ? data.speed.toStringAsFixed(1) : '--')
                            : (gps.speedKmh?.toStringAsFixed(1) ?? '--'),
                        key: const ValueKey('secondary-speed'),
                        style: const TextStyle(color: Colors.white70, fontSize: 24),
                      ),
                      Text(!useGps && !gps.comparisonEnabled ? '对比未开启' : 'km/h',
                          style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // 副信息
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMiniInfo('AVG', tripAvailable ? '${avg.toStringAsFixed(1)} km/h' : '--'),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withValues(alpha: 0.15),
                margin: const EdgeInsets.symmetric(horizontal: 24),
              ),
              _buildMiniInfo('MAX', tripAvailable ? '${max.toStringAsFixed(1)} km/h' : '--'),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withValues(alpha: 0.15),
                margin: const EdgeInsets.symmetric(horizontal: 24),
              ),
              _buildMiniInfo('里程', tripAvailable ? '${trip.toStringAsFixed(1)} km' : '--'),
            ],
          ),
        ],
      ),
    );
  }

  /// 小标签信息
  Widget _buildMiniInfo(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }

  /// 助力控制面板：模式 + 等级/百分比 + 停止
  Widget _buildAssistControl(BleService ble, BikeData data) {
    final modeEnabled = ble.isConnected && _pendingCommand == null;
    final manual = ble.assistModeConfirmed && ble.assistMode == AssistMode.manual;
    final connected = manual && modeEnabled;
    final percent = ble.assistPercent;
    final badgeText = ble.assistModeStatus;


    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange.withValues(alpha: 0.16),
            Colors.orange.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              const Icon(Icons.electric_bike, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Text('助力控制',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              if (manual)
                Text(ble.assistPercentConfirmed ? '已确认 ${ble.assistPercent}%' : '百分比未知（默认位置 51%）',
                    style: TextStyle(
                        color: Colors.orange.withValues(alpha: 0.8), fontSize: 10)),
              const Spacer(),
              if (_pendingCommand != null) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),
                const SizedBox(width: 6),
                Text('等待确认',
                    style: TextStyle(
                        color: Colors.orange.withValues(alpha: 0.8), fontSize: 10)),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 助力模式
          _buildModeRow(ble, modeEnabled),
          const SizedBox(height: 10),

          // 等级 / 百分比调节
          _buildControlRow(ble, connected, manual, percent),
        ],
      ),
    );
  }

  /// 手动模式：0~99% 滑块；其余模式的等级控制暂未启用。
  Widget _buildControlRow(
      BleService ble, bool connected, bool manual, int percent) {
    const level = 0; // 当前助力等级未从蓝牙确认，不展示默认状态。

    return Row(
      children: [
        if (manual) ...[
          _buildStepButton(
            icon: Icons.remove,
            enabled: connected && percent > 0,
            onTap: () => _runCommand(ble, () => ble.stepAssistPercent(-5), '助力 -5%'),
          ),
          const SizedBox(width: 6),
          Expanded(child: _buildPercentSlider(ble, connected, percent)),
          const SizedBox(width: 6),
          _buildStepButton(
            icon: Icons.add,
            enabled: connected && percent < 99,
            onTap: () => _runCommand(ble, () => ble.stepAssistPercent(5), '助力 +5%'),
          ),
        ] else ...[
          _buildStepButton(
            icon: Icons.remove,
            enabled: connected && level > 0,
            onTap: () => _runCommand(ble, () => ble.stepAssist(-1), '助力 -1'),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildLevelSegments(ble, connected, level)),
          const SizedBox(width: 8),
          _buildStepButton(
            icon: Icons.add,
            enabled: connected && level < 5,
            onTap: () => _runCommand(ble, () => ble.stepAssist(1), '助力 +1'),
          ),
        ],
      ],
    );
  }

  /// 手动模式百分比滑块（松手才下发，避免拖动过程刷屏）
  Widget _buildPercentSlider(BleService ble, bool connected, int percent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: Colors.orange,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
            thumbColor: Colors.orange,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(
            value: _percentDraft ?? percent.toDouble(),
            min: 0,
            max: 99,
            divisions: 99,
            label: '${(_percentDraft ?? percent.toDouble()).round()}%',
            onChanged: connected ? (value) => setState(() => _percentDraft = value) : null,
            onChangeEnd: connected ? (value) {
              setState(() => _percentDraft = null);
              _runCommand(ble, () => ble.setAssistPercent(value.round()), '手动助力 ${value.round()}%');
            } : null,
          ),
        ),
      ],
    );
  }

  /// 助力模式选择（5 个模式等宽排一行，保证都能看到）
  Widget _buildModeRow(BleService ble, bool connected) {
    return Row(
      children: [
        for (var i = 0; i < AssistMode.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _buildModeChip(ble, connected, AssistMode.values[i])),
        ],
      ],
    );
  }

  Widget _buildModeChip(BleService ble, bool connected, AssistMode mode) {
    final selected = ble.assistModeConfirmed && ble.assistMode == mode;
    return GestureDetector(
      onTap: connected ? () => _runCommand(ble, () => ble.setAssistMode(mode), '模式 ${mode.label}') : null,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: selected ? Colors.orange.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.orange : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(mode.icon,
                size: 13,
                color: Colors.white.withValues(alpha: 0.55)),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                mode.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 五段助力等级，可点按直接选档
  Widget _buildLevelSegments(BleService ble, bool connected, int level) {
    return Row(
      children: List.generate(5, (i) {
        final active = i < level;
        return Expanded(
          child: GestureDetector(
            onTap: connected
                ? () => _runCommand(ble, () => ble.setAssistLevel(i + 1), '助力 ${i + 1} 档')
                : null,
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: active
                    ? Colors.orange.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: active
                      ? Colors.orange
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.1 : 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Colors.white.withValues(alpha: enabled ? 0.85 : 0.2),
        ),
      ),
    );
  }

  /// 执行一条助力指令：等待设备回包确认后再提示结果
  Future<void> _runCommand(
    BleService ble,
    Future<CommandResult> Function() action,
    String label,
  ) async {
    if (!ble.isConnected) {
      await showAppDialog(
        context,
        title: '未连接设备',
        message: '助力控制需要先连接控制器。要现在去连接吗？',
        icon: Icons.bluetooth_disabled,
        primaryLabel: '去连接',
        onPrimary: () => widget.onOpenDevices?.call(),
      );
      return;
    }
    if (_pendingCommand != null) return;

    setState(() => _pendingCommand = label);
    final result = await action();
    if (!mounted) return;
    setState(() => _pendingCommand = null);

    if (result.isError) {
      await showAppDialog(
        context,
        title: result.title,
        message: result.message,
        icon: Icons.error_outline,
        color: Colors.red,
        primaryLabel: result == CommandResult.notConnected ? '去连接' : null,
        onPrimary: () => widget.onOpenDevices?.call(),
      );
      return;
    }

    switch (result) {
      case CommandResult.ok:
        showAppToast(context, '$label · 设备已确认');
      case CommandResult.noResponse:
        showAppToast(context, '$label · 未确认，可能已执行，请核实后再操作', warning: true);
      case CommandResult.deviceError:
        showAppToast(context, '$label · 设备返回失败', error: true);
      default:
        showAppToast(context, '$label · 发送失败', error: true);
    }
  }

  /// 信息卡片网格
  Widget _buildInfoGrid(BikeData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: [
          _buildInfoCard(
            icon: Icons.landscape,
            title: '坡度信息',
            value: data.gyroAngleAvailable ? '${data.slope.toStringAsFixed(1)}°' : '--',
            subValue: data.gyroAngleAvailable ? '蓝牙车体倾角' : '尚未读取',
            color: Colors.cyan,
          ),
          _buildInfoCard(
            icon: Icons.battery_full,
            title: '电量',
            value: data.voltage > 0 ? '${data.voltage.toStringAsFixed(1)} V' : '--',
            subValue: data.batteryLevelAvailable
                ? '${data.batteryLevel}%${data.batteryLevelEstimated ? " · 估算" : ""}'
                : '电量 --',
            color: !data.batteryLevelAvailable
                ? Colors.white70
                : (data.batteryLevel > 20 ? Colors.green : Colors.red),
            extra: data.batteryLevelAvailable ? _buildBatteryBar(data.batteryLevel) : null,
          ),
          _buildInfoCard(
            icon: Icons.thermostat,
            title: '温度',
            value: data.temperatureAvailable
                ? data.controllerTemperature.toStringAsFixed(1)
                : '--',
            subValue: '°C · 控制器',
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  /// 信息卡片
  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    String? subValue,
    required Color color,
    Widget? extra,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subValue != null)
            Text(
              subValue,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
            ),
          if (extra != null) extra,
        ],
      ),
    );
  }

  /// 电量条
  Widget _buildBatteryBar(int level) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: level / 100.0,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation<Color>(
            level > 50
                ? Colors.green
                : level > 20
                    ? Colors.orange
                    : Colors.red,
          ),
          minHeight: 4,
        ),
      ),
    );
  }

  /// 连接提示
  Widget _buildConnectPrompt(BleService ble) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled,
                size: 64, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            const Text('未连接设备',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('请前往设备页面搜索并连接',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: ble.isScanning
                  ? null
                  : () => widget.onOpenDevices?.call(),
              icon: const Icon(Icons.bluetooth_searching, size: 18),
              label: const Text('连接设备'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}