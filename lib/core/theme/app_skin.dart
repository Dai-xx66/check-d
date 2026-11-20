import 'package:flutter/material.dart';

/// 可切换的外观皮肤。
///
/// 设计约束（重要）：
/// 1. **只换视觉令牌，不换结构**。三套皮肤共用同一套页面骨架、间距与圆角，
///    差异只发生在颜色、阴影、渐变上。这样任何页面都不需要为皮肤写分支。
/// 2. **皮肤是运行时可变的**，所以颜色不能是 `const`。
///    全仓库 385 处 `AppColors.xxx` 通过 getter 读取当前皮肤，
///    新增页面只要继续用 `AppColors`，就自动跟随皮肤，不需要额外适配。
/// 3. 皮肤只存本地（设备偏好），不参与云同步。
enum AppSkinId { lamb, slate, neutral }

extension AppSkinIdX on AppSkinId {
  String get storageKey => switch (this) {
    AppSkinId.lamb => 'lamb',
    AppSkinId.slate => 'slate',
    AppSkinId.neutral => 'neutral',
  };

  static AppSkinId fromStorage(String? raw) => switch (raw) {
    'slate' => AppSkinId.slate,
    'neutral' => AppSkinId.neutral,
    _ => AppSkinId.lamb,
  };
}

@immutable
class AppSkin {
  const AppSkin({
    required this.id,
    required this.label,
    required this.tagline,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.glass,
    required this.glassStrong,
    required this.ink,
    required this.muted,
    required this.border,
    required this.primary,
    required this.primaryStrong,
    required this.current,
    required this.green,
    required this.orange,
    required this.purple,
    required this.red,
    required this.cyan,
    required this.blush,
    required this.lavender,
    required this.blueMist,
    required this.cream,
    required this.creamYellow,
    required this.mint,
    required this.accentPink,
    required this.accentLavender,
    required this.accentBlue,
    required this.accentMint,
    required this.softShadow,
    required this.glassShadow,
    required this.gradientStart,
    required this.gradientEnd,
    required this.onPrimary,
    required this.logoAsset,
  });

  final AppSkinId id;
  final String label;
  final String tagline;
  final Brightness brightness;

  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color glass;
  final Color glassStrong;
  final Color ink;
  final Color muted;
  final Color border;
  final Color primary;
  final Color primaryStrong;
  final Color current;
  final Color green;
  final Color orange;
  final Color purple;
  final Color red;
  final Color cyan;
  final Color blush;
  final Color lavender;
  final Color blueMist;
  final Color cream;
  final Color creamYellow;
  final Color mint;
  final Color accentPink;
  final Color accentLavender;
  final Color accentBlue;
  final Color accentMint;

  final BoxShadow softShadow;
  final BoxShadow glassShadow;
  final Color gradientStart;
  final Color gradientEnd;
  final Color onPrimary;
  final String logoAsset;

  LinearGradient get primaryGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );

  bool get isDark => brightness == Brightness.dark;

  /// 「小羊日常」——现有默认皮肤，暖白 + 四色强调 + 轻玻璃。
  static const lamb = AppSkin(
    id: AppSkinId.lamb,
    label: '小羊日常',
    tagline: '暖白 · 四色 · 轻玻璃',
    brightness: Brightness.light,
    background: Color(0xFFFFFBF7),
    surface: Color(0xFFFFFEFC),
    surfaceSoft: Color(0xFFFFF8F5),
    glass: Color(0xCFFFFFFF),
    glassStrong: Color(0xE8FFFFFF),
    ink: Color(0xFF3F3435),
    muted: Color(0xFF918588),
    border: Color(0xFFF1E8E5),
    primary: Color(0xFFF47F9E),
    primaryStrong: Color(0xFFEA668A),
    current: Color(0xFFE94E68),
    green: Color(0xFF7CBFA2),
    orange: Color(0xFFF2AB79),
    purple: Color(0xFFA58AE2),
    red: Color(0xFFE9788B),
    cyan: Color(0xFF78B9C7),
    blush: Color(0xFFFFE7ED),
    lavender: Color(0xFFF0EBFF),
    blueMist: Color(0xFFE6F2FF),
    cream: Color(0xFFFFF4E8),
    creamYellow: Color(0xFFF5C96B),
    mint: Color(0xFFE5F6EC),
    accentPink: Color(0xFFF17F9D),
    accentLavender: Color(0xFFA58AE2),
    accentBlue: Color(0xFF8FAFEA),
    accentMint: Color(0xFF7CBFA2),
    softShadow: BoxShadow(
      color: Color(0x0D40252B),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
    glassShadow: BoxShadow(
      color: Color(0x1240252B),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
    gradientStart: Color(0xFFF47F9E),
    gradientEnd: Color(0xFFA58AE2),
    onPrimary: Colors.white,
    logoAsset: 'assets/images/app_icon_lamb.png',
  );

  /// 珍珠白与低饱和雾蓝，使用浅色玻璃面板。
  static const slate = AppSkin(
    id: AppSkinId.slate,
    label: '雾蓝',
    tagline: '珍珠白 · 雾蓝 · 轻盈玻璃',
    brightness: Brightness.light,
    background: Color(0xFFEDF3F8),
    surface: Color(0xD9FFFFFF),
    surfaceSoft: Color(0xFFEEF3F8),
    glass: Color(0xA8FFFFFF),
    glassStrong: Color(0xCFFFFFFF),
    ink: Color(0xFF2C4055),
    muted: Color(0xFF596E82),
    border: Color(0xBAFFFFFF),
    primary: Color(0xFF4C7294),
    primaryStrong: Color(0xFF3D688D),
    current: Color(0xFFC26B8D),
    green: Color(0xFF6D9B8B),
    orange: Color(0xFFB48A60),
    purple: Color(0xFF9384BC),
    red: Color(0xFFC26B8D),
    cyan: Color(0xFF6B9DAA),
    blush: Color(0xA8DCEAF7),
    lavender: Color(0xB3EBE7F7),
    blueMist: Color(0xC4DEECF9),
    cream: Color(0xB3F7EDDF),
    creamYellow: Color(0xFFB99858),
    mint: Color(0xB3E1F0E8),
    accentPink: Color(0xFFC58DA5),
    accentLavender: Color(0xFF9384BC),
    accentBlue: Color(0xFF7A9CBE),
    accentMint: Color(0xFF6D9B8B),
    softShadow: BoxShadow(
      color: Color(0x08607B98),
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
    glassShadow: BoxShadow(
      color: Color(0x14607B98),
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
    gradientStart: Color(0xFF4C7294),
    gradientEnd: Color(0xFF64749D),
    onPrimary: Colors.white,
    logoAsset: 'assets/images/app_icon_mist_d.png',
  );

  /// 暖纸白与奶油黄，适合日常学习与工作。
  static const neutral = AppSkin(
    id: AppSkinId.neutral,
    label: '素纸',
    tagline: '暖白 · 奶油黄 · 清透日常',
    brightness: Brightness.light,
    background: Color(0xFFF7F5EE),
    surface: Color(0xD9FFFFFC),
    surfaceSoft: Color(0xFFF5F0E4),
    glass: Color(0xA8FFFFFC),
    glassStrong: Color(0xCFFFFFFC),
    ink: Color(0xFF4A4032),
    muted: Color(0xFF776B5A),
    border: Color(0xD9FFFFFF),
    primary: Color(0xFF96753D),
    primaryStrong: Color(0xFF7D5E2A),
    current: Color(0xFFC26075),
    green: Color(0xFF507E64),
    orange: Color(0xFF9D6C3D),
    purple: Color(0xFF8270A6),
    red: Color(0xFFBD5367),
    cyan: Color(0xFF4A7D88),
    blush: Color(0xFFF3E8CE),
    lavender: Color(0xFFEFEBF5),
    blueMist: Color(0xFFE8EFF5),
    cream: Color(0xFFF4EEE1),
    creamYellow: Color(0xFF9D7938),
    mint: Color(0xFFE4EEE6),
    accentPink: Color(0xFFB96D83),
    accentLavender: Color(0xFF8270A6),
    accentBlue: Color(0xFF6586A5),
    accentMint: Color(0xFF507E64),
    softShadow: BoxShadow(
      color: Color(0x08273C35),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
    glassShadow: BoxShadow(
      color: Color(0x10273C35),
      blurRadius: 22,
      offset: Offset(0, 8),
    ),
    gradientStart: Color(0xFF96753D),
    gradientEnd: Color(0xFF9B7D47),
    onPrimary: Colors.white,
    logoAsset: 'assets/images/app_icon_cream_d.png',
  );

  static const all = <AppSkin>[lamb, slate, neutral];

  static AppSkin of(AppSkinId id) => switch (id) {
    AppSkinId.lamb => lamb,
    AppSkinId.slate => slate,
    AppSkinId.neutral => neutral,
  };
}

/// 皮肤的运行时宿主。
///
/// 为什么用静态可变量而不是 ThemeExtension：
/// 现有代码有 385 处 `AppColors.xxx` 与 63 处 const 上下文，改成
/// `context.colors.xxx` 需要动 31 个文件、且每个 build 都要拿 context；
/// 一旦漏改某处，那处就会永远停在默认皮肤（换肤后出现“花斑”）。
/// 用静态宿主 + 整树重建，可以做到 **新增页面零适配成本**，
/// 代价是换肤时必须重建整棵树（见 `CheckDApp` 里的 ValueKey）。
abstract final class AppSkinHost {
  static AppSkin _current = AppSkin.lamb;

  static AppSkin get current => _current;

  static void apply(AppSkin skin) {
    _current = skin;
  }
}
