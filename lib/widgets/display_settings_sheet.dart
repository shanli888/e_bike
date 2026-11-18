import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/assist_step_settings.dart';
import '../services/demo_mode_settings.dart';
import '../services/gps_service.dart';
import '../theme/dashboard_theme.dart';

/// 主速度区右上角齿轮打开的底部「显示设置」面板（规格 §5）。
/// 把速度来源、副速度对比、加减步进三处入口集中在这里，逻辑仍走各自服务。
Future<void> showDisplaySettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: DashColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _DisplaySettingsSheet(),
  );
}

class _DisplaySettingsSheet extends StatelessWidget {
  const _DisplaySettingsSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 28 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('显示设置',
              style: TextStyle(
                  color: DashColors.txt,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          const Text('速度来源',
              style: TextStyle(color: DashColors.muted2, fontSize: 12)),
          const SizedBox(height: 8),
          Consumer<GpsService>(
            builder: (context, gps, _) => SegmentedButton<SpeedSource>(
              segments: const [
                ButtonSegment(
                    value: SpeedSource.bluetooth,
                    icon: Icon(Icons.bluetooth,
                        size: 16, color: DashColors.sourceBluetooth),
                    label: Text('蓝牙')),
                ButtonSegment(
                    value: SpeedSource.gps,
                    icon: Icon(Icons.gps_fixed,
                        size: 16, color: DashColors.sourceGps),
                    label: Text('GPS')),
              ],
              selected: {gps.source},
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? DashColors.orange.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.05)),
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? Colors.white
                        : Colors.white70),
              ),
              onSelectionChanged: (selection) => gps.setSource(selection.first),
            ),
          ),
          const SizedBox(height: 6),
          Consumer<GpsService>(
            builder: (context, gps, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('GPS 副速度对比',
                  style: TextStyle(color: DashColors.txt, fontSize: 13)),
              subtitle: const Text('关闭后首页右上角不再显示副速度',
                  style: TextStyle(color: DashColors.muted, fontSize: 11)),
              value: gps.comparisonEnabled,
              activeThumbColor: DashColors.orange,
              onChanged: (value) => gps.setComparisonEnabled(value),
            ),
          ),
          Consumer<DemoModeSettings>(
            builder: (context, settings, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('演示数据',
                  style: TextStyle(color: DashColors.txt, fontSize: 13)),
              subtitle: const Text('未连接时填充演示数据；电量与温度每 24 秒循环一轮，可查看各档配色',
                  style: TextStyle(color: DashColors.muted, fontSize: 11)),
              value: settings.enabled,
              activeThumbColor: DashColors.orange,
              onChanged: (value) => settings.setEnabled(value),
            ),
          ),
          const SizedBox(height: 10),
          const Text('加减步进',
              style: TextStyle(color: DashColors.muted2, fontSize: 12)),
          const SizedBox(height: 8),
          Consumer<AssistStepSettings>(
            builder: (context, settings, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [1, 5, 10, 20]
                  .map((value) => ChoiceChip(
                        label: Text('$value%'),
                        selected: settings.step == value,
                        // 选中只做高亮，不显示对钩。
                        showCheckmark: false,
                        selectedColor: DashColors.orange,
                        labelStyle: TextStyle(
                          color: settings.step == value
                              ? Colors.white
                              : Colors.white70,
                          fontSize: 13,
                        ),
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.06),
                        onSelected: (_) => settings.setStep(value),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          const Text('手动模式加/减按钮与闪控上/下键共用此数值，保存在本机。',
              style: TextStyle(color: DashColors.muted, fontSize: 11)),
        ],
      ),
    );
  }
}
