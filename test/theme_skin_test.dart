import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/theme/app_skin.dart';
import 'package:check_d/core/theme/app_theme.dart';
import 'package:check_d/core/theme/appearance_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppSkinHost.apply(AppSkin.lamb));

  group('皮肤令牌', () {
    test('三套皮肤的背景与主色互不相同', () {
      final backgrounds = AppSkin.all
          .map((s) => s.background.toARGB32())
          .toSet();
      final primaries = AppSkin.all.map((s) => s.primary.toARGB32()).toSet();
      expect(backgrounds.length, 3, reason: '三套皮肤必须有可区分的背景色');
      expect(primaries.length, 3, reason: '三套皮肤必须有可区分的主色');
    });

    test('AppColors 跟随运行时宿主切换', () {
      AppSkinHost.apply(AppSkin.slate);
      expect(AppColors.background, AppSkin.slate.background);
      expect(AppColors.ink, AppSkin.slate.ink);
      expect(AppColors.primary, AppSkin.slate.primary);

      AppSkinHost.apply(AppSkin.neutral);
      expect(AppColors.background, AppSkin.neutral.background);
      expect(AppColors.primary, AppSkin.neutral.primary);
    });

    test('三套轻玻璃皮肤均使用浅色 ThemeData', () {
      for (final skin in AppSkin.all) {
        expect(AppTheme.build(skin).brightness, Brightness.light);
      }
    });

    test('theme 的 scaffold 背景与皮肤一致', () {
      for (final skin in AppSkin.all) {
        final theme = AppTheme.build(skin);
        expect(theme.scaffoldBackgroundColor, skin.background);
      }
    });

    test('每套皮肤的强调色都不透明且可读', () {
      for (final skin in AppSkin.all) {
        for (final color in [
          skin.background,
          skin.ink,
          skin.muted,
          skin.primary,
        ]) {
          expect(color.a, 1.0, reason: '${skin.label} 存在透明的基础色');
        }
        expect(skin.surface.a, inInclusiveRange(.6, 1.0));
        // 玻璃表面允许透色，正文仍需与实际合成后的表面保持清楚对比。
        final surface = Color.alphaBlend(skin.surface, skin.background);
        final lighter = surface.computeLuminance();
        final darker = skin.ink.computeLuminance();
        expect((lighter + .05) / (darker + .05), greaterThanOrEqualTo(4.5));
        final contrast =
            (skin.ink.computeLuminance() - skin.background.computeLuminance())
                .abs();
        expect(contrast, greaterThan(0.35), reason: '${skin.label} 的正文对比度不足');
      }
    });

    test('皮肤 id 与存储键可往返', () {
      for (final skin in AppSkin.all) {
        expect(AppSkinIdX.fromStorage(skin.id.storageKey), skin.id);
      }
      expect(AppSkinIdX.fromStorage('unknown'), AppSkinId.lamb);
      expect(AppSkinIdX.fromStorage(null), AppSkinId.lamb);
    });
  });

  group('外观偏好持久化', () {
    late AppDatabase database;
    late AppearancePreferencesRepository repository;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = AppearancePreferencesRepository(database);
    });

    tearDown(() => database.close());

    test('空库读出默认皮肤与默认图标', () async {
      final prefs = await repository.load();
      expect(prefs.skin, AppSkinId.lamb);
      expect(prefs.icon, AppIconStyle.lamb);
    });

    test('保存后可原样读回', () async {
      await repository.save(
        const AppearancePreferences(
          skin: AppSkinId.slate,
          icon: AppIconStyle.neutral,
        ),
      );
      final prefs = await repository.load();
      expect(prefs.skin, AppSkinId.slate);
      expect(prefs.icon, AppIconStyle.neutral);
    });

    test('脏数据回退到默认，不抛异常', () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppearancePreferencesRepository.skinKey,
              value: 'not-a-skin',
              updatedAt: now,
            ),
          );
      final prefs = await repository.load();
      expect(prefs.skin, AppSkinId.lamb);
    });

    test('覆盖保存只保留最后一次', () async {
      await repository.save(const AppearancePreferences(skin: AppSkinId.slate));
      await repository.save(
        const AppearancePreferences(skin: AppSkinId.neutral),
      );
      final prefs = await repository.load();
      expect(prefs.skin, AppSkinId.neutral);
    });
  });
}
