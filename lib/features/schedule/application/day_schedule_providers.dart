import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/day_schedule_repository.dart';
import '../domain/day_schedule_models.dart';

final dayScheduleRepositoryProvider = Provider<DayScheduleRepository>((ref) {
  return DayScheduleRepository(
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    userId: ref.watch(currentDataOwnerProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

final dailyOverridesProvider = StreamProvider.autoDispose
    .family<List<DailyItemOverride>, DateTime>((ref, date) {
      return ref
          .watch(dayScheduleRepositoryProvider)
          .watchOverridesForDate(date);
    });

final dailyOverridesSnapshotProvider = FutureProvider.autoDispose
    .family<List<DailyItemOverride>, DateTime>((ref, date) {
      return ref
          .watch(dayScheduleRepositoryProvider)
          .loadOverridesForDate(date);
    });

final adHocTimersForDateProvider = StreamProvider.autoDispose
    .family<List<AdHocTimerDetails>, DateTime>((ref, date) {
      return ref
          .watch(dayScheduleRepositoryProvider)
          .watchAdHocTimersForDate(date);
    });

final unfinishedAdHocTimersProvider =
    StreamProvider.autoDispose<List<AdHocTimerDetails>>((ref) {
      return ref
          .watch(dayScheduleRepositoryProvider)
          .watchUnfinishedAdHocTimers();
    });

final reminderRulesProvider = StreamProvider.autoDispose
    .family<List<ReminderRule>, ReminderRuleFilter>((ref, filter) {
      return ref
          .watch(dayScheduleRepositoryProvider)
          .watchReminderRules(
            ownerType: filter.ownerType,
            ownerId: filter.ownerId,
          );
    });

/// A scheduler-only trigger. It intentionally observes all overrides and
/// reminder configurations, including disabled entries, so changing a single
/// occurrence reliably rebuilds future notification registrations.
final reminderScheduleTriggerProvider = StreamProvider.autoDispose<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final query = database.customSelect(
    'SELECT (SELECT COUNT(*) FROM daily_item_override_records) + '
    '(SELECT COUNT(*) FROM reminder_rule_records) AS revision',
    readsFrom: {
      database.dailyItemOverrideRecords,
      database.reminderRuleRecords,
    },
  );
  return query.watchSingle().map((row) => row.read<int>('revision'));
});

class ReminderRuleFilter {
  const ReminderRuleFilter({this.ownerType, this.ownerId});

  final DayItemType? ownerType;
  final String? ownerId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReminderRuleFilter &&
            other.ownerType == ownerType &&
            other.ownerId == ownerId;
  }

  @override
  int get hashCode => Object.hash(ownerType, ownerId);
}
