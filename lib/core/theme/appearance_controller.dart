import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import 'app_skin.dart';
import 'appearance_preferences.dart';

final appearanceRepositoryProvider = Provider<AppearancePreferencesRepository>(
  (ref) => AppearancePreferencesRepository(ref.watch(appDatabaseProvider)),
);

/// 外观状态：皮肤 + 图标。
///
/// 副作用的边界：
/// - `build()` 会把持久化的皮肤写入 `AppSkinHost`，保证热重启后首帧正确；
/// - `select*` 先改内存令牌再落库，保证点击后立即变色（不等 IO）。
///
/// 注意：颜色令牌变更不会自动触发已有页面重建，
/// 依赖的是 `MaterialApp.theme` 变化 —— 所有读过 `Theme.of(context)` 的
/// 页面会自动 rebuild。`AppShell` 已显式建立该依赖，无需每个页面单独处理。
class AppearanceController extends AsyncNotifier<AppearancePreferences> {
  Future<void> _saveTail = Future<void>.value();
  AppearancePreferences _lastSaved = const AppearancePreferences();

  @override
  Future<AppearancePreferences> build() async {
    final prefs = await ref.watch(appearanceRepositoryProvider).load();
    if (ref.mounted) {
      _lastSaved = prefs;
      AppSkinHost.apply(AppSkin.of(prefs.skin));
    }
    return prefs;
  }

  Future<void> selectSkin(AppSkinId id) async {
    // Do not overwrite another saved preference with its default while the
    // initial database read is still in flight.
    if (state.isLoading || !state.hasValue) await future;
    if (!ref.mounted) return;
    final current = state.requireValue;
    if (current.skin == id) return;
    AppSkinHost.apply(AppSkin.of(id));
    final next = current.copyWith(skin: id);
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> selectIcon(AppIconStyle style) async {
    if (state.isLoading || !state.hasValue) await future;
    if (!ref.mounted) return;
    final current = state.requireValue;
    if (current.icon == style) return;
    final next = current.copyWith(icon: style);
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> _save(AppearancePreferences next) {
    final repository = ref.read(appearanceRepositoryProvider);
    final write = _saveTail.then((_) async {
      try {
        await repository.save(next);
        _lastSaved = next;
      } catch (_) {
        // A failed older write must not undo a newer optimistic selection.
        // If this is still the active choice, restore the last durable value
        // so selecting the same option again actually retries the save.
        if (ref.mounted && identical(state.value, next)) {
          state = AsyncData(_lastSaved);
          AppSkinHost.apply(AppSkin.of(_lastSaved.skin));
        }
        rethrow;
      }
    });
    // Serialize writes, but keep the queue usable after a failed operation.
    _saveTail = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}

final appearanceControllerProvider =
    AsyncNotifierProvider<AppearanceController, AppearancePreferences>(
      AppearanceController.new,
    );
