import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/day_schedule_repository.dart';
import '../domain/day_schedule_models.dart';

final dayScheduleRepositoryProvider = Provider<DayScheduleRepository>((ref) {
  return DayScheduleRepository(
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    userId: ref.watch(currentDataOwnerProvider),
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

final reminderRulesProvider = StreamProvider.autoDispose
    .family<List<ReminderRule>, ReminderRuleFilter>((ref, filter) {
      return ref
          .watch(dayScheduleRepositoryProvider)
          .watchReminderRules(
            ownerType: filter.ownerType,
            ownerId: filter.ownerId,
          );
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
