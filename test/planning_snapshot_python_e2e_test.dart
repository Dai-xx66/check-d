import 'dart:convert';
import 'dart:io';

import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/planning/data/planning_snapshot_adapter.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CheckD course occurrence -> snapshot JSON -> Python planner avoids class',
    () async {
      final monday = DateTime(2026, 11, 16);
      final course = CourseDetails(
        id: 'course-fixture',
        name: '脱敏课程',
        colorValue: 0,
        status: CourseStatus.active,
        createdAt: monday,
        updatedAt: monday,
        semesterStartsOn: DateTime(2026, 11, 2),
        rules: [
          CourseScheduleRule(
            id: 'rule-fixture',
            courseId: 'course-fixture',
            weekday: DateTime.monday,
            weekRuleType: CourseWeekRuleType.oddWeeks,
            startsAtMinute: 10 * 60,
            endsAtMinute: 11 * 60,
            createdAt: monday,
            updatedAt: monday,
          ),
        ],
      );
      final task = TaskDetails(
        id: 'task-fixture',
        name: '脱敏任务',
        kind: TaskKind.oneTime,
        colorValue: 0,
        status: TaskLifecycle.active,
        createdAt: monday,
        updatedAt: monday,
      );
      final snapshot = const PlanningSnapshotAdapter().build(
        subjectRef: 'fixture-subject',
        source: 'drift_test_fixture',
        capturedAt: monday,
        version: 'fixture-v1',
        syncState: 'current',
        now: DateTime(2026, 11, 16, 9),
        horizonEnd: DateTime(2026, 11, 16, 18),
        date: monday,
        tasks: [task],
        courses: [course],
        overrides: const [],
        remainingSecondsByTask: const {'task-fixture': 7200},
      );
      // Feed the actual serialized adapter output to the Python runner.
      final tmp = await Directory.systemTemp.createTemp('checkd-plan-e2e-');
      try {
        final input = File('${tmp.path}/snapshot.json');
        await input.writeAsString(jsonEncode(snapshot));
        final actual = await Process.run(
          'python3',
          [
            '-c',
            'import sys; from runpy import run_path; import json; sys.stdin=open(sys.argv[1]); run_path(sys.argv[2], run_name="__main__")',
            input.path,
            'tools/checkd_planning_engine/examples/run_snapshot.py',
          ],
          workingDirectory: Directory.current.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        expect(actual.exitCode, 0, reason: actual.stderr as String);
        final result =
            jsonDecode(actual.stdout as String) as Map<String, dynamic>;
        expect(result['execution_eligible'], isFalse);
        expect(result['schedule']['feasible'], isTrue);
        expect(result['unknown_effort_task_ids'], isEmpty);
        expect(result['missing_deadline_task_ids'], ['task-fixture']);
        expect(result['outcome'], 'unknown_due_to_missing_data');
        for (final block in result['schedule']['blocks'] as List) {
          final start = DateTime.parse(block['starts_at'] as String).toUtc();
          final end = DateTime.parse(block['ends_at'] as String).toUtc();
          final classStart = DateTime.utc(
            2026,
            11,
            16,
            2,
          ); // 10:00 Asia/Shanghai
          final classEnd = DateTime.utc(2026, 11, 16, 3);
          expect(start.isBefore(classEnd) && classStart.isBefore(end), isFalse);
        }
      } finally {
        await tmp.delete(recursive: true);
      }
    },
  );
}
