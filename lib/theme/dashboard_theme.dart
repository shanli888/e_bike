import 'package:flutter/material.dart';

/// DSEG7 开源七段字体族（SIL OFL 1.1），与 pubspec.yaml 的 fonts 声明对应。
class DashFonts {
  const DashFonts._();

  /// 原型默认：`SEGClassic`（DSEG7 Classic Bold，700）。
  static const String segClassic = 'DSEG7Classic';

  /// 细笔画变体，笔画更秀气。
  static const String segClassicThin = 'DSEG7ClassicThin';

  /// 段间距更紧凑，适合小字号。
  static const String segMini = 'DSEG7Mini';

  /// 数字与全灭字符 `!` 的 advance width，取自字体 hmtx（816 / unitsPerEm 1000）。
  /// 用于计算整行宽度与小数点/角标定位。
  static const double advanceRatio = 0.816;
}

/// 取自《智能码表界面 · 布局规格说明书》§1.4 与原型 `:root` 的实测取值。
class DashColors {
  const DashColors._();

  static const Color bg = Color(0xFF0B0F1D);
  static const Color bg2 = Color(0xFF10162A);
  static const Color card = Color(0xFF151C2F);
  static const Color card2 = Color(0xFF1B2338);
  static const Color nav = Color(0xFF0D1324);

  static const Color txt = Color(0xFFF2F5FC);
  static const Color muted = Color(0xFF8B95AD);
  static const Color muted2 = Color(0xFFAAB5CB);

  static const Color orange = Color(0xFFFFB020);
  static const Color green = Color(0xFF3DDC8C);
  static const Color blue = Color(0xFF4AA8FF);
  static const Color amber = Color(0xFFFF9F45);

  /// 速度来源图标的统一配色：蓝牙=蓝、GPS=绿。
  /// 首页主速度角标、右上角副速度与设置里的来源选择都走这两个常量。
  static const Color sourceBluetooth = blue;
  static const Color sourceGps = green;

  /// 传感器分级配色：低电/过热用**正红**（纯 #FF0000，无蓝绿分量偏色），
  /// 温度偏热用黄色。原先的 #FF5468 蓝分量偏高、看起来接近粉红。
  static const Color red = Color(0xFFFF0000);
  static const Color yellow = Color(0xFFFFD54F);

  static const Color segOn = Color(0xFFF4F9FF);
  static const Color segSub = Color(0xFFE9F1FF);
  static const Color segGhost = Color(0x1296AFD7); // rgba(150,175,215,.07)
  static const Color segGlow = Color(0x2982BEFF); // rgba(130,190,255,.16)

  static const Color line = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  static const Color subLine = Color(0x12FFFFFF); // .07
  static const Color subDivider = Color(0x21FFFFFF); // .13

  static const LinearGradient pageBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0C1120), Color(0xFF0A0E1C)],
  );

  /// 助力卡片的暖色描边渐变（§2.5）
  static const LinearGradient assistBorder = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.8, 1),
    colors: [
      Color(0xF2FFBE50),
      Color(0x59FFA028),
      Color(0x8CFFB43C),
    ],
  );

  static const LinearGradient assistFill = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.8, 1),
    colors: [Color(0xFF2C2314), Color(0xFF1A1C28), Color(0xFF141B2D)],
    stops: [0.0, 0.34, 1.0],
  );

  static const LinearGradient modeSelected = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFC44D), Color(0xFFF5A015)],
  );
}
