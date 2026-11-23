import 'package:flutter/material.dart';

/// 滑动确认按钮：把滑块从左侧拖到右侧终点才触发 [onConfirmed]，中途松手回弹。
/// 用于防误触的破坏性操作（如结束骑行）。
///
/// - [progress] 为滑块当前进度 0~1；达到 [commitThreshold] 松手即视为确认。
/// - 提供 key 'slide-thumb' / 'slide-track' 便于测试与拖动。
class SlideToEnd extends StatefulWidget {
  const SlideToEnd({
    super.key,
    required this.label,
    required this.color,
    required this.onConfirmed,
    this.height = 46,
    this.thumbSize = 40,
    this.commitThreshold = 0.82,
  });

  final String label;
  final Color color;
  final VoidCallback onConfirmed;
  final double height;
  final double thumbSize;
  final double commitThreshold;

  @override
  State<SlideToEnd> createState() => _SlideToEndState();
}

class _SlideToEndState extends State<SlideToEnd> {
  double _progress = 0;
  double _dragStartX = 0;
  double _startProgress = 0;
  double _trackWidth = 1;

  double get _thumbTravel => _trackWidth - widget.thumbSize - 8;

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragStartX = d.globalPosition.dx;
    _startProgress = _progress;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    final dx = d.globalPosition.dx - _dragStartX;
    final delta = _thumbTravel > 0 ? dx / _thumbTravel : 0;
    setState(() {
      _progress = (_startProgress + delta).clamp(0.0, 1.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    if (_progress >= widget.commitThreshold) {
      // 吸附到终点并触发确认。
      setState(() => _progress = 1);
      widget.onConfirmed();
    } else {
      // 未达阈值回弹。
      setState(() => _progress = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _trackWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 300;
        final thumbLeft = 4 + _progress * _thumbTravel;
        return Container(
          key: const ValueKey('slide-track'),
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(widget.height / 2),
            border: Border.all(color: widget.color.withValues(alpha: 0.55)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // 已完成部分的填充
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.height / 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _progress,
                    child: Container(color: widget.color.withValues(alpha: 0.28)),
                  ),
                ),
              ),
              // 居中文案：拖动时淡出，提示"继续滑动"
              Center(
                child: Opacity(
                  opacity: (1 - _progress * 1.4).clamp(0.0, 1.0),
                  child: Text(
                    widget.label,
                    style: TextStyle(
                        color: widget.color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1),
                  ),
                ),
              ),
              // 滑块
              Positioned(
                left: thumbLeft,
                top: (widget.height - widget.thumbSize) / 2,
                child: GestureDetector(
                  key: const ValueKey('slide-thumb'),
                  onHorizontalDragStart: _onHorizontalDragStart,
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: Container(
                    width: widget.thumbSize,
                    height: widget.thumbSize,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: widget.color.withValues(alpha: 0.45),
                            blurRadius: 8),
                      ],
                    ),
                    child: Icon(Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.9), size: 24),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
