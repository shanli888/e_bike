import 'package:flutter/material.dart';

import '../models/ride_record.dart';
import '../theme/dashboard_theme.dart';

/// 骑行结束后的汇总弹层：6 项核心指标 + 保存/放弃。
/// 保存动作由外部 onSave 完成（记录器 finish 已落库，这里主要展示与跳转）。
Future<void> showRideSummary(
  BuildContext context, {
  required RideSession ride,
  required VoidCallback onDone,
  VoidCallback? onViewHistory,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _Sheet(ride: ride, onDone: onDone, onViewHistory: onViewHistory),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.ride,
    required this.onDone,
    this.onViewHistory,
  });

  final RideSession ride;
  final VoidCallback onDone;
  final VoidCallback? onViewHistory;

  TextStyle get _seg => const TextStyle(
        fontFamily: DashFonts.segClassic,
        fontSize: 26,
        color: DashColors.txt,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DashColors.bg2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Icon(Icons.emoji_events, color: DashColors.orange, size: 34),
          const SizedBox(height: 8),
          const Text('骑行完成',
              style: TextStyle(
                  color: DashColors.txt,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(ride.name,
              style: const TextStyle(color: DashColors.muted, fontSize: 12)),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              _cell('距离', ride.distanceKm.toStringAsFixed(2), 'km', DashColors.green),
              _cell('时长', ride.durationLabel, '', DashColors.txt),
              _cell('均速', ride.avgSpeedKmh.toStringAsFixed(1), '', DashColors.blue),
              _cell('极速', ride.maxSpeedKmh.toStringAsFixed(1), '', DashColors.orange),
              _cell('爬升', ride.ascentM.toStringAsFixed(0), 'm', DashColors.amber),
              _cell('消耗', '${ride.calories}', 'kcal', DashColors.muted2),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: onDone,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DashColors.muted2,
                      side: const BorderSide(color: DashColors.subDivider),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('完成'),
                  ),
                ),
              ),
              if (onViewHistory != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: onViewHistory,
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('看记录'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DashColors.orange,
                        foregroundColor: const Color(0xFF1A1206),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value, String unit, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: DashColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DashColors.line),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: DashColors.muted, fontSize: 11)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: _seg.copyWith(color: color)),
                if (unit.isNotEmpty)
                  Text(' $unit',
                      style: const TextStyle(
                          color: DashColors.muted, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
