import 'package:check_d/app/app.dart';
import 'package:check_d/app/app_providers.dart';
import 'package:check_d/core/config/app_config.dart';
import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/theme/app_skin.dart';
import 'package:check_d/core/theme/app_theme.dart';
import 'package:check_d/core/theme/appearance_preferences.dart';
import 'package:check_d/features/profile/presentation/appearance_settings_page.dart';
import 'package:check_d/shared/widgets/check_d_design.dart';
import 'package:check_d/shared/widgets/mascot.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  tearDown(() => AppSkinHost.apply(AppSkin.lamb));

  testWidgets('decorative poses keep their semantic status across skins', (
    tester,
  ) async {
    for (final skin in AppSkin.all) {
      AppSkinHost.apply(skin);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(skin),
          home: const Scaffold(
            body: CheckDSheep(
              state: SheepState.idle,
              artworkState: SheepState.breakTime,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('check-d-sheep-idle')),
      );
      final expectedAsset = skin.id == AppSkinId.lamb
          ? sheepAssetFor(SheepState.idle)
          : 'assets/images/sheep_${skin.id.name}_break.png';
      expect((image.image as AssetImage).assetName, expectedAsset);
      expect(find.bySemanticsLabel('小羊状态：空闲'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shared glass surfaces use the selected palette', (tester) async {
    AppSkinHost.apply(AppSkin.slate);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppSkin.slate),
        home: const Scaffold(body: CheckDSurface(child: Text('专注'))),
      ),
    );
    final container = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(CheckDSurface),
            matching: find.byType(AnimatedContainer),
          )
          .last,
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      AppSkin.slate.surface,
    );
    expect(
      Theme.of(tester.element(find.text('专注'))).brightness,
      Brightness.light,
    );
  });

  testWidgets('changing skin preserves the settings route and selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
          ),
          appDatabaseProvider.overrideWithValue(database),
          supabaseClientProvider.overrideWithValue(null),
        ],
        child: const CheckDApp(),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.text('欢迎回来'));
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AppearanceSettingsPage()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('雾蓝'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('雾蓝'));
    await tester.pumpAndSettle();
    expect(find.text('外观设置'), findsOneWidget);
    expect(find.text('找到舒服的日常。'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('外观设置'))).brightness,
      Brightness.light,
    );
    expect(
      (await AppearancePreferencesRepository(database).load()).skin,
      AppSkinId.slate,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
