import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ride_recorder.dart';
import '../theme/dashboard_theme.dart';
import 'slide_to_end.dart';

/// 骑行记录控制条：待记录 / 记录中 / 已暂停 三态。
///
/// 未连接助力器时占据原助力卡片的位置（主位），已连接时作为紧凑条显示在
/// 传感器行上方。所有按钮只驱动 [RideRecorder]，与助力控制完全解耦。
class RideRecordBar extends StatelessWidget {
  const RideRecordBar({
    super.key,
    required this.scale,
    required this.onStart,
    required this.onFinish,
    this.onViewHistory,
    this.onConnectAssist,
    this.compact = false,
  });

  final double scale;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback? onViewHistory;
  final VoidCallback? onConnectAssist;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Selector<RideRecorder, RideRecordState>(
      selector: (_, r) => r.state,
      builder: (context, state, _) {
        return switch (state) {
          RideRecordState.idle => _idle(context),
          RideRecordState.recording => _active(context, recording: true),
          RideRecordState.paused => _active(context, recording: false),
        };
      },
    );
  }

  TextStyle _segStyle(double size, Color color) => TextStyle(
        fontFamily: DashFonts.segClassic,
        fontSize: size,
        color: color,
        letterSpacing: 1,
      );

  Widget _idle(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: compact ? 12 * scale : 18 * scale,
      ),
      decoration: BoxDecoration(
        color: DashColors.card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(color: DashColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(Icons.route, size: 26 * scale, color: DashColors.green),
            SizedBox(height: 8 * scale),
            Text(
              '纯码表模式 · 随时开骑',
              style: TextStyle(color: DashColors.txt, fontSize: 14 * scale),
            ),
            SizedBox(height: 3 * scale),
            Text(
              '仅用手机 GPS 记录轨迹、速度与里程',
              style: TextStyle(color: DashColors.muted, fontSize: 11 * scale),
            ),
            SizedBox(height: 14 * scale),
          ],
          SizedBox(
            width: double.infinity,
            height: (compact ? 40 : 48) * scale,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: Icon(Icons.play_arrow_rounded, size: 20 * scale),
              label: Text('开始骑行',
                  style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: DashColors.green,
                foregroundColor: const Color(0xFF041A10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12 * scale)),
              ),
            ),
          ),
          if (!compact || onViewHistory != null || onConnectAssist != null) ...[
            SizedBox(height: 6 * scale),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onViewHistory != null)
                  SizedBox(
                    height: 32 * scale,
                    child: OutlinedButton.icon(
                      key: const ValueKey('history-entry'),
                      onPressed: onViewHistory,
                      icon: Icon(Icons.history, size: 15 * scale),
                      label: Text('骑行历史',
                          style: TextStyle(
                              fontSize: 12 * scale, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DashColors.orange,
                        side: BorderSide(
                            color: DashColors.orange.withValues(alpha: 0.55)),
                        backgroundColor:
                            DashColors.orange.withValues(alpha: 0.10),
                        padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10 * scale)),
                      ),
                    ),
                  ),
                if (onViewHistory != null && onConnectAssist != null)
                  Text('·', style: TextStyle(color: DashColors.muted, fontSize: 11 * scale)),
                if (onConnectAssist != null)
                  TextButton.icon(
                    onPressed: onConnectAssist,
                    icon: Icon(Icons.bluetooth_searching, size: 14 * scale),
                    label: Text('连接助力器',
                        style: TextStyle(fontSize: 11 * scale)),
                    style: TextButton.styleFrom(
                        foregroundColor: DashColors.orange,
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _active(BuildContext context, {required bool recording}) {
    final recorder = context.watch<RideRecorder>();
    final recColor = recording ? const Color(0xFFFF4D5E) : DashColors.amber;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 12 * scale,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            recColor.withValues(alpha: 0.16),
            recColor.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(color: recColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 状态行：红点与骑行时间已移到顶部状态栏；暂停由 GPS 速度自动判定。
          Row(
            children: [
              Text(
                recording ? '记录中' : '已暂停',
                style: TextStyle(
                    color: recColor,
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1),
              ),
              SizedBox(width: 8 * scale),
              Text(
                recording ? '移动中自动记录' : '速度低于阈值，停车自动暂停',
                style: TextStyle(color: DashColors.muted, fontSize: 10.5 * scale),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          // 码表主体已有距离/均速、状态栏已有骑行时间，这里只留增量信息 + 坡度。
          Row(
            children: [
              _slopeMetric(recorder.slopePercent, scale),
              _metric('爬升', recorder.ascentM.toStringAsFixed(0), 'm', DashColors.amber),
              _metric('千卡', '${recorder.calories.round()}', '', DashColors.muted2),
            ],
          ),
          SizedBox(height: 10 * scale),
          // 开始自动、暂停自动；「结束」改为滑动确认，防止误触。
          SlideToEnd(
            label: '滑动结束骑行',
            color: recColor,
            onConfirmed: onFinish,
            height: 44 * scale,
            thumbSize: 38 * scale,
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, String unit, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(color: DashColors.muted, fontSize: 10 * scale)),
          SizedBox(height: 3 * scale),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: _segStyle(17 * scale, color)),
              if (unit.isNotEmpty)
                Text(' $unit',
                    style: TextStyle(color: DashColors.muted, fontSize: 9 * scale)),
            ],
          ),
        ],
      ),
    );
  }

  /// 实时坡度：上坡红、下坡绿、平路蓝；无数据显示 --。
  Widget _slopeMetric(double? percent, double scale) {
    final has = percent != null;
    final color = !has
        ? DashColors.muted2
        : percent > 1
            ? DashColors.red
            : percent < -1
                ? DashColors.green
                : DashColors.blue;
    final text = !has
        ? '--'
        : '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1)}';
    return Expanded(
      child: Column(
        children: [
          Text('坡度', style: TextStyle(color: DashColors.muted, fontSize: 10 * scale)),
          SizedBox(height: 3 * scale),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(text,
                  key: const ValueKey('record-slope'),
                  style: _segStyle(17 * scale, color)),
              Text(' %',
                  style: TextStyle(color: DashColors.muted, fontSize: 9 * scale)),
            ],
          ),
        ],
      ),
    );
  }
}
