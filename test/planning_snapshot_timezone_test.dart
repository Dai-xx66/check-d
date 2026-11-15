import 'package:check_d/features/planning/data/planning_snapshot_adapter.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unsupported deadline and availability stay unknown in the v1 model',
    () {
      final day = DateTime(2026, 11, 16);
      final task = TaskDetails(
        id: 'task',
        name: '脱敏任务',
        kind: TaskKind.oneTime,
        colorValue: 0,
        status: TaskLifecycle.active,
        createdAt: day,
        updatedAt: day,
        scheduledAt: DateTime(2026, 11, 16, 10),
      );
      final snapshot = const PlanningSnapshotAdapter().build(
        subjectRef: 'fixture-user',
        source: 'fixture',
        capturedAt: day,
        version: 'v1',
        syncState: 'current',
        now: DateTime(2026, 11, 16, 9),
        horizonEnd: DateTime(2026, 11, 17, 18),
        date: day,
        tasks: [task],
        courses: const [],
        overrides: const [],
      );

      final row = (snapshot['tasks'] as List).single as Map<String, Object?>;
      expect(row['available_from'], isNull);
      expect(row['deadline_date'], isNull);
      expect(row['deadline_at'], isNull);
      expect(row['planned_at'], '2026-11-16T02:00:00.000Z');
      expect(row['earliest_start'], '2026-11-16T01:00:00.000Z');
    },
  );
}
