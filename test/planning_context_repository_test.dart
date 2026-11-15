import 'dart:convert';
import 'dart:io';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/planning/data/planning_context_repository.dart';
import 'package:check_d/features/planning/data/planning_plan_repository.dart';
import 'package:check_d/features/planning/domain/local_planning_engine.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'aggregates user-scoped Drift task, course occurrence and sync state',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final queue = SyncQueueService(database);
      final taskRepository = TaskRepository(
        database: database,
        syncQueue: queue,
        userId: 'user-a',
      );
      final courseRepository = CourseRepository(
        database: database,
        syncQueue: queue,
        userId: 'user-a',
      );
      final semesterRepository = SemesterRepository(
        database: database,
        syncQueue: queue,
        userId: 'user-a',
      );
      final scheduleRepository = DayScheduleRepository(
        database: database,
        syncQueue: queue,
        userId: 'user-a',
      );
      final taskRepositoryB = TaskRepository(
        database: database,
        syncQueue: queue,
        userId: 'user-b',
      );
      await taskRepositoryB.saveOneTimeReminder(
        OneTimeReminderDraft(name: '用户 B 的任务', colorValue: 0),
      );
      final day = DateTime(2026, 11, 16);
      final courseId = await courseRepository.saveCourse(
        CourseDraft(
          name: '课程 fixture',
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
        OneTimeReminderDraft(
          name: '任务 fixture',
          colorValue: 0,
          scheduledAt: DateTime(2026, 11, 16, 13),
        ),
      );
      await taskRepository.saveRecurringTask(
        RecurringTaskDraft(
          name: '重复任务 fixture',
          colorValue: 0,
          executionMode: RecurringExecutionMode.timed,
          targetDurationSeconds: 1800,
          schedulePreset: SchedulePreset.custom,
          weekdays: {DateTime.monday},
          startsOn: DateTime(2026, 11, 2),
          holidayPause: false,
          scheduledMinuteOfDay: 9 * 60,
        ),
      );
      await scheduleRepository.saveDailyOverride(
        DailyItemOverrideDraft(
          itemType: DayItemType.oneTime,
          itemId: taskId,
          localDate: day,
          action: DayOverrideAction.reschedule,
          plannedStartMinute: 13 * 60,
          plannedEndMinute: 14 * 60,
        ),
      );
      await database
          .into(database.timerSessionRecords)
          .insert(
            TimerSessionRecordsCompanion.insert(
              id: 'timer-a',
              taskId: taskId,
              userId: 'user-a',
              startedAt: DateTime.utc(2026, 11, 16, 1),
              endedAt: Value(DateTime.utc(2026, 11, 16, 1, 20)),
              durationSeconds: const Value(1200),
              state: TimerSessionStatus.finished.name,
              createdAt: DateTime.utc(2026, 11, 16, 1),
              updatedAt: DateTime.utc(2026, 11, 16, 1, 20),
            ),
          );
      // A failed queue item still represents local data not acknowledged by
      // the server, so the snapshot must remain provisional.
      await (database.update(database.syncOperations)
            ..where((row) => row.userId.equals('user-a')))
          .write(const SyncOperationsCompanion(status: Value('failed')));

      final context = PlanningContextRepository(
        database: database,
        tasks: taskRepository,
        courses: courseRepository,
        semesters: semesterRepository,
        schedule: scheduleRepository,
        authenticatedUserId: 'user-a',
      );
      final snapshot = await context.load(
        from: day,
        through: day,
        now: DateTime(2026, 11, 16, 9),
      );
      expect(snapshot['sync_state'], 'pending_local_changes');
      expect(snapshot['sync_queue_pending_count'], 0);
      expect(snapshot['sync_queue_failed_count'], greaterThan(0));
      expect(snapshot['provisional'], isTrue);
      expect(snapshot['execution_eligible'], isFalse);
      expect(snapshot['tasks'], hasLength(1));
      expect((snapshot['tasks'] as List).single['name'], isNot('用户 B 的任务'));
      expect(snapshot['unknown_effort_task_ids'], hasLength(1));
      expect((snapshot['tasks'] as List).single['planned_at'] != null, isTrue);
      expect(
        (snapshot['tasks'] as List).single['deadline_date'] == null,
        isTrue,
      );
      expect((snapshot['tasks'] as List).single['deadline_at'] == null, isTrue);
      expect(snapshot['course_occurrences'], hasLength(1));
      expect(snapshot['recurring_occurrences'], hasLength(1));
      expect(snapshot['unmodeled_recurring_occurrence_ids'], isEmpty);
      expect(snapshot['version'], startsWith('local-fnv64-'));
      expect(snapshot['timer_facts'], hasLength(1));
      expect(snapshot['occupied_blocks'], hasLength(2));

      final laterClock = await context.load(
        from: day,
        through: day,
        now: DateTime(2026, 11, 16, 9, 1),
      );
      expect(laterClock['version'], snapshot['version']);
      final planningInput =
          jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>;
      final planningTask = (planningInput['tasks'] as List).single as Map;
      planningTask['remaining_seconds'] = 3600;
      planningTask['remaining_effort_state'] = 'known';
      planningTask['deadline_date'] = '2026-11-16';
      planningTask['effort_source'] = 'synthetic_user_input';
      final planResult = const LocalPlanningEngine().preview(planningInput);
      expect(planResult['outcome'], 'found_feasible');
      final proposedBlocks = (planResult['schedule'] as Map)['blocks'] as List;
      final courseBlock =
          (snapshot['course_occurrences'] as List).single as Map;
      for (final rawBlock in proposedBlocks) {
        final block = rawBlock as Map;
        final start = DateTime.parse(block['starts_at'] as String);
        final end = DateTime.parse(block['ends_at'] as String);
        final courseStart = DateTime.parse(courseBlock['starts_at'] as String);
        final courseEnd = DateTime.parse(courseBlock['ends_at'] as String);
        expect(
          start.isBefore(courseEnd) && courseStart.isBefore(end),
          isFalse,
          reason: 'planner candidate must avoid the Flutter course occurrence',
        );
      }

      await database
          .into(database.taskEffortRecords)
          .insert(
            TaskEffortRecordsCompanion.insert(
              taskId: taskId,
              userId: 'user-a',
              remainingSeconds: const Value(2400),
              source: 'user_confirmed',
              updatedAt: DateTime.utc(2026, 11, 16, 1),
            ),
          );
      final withEffort = await context.load(
        from: day,
        through: day,
        now: DateTime(2026, 11, 16, 9),
      );
      expect(withEffort['version'], isNot(snapshot['version']));
      expect((withEffort['tasks'] as List).single['remaining_seconds'], 2400);

      final planRepository = PlanningPlanRepository(
        database: database,
        userId: 'user-a',
      );
      final localPlan = await planRepository.confirmPlan(
        expectedSnapshotVersion: withEffort['version']! as String,
        readCurrentSnapshotVersion: () async =>
            (await context.load(
                  from: day,
                  through: day,
                  now: DateTime(2026, 11, 16, 9, 2),
                ))['version']!
                as String,
        startsOn: day,
        endsOn: day,
        rulesVersion: 'local-edf-v1',
        blocks: [
          CandidatePlanBlock(
            taskId: taskId,
            startsAt: DateTime.utc(2026, 11, 16, 4),
            endsAt: DateTime.utc(2026, 11, 16, 4, 40),
            plannedSeconds: 2400,
          ),
        ],
        now: DateTime.utc(2026, 11, 16, 1),
      );
      expect(localPlan.status, LocalPlanStatus.confirmed);
      final persistedPlans = await planRepository.loadPlans(
        startsOnOrBefore: day,
        endsOnOrAfter: day,
      );
      expect(persistedPlans, hasLength(1));
      expect(persistedPlans.single.blocks, hasLength(1));

      await scheduleRepository.saveDailyOverride(
        DailyItemOverrideDraft(
          itemType: DayItemType.course,
          itemId: courseId,
          localDate: day,
          action: DayOverrideAction.skip,
        ),
      );
      final afterCourseChange = await context.load(
        from: day,
        through: day,
        now: DateTime(2026, 11, 16, 9, 2),
      );
      expect(afterCourseChange['version'], isNot(withEffort['version']));
      await expectLater(
        planRepository.confirmPlan(
          expectedSnapshotVersion: withEffort['version']! as String,
          readCurrentSnapshotVersion: () async =>
              (await context.load(
                    from: day,
                    through: day,
                    now: DateTime(2026, 11, 16, 9, 2),
                  ))['version']!
                  as String,
          startsOn: day,
          endsOn: day,
          rulesVersion: 'local-edf-v1',
          blocks: [
            CandidatePlanBlock(
              taskId: taskId,
              startsAt: DateTime.utc(2026, 11, 16, 6),
              endsAt: DateTime.utc(2026, 11, 16, 6, 40),
              plannedSeconds: 2400,
            ),
          ],
          now: DateTime.utc(2026, 11, 16, 1),
        ),
        throwsA(isA<LocalPlanSnapshotChanged>()),
      );

      await taskRepository.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: '任务 fixture 已修改',
          colorValue: 0,
          scheduledAt: DateTime(2026, 11, 16, 14),
        ),
        taskId: taskId,
      );
      await expectLater(
        planRepository.confirmPlan(
          expectedSnapshotVersion: withEffort['version']! as String,
          readCurrentSnapshotVersion: () async =>
              (await context.load(
                    from: day,
                    through: day,
                    now: DateTime(2026, 11, 16, 9, 3),
                  ))['version']!
                  as String,
          startsOn: day,
          endsOn: day,
          rulesVersion: 'local-edf-v1',
          blocks: [
            CandidatePlanBlock(
              taskId: taskId,
              startsAt: DateTime.utc(2026, 11, 16, 5),
              endsAt: DateTime.utc(2026, 11, 16, 5, 40),
              plannedSeconds: 2400,
            ),
          ],
          now: DateTime.utc(2026, 11, 16, 1),
        ),
        throwsA(isA<LocalPlanSnapshotChanged>()),
      );
      expect(
        await database.select(database.taskPlanVersionRecords).get(),
        hasLength(1),
      );

      final coursesB = CourseRepository(
        database: database,
        syncQueue: queue,
        userId: 'user-b',
      );
      final scheduleB = DayScheduleRepository(
        database: database,
        syncQueue: queue,
        userId: 'user-b',
      );
      final snapshotB = await PlanningContextRepository(
        database: database,
        tasks: taskRepositoryB,
        courses: coursesB,
        semesters: SemesterRepository(
          database: database,
          syncQueue: queue,
          userId: 'user-b',
        ),
        schedule: scheduleB,
        authenticatedUserId: 'user-b',
      ).load(from: day, through: day, now: DateTime(2026, 11, 16, 9));
      expect(snapshotB['subject_ref'], 'user-b');
      expect(snapshotB['tasks'], hasLength(1));
      expect((snapshotB['tasks'] as List).single['name'], '用户 B 的任务');
      expect(snapshotB['course_occurrences'], isEmpty);

      final tempDirectory = await Directory.systemTemp.createTemp(
        'checkd-planning-context-e2e-',
      );
      try {
        final snapshotFile = File('${tempDirectory.path}/snapshot.json');
        await snapshotFile.writeAsString(jsonEncode(snapshot));
        final pythonResult = await Process.run(
          'python3',
          [
            '-c',
            'import sys; from runpy import run_path; sys.stdin=open(sys.argv[1]); run_path(sys.argv[2], run_name="__main__")',
            snapshotFile.path,
            'tools/checkd_planning_engine/examples/run_snapshot.py',
          ],
          workingDirectory: Directory.current.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        expect(pythonResult.exitCode, 0, reason: pythonResult.stderr as String);
        final analysis =
            jsonDecode(pythonResult.stdout as String) as Map<String, dynamic>;
        expect(analysis['snapshot_version'], snapshot['version']);
        expect(analysis['provisional'], isTrue);
        expect(analysis['execution_eligible'], isFalse);
        expect(analysis['unknown_effort_task_ids'], isNotEmpty);
        expect(analysis['schedule']['feasible'], isTrue);
        expect(analysis['schedule']['blocks'], isEmpty);
      } finally {
        await tempDirectory.delete(recursive: true);
      }
    },
  );
}
