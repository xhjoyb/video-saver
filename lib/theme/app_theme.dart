import 'package:flutter/material.dart';

/// 深色基底：纯黑背景 + 实色卡片（避免玻璃层在纯黑上失效）
class AppColors {
  const AppColors._();

  static const bg = Color(0xFF08080C);
  static const card = Color(0xFF12121A);
  static const cardAlt = Color(0xFF181822);
  static const border = Color(0xFF23232F);
  static const borderStrong = Color(0xFF2E2E3C);

  static const accent = Color(0xFFFF3B5C);
  static const accent2 = Color(0xFFFF7A45);
  static const success = Color(0xFF3DDC97);

  static const text = Color(0xFFF2F3F7);
  static const dim = Color(0xFF9DA2B4);
  static const faint = Color(0xFF676C7E);
}

/// 收敛到 6 个字号层级，避免满屏层级互相竞争
class AppText {
  const AppText._();

  static const hero = TextStyle(
    fontSize: 27,
    height: 1.32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.text,
  );

  static const title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.text,
  );

  static const section = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  static const body = TextStyle(
    fontSize: 13.5,
    height: 1.5,
    color: AppColors.text,
  );

  static const sub = TextStyle(
    fontSize: 12.5,
    height: 1.5,
    color: AppColors.dim,
  );

  static const label = TextStyle(
    fontSize: 11.5,
    height: 1.4,
    color: AppColors.faint,
  );
}

class AppGradients {
  const AppGradients._();

  static const brand = LinearGradient(
    colors: [AppColors.accent, AppColors.accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        onPrimary: Colors.white,
        secondary: AppColors.accent2,
        onSecondary: Colors.white,
        surface: AppColors.card,
        onSurface: AppColors.text,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      dividerColor: AppColors.border,
      splashColor: Colors.white.withOpacity(0.04),
      highlightColor: Colors.transparent,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cardAlt,
        contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
      ),
    );
  }
}