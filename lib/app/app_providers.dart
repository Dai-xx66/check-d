import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/database/app_database.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('AppConfig must be overridden in main.'),
);

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('AppDatabase must be overridden in main.'),
);

final supabaseClientProvider = Provider<SupabaseClient?>(
  (ref) =>
      throw UnimplementedError('SupabaseClient must be overridden in main.'),
);

/// Increments when the independent desktop mini window changes persisted data.
/// Consumers recreate their Drift streams instead of keeping a second state.
class MiniWindowDataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final miniWindowDataRevisionProvider =
    NotifierProvider<MiniWindowDataRevision, int>(MiniWindowDataRevision.new);
