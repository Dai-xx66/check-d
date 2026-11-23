import 'package:flutter/material.dart';

import 'app_skin.dart';

/// 语义色令牌。
///
/// 全部是 **getter**，读 `AppSkinHost.current`，所以：
/// - 换肤后所有引用自动跟随，不需要改页面代码；
/// - 代价是不能再用在 `const` 构造里（本文件与相关调用点已去掉 const）。
///
/// 新增页面请继续使用 `AppColors.xxx`，不要写死 `Color(0x...)`，
/// 否则该处会成为换肤后的“花斑”。
abstract final class AppColors {
  static AppSkin get _s => AppSkinHost.current;

  static Color get background => _s.background;
  static Color get surface => _s.surface;
  static Color get surfaceSoft => _s.surfaceSoft;
  static Color get glass => _s.glass;
  static Color get glassStrong => _s.glassStrong;
  static Color get ink => _s.ink;
  static Color get muted => _s.muted;
  static Color get border => _s.border;
  static Color get primary => _s.primary;
  static Color get primaryStrong => _s.primaryStrong;
  static Color get current => _s.current;
  static Color get green => _s.green;
  static Color get orange => _s.orange;
  static Color get purple => _s.purple;
  static Color get red => _s.red;
  static Color get cyan => _s.cyan;
  static Color get blush => _s.blush;
  static Color get lavender => _s.lavender;
  static Color get blueMist => _s.blueMist;
  static Color get cream => _s.cream;
  static Color get creamYellow => _s.creamYellow;
  static Color get mint => _s.mint;

  static Color get accentPink => _s.accentPink;
  static Color get accentLavender => _s.accentLavender;
  static Color get accentBlue => _s.accentBlue;
  static Color get accentMint => _s.accentMint;

  static Color get onPrimary => _s.onPrimary;
  static Color get heroSurface => _s.isDark ? _s.blueMist : _s.surfaceSoft;

  /// 深色皮肤下，卡片内“再抬高一层”的填充。
  static Color get elevatedFill =>
      _s.isDark ? const Color(0x0AFFFFFF) : const Color(0x66FFFFFF);
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
  static BoxShadow get soft => AppSkinHost.current.softShadow;
  static BoxShadow get glass => AppSkinHost.current.glassShadow;
}

abstract final class AppGradients {
  static LinearGradient get primary => AppSkinHost.current.primaryGradient;

  static LinearGradient get backdrop => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.alphaBlend(
        AppColors.accentBlue.withValues(alpha: .13),
        AppColors.background,
      ),
      AppColors.background,
      Color.alphaBlend(
        AppColors.accentLavender.withValues(alpha: .1),
        AppColors.background,
      ),
    ],
  );

  static LinearGradient get header => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.heroSurface, AppColors.surface],
  );

  static LinearGradient get sidebar => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.surface, AppColors.surfaceSoft],
  );
}

abstract final class AppTheme {
  /// 兼容既有调用点。
  static ThemeData get light => build(AppSkinHost.current);

  static ThemeData build(AppSkin skin) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: skin.primary,
          brightness: skin.brightness,
          surface: skin.surface,
        ).copyWith(
          primary: skin.primary,
          onPrimary: skin.onPrimary,
          onSurface: skin.ink,
          onSurfaceVariant: skin.muted,
          outline: skin.muted,
          outlineVariant: skin.border,
        );

    final sheetSurface = skin.surface.withValues(
      alpha: skin.isDark ? 0.96 : 0.98,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: skin.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: skin.background,
      canvasColor: skin.background,
      disabledColor: skin.muted.withValues(alpha: .5),
      iconTheme: IconThemeData(color: skin.muted, size: 22),
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: skin.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: skin.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: skin.ink,
        ),
        bodyMedium: TextStyle(color: skin.ink, height: 1.45),
        bodySmall: TextStyle(color: skin.muted, height: 1.4),
        bodyLarge: TextStyle(color: skin.ink, fontSize: 16, height: 1.5),
      ),
      cardTheme: CardThemeData(
        color: skin.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(AppRadius.card),
          side: BorderSide(color: skin.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: skin.isDark ? skin.surfaceSoft : const Color(0xCCFFFFFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: skin.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: skin.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: skin.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: skin.primary,
          foregroundColor: skin.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: skin.primary,
          side: BorderSide(color: skin.primary.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: const StadiumBorder(),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: skin.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: skin.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: skin.isDark ? skin.surface : const Color(0xF9FFF9FA),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          side: BorderSide(color: skin.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sheetSurface,
        elevation: 0,
        height: 76,
        indicatorColor: skin.blush,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: skin.blush,
        selectedIconTheme: IconThemeData(color: skin.primary),
        selectedLabelTextStyle: TextStyle(
          color: skin.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerColor: skin.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: skin.isDark ? skin.surfaceSoft : skin.ink,
        contentTextStyle: TextStyle(
          color: skin.isDark ? skin.ink : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
