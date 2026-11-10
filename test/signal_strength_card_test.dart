import 'package:bike_computer/widgets/signal_strength_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Color? segmentColor(WidgetTester tester, int index) {
    final container = tester.widget<Container>(
      find.byKey(ValueKey('signal-segment-$index')),
    );
    return (container.decoration! as BoxDecoration).color;
  }

  Future<void> showCard(WidgetTester tester, int rssi, bool connected) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SignalStrengthCard(rssi: rssi, isConnected: connected),
      ),
    ));
  }

  testWidgets('强在左弱在右，强信号靠左灰色靠右绿色', (tester) async {
    await showCard(tester, -49, true);

    expect(tester.getTopLeft(find.text('强')).dx,
        lessThan(tester.getTopLeft(find.text('弱')).dx));
    expect(find.text('-49 dBm'), findsOneWidget);
    expect(segmentColor(tester, 0), Colors.white.withValues(alpha: 0.1));
    expect(segmentColor(tester, 3), Colors.white.withValues(alpha: 0.1));
    expect(segmentColor(tester, 4), Colors.green);
    expect(segmentColor(tester, 19), Colors.green);
  });

  testWidgets('信号越弱亮起的格子越少，弱信号显示橙色', (tester) async {
    await showCard(tester, -85, true);
    expect(segmentColor(tester, 14), Colors.white.withValues(alpha: 0.1));
    expect(segmentColor(tester, 16), Colors.orange);
    expect(segmentColor(tester, 19), Colors.orange);
  });

  testWidgets('未连接时不显示信号格和旧 RSSI', (tester) async {
    await showCard(tester, -49, false);
    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('-49 dBm'), findsNothing);
    for (var i = 0; i < 20; i++) {
      expect(segmentColor(tester, i), Colors.white.withValues(alpha: 0.1));
    }
  });
}
