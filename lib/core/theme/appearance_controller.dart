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
  @override
  Future<AppearancePreferences> build() async {
    final prefs = await ref.watch(appearanceRepositoryProvider).load();
    AppSkinHost.apply(AppSkin.of(prefs.skin));
    return prefs;
  }

  Future<void> selectSkin(AppSkinId id) async {
    final current = state.value ?? const AppearancePreferences();
    if (current.skin == id) return;
    AppSkinHost.apply(AppSkin.of(id));
    final next = current.copyWith(skin: id);
    state = AsyncData(next);
    await ref.read(appearanceRepositoryProvider).save(next);
  }

  Future<void> selectIcon(AppIconStyle style) async {
    final current = state.value ?? const AppearancePreferences();
    if (current.icon == style) return;
    final next = current.copyWith(icon: style);
    state = AsyncData(next);
    await ref.read(appearanceRepositoryProvider).save(next);
  }
}

final appearanceControllerProvider =
    AsyncNotifierProvider<AppearanceController, AppearancePreferences>(
      AppearanceController.new,
    );
