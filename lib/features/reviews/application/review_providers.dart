import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/holiday/holiday_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/review_repository.dart';
import '../domain/review_models.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    userId: ref.watch(currentDataOwnerProvider),
    holidayCalendar: ref.watch(holidayCalendarProvider),
  );
});

final reviewProvider = StreamProvider.autoDispose
    .family<ReviewDetails?, ReviewPeriod>((ref, period) {
      return ref.watch(reviewRepositoryProvider).watchReview(period);
    });

final reviewSnapshotProvider = FutureProvider.autoDispose
    .family<ReviewSnapshot, ReviewPeriod>((ref, period) {
      return ref.watch(reviewRepositoryProvider).loadSnapshot(period);
    });
