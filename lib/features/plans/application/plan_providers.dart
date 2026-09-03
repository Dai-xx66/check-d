import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/holiday/holiday_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/plan_repository.dart';
import '../domain/plan_models.dart';

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return PlanRepository(
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    userId: ref.watch(currentDataOwnerProvider),
    holidayCalendar: ref.watch(holidayCalendarProvider),
  );
});

final plansProvider = StreamProvider.autoDispose<List<PlanDetails>>((ref) {
  return ref.watch(planRepositoryProvider).watchPlans();
});
