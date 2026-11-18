import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../models/device_settings.dart';
import '../models/command_result.dart';
import '../widgets/app_dialogs.dart';
import '../services/ble_service.dart';
import '../services/local_wheel_settings.dart';
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
  static String _formatTireSize(double size) => size == size.roundToDouble()
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, ble, _) {
        final settings = ble.deviceSettings;

        return Container(
          color: const Color(0xFF1A1A2E),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 设置
              _buildSectionHeader('设备设置'),
              const SizedBox(height: 12),

              // 重启设备
              _buildActionCard(
                icon: Icons.restart_alt,
                title: '重启设备',
                subtitle: ble.isConnected ? '发送原厂重启请求，执行结果需自行确认' : '连接设备后可用',
                color: Colors.red,
                onTap: ble.isConnected
                    ? () => _confirmAction(ble, restart: true)
                    : null,
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
                    ? '${ble.bikeData.slope.toStringAsFixed(3)}°'
                    : '--',
                valueColor: Colors.cyan,
              ),

              const SizedBox(height: 8),

              // 校准陀螺仪
              _buildActionCard(
                icon: Icons.tune,
                title: '校准陀螺仪',
                subtitle: ble.isConnected ? '请停车并保持车辆平稳后校准' : '连接设备后可用',
                color: Colors.cyan,
                onTap: ble.isConnected
                    ? () => _confirmAction(ble, restart: false)
                    : null,
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
                value: ble.bikeData.climbingAngle == null ||
                        ble.bikeData.climbingLevel == null
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
              const Expanded(
                  child: Text('本地 CSC 轮径',
                      style: TextStyle(color: Colors.white, fontSize: 15))),
              Text(wheel.loaded ? '${wheel.diameterMm} mm' : '加载中',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            const Text('仅用于手机计算标准 CSC 轮速，不会写入电机；当前 LVBU 速度及 GPS 不受影响。',
                style: TextStyle(
                    color: Colors.white54, fontSize: 11, height: 1.4)),
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
                  onSelected: !wheel.loaded || wheel.saving
                      ? null
                      : (_) async {
                          final saved = await wheel.setDiameterMm(diameter);
                          if (!context.mounted) return;
                          _toast(saved ? '本地 CSC 轮径已保存，未修改电机' : '本地设置保存失败',
                              error: !saved);
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
        content: Text(restart
            ? '请停车后操作；设备可能断开连接，写入成功不代表已重启。'
            : '请将车辆停稳并保持水平静止；该操作会改变设备标定。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result =
        restart ? await ble.restartLvbuDevice() : await ble.calibrateGyro();
    if (!mounted) return;
    final message = restart && result == CommandResult.noResponse
        ? '重启结果未确认；设备可能已执行，请勿连续重试。'
        : '${result.title}：${result.message}';
    showAppToast(context, message,
        error: result.isError, warning: result == CommandResult.noResponse);
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
                  Text(title,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.3)),
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
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
          _buildInfoLine('厂商',
              settings.manufacturer.isNotEmpty ? settings.manufacturer : '--'),
          _buildDivider(),
          _buildInfoLine('型号',
              settings.modelNumber.isNotEmpty ? settings.modelNumber : '--'),
          _buildDivider(),
          _buildInfoLine(
              '固件版本',
              settings.firmwareVersion.isNotEmpty
                  ? settings.firmwareVersion
                  : '--'),
          _buildDivider(),
          _buildInfoLine(
              '硬件版本',
              settings.hardwareVersion.isNotEmpty
                  ? settings.hardwareVersion
                  : '--'),
          _buildDivider(),
          _buildInfoLine('序列号',
              settings.serialNumber.isNotEmpty ? settings.serialNumber : '--'),
          _buildDivider(),
          _buildInfoLine('电机型号',
              settings.motorType.isNotEmpty ? settings.motorType : '--'),
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
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          Text(value,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
              child: const Icon(Icons.info_outline,
                  color: Colors.orange, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关于',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  SizedBox(height: 2),
                  Text('应用简介、版本与更新信息',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.3)),
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
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '基于 Flutter 的 LVBU / WePower 白标电助力控制器离线蓝牙版。\n'
                '纯离线、无登录，支持 BLE 数据和 GPS 测速。模式设置为实验功能，其他助力控制尚未启用。',
                style:
                    TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 16),
              _buildInfoLine('版本号', version),
              _buildDivider(),
              _buildInfoLine('更新日期', '2026-11-16'),
              _buildDivider(),
              _buildInfoLine('构建环境', 'Flutter 3.47.9 · Dart 3.13.7'),
              _buildDivider(),
              const Text('本次更新',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              const Text(
                '闪控图标换成按新设计稿重绘的双态闪控图标（实心圆 + 快门方块 + 四向按键 + 蓝牙信号弧线，连接绿 / 未连接灰），顶部状态栏与设备页同步替换。\n'
                '裁剪掉设计稿的空白边框并按内容边界居中放大，状态栏的蓝牙 / 信号 / 闪控三个图标与设备页闪控图标都调大一号。\n'
                '状态栏里的闪控图标靠左显示，连接设备的名称标签去掉；蓝牙图标在连接成功时换成 bluetooth_connected。\n'
                '骑行时间移到顶部状态栏，用小一号数码管显示，与状态栏其它内容相称；闪控连接指示灯也从助力卡移到状态栏右侧。\n'
                '演示模式：黄色的「演示数据」标签已删除，状态栏按「数据正常」显示绿色连接信号与连接态蓝牙图标，设备名称标签整体去掉。\n'
                '连接成功后自动同步一次手动模式：读到电量和码表速度后立即下发一次「手动」，保证设备侧与界面一致；停止助力前若设备不在手动模式，也会先补一条手动模式再下发 0%。\n'
                '闪控上/下键直接映射到助力面板的加/减按钮，按下时对应按钮显示按下效果；原先的按键弹窗提示已取消。\n'
                '重新核对原厂 LVBU 3.4.0 的全部命令字后确认：没有独立的「停止助力」命令，原厂桌面小组件的停止按钮就是把手动助力写成 A5 百分比 00。本应用此前的 5 秒写入冷却、写入后再锁 5 秒、以及只读轮询抢占链路，会让停止指令经常直接返回「蓝牙繁忙」而根本没发出去。\n'
                '停止助力改为优先级下发：跳过冷却与「结果不确定」封锁，期间暂停只读轮询，链路忙时最多等 8 秒再发；写入后的稳定等待缩短到 0.8 秒并提前释放写锁，A5 冷却缩短到 1.5 秒。设备明确拒绝时自动切到手动模式重试一次。停止后按上下键恢复原助力同样走优先级通道，不会被冷却挡住。\n'
                '闪控连接后，助力卡右上角的闪控图标转绿并点亮一颗常亮指示灯；未连控制器时连接提示里也会显示「闪控已连接 / 未连接」，闪控状态一眼可见。\n'
                '按下闪控主键（home）停止助力后，再按上/下键直接恢复到停止前的助力百分比，不必从 0% 一格一格按回去；手动拖动滑杆后该恢复值自动失效。\n'
                '大设置页只保留设备与关于相关内容：显示设置（速度来源、副速度对比、演示数据）与加减步进全部集中在首页右上角设置按钮弹出的「显示设置」里；步进档位去掉 2%，选中只高亮不显示对钩。\n'
                '顶部标题栏的信号强度图标移到蓝牙图标旁边（连接绿色、未连接灰色），dBm 数值不再显示。\n'
                '闪控按键与向电机下发调速 / 停止助力命令均有 toast 反馈；手动模式在助力控制面板标题后实时显示当前助力百分比。单击右上角副速度可在蓝牙 / GPS 之间交替切换主速度来源。\n'
                '骑行时间移到与副速度同一栏、靠左显示，去掉「骑行时间」文字，只留 icon 与 HH:MM；副速度与骑行时间都改用 DSEG7 数显管，同字体同字号。所有速度来源蓝牙图标统一蓝色、GPS 图标统一绿色；移除状态栏右上角无实际功能的电源按钮。\n'
                '顶部状态栏去掉「已连接 / 未连接」文字标签，连上控制器后信号强度图标转为绿色（蓝牙图标统一蓝色）；闪控主键（home）按下立即下发原厂停止助力命令（手动助力设为 0%），不再走已停用的旧协议帧。\n'
                '闪控上/下键支持连续调速：按键先本地移动助力滑杆，1 秒内连按只合并下发一次最终值，停止键不延迟；助力卡不再显示按键调试信息。\n'
                '电量百分比按 36V 电池重新标定：满电 42.0V = 100%、空电 30.0V = 0%，电压估算与演示数据共用同一条曲线，百分比与电压不再矛盾；温度过热与低电量的红色改为正红 #FF0000，去掉偏粉的旧红色。\n'
                '演示数据的电量、电压与温度改为 24 秒一轮的循环数据：电量 0~100% 扫过四档配色、温度 20~60℃ 扫过三档配色，方便直接查看多色与进度条效果；连接真实设备后自动切回真实数据。\n'
                '电量进度条改为单一连续填充条：底轨不再铺四档分区色、取消底部四色色标，填充改用不透明档位色，修复右侧露出绿色空槽、分区竖线透出、整条被切碎的问题。\n'
                '首页电量卡分级多色：>80% 绿、50~80% 蓝、20~50% 橙、<20% 红，含百分比 / 连续进度条 / 电压；温度 <30℃ 绿、30~50℃ 黄、>50℃ 红，并标注 正常 / 偏热 / 过热。\n'
                '连接控制器或 BR80 闪控后自动保持屏幕常亮，全部断开后恢复系统自动熄屏；主速度小数位上方的 GPS / 蓝牙来源图标上移，与数字拉开间距。\n'
                '此前功能保留：开源 DSEG7 七段字体、熄灭段底纹与位数恒定、连接真实设备自动切回真实数据、骑行时间 HH:MM 按速度启停、副速度对比联动、默认手动、可配置加减步进与闪控联动。',
                style:
                    TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
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
