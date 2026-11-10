import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../models/device_settings.dart';
import '../models/command_result.dart';
import '../widgets/app_dialogs.dart';
import '../services/ble_service.dart';
import '../services/gps_service.dart';
import '../services/local_wheel_settings.dart';
import '../widgets/signal_strength_card.dart';
import 'debug_screen.dart';

/// 设置页面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<double> _commonTireSizes = [16, 20, 24, 26, 27.5, 29];



  /// 26.0 -> "26"，27.5 -> "27.5"
  static String _formatTireSize(double size) =>
      size == size.roundToDouble() ? size.toStringAsFixed(0) : size.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Consumer2<BleService, GpsService>(
      builder: (context, ble, gps, _) {
        final settings = ble.deviceSettings;

        return Container(
          color: const Color(0xFF1A1A2E),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 显示设置
              _buildSectionHeader('显示'),
              const SizedBox(height: 12),

              _buildSpeedSourceCard(gps),
              const SizedBox(height: 24),

              // 页面标题
              _buildSectionHeader('设备信息'),
              const SizedBox(height: 12),

              // 设备信号
              _buildSignalCard(ble),
              const SizedBox(height: 24),

              // 设置
              _buildSectionHeader('设备设置'),
              const SizedBox(height: 12),

              // 重启设备
              _buildActionCard(
                icon: Icons.restart_alt,
                title: '重启设备',
                subtitle: ble.isConnected ? '发送原厂重启请求，执行结果需自行确认' : '连接设备后可用',
                color: Colors.red,
                onTap: ble.isConnected ? () => _confirmAction(ble, restart: true) : null,
              ),

              const SizedBox(height: 10),

              // 轮胎尺寸
              _buildTireSizeCard(ble.localWheel),
              const SizedBox(height: 24),

              // 陀螺仪
              _buildSectionHeader('陀螺仪'),
              const SizedBox(height: 12),

              // 陀螺仪状态
              _buildInfoRow(
                icon: Icons.sensors,
                title: '陀螺仪角度',
                value: ble.bikeData.gyroAngleAvailable
                    ? '${ble.bikeData.slope.toStringAsFixed(3)}°' : '--',
                valueColor: Colors.cyan,
              ),

              const SizedBox(height: 8),

              // 校准陀螺仪
              _buildActionCard(
                icon: Icons.tune,
                title: '校准陀螺仪',
                subtitle: ble.isConnected ? '请停车并保持车辆平稳后校准' : '连接设备后可用',
                color: Colors.cyan,
                onTap: ble.isConnected ? () => _confirmAction(ble, restart: false) : null,
              ),

              const SizedBox(height: 10),

              // 查询陀螺仪状态
              _buildActionCard(
                icon: Icons.info_outline,
                title: '陀螺仪自动读取',
                subtitle: '连接后只读查询；校准状态尚未获取',
                color: Colors.blueGrey,
                onTap: null,
              ),

              const SizedBox(height: 24),

              _buildInfoRow(
                icon: Icons.terrain,
                title: '爬坡参数（只读）',
                value: ble.bikeData.climbingAngle == null || ble.bikeData.climbingLevel == null
                    ? '--'
                    : '${ble.bikeData.climbingAngle!.toStringAsFixed(1)}° / ${ble.bikeData.climbingLevel}',
                valueColor: Colors.white70,
              ),
              const SizedBox(height: 24),

              // 协议调试
              _buildSectionHeader('协议调试'),
              const SizedBox(height: 12),

              _buildActionCard(
                icon: Icons.terminal,
                title: '蓝牙调试',
                subtitle: '查看收发原始报文，手动下发十六进制命令',
                color: Colors.teal,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DebugScreen()),
                ),
              ),

              const SizedBox(height: 24),

              // 设备信息
              _buildSectionHeader('设备详情'),
              const SizedBox(height: 12),

              _buildDeviceInfo(ble, settings),

              const SizedBox(height: 24),

              // 关于
              _buildSectionHeader('关于'),
              const SizedBox(height: 12),

              _buildAboutCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }

  /// 速度来源：蓝牙（设备上报）/ GPS（手机定位）
  Widget _buildSpeedSourceCard(GpsService gps) {
    final gpsSelected = gps.source == SpeedSource.gps;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, color: Colors.lightBlueAccent, size: 20),
              const SizedBox(width: 10),
              const Text('速度来源',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const Spacer(),
              Text(
                gpsSelected ? (gps.hasFix ? 'GPS 定位中' : 'GPS 未定位') : '设备上报',
                style: TextStyle(
                  color: gpsSelected
                      ? (gps.hasFix ? Colors.green : Colors.orange)
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<SpeedSource>(
              segments: const [
                ButtonSegment(
                  value: SpeedSource.bluetooth,
                  icon: Icon(Icons.bluetooth, size: 16),
                  label: Text('蓝牙'),
                ),
                ButtonSegment(
                  value: SpeedSource.gps,
                  icon: Icon(Icons.gps_fixed, size: 16),
                  label: Text('GPS'),
                ),
              ],
              selected: {gps.source},
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return selected
                      ? Colors.orange.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.05);
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.7)),
                side: WidgetStatePropertyAll(
                  BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
              ),
              onSelectionChanged: (selection) async {
                final target = selection.first;
                final ok = await gps.setSource(target);
                if (!mounted) return;
                if (!ok) {
                  _toast('GPS 不可用：${gps.status}', error: true);
                } else if (target == SpeedSource.gps) {
                  _toast('已切换为 GPS 测速');
                }
              },
            ),
          ),
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('GPS 副速度对比', style: TextStyle(color: Colors.white70, fontSize: 13)),
            subtitle: const Text('开启后使用手机定位，可能增加耗电', style: TextStyle(color: Colors.white54, fontSize: 11)),
            value: gps.comparisonEnabled,
            onChanged: (enabled) async {
              final ok = await gps.setComparisonEnabled(enabled);
              if (!mounted) return;
              if (enabled && !ok) {
                _toast('GPS 不可用：${gps.status}', error: true);
              }
            },
            ),
          ),
          if (gps.gpsRequested) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    gps.status,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ),
                if (!gps.hasFix)
                  TextButton(
                    onPressed: () async {
                      final ok = await gps.retry();
                      if (!mounted) return;
                      if (!ok) _toast('GPS 不可用：${gps.status}', error: true);
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                    child: const Text('重试定位'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 信号卡片
  Widget _buildSignalCard(BleService ble) {
    return SignalStrengthCard(
      rssi: ble.bikeData.rssi,
      isConnected: ble.isConnected,
    );
  }

  /// 手机本地 CSC 轮径，不是电机设置。
  Widget _buildTireSizeCard(LocalWheelSettings wheel) {
    return ListenableBuilder(
      listenable: wheel,
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.tire_repair, color: Colors.amber, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('本地 CSC 轮径', style: TextStyle(color: Colors.white, fontSize: 15))),
              Text(wheel.loaded ? '${wheel.diameterMm} mm' : '加载中',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            const Text('仅用于手机计算标准 CSC 轮速，不会写入电机；当前 LVBU 速度及 GPS 不受影响。',
                style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _commonTireSizes.map((size) {
                final diameter = LocalWheelSettings.diameterFromInches(size);
                final selected = wheel.loaded && wheel.diameterMm == diameter;
                return ChoiceChip(
                  label: Text('${_formatTireSize(size)}"'),
                  selected: selected,
                  onSelected: !wheel.loaded || wheel.saving ? null : (_) async {
                    final saved = await wheel.setDiameterMm(diameter);
                    if (!context.mounted) return;
                    _toast(saved ? '本地 CSC 轮径已保存，未修改电机' : '本地设置保存失败', error: !saved);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAction(BleService ble, {required bool restart}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(restart ? '重启设备？' : '校准陀螺仪？'),
        content: Text(restart ? '请停车后操作；设备可能断开连接，写入成功不代表已重启。' : '请将车辆停稳并保持水平静止；该操作会改变设备标定。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = restart ? await ble.restartLvbuDevice() : await ble.calibrateGyro();
    if (!mounted) return;
    final message = restart && result == CommandResult.noResponse
        ? '重启结果未确认；设备可能已执行，请勿连续重试。'
        : '${result.title}：${result.message}';
    showAppToast(context, message, error: result.isError, warning: result == CommandResult.noResponse);
  }

  /// 操作卡片
  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  /// 信息行
  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.5), size: 20),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 设备信息
  Widget _buildDeviceInfo(BleService ble, DeviceSettings settings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          _buildInfoLine('设备名称', ble.connectedDevice?.platformName ?? '未连接'),
          _buildDivider(),
          _buildInfoLine('厂商', settings.manufacturer.isNotEmpty ? settings.manufacturer : '--'),
          _buildDivider(),
          _buildInfoLine('型号', settings.modelNumber.isNotEmpty ? settings.modelNumber : '--'),
          _buildDivider(),
          _buildInfoLine('固件版本', settings.firmwareVersion.isNotEmpty ? settings.firmwareVersion : '--'),
          _buildDivider(),
          _buildInfoLine('硬件版本', settings.hardwareVersion.isNotEmpty ? settings.hardwareVersion : '--'),
          _buildDivider(),
          _buildInfoLine('序列号', settings.serialNumber.isNotEmpty ? settings.serialNumber : '--'),
          _buildDivider(),
          _buildInfoLine('电机型号', settings.motorType.isNotEmpty ? settings.motorType : '--'),
          _buildDivider(),
          _buildInfoLine('速度限制', '--（未读取）'),
        ],
      ),
    );
  }

  Widget _buildInfoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(color: Colors.white.withValues(alpha: 0.06), height: 1);
  }

  /// 关于卡片
  Widget _buildAboutCard() {
    return GestureDetector(
      onTap: _showAboutDialog,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.info_outline, color: Colors.orange, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关于', style: TextStyle(color: Colors.white, fontSize: 14)),
                  SizedBox(height: 2),
                  Text('应用简介、版本与更新信息',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  /// 关于弹窗
  Future<void> _showAboutDialog() async {
    String version = '未知';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252540),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.electric_bike, color: Colors.orange, size: 40),
        title: const Text('智能码表',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '基于 Flutter 的 LVBU / WePower 白标电助力控制器离线蓝牙版。\n'
                '纯离线、无登录，支持 BLE 数据和 GPS 测速。模式设置为实验功能，其他助力控制尚未启用。',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 16),
              _buildInfoLine('版本号', version),
              _buildDivider(),
              _buildInfoLine('更新日期', '2026-11-10'),
              _buildDivider(),
              _buildInfoLine('构建环境', 'Flutter 3.47.9 · Dart 3.13.7'),
              _buildDivider(),
              const Text('本次更新',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              const Text(
                '首页显示蓝牙车体倾角，电量卡片突出电压并标注估算电量。',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }
}