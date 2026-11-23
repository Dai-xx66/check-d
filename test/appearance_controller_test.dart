import 'dart:async';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/theme/app_skin.dart';
import 'package:check_d/core/theme/appearance_controller.dart';
import 'package:check_d/core/theme/appearance_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ControlledAppearanceRepository extends AppearancePreferencesRepository {
  _ControlledAppearanceRepository(super.database);

  AppearancePreferences saved = const AppearancePreferences();
  Completer<AppearancePreferences>? pendingLoad;
  final writes = <AppearancePreferences>[];
  final writeGates = <Completer<void>>[];
  bool failNextWrite = false;

  @override
  Future<AppearancePreferences> load() async =>
      pendingLoad == null ? saved : await pendingLoad!.future;

  @override
  Future<void> save(AppearancePreferences value) async {
    writes.add(value);
    if (writeGates.isNotEmpty) await writeGates.removeAt(0).future;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Simulated local storage failure');
    }
    saved = value;
  }
}

void main() {
  late AppDatabase database;
  late _ControlledAppearanceRepository repository;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = _ControlledAppearanceRepository(database);
    container = ProviderContainer(
      overrides: [appearanceRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    AppSkinHost.apply(AppSkin.lamb);
  });

  test('failed appearance save restores the saved choice and can be retried',
      () async {
    await container.read(appearanceControllerProvider.future);
    final controller = container.read(appearanceControllerProvider.notifier);
    repository.failNextWrite = true;

    await expectLater(controller.selectSkin(AppSkinId.slate), throwsStateError);

    expect(container.read(appearanceControllerProvider).requireValue.skin,
        AppSkinId.lamb);
    expect(AppSkinHost.current.id, AppSkinId.lamb);
    await controller.selectSkin(AppSkinId.slate);
    expect(repository.writes, hasLength(2));
    expect(repository.saved.skin, AppSkinId.slate);
    expect(AppSkinHost.current.id, AppSkinId.slate);
  });

  test('selection during initial load preserves the other saved preference',
      () async {
    repository.pendingLoad = Completer<AppearancePreferences>();
    final initialLoad = container.read(appearanceControllerProvider.future);
    final controller = container.read(appearanceControllerProvider.notifier);
    final selection = controller.selectSkin(AppSkinId.slate);
    repository.pendingLoad!.complete(
      const AppearancePreferences(icon: AppIconStyle.neutral),
    );

    await initialLoad;
    await selection;

    final prefs = container.read(appearanceControllerProvider).requireValue;
    expect(prefs.skin, AppSkinId.slate);
    expect(prefs.icon, AppIconStyle.neutral);
    expect(repository.saved.skin, AppSkinId.slate);
    expect(repository.saved.icon, AppIconStyle.neutral);
  });

  test('rapid skin and icon selections persist in the order they were made',
      () async {
    await container.read(appearanceControllerProvider.future);
    final controller = container.read(appearanceControllerProvider.notifier);
    final firstWrite = Completer<void>();
    repository.writeGates.add(firstWrite);

    final skinSelection = controller.selectSkin(AppSkinId.slate);
    final iconSelection = controller.selectIcon(AppIconStyle.neutral);
    await Future<void>.delayed(Duration.zero);

    // The newer preference must not finish before the delayed older write and
    // then be overwritten when that older write eventually completes.
    expect(repository.writes, hasLength(1));
    firstWrite.complete();
    await Future.wait([skinSelection, iconSelection]);

    expect(repository.saved.skin, AppSkinId.slate);
    expect(repository.saved.icon, AppIconStyle.neutral);
    expect(container.read(appearanceControllerProvider).requireValue.icon,
        AppIconStyle.neutral);
  });
}
