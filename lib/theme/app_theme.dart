import 'package:flutter/material.dart';

/// 深色科技感配色：近黑底 + 珊瑚红主色 + 青色点缀
class AppColors {
  const AppColors._();

  static const bg = Color(0xFF08080C);
  static const bgSoft = Color(0xFF0E0E15);
  static const surface = Color(0xFF12121B);
  static const surfaceAlt = Color(0xFF1A1A26);

  static const accent = Color(0xFFFF3B5C);
  static const accentEnd = Color(0xFFFF7A45);
  static const cyan = Color(0xFF22D3EE);

  static const text = Color(0xFFF4F5FA);
  static const textDim = Color(0xFFA2A7BA);
  static const textFaint = Color(0xFF6B7085);

  static const border = Color(0xFF242433);
  static const success = Color(0xFF3DDC97);
}

class AppGradients {
  const AppGradients._();

  /// 主品牌渐变（按钮、Logo、强调块）
  static const brand = LinearGradient(
    colors: [AppColors.accent, AppColors.accentEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 卡片顶部微光
  static const cardSheen = LinearGradient(
    colors: [Color(0x14FFFFFF), Color(0x06FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 平台图标的柔和底
  static const ice = LinearGradient(
    colors: [Color(0x3322D3EE), Color(0x11FF3B5C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.cyan,
      onSecondary: Color(0xFF00131A),
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: Color(0xFFFF5A5A),
      onError: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: base.textTheme.copyWith(
        displaySmall: const TextStyle(
          fontSize: 30,
          height: 1.24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: AppColors.text,
        ),
        headlineSmall: const TextStyle(
          fontSize: 21,
          height: 1.3,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: AppColors.text,
        ),
        titleMedium: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13.5,
          height: 1.55,
          color: AppColors.textDim,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.45,
          color: AppColors.textFaint,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerColor: AppColors.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
        actionTextColor: AppColors.cyan,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      splashColor: Colors.white.withOpacity(0.04),
      highlightColor: Colors.transparent,
    );
  }
}
