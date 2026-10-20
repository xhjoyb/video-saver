import 'package:flutter/material.dart';

import 'app_palette.dart';

/// 文字层级：字号固定 6 级，颜色跟随当前调色板
class AppText {
  const AppText._();

  static TextStyle hero(BuildContext c) => TextStyle(
        fontSize: 27,
        height: 1.32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: c.palette.text,
      );

  static TextStyle title(BuildContext c) => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: c.palette.text,
      );

  static TextStyle section(BuildContext c) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: c.palette.text,
      );

  static TextStyle body(BuildContext c) => TextStyle(
        fontSize: 13.5,
        height: 1.5,
        color: c.palette.text,
      );

  static TextStyle sub(BuildContext c) => TextStyle(
        fontSize: 12.5,
        height: 1.5,
        color: c.palette.dim,
      );

  static TextStyle label(BuildContext c) => TextStyle(
        fontSize: 11.5,
        height: 1.4,
        color: c.palette.faint,
      );
}

ThemeData buildAppTheme(AppPalette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent2,
    onSecondary: p.onAccent,
    error: const Color(0xFFFF5A5A),
    onError: Colors.white,
    surface: p.card,
    onSurface: p.text,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
  );

  return base.copyWith(
    // 背景由 AppBackground 提供，页面自身透明
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    extensions: <ThemeExtension<dynamic>>[p],
    textTheme: base.textTheme.apply(
      bodyColor: p.text,
      displayColor: p.text,
    ),
    dividerColor: p.border,
    splashColor: p.text.withOpacity(0.05),
    highlightColor: Colors.transparent,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.cardAlt,
      contentTextStyle: TextStyle(color: p.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.borderStrong),
      ),
    ),
  );
}