import '../database/app_database.dart';
import 'app_skin.dart';

/// 应用图标风格。与皮肤独立选择，允许「夜航皮肤 + 小羊图标」这种组合。
enum AppIconStyle { lamb, slate, neutral }

extension AppIconStyleX on AppIconStyle {
  String get storageKey => switch (this) {
    AppIconStyle.lamb => 'lamb',
    AppIconStyle.slate => 'slate',
    AppIconStyle.neutral => 'neutral',
  };

  String get label => switch (this) {
    AppIconStyle.lamb => '小羊',
    AppIconStyle.slate => '雾蓝',
    AppIconStyle.neutral => '素纸',
  };

  /// 桌面/启动器展示用的大图（1024 长边，带透明边距）。
  String get previewAsset => switch (this) {
    AppIconStyle.lamb => 'assets/images/app_icon_lamb.png',
    AppIconStyle.slate => 'assets/images/app_icon_mist_d.png',
    AppIconStyle.neutral => 'assets/images/app_icon_cream_d.png',
  };

  static AppIconStyle fromStorage(String? raw) => switch (raw) {
    'slate' => AppIconStyle.slate,
    'neutral' => AppIconStyle.neutral,
    _ => AppIconStyle.lamb,
  };
}

class AppearancePreferences {
  const AppearancePreferences({
    this.skin = AppSkinId.lamb,
    this.icon = AppIconStyle.lamb,
  });

  final AppSkinId skin;
  final AppIconStyle icon;

  AppearancePreferences copyWith({AppSkinId? skin, AppIconStyle? icon}) =>
      AppearancePreferences(skin: skin ?? this.skin, icon: icon ?? this.icon);
}

/// 外观偏好只存本机（`AppSettings` 键值表），不参与云同步。
///
/// 理由：皮肤是设备/屏幕相关的偏好，同一账号在手机与桌面上适合不同皮肤；
/// 同步反而会造成「在手机上切了深色，桌面跟着变」的意外。
class AppearancePreferencesRepository {
  AppearancePreferencesRepository(this.database);

  final AppDatabase database;

  static const skinKey = 'appearance.skin';
  static const iconKey = 'appearance.icon';

  Future<AppearancePreferences> load() async {
    final rows = await (database.select(
      database.appSettings,
    )..where((row) => row.key.isIn([skinKey, iconKey]))).get();

    String? skinRaw;
    String? iconRaw;
    for (final row in rows) {
      if (row.key == skinKey) skinRaw = row.value;
      if (row.key == iconKey) iconRaw = row.value;
    }
    return AppearancePreferences(
      skin: AppSkinIdX.fromStorage(skinRaw),
      icon: AppIconStyleX.fromStorage(iconRaw),
    );
  }

  Future<void> save(AppearancePreferences value) async {
    final now = DateTime.now().toUtc();
    await database.batch((batch) {
      batch.insertAllOnConflictUpdate(database.appSettings, [
        AppSettingsCompanion.insert(
          key: skinKey,
          value: value.skin.storageKey,
          updatedAt: now,
        ),
        AppSettingsCompanion.insert(
          key: iconKey,
          value: value.icon.storageKey,
          updatedAt: now,
        ),
      ]);
    });
  }
}
