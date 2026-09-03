import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/app_providers.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/notifications/notification_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  await notificationService.initialize();

  const config = AppConfig.fromEnvironment();
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
        appDatabaseProvider.overrideWithValue(AppDatabase()),
        supabaseClientProvider.overrideWithValue(supabaseClient),
      ],
      child: const CheckDApp(),
    ),
  );
}
