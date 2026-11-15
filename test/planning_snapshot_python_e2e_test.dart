import 'dart:convert';
import 'dart:io';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/planning/data/planning_context_repository.dart';
import 'package:check_d/features/planning/data/planning_snapshot_adapter.dart';
import 'package:check_d/features/planning/data/planning_preview_client.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
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

  test(
    'Drift repositories -> Flutter snapshot -> Python HTTP preview and delay',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final syncQueue = SyncQueueService(database);
      const userId = 'test-user-a';
      final taskRepository = TaskRepository(
        database: database,
        syncQueue: syncQueue,
        userId: userId,
      );
      final courseRepository = CourseRepository(
        database: database,
        syncQueue: syncQueue,
        userId: userId,
      );
      final semesterRepository = SemesterRepository(
        database: database,
        syncQueue: syncQueue,
        userId: userId,
      );
      final scheduleRepository = DayScheduleRepository(
        database: database,
        syncQueue: syncQueue,
        userId: userId,
      );
      final monday = DateTime(2026, 11, 16);
      final courseId = await courseRepository.saveCourse(
        CourseDraft(
          name: '本地测试课程',
          colorValue: 0,
          semesterStartsOn: DateTime(2026, 11, 2),
        ),
      );
      await courseRepository.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: DateTime.monday,
          weekRuleType: CourseWeekRuleType.oddWeeks,
          startsAtMinute: 10 * 60,
          endsAtMinute: 11 * 60,
        ),
      );
      final taskId = await taskRepository.saveOneTimeReminder(
        OneTimeReminderDraft(name: '本地测试事项', colorValue: 0),
      );
      final planningContext = PlanningContextRepository(
        database: database,
        tasks: taskRepository,
        courses: courseRepository,
        semesters: semesterRepository,
        schedule: scheduleRepository,
        authenticatedUserId: userId,
      );
      final snapshot = await planningContext.load(
        from: monday,
        through: monday,
        now: DateTime(2026, 11, 16, 9),
      );
      // This test-only supplemental input represents values the user supplied
      // to the preview; the app does not persist these values to Task.
      final taskRow = (snapshot['tasks'] as List).single as Map;
      expect(taskRow['task_id'], taskId);
      taskRow['remaining_seconds'] = 7200;
      taskRow['remaining_effort_state'] = 'known';
      taskRow['effort_source'] = 'ephemeral_user_input';
      taskRow['deadline_date'] = '2026-11-16';
      final token = 'flutter-integration-test-token-1234567890';
      final environment = Map<String, String>.from(Platform.environment)
        ..['PYTHONPATH'] = 'src'
        ..['CHECKD_PLANNING_PREVIEW_TOKEN'] = token;
      final process = await Process.start(
        'python3',
        ['-m', 'checkd_planning_engine.local_preview_http', '--port', '0'],
        workingDirectory:
            '${Directory.current.path}/tools/checkd_planning_engine',
        environment: environment,
      );
      final client = PlanningPreviewClient(
        baseUrl: 'http://127.0.0.1:0',
        token: token,
      );
      try {
        final readyLine = await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 10));
        final ready = jsonDecode(readyLine) as Map<String, dynamic>;
        final httpClient = PlanningPreviewClient(
          baseUrl: 'http://127.0.0.1:${ready['port']}',
          token: token,
        );
        addTearDown(httpClient.close);
        late final Map<String, Object?> preview;
        try {
          preview = await httpClient.preview(snapshot);
        } on PlanningPreviewException catch (error) {
          fail('preview request: $error');
        }
        expect(preview['snapshot_version'], snapshot['version']);
        expect(preview['execution_eligible'], isFalse);
        expect(preview['outcome'], 'found_feasible');
        final blocks = (preview['schedule'] as Map)['blocks'] as List;
        expect(blocks, isNotEmpty);
        for (final rawBlock in blocks) {
          final block = rawBlock as Map;
          final start = DateTime.parse(block['starts_at'] as String).toUtc();
          final end = DateTime.parse(block['ends_at'] as String).toUtc();
          expect(
            start.isBefore(DateTime.utc(2026, 11, 16, 3)) &&
                DateTime.utc(2026, 11, 16, 2).isBefore(end),
            isFalse,
          );
        }
        late final Map<String, Object?> delayed;
        try {
          delayed = await httpClient.simulateDelay(
            snapshot: snapshot,
            taskId: taskId,
            until: DateTime.parse('2026-11-16T12:00:00+08:00'),
          );
        } on PlanningPreviewException catch (error) {
          fail('delay request: $error');
        }
        final analysis = delayed['delay_analysis'] as Map;
        expect(analysis['before_feasible'], isTrue);
        expect(analysis.containsKey('after_feasible'), isTrue);
      } finally {
        client.close();
        process.kill();
        await process.exitCode;
      }
    },
  );
}
