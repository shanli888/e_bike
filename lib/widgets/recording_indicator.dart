import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ride_recorder.dart';
import '../theme/dashboard_theme.dart';

/// 状态栏录制指示器：把原记录卡片里的红点移到标题栏。
///
/// - 记录中（recording）：红色脉动点 + 「记录中」
/// - 自动暂停（paused）：琥珀色脉动点 + 「已暂停」
/// - 待记录（idle）：不占位
class RecordingIndicator extends StatelessWidget {
  const RecordingIndicator({super.key, this.scale = 1.0});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Selector<RideRecorder, RideRecordState>(
      selector: (_, r) => r.state,
      builder: (context, state, _) {
        if (state == RideRecordState.idle) {
          return const SizedBox(key: ValueKey('recording-indicator'), width: 0, height: 0);
        }
        final recording = state == RideRecordState.recording;
        final color = recording ? const Color(0xFFFF4D5E) : DashColors.amber;
        return Row(
          key: const ValueKey('recording-indicator'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulseDot(color: color, scale: scale),
            SizedBox(width: 4 * scale),
            Text(
              recording ? '记录中' : '已暂停',
              style: TextStyle(
                color: color,
                fontSize: 10.5 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        );
      },
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
        width: 8 * widget.scale,
        height: 8 * widget.scale,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}
