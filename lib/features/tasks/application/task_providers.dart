import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/holiday/holiday_providers.dart';
import '../../../core/notifications/notification_providers.dart';
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
    holidayCalendar: ref.watch(holidayCalendarProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

final tasksForDateProvider = StreamProvider.autoDispose
    .family<List<TaskDetails>, DateTime>((ref, date) {
      ref.watch(miniWindowDataRevisionProvider);
      return ref.watch(taskRepositoryProvider).watchTasksForDate(date);
    });

final taskDetailsProvider = StreamProvider.autoDispose
    .family<TaskDetails?, String>((ref, taskId) {
      ref.watch(miniWindowDataRevisionProvider);
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

final taskTimerStateProvider = StreamProvider.autoDispose
    .family<TaskTimerState, String>((ref, taskId) {
      ref.watch(miniWindowDataRevisionProvider);
      return ref
          .watch(taskRepositoryProvider)
          .watchTimerState(taskId, dateOnly(DateTime.now()));
    });

final timerNowProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );
});

final dailyTimerStateProvider = StreamProvider.autoDispose
    .family<TaskTimerState, DateTime>((ref, date) {
      return ref.watch(taskRepositoryProvider).watchTimerState(null, date);
    });

final runningTimerTaskIdProvider = FutureProvider.autoDispose<String?>((ref) {
  return ref.watch(taskRepositoryProvider).runningTimerTaskId();
});

/// All task timers that have not been ended. Paused entries remain here so a
/// page reload can restore their controls without treating pause as finish.
final unfinishedTaskTimersProvider =
    StreamProvider.autoDispose<List<TimerSessionEntry>>((ref) {
      ref.watch(miniWindowDataRevisionProvider);
      return ref.watch(taskRepositoryProvider).watchUnfinishedTimers();
    });

final runningTaskTimersProvider = Provider.autoDispose<List<TimerSessionEntry>>(
  (ref) => (ref.watch(unfinishedTaskTimersProvider).value ?? const [])
      .where((timer) => timer.status == TimerSessionStatus.running)
      .toList(),
);

final calendarMonthProvider = StreamProvider.autoDispose
    .family<CalendarMonthData, DateTime>((ref, month) {
      return ref.watch(taskRepositoryProvider).watchCalendarMonth(month);
    });
