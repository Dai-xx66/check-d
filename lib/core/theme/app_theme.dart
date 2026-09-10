import 'package:flutter/material.dart';

abstract final class AppColors {
  // Check D v1 keeps the canvas warm and quiet. Pink is an action/status
  // accent rather than the page background.
  static const background = Color(0xFFFFFBF7);
  static const surface = Color(0xFFFFFEFC);
  static const surfaceSoft = Color(0xFFFFF8F5);
  static const glass = Color(0xCFFFFFFF);
  static const glassStrong = Color(0xE8FFFFFF);
  static const ink = Color(0xFF3F3435);
  static const muted = Color(0xFF918588);
  static const border = Color(0xFFF1E8E5);
  static const primary = Color(0xFFF47F9E);
  static const primaryStrong = Color(0xFFEA668A);
  static const current = Color(0xFFE94E68);
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
  static const control = Radius.circular(12);
  static const chip = Radius.circular(14);
  static const card = Radius.circular(16);
  static const importantCard = Radius.circular(20);
  static const feature = Radius.circular(24);
  static const sheet = Radius.circular(28);
  static const section = importantCard;
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const page = 16.0;
}

abstract final class AppMotion {
  static const quick = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 220);
  static const emphasis = Duration(milliseconds: 300);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration value) {
    return MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : value;
  }
}

abstract final class AppShadows {
  static const soft = BoxShadow(
    color: Color(0x0D40252B),
    blurRadius: 16,
    offset: Offset(0, 6),
  );

  static const glass = BoxShadow(
    color: Color(0x1240252B),
    blurRadius: 20,
    offset: Offset(0, 8),
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
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
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
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(AppRadius.card),
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
