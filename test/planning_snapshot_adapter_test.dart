import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/planning/data/planning_snapshot_adapter.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot is provisional when local synchronization is pending', () {
    final now = DateTime(2026, 11, 14, 9);
    final snapshot = const PlanningSnapshotAdapter().build(
      subjectRef: 'fixture-user',
      source: 'drift_fixture',
      capturedAt: now,
      version: 'fixture-v1',
      syncState: 'pending_local_changes',
      now: now,
      horizonEnd: DateTime(2026, 11, 14, 18),
      date: now,
      tasks: const [],
      courses: const <CourseDetails>[],
      overrides: const <DailyItemOverride>[],
    );
    expect(snapshot['provisional'], isTrue);
    expect(snapshot['execution_eligible'], isFalse);
    expect(snapshot['version'], 'fixture-v1');
  });

  test('rejects missing user/version and invalid sync state', () {
    final now = DateTime(2026, 11, 14);
    expect(
      () => const PlanningSnapshotAdapter().build(
        subjectRef: '',
        source: 'fixture',
        capturedAt: now,
        version: 'v1',
        syncState: 'current',
        now: now,
        horizonEnd: now.add(const Duration(days: 1)),
        date: now,
        tasks: const [],
        courses: const <CourseDetails>[],
        overrides: const <DailyItemOverride>[],
      ),
      throwsArgumentError,
    );
  });
}
