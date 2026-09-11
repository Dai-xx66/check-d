import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/reminder_defaults_repository.dart';

final reminderDefaultsRepositoryProvider = Provider<ReminderDefaultsRepository>(
  (ref) => ReminderDefaultsRepository(
    database: ref.watch(appDatabaseProvider),
    userId: ref.watch(currentDataOwnerProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
  ),
);

final reminderDefaultsProvider = FutureProvider<ReminderDefaults>((ref) {
  return ref.watch(reminderDefaultsRepositoryProvider).load();
});
