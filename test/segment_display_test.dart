import 'package:bike_computer/theme/dashboard_theme.dart';
import 'package:bike_computer/widgets/segment_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

Text _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key)));

void main() {
  testWidgets('DSEG7 双层叠字：ghost 固定 88.8，on 显示实际数值', (tester) async {
    await tester.pumpWidget(_host(const SegmentNumber(
      text: '08.6',
      integerDigits: 2,
      fractionDigits: 1,
      height: 100,
    )));

    expect(_text(tester, 'segment-ghost-int').data, '88');
    expect(_text(tester, 'segment-ghost-frac').data, '8');
    expect(_text(tester, 'segment-on-int').data, '08');
    expect(_text(tester, 'segment-on-frac').data, '6');
    expect(tester.takeException(), isNull);
  });

  testWidgets('整数 128:74 基线对齐，整数位大、小数位小', (tester) async {
    await tester.pumpWidget(_host(const SegmentNumber(
      text: '08.6',
      integerDigits: 2,
      fractionDigits: 1,
      height: 100,
    )));

    final big = _text(tester, 'segment-on-int').style!;
    final small = _text(tester, 'segment-on-frac').style!;
    expect(big.fontSize, 100);
    expect(small.fontSize, closeTo(57.8, 0.01));
    expect(big.height, 1.0);
    expect(small.height, 1.0);
    // 字体 descent 为 0，行底即基线，end 对齐等价基线对齐。
    final rows = tester.widgetList<Row>(find.byType(Row));
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row.crossAxisAlignment, CrossAxisAlignment.end);
    }
  });

  testWidgets('使用开源 DSEG7 字体，并可切换细笔画变体', (tester) async {
    await tester.pumpWidget(_host(const SegmentNumber(
      text: '08.6',
      integerDigits: 2,
      fractionDigits: 1,
      height: 100,
    )));
    expect(_text(tester, 'segment-on-int').style!.fontFamily,
        DashFonts.segClassic);

    await tester.pumpWidget(_host(const SegmentNumber(
      text: '08.6',
      integerDigits: 2,
      fractionDigits: 1,
      height: 100,
      fontFamily: DashFonts.segClassicThin,
    )));
    expect(_text(tester, 'segment-on-int').style!.fontFamily,
        DashFonts.segClassicThin);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无数据时仅保留熄灭段底纹，点亮层用全灭字符占位', (tester) async {
    for (final text in [null, '--', '']) {
      await tester.pumpWidget(_host(SegmentNumber(
        text: text,
        integerDigits: 2,
        fractionDigits: 1,
        height: 100,
      )));
      expect(_text(tester, 'segment-ghost-int').data, '88',
          reason: 'text=$text');
      expect(_text(tester, 'segment-ghost-frac').data, '8',
          reason: 'text=$text');
      // `!` 是 DSEG7 的零轮廓全灭字符，宽度与数字一致。
      expect(_text(tester, 'segment-on-int').data, '!!', reason: 'text=$text');
      expect(_text(tester, 'segment-on-frac').data, '!', reason: 'text=$text');
      expect(_text(tester, 'segment-on-int').style!.color,
          DashColors.segGhost,
          reason: 'text=$text');
      expect(tester.takeException(), isNull, reason: 'text=$text');
    }
  });

  testWidgets('里程不补零，整数高位留熄灭槽但仍占位', (tester) async {
    await tester.pumpWidget(_host(const SegmentNumber(
      text: '1.5',
      integerDigits: 2,
      fractionDigits: 1,
      height: 100,
      padInteger: false,
    )));

    expect(_text(tester, 'segment-ghost-int').data, '88');
    expect(_text(tester, 'segment-on-int').data, '!1');
    expect(_text(tester, 'segment-on-frac').data, '5');
  });

  testWidgets('整数位数可扩展，超过 99.9 的里程不会丢高位', (tester) async {
    await tester.pumpWidget(_host(const SegmentNumber(
      text: '123.4',
      integerDigits: 3,
      fractionDigits: 1,
      height: 100,
      padInteger: false,
    )));

    expect(_text(tester, 'segment-ghost-int').data, '888');
    expect(_text(tester, 'segment-on-int').data, '123');
    expect(_text(tester, 'segment-on-frac').data, '4');
  });

  testWidgets('fractionDigits 为 0 时不画小数点与小数位', (tester) async {
    await tester.pumpWidget(_host(const SegmentNumber(
      text: '42',
      integerDigits: 2,
      fractionDigits: 0,
      height: 100,
    )));

    expect(_text(tester, 'segment-on-int').data, '42');
    expect(find.byKey(const ValueKey('segment-on-frac')), findsNothing);
    expect(find.byKey(const ValueKey('segment-ghost-frac')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showGhost 关闭时底纹层透明但保留占位', (tester) async {
    await tester.pumpWidget(_host(const SegmentNumber(
      text: '08.6',
      integerDigits: 2,
      fractionDigits: 1,
      height: 100,
      showGhost: false,
    )));

    expect(_text(tester, 'segment-ghost-int').data, '88');
    expect(_text(tester, 'segment-ghost-int').style!.color,
        Colors.transparent);
  });

  testWidgets('语义标签可覆盖原始文本，便于读屏与测试定位', (tester) async {
    await tester.pumpWidget(_host(const SegmentNumber(
      text: '1.5',
      integerDigits: 2,
      fractionDigits: 1,
      height: 100,
      semanticsLabel: '1.5 km',
    )));

    expect(
      find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '1.5 km'),
      findsOneWidget,
    );
  });
}
