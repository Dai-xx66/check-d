import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFFFF7F8);
  static const surface = Color(0xEFFFFBFC);
  static const glass = Color(0xCFFFFFFF);
  static const glassStrong = Color(0xE8FFFFFF);
  static const ink = Color(0xFF533B3D);
  static const muted = Color(0xFF9C7D82);
  static const border = Color(0xFFFFE2E8);
  static const primary = Color(0xFFF17F9D);
  static const green = Color(0xFF7CBFA2);
  static const orange = Color(0xFFF2AB79);
  static const purple = Color(0xFFA58AE2);
  static const red = Color(0xFFE9788B);
  static const cyan = Color(0xFF78B9C7);
  static const blush = Color(0xFFFFE7ED);
  static const lavender = Color(0xFFF0EBFF);
  static const blueMist = Color(0xFFE6F2FF);
  static const cream = Color(0xFFFFF4E8);
  static const creamYellow = Color(0xFFF5C96B);
  static const mint = Color(0xFFE5F6EC);

  // Shared functional accents: pink, lavender, blue, and mint.
  static const accentPink = Color(0xFFF17F9D);
  static const accentLavender = Color(0xFFA58AE2);
  static const accentBlue = Color(0xFF8FAFEA);
  static const accentMint = Color(0xFF7CBFA2);
}

abstract final class AppRadius {
  static const card = Radius.circular(24);
  static const section = Radius.circular(20);
  static const control = Radius.circular(14);
}

abstract final class AppShadows {
  static const soft = BoxShadow(
    color: Color(0x100F0010),
    blurRadius: 18,
    offset: Offset(0, 7),
  );

  static const glass = BoxShadow(
    color: Color(0x140F0010),
    blurRadius: 14,
    offset: Offset(0, 5),
  );
}

abstract final class AppGradients {
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.purple],
  );
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        bodyMedium: TextStyle(color: AppColors.ink, height: 1.45),
        bodySmall: TextStyle(color: AppColors.muted, height: 1.4),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 1,
        shadowColor: Color(0x140F0010),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xCCFFFFFF),
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: Color(0xFFFFB8C8)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: const StadiumBorder(),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xF9FFF9FA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xF9FFF9FA),
        elevation: 0,
        height: 76,
        indicatorColor: AppColors.blush,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.blush,
        selectedIconTheme: IconThemeData(color: AppColors.primary),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerColor: AppColors.border,
    );
  }
}
