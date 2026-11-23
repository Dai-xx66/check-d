import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/app_providers.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/notifications/notification_providers.dart';
import 'core/platform/desktop_mini_window.dart';
import 'core/theme/app_skin.dart';
import 'core/theme/appearance_preferences.dart';
import 'features/mini_window/presentation/mini_window_page.dart';
import 'features/tasks/application/task_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');

  const config = AppConfig.fromEnvironment();
  final windowArguments = await currentDesktopWindowArguments();
  final database = AppDatabase();

  // 皮肤必须在 runApp 之前写进运行时宿主，否则首帧会用默认皮肤闪一下。
  // 读失败不阻断启动：`load()` 内部已对缺失/脏值回退到默认皮肤。
  final appearance = await AppearancePreferencesRepository(database).load();
  AppSkinHost.apply(AppSkin.of(appearance.skin));

  if (windowArguments.isMiniWindow) {
    runApp(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          appDatabaseProvider.overrideWithValue(database),
          supabaseClientProvider.overrideWithValue(null),
          currentDataOwnerProvider.overrideWithValue(windowArguments.ownerId!),
        ],
        child: MiniWindowApp(ownerId: windowArguments.ownerId!),
      ),
    );
    return;
  }

  await notificationService.initialize();
  SupabaseClient? supabaseClient;

  if (config.hasCloudConfiguration) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
    );
    supabaseClient = Supabase.instance.client;
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        appDatabaseProvider.overrideWithValue(database),
        supabaseClientProvider.overrideWithValue(supabaseClient),
      ],
      child: const CheckDApp(),
    ),
  );
}
