import 'package:flutter/material.dart';

/// 蓝牙信号强度：左侧代表较强的 RSSI，右侧代表较弱的 RSSI。
class SignalStrengthCard extends StatelessWidget {
  const SignalStrengthCard({
    super.key,
    required this.rssi,
    required this.isConnected,
  });

  final int rssi;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final signalColor = rssi > -75 ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('蓝牙信号强度',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              Text(
                isConnected ? '$rssi dBm' : '未连接',
                style: TextStyle(
                  color: isConnected ? signalColor : Colors.red,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(20, (i) {
              final threshold = -40 - i * 3;
              final active = isConnected && rssi > threshold;
              return Expanded(
                child: Container(
                  key: ValueKey('signal-segment-$i'),
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: active
                        ? signalColor
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('强', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
              Text('弱', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
