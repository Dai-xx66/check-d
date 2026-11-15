import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../courses/application/course_providers.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/planning_context_repository.dart';
import '../data/planning_preview_client.dart';

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
    this.result,
    this.riskResult,
  });

  final Map<String, Object?> snapshot;
  final Map<String, Object?>? result;
  final Map<String, Object?>? riskResult;
  bool get serviceConfigured => result != null;
}

final planningPreviewProvider = FutureProvider.autoDispose
    .family<PlanningPreviewResult, PlanningDateRange>((ref, range) async {
      final snapshot = await ref.watch(planningSnapshotProvider(range).future);
      final client = ref.watch(planningPreviewClientProvider);
      if (client == null) return PlanningPreviewResult(snapshot: snapshot);
      final result = await client.preview(snapshot);
      final riskResult = await client.risks(snapshot);
      return PlanningPreviewResult(
        snapshot: snapshot,
        result: result,
        riskResult: riskResult,
      );
    });
