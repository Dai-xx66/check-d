import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/task_repository.dart';
import '../domain/task_models.dart';

final currentDataOwnerProvider = Provider<String>((ref) {
  return ref.watch(supabaseClientProvider)?.auth.currentUser?.id ??
      'offline-user';
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    userId: ref.watch(currentDataOwnerProvider),
  );
});

final tasksForDateProvider = StreamProvider.autoDispose
    .family<List<TaskDetails>, DateTime>((ref, date) {
      return ref.watch(taskRepositoryProvider).watchTasksForDate(date);
    });

final taskDetailsProvider = StreamProvider.autoDispose
    .family<TaskDetails?, String>((ref, taskId) {
      return ref.watch(taskRepositoryProvider).watchTask(taskId);
    });

final tasksByStatusProvider = StreamProvider.autoDispose
    .family<List<TaskDetails>, TaskLifecycle>((ref, status) {
      return ref.watch(taskRepositoryProvider).watchTasksByStatus(status);
    });

final taskCompletionHistoryProvider = StreamProvider.autoDispose
    .family<List<CompletionHistoryEntry>, String>((ref, taskId) {
      return ref.watch(taskRepositoryProvider).watchCompletionHistory(taskId);
    });
