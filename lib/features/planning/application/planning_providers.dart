import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../courses/application/course_providers.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/planning_context_repository.dart';

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
