import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../courses/application/course_providers.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/planning_context_repository.dart';
import '../data/planning_plan_repository.dart';
import '../data/planning_preview_client.dart';
import '../domain/local_planning_engine.dart';

/// Uses the same per-user repositories as the app's task, course, and schedule
/// screens. The principal is supplied by the existing authenticated/offline
/// owner provider, never by a planning request payload.
final planningContextRepositoryProvider = Provider<PlanningContextRepository>(
  (ref) => PlanningContextRepository(
    database: ref.watch(appDatabaseProvider),
    tasks: ref.watch(taskRepositoryProvider),
    courses: ref.watch(courseRepositoryProvider),
    semesters: ref.watch(semesterRepositoryProvider),
    schedule: ref.watch(dayScheduleRepositoryProvider),
    authenticatedUserId: ref.watch(currentDataOwnerProvider),
  ),
);

final planningPlanRepositoryProvider = Provider<PlanningPlanRepository>(
  (ref) => PlanningPlanRepository(
    database: ref.watch(appDatabaseProvider),
    userId: ref.watch(currentDataOwnerProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
  ),
);

class PlanningDateRange {
  const PlanningDateRange({required this.from, required this.through});

  final DateTime from;
  final DateTime through;

  @override
  bool operator ==(Object other) =>
      other is PlanningDateRange &&
      from == other.from &&
      through == other.through;

  @override
  int get hashCode => Object.hash(from, through);
}

final planningSnapshotProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>, PlanningDateRange>((ref, range) {
      return ref
          .watch(planningContextRepositoryProvider)
          .load(from: range.from, through: range.through, now: DateTime.now());
    });

final localPlanningEngineProvider = Provider<LocalPlanningEngine>(
  (ref) => const LocalPlanningEngine(),
);

/// Opt-in local development bridge. It is disabled in ordinary builds and is
/// not the production WorkBuddy/Auth endpoint.
final planningPreviewClientProvider = Provider<PlanningPreviewClient?>((ref) {
  const baseUrl = String.fromEnvironment('CHECKD_PLANNING_PREVIEW_URL');
  const token = String.fromEnvironment('CHECKD_PLANNING_PREVIEW_TOKEN');
  if (baseUrl.isEmpty || token.isEmpty) return null;
  final client = PlanningPreviewClient(baseUrl: baseUrl, token: token);
  ref.onDispose(client.close);
  return client;
});

class PlanningPreviewResult {
  const PlanningPreviewResult({
    required this.snapshot,
    required this.result,
    required this.riskResult,
  });

  final Map<String, Object?> snapshot;
  final Map<String, Object?> result;
  final Map<String, Object?> riskResult;
  bool get calculationAvailable => result['ok'] == true;
}

final planningPreviewProvider = FutureProvider.autoDispose
    .family<PlanningPreviewResult, PlanningDateRange>((ref, range) async {
      final snapshot = await ref.watch(planningSnapshotProvider(range).future);
      final engine = ref.watch(localPlanningEngineProvider);
      final result = engine.preview(snapshot);
      final riskResult = engine.assessRisks(snapshot);
      return PlanningPreviewResult(
        snapshot: snapshot,
        result: result,
        riskResult: riskResult,
      );
    });

final savedPlanningPlansProvider = FutureProvider.autoDispose
    .family<List<SavedLocalPlan>, PlanningDateRange>((ref, range) {
      return ref
          .watch(planningPlanRepositoryProvider)
          .loadPlans(
            startsOnOrBefore: range.through,
            endsOnOrAfter: range.from,
          );
    });
