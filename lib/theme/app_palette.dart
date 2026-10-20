import 'package:flutter/material.dart';

/// 日间 / 夜间两套调色板。所有界面颜色都从这里取，禁止再硬编码。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.bgTop,
    required this.bgBottom,
    required this.card,
    required this.cardAlt,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.dim,
    required this.faint,
    required this.accent,
    required this.accent2,
    required this.onAccent,
    required this.scrim,
    required this.success,
    required this.navBar,
  });

  final Brightness brightness;
  final Color bgTop;
  final Color bgBottom;

  /// 卡片带透明度，让自定义背景能透出来
  final Color card;
  final Color cardAlt;
  final Color border;
  final Color borderStrong;

  final Color text;
  final Color dim;
  final Color faint;

  final Color accent;
  final Color accent2;

  /// 压在 accent 渐变色块上的前景色（文字/图标）：
  /// 深色主题 accent 偏亮 → 用墨绿；浅色主题 accent 偏深 → 用白色。
  final Color onAccent;

  /// 背景图/视频之上的遮罩，保证文字可读
  final Color scrim;

  final Color success;
  final Color navBar;

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    bgTop: Color(0xFF0B0B12),
    bgBottom: Color(0xFF07070B),
    card: Color(0xC912121A),
    cardAlt: Color(0xD91A1A26),
    border: Color(0xFF2A2A36),
    borderStrong: Color(0xFF353542),
    text: Color(0xFFF2F3F7),
    dim: Color(0xFFA0A5B6),
    faint: Color(0xFF6D7284),
    accent: Color(0xFF19E8BE),
    accent2: Color(0xFF00C9A6),
    onAccent: Color(0xFF04120F),
    scrim: Color(0x8C000000),
    success: Color(0xFF3DDC97),
    navBar: Color(0xF21A1A26),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    bgTop: Color(0xFFF8F9FC),
    bgBottom: Color(0xFFEDEFF5),
    card: Color(0xE6FFFFFF),
    cardAlt: Color(0xF2F1F3F8),
    border: Color(0xFFE0E3EB),
    borderStrong: Color(0xFFCFD3DE),
    text: Color(0xFF14161C),
    dim: Color(0xFF5A6070),
    faint: Color(0xFF8D93A3),
    accent: Color(0xFF008F76),
    accent2: Color(0xFF00B394),
    onAccent: Colors.white,
    scrim: Color(0x4DFFFFFF),
    success: Color(0xFF12A66A),
    navBar: Color(0xF7FFFFFF),
  );

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? bgTop,
    Color? bgBottom,
    Color? card,
    Color? cardAlt,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? dim,
    Color? faint,
    Color? accent,
    Color? accent2,
    Color? onAccent,
    Color? scrim,
    Color? success,
    Color? navBar,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      bgTop: bgTop ?? this.bgTop,
      bgBottom: bgBottom ?? this.bgBottom,
      card: card ?? this.card,
      cardAlt: cardAlt ?? this.cardAlt,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      dim: dim ?? this.dim,
      faint: faint ?? this.faint,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      onAccent: onAccent ?? this.onAccent,
      scrim: scrim ?? this.scrim,
      success: success ?? this.success,
      navBar: navBar ?? this.navBar,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      bgTop: c(bgTop, other.bgTop),
      bgBottom: c(bgBottom, other.bgBottom),
      card: c(card, other.card),
      cardAlt: c(cardAlt, other.cardAlt),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      text: c(text, other.text),
      dim: c(dim, other.dim),
      faint: c(faint, other.faint),
      accent: c(accent, other.accent),
      accent2: c(accent2, other.accent2),
      onAccent: c(onAccent, other.onAccent),
      scrim: c(scrim, other.scrim),
      success: c(success, other.success),
      navBar: c(navBar, other.navBar),
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}