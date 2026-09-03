import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/holiday/holiday_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../data/statistics_repository.dart';
import '../domain/statistics_models.dart';

final statisticsRepositoryProvider = Provider<StatisticsRepository>(
  (ref) => StatisticsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(currentDataOwnerProvider),
    holidayCalendar: ref.watch(holidayCalendarProvider),
  ),
);

final statisticsDataProvider = StreamProvider.autoDispose<StatisticsData>((
  ref,
) {
  ref.watch(
    timerNowProvider.select(
      (value) => value.value == null ? null : localDateKey(value.value!),
    ),
  );
  return ref.watch(statisticsRepositoryProvider).watchData();
});

/// Used by the Today page, whose parent already owns the live clock. Keeping
/// this stream clock-free avoids a second periodic subscription for the same UI.
final statisticsSnapshotProvider = StreamProvider.autoDispose<StatisticsData>((
  ref,
) {
  return ref.watch(statisticsRepositoryProvider).watchData();
});
