import 'package:flutter/material.dart';

import '../theme/dashboard_theme.dart';

/// 七段数码管数字。
///
/// 使用开源 DSEG7 字体（keshikan，SIL OFL 1.1）渲染，对应规格书 §2.3 / §4
/// 的「双层文本叠加」机制：
/// - `ghost` 层固定显示 `8`（熄灭段底纹），锁死每个槽位的宽度；
/// - `on` 层覆盖实际数字，只点亮对应段；
/// - 空槽位用字体的 `!`（全灭、零轮廓，且 advance width 与数字一致）占位。
///
/// 因此位数恒定，骑行时数字跳变不会左右抖动。整数位大、小数位小，字体
/// descent 为 0，行底即基线，`CrossAxisAlignment.end` 天然实现基线对齐。
class SegmentNumber extends StatelessWidget {
  const SegmentNumber({
    super.key,
    required this.text,
    required this.integerDigits,
    required this.fractionDigits,
    required this.height,
    this.fractionHeight,
    this.color = DashColors.segOn,
    this.ghostColor = DashColors.segGhost,
    this.glowColor = DashColors.segGlow,
    this.showGhost = true,
    this.padInteger = true,
    this.fontFamily = DashFonts.segClassic,
    this.semanticsLabel,
  });

  /// 已格式化的数字串，如 `08.6` / `06.9`；`null` 或 `--` 表示无数据。
  final String? text;
  final int integerDigits;
  final int fractionDigits;

  /// 整数位字号（逻辑像素）。DSEG7 字形高度恰为 1em，故也是可见字高。
  final double height;

  /// 小数位字号，默认按规格的 74/128 ≈ 0.578。
  final double? fractionHeight;

  final Color color;
  final Color ghostColor;
  final Color glowColor;
  final bool showGhost;

  /// 整数不足位数时是否补 0；里程不补零，高位留熄灭槽。
  final bool padInteger;

  /// 可在 Classic / ClassicThin / Mini 间切换笔画风格。
  final String fontFamily;
  final String? semanticsLabel;

  /// DSEG7 的 `!` 为全灭字符（0 轮廓），宽度与数字相同，用作空槽占位。
  static const String _blank = '!';

  List<String?> get _integerChars {
    final parts = _parts();
    final raw = parts?[0];
    final chars = <String?>[];
    for (var i = 0; i < integerDigits; i++) {
      if (raw == null) {
        chars.add(null);
      } else if (!padInteger &&
          raw.length < integerDigits &&
          i < integerDigits - raw.length) {
        chars.add(null);
      } else {
        final padded = raw.padLeft(integerDigits, '0');
        final c = padded[padded.length - integerDigits + i];
        chars.add(c);
      }
    }
    return chars;
  }

  List<String?> get _fractionChars {
    final parts = _parts();
    String? raw;
    if (fractionDigits > 0 && parts != null && parts.length > 1) {
      raw = parts[1];
    }
    return List<String?>.generate(fractionDigits, (i) {
      if (raw == null) return null;
      return i < raw.length ? raw[i] : '0';
    });
  }

  List<String>? _parts() {
    final value = text;
    if (value == null || value == '--' || value.isEmpty) return null;
    final dot = value.indexOf('.');
    if (dot < 0) return [value, ''];
    return [value.substring(0, dot), value.substring(dot + 1)];
  }

  static String _join(List<String?> chars, {required bool ghost}) => ghost
      ? '8' * chars.length
      : chars.map((c) => c ?? _blank).join();

  @override
  Widget build(BuildContext context) {
    final bigH = height;
    final smallH = fractionHeight ?? bigH * 0.578;
    final hasData = _parts() != null;
    final intChars = _integerChars;
    final fracChars = _fractionChars;

    return Semantics(
      label: semanticsLabel ?? text ?? '无数据',
      child: ExcludeSemantics(
        child: Stack(
          alignment: AlignmentDirectional.bottomStart,
          children: [
            _buildLayer(
              ghost: true,
              intChars: intChars,
              fracChars: fracChars,
              bigH: bigH,
              smallH: smallH,
              hasData: hasData,
            ),
            _buildLayer(
              ghost: false,
              intChars: intChars,
              fracChars: fracChars,
              bigH: bigH,
              smallH: smallH,
              hasData: hasData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayer({
    required bool ghost,
    required List<String?> intChars,
    required List<String?> fracChars,
    required double bigH,
    required double smallH,
    required bool hasData,
  }) {
    final ink = ghost
        ? (showGhost ? ghostColor : Colors.transparent)
        : (hasData ? color : ghostColor);
    final lit = !ghost && hasData;

    TextStyle style(double size) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          // DSEG7 的 ascent = 1000 / descent = 0，行高 1.0 时字形正好占满。
          height: 1.0,
          color: ink,
          shadows: lit
              ? [
                  Shadow(color: glowColor, blurRadius: size * 0.188),
                  Shadow(color: glowColor, blurRadius: size * 0.047),
                ]
              : null,
        );

    final dotSize = bigH * 0.102;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _join(intChars, ghost: ghost),
          key: ValueKey(ghost ? 'segment-ghost-int' : 'segment-on-int'),
          style: style(bigH),
        ),
        if (fractionDigits > 0) ...[
          SizedBox(width: bigH * 0.055),
          Container(
            width: dotSize,
            height: dotSize,
            margin: EdgeInsets.only(bottom: bigH * 0.012),
            decoration: BoxDecoration(
              color: lit ? color : (showGhost ? ghostColor : Colors.transparent),
              shape: BoxShape.circle,
              boxShadow: lit
                  ? [
                      BoxShadow(
                        color: glowColor,
                        blurRadius: bigH * 0.11,
                        spreadRadius: bigH * 0.016,
                      ),
                    ]
                  : null,
            ),
          ),
          SizedBox(width: bigH * 0.042),
          Text(
            _join(fracChars, ghost: ghost),
            key: ValueKey(ghost ? 'segment-ghost-frac' : 'segment-on-frac'),
            style: style(smallH),
          ),
        ],
      ],
    );
  }
}

/// HH:MM 骑行时间：与速度数字同族的 DSEG7 数码管。
///
/// 冒号不依赖字体是否内置 `:` 字形，改为自己画两个圆点：熄灭时与数字的
/// ghost 底纹同色，点亮时与数字同色，风格完全一致。
class SegmentClock extends StatelessWidget {
  const SegmentClock({
    super.key,
    required this.text,
    required this.height,
    this.color = DashColors.segSub,
    this.ghostColor = DashColors.segGhost,
    this.glowColor = DashColors.segGlow,
    this.semanticsLabel,
  });

  /// `HH:MM`；其它格式按无数据处理（只留熄灭底纹）。
  final String text;

  /// 数字字号（逻辑像素），与副速度数码管保持一致。
  final double height;
  final Color color;
  final Color ghostColor;
  final Color glowColor;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final parts = text.split(':');
    final valid = parts.length == 2 &&
        parts[0].isNotEmpty &&
        parts[1].isNotEmpty;
    final hours = valid ? parts[0] : null;
    final minutes = valid ? parts[1] : null;
    final dot = height * 0.11;

    Widget colonDot() => Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            color: valid ? color : ghostColor,
            shape: BoxShape.circle,
            boxShadow: valid
                ? [BoxShadow(color: glowColor, blurRadius: height * 0.12)]
                : null,
          ),
        );

    return Semantics(
      label: semanticsLabel ?? '骑行时间 $text',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SegmentNumber(
              text: hours,
              integerDigits: 2,
              fractionDigits: 0,
              height: height,
              color: color,
              ghostColor: ghostColor,
              glowColor: glowColor,
            ),
            SizedBox(width: height * 0.11),
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                colonDot(),
                SizedBox(height: height * 0.18),
                colonDot(),
              ],
            ),
            SizedBox(width: height * 0.11),
            SegmentNumber(
              text: minutes,
              integerDigits: 2,
              fractionDigits: 0,
              height: height,
              color: color,
              ghostColor: ghostColor,
              glowColor: glowColor,
            ),
          ],
        ),
      ),
    );
  }
}
