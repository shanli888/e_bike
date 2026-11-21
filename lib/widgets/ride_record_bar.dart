import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ride_recorder.dart';
import '../theme/dashboard_theme.dart';

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
                  TextButton.icon(
                    onPressed: onViewHistory,
                    icon: Icon(Icons.history, size: 14 * scale),
                    label: Text('历史', style: TextStyle(fontSize: 11 * scale)),
                    style: TextButton.styleFrom(
                        foregroundColor: DashColors.muted2,
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale)),
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
    String two(int v) => v.toString().padLeft(2, '0');
    final secs = recorder.elapsed.inSeconds;
    final clock =
        '${two(secs ~/ 3600)}:${two((secs % 3600) ~/ 60)}:${two(secs % 60)}';

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
          Row(
            children: [
              _PulseDot(color: recColor, scale: scale),
              SizedBox(width: 9 * scale),
              Text(
                recording ? '记录中' : '已暂停',
                style: TextStyle(
                    color: recColor,
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1),
              ),
              const Spacer(),
              Text(clock, style: _segStyle(20 * scale, DashColors.txt)),
            ],
          ),
          SizedBox(height: 12 * scale),
          Row(
            children: [
              _metric('距离', recorder.distanceKm.toStringAsFixed(2), 'km', DashColors.green),
              _metric('均速', recorder.avgSpeedKmh.toStringAsFixed(1), '', DashColors.blue),
              _metric('爬升', recorder.ascentM.toStringAsFixed(0), 'm', DashColors.amber),
              _metric('千卡', '${recorder.calories.round()}', '', DashColors.muted2),
            ],
          ),
          SizedBox(height: 12 * scale),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40 * scale,
                  child: OutlinedButton.icon(
                    onPressed: recording
                        ? recorder.pause
                        : recorder.resume,
                    icon: Icon(
                        recording ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 18 * scale),
                    label: Text(recording ? '暂停' : '继续',
                        style: TextStyle(fontSize: 13 * scale)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DashColors.txt,
                      side: const BorderSide(color: DashColors.subDivider),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11 * scale)),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                child: SizedBox(
                  height: 40 * scale,
                  child: FilledButton.icon(
                    onPressed: onFinish,
                    icon: Icon(Icons.stop_rounded, size: 18 * scale),
                    label: Text('结束', style: TextStyle(fontSize: 13 * scale)),
                    style: FilledButton.styleFrom(
                      backgroundColor: recColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11 * scale)),
                    ),
                  ),
                ),
              ),
            ],
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
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.scale});
  final Color color;
  final double scale;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35)
          .chain(CurveTween(curve: Curves.easeInOut))
          .animate(_c),
      child: Container(
        width: 11 * widget.scale,
        height: 11 * widget.scale,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}
