import 'dart:math';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_apply_scope.dart';
import 'package:check_d/core/sync/sync_download_service.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/core/sync/sync_upload_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/planning/application/planning_providers.dart';
import 'package:check_d/features/planning/data/planning_context_repository.dart';
import 'package:check_d/features/planning/data/planning_plan_repository.dart';
import 'package:check_d/features/planning/domain/local_planning_engine.dart';
import 'package:check_d/features/planning/presentation/planning_preview_page.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('isolated Android Drift -> Supabase -> proposal -> apply -> readback', (
    tester,
  ) async {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const publishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    expect(supabaseUrl, startsWith('http://10.0.2.2:'));
    expect(publishableKey, isNotEmpty);
    await Supabase.initialize(url: supabaseUrl, publishableKey: publishableKey);
    final client = Supabase.instance.client;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final email = 'planning-e2e-$suffix@example.invalid';
    final random = Random.secure();
    final password =
        'Test-${List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join()}!';
    final auth = await client.auth.signUp(email: email, password: password);
    final userId = auth.user?.id;
    expect(userId, isNotNull);
    expect(client.auth.currentUser?.id, userId);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final queue = SyncQueueService(database);
    final tasks = TaskRepository(
      database: database,
      syncQueue: queue,
      userId: userId!,
    );
    final courses = CourseRepository(
      database: database,
      syncQueue: queue,
      userId: userId,
    );
    final semesters = SemesterRepository(
      database: database,
      syncQueue: queue,
      userId: userId,
    );
    final schedule = DayScheduleRepository(
      database: database,
      syncQueue: queue,
      userId: userId,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final through = today.add(const Duration(days: 14));
    final taskId = await tasks.saveOneTimeReminder(
      OneTimeReminderDraft(
        name: 'E2E 合成实验报告',
        colorValue: 0xff887766,
        availableFrom: today,
        plannedDate: tomorrow,
        dueDate: today.add(const Duration(days: 5)),
      ),
    );
    final courseId = await courses.saveCourse(
      CourseDraft(
        name: 'E2E 合成课程',
        colorValue: 0xff6688aa,
        semesterStartsOn: today,
      ),
    );
    final ruleId = await courses.saveScheduleRule(
      CourseScheduleRuleDraft(
        courseId: courseId,
        weekday: tomorrow.weekday,
        weekRuleType: CourseWeekRuleType.everyWeek,
        startsAtMinute: 10 * 60,
        endsAtMinute: 11 * 60,
      ),
    );
    Future<String> addCourse(
      String name,
      CourseWeekRuleType weekRule, {
      required int startMinute,
      required int endMinute,
      DateTime? endsOn,
    }) async {
      final id = await courses.saveCourse(
        CourseDraft(
          name: name,
          colorValue: 0xff44aa88,
          semesterStartsOn: today,
          semesterEndsOn: endsOn ?? through,
        ),
      );
      await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: id,
          weekday: tomorrow.weekday,
          weekRuleType: weekRule,
          startsAtMinute: startMinute,
          endsAtMinute: endMinute,
        ),
      );
      return id;
    }

    final oddCourseId = await addCourse(
      'E2E odd-week fixture',
      CourseWeekRuleType.oddWeeks,
      startMinute: 9 * 60,
      endMinute: 9 * 60 + 30,
    );
    final evenCourseId = await addCourse(
      'E2E even-week fixture',
      CourseWeekRuleType.evenWeeks,
      startMinute: 11 * 60,
      endMinute: 11 * 60 + 30,
    );
    final boundedCourseId = await addCourse(
      'E2E semester-end fixture',
      CourseWeekRuleType.everyWeek,
      startMinute: 13 * 60,
      endMinute: 14 * 60,
      endsOn: tomorrow,
    );
    final makeupCourseId = await addCourse(
      'E2E makeup fixture',
      CourseWeekRuleType.evenWeeks,
      startMinute: 12 * 60,
      endMinute: 13 * 60,
    );
    await schedule.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.course,
        itemId: ruleId,
        localDate: tomorrow,
        action: DayOverrideAction.courseChange,
        plannedStartMinute: 15 * 60,
        plannedEndMinute: 16 * 60,
      ),
    );
    await schedule.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.course,
        itemId: ruleId,
        localDate: today.add(const Duration(days: 8)),
        action: DayOverrideAction.skip,
      ),
    );
    await schedule.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.course,
        itemId: makeupCourseId,
        localDate: tomorrow,
        action: DayOverrideAction.extraCourse,
        plannedStartMinute: 16 * 60,
        plannedEndMinute: 17 * 60,
      ),
    );
    await database
        .into(database.taskEffortRecords)
        .insertOnConflictUpdate(
          TaskEffortRecordsCompanion.insert(
            taskId: taskId,
            userId: userId,
            estimatedSeconds: const Value(3600),
            remainingSeconds: const Value(3600),
            source: 'user_confirmed',
            updatedAt: DateTime.now().toUtc(),
            deletedAt: const Value(null),
          ),
        );
    await queue.enqueue(
      entityType: 'task_effort_estimates',
      entityId: taskId,
      operation: SyncOperationType.upsert,
      payload: const {'task_id': ''},
      userId: userId,
    );

    // This is the real app outbox/upload executor against an isolated local
    // Supabase Auth/PostgREST endpoint, not a fake remote store.
    final upload = SyncUploadExecutor(
      database: database,
      queue: queue,
      remote: SupabaseSyncRemoteStore(client),
      currentUserId: () => client.auth.currentUser?.id,
    );
    final flush = await upload.flush(force: true);
    final failedOps =
        await (database.select(database.syncOperations)..where(
              (row) => row.userId.equals(userId) & row.status.equals('failed'),
            ))
            .get();
    final failureSummary = failedOps
        .map((op) {
          final match = RegExp(
            r'(?:code|Code)[:= ]+([A-Z0-9]+)',
          ).firstMatch(op.lastError ?? '');
          return '${op.entityType}:${match?.group(1) ?? 'unclassified'}';
        })
        .join(',');
    expect(flush.failed, 0, reason: failureSummary);
    expect(flush.watermarkFailed, isFalse);
    final localWatermark = await (database.select(
      database.syncDeviceStates,
    )..where((row) => row.userId.equals(userId))).getSingle();
    expect(
      localWatermark.serverAcknowledgedGeneration,
      localWatermark.localGeneration,
    );
    final pending = await queue.loadRetryableForUser(userId);
    expect(pending, isEmpty);
    String dateKey(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

    final cloudTask = await client
        .from('tasks')
        .select('id')
        .eq('user_id', userId)
        .eq('id', taskId);
    final cloudCourse = await client
        .from('courses')
        .select('id')
        .eq('user_id', userId)
        .eq('id', courseId);
    expect(cloudTask, hasLength(1));
    expect(cloudCourse, hasLength(1));
    final cloudReminder = await client
        .from('one_time_reminders')
        .select('available_from,planned_date,due_date,due_at')
        .eq('user_id', userId)
        .eq('task_id', taskId)
        .single();
    expect(cloudReminder['available_from'], dateKey(today));
    expect(cloudReminder['planned_date'], dateKey(tomorrow));
    expect(
      cloudReminder['due_date'],
      dateKey(today.add(const Duration(days: 5))),
    );
    expect(cloudReminder['due_at'], isNull);
    final cloudEffort = await client
        .from('task_effort_estimates')
        .select('remaining_seconds')
        .eq('user_id', userId)
        .eq('task_id', taskId)
        .single();
    expect(cloudEffort['remaining_seconds'], 3600);

    final from = dateKey(today);
    final throughKey = dateKey(through);
    final serverSnapshot = Map<String, dynamic>.from(
      await client.rpc(
            'build_agent_planning_snapshot',
            params: {'p_from': from, 'p_through': throughKey},
          )
          as Map,
    );
    final source = Map<String, dynamic>.from(serverSnapshot['source'] as Map);
    final remoteOccurrences = (source['course_occurrences'] as List)
        .cast<Map>();

    final context = PlanningContextRepository(
      database: database,
      tasks: tasks,
      courses: courses,
      semesters: semesters,
      schedule: schedule,
      authenticatedUserId: userId,
    );
    final localSnapshot = await context.load(
      from: today,
      through: through,
      now: now,
    );
    expect(localSnapshot['provisional'], isTrue);
    final localOccurrences = (localSnapshot['course_occurrences'] as List)
        .cast<Map>();
    List<String> occurrenceIntervals(List<Map> rows) =>
        rows
            .map(
              (row) =>
                  '${DateTime.parse(row['starts_at'] as String).toUtc().toIso8601String()}/${DateTime.parse(row['ends_at'] as String).toUtc().toIso8601String()}',
            )
            .toList()
          ..sort();
    expect(
      occurrenceIntervals(localOccurrences),
      occurrenceIntervals(remoteOccurrences),
    );
    expect(remoteOccurrences.length, greaterThanOrEqualTo(6));
    final nextTuesdayKey = dateKey(today.add(const Duration(days: 8)));
    expect(
      remoteOccurrences.cast<Map>().where(
        (row) =>
            row['course_id'] == oddCourseId &&
            row['local_date'] == dateKey(tomorrow),
      ),
      hasLength(1),
    );
    expect(
      remoteOccurrences.cast<Map>().where(
        (row) =>
            row['course_id'] == oddCourseId &&
            row['local_date'] == nextTuesdayKey,
      ),
      isEmpty,
    );
    expect(
      remoteOccurrences.cast<Map>().where(
        (row) =>
            row['course_id'] == evenCourseId &&
            row['local_date'] == dateKey(tomorrow),
      ),
      isEmpty,
    );
    expect(
      remoteOccurrences.cast<Map>().where(
        (row) =>
            row['course_id'] == evenCourseId &&
            row['local_date'] == nextTuesdayKey,
      ),
      hasLength(1),
    );
    expect(
      remoteOccurrences.cast<Map>().where(
        (row) =>
            row['rule_id'] == ruleId && row['local_date'] == nextTuesdayKey,
      ),
      isEmpty,
    );
    final rescheduled = remoteOccurrences.cast<Map>().where(
      (row) =>
          row['rule_id'] == ruleId && row['local_date'] == dateKey(tomorrow),
    );
    expect(rescheduled, hasLength(1));
    expect(
      DateTime.parse(rescheduled.single['starts_at'] as String).toUtc(),
      DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day, 7),
    );
    expect(
      remoteOccurrences.cast<Map>().where(
        (row) =>
            row['course_id'] == boundedCourseId &&
            row['local_date'] != dateKey(tomorrow),
      ),
      isEmpty,
    );
    expect(
      remoteOccurrences.cast<Map>().where(
        (row) =>
            row['course_id'] == makeupCourseId &&
            row['local_date'] == dateKey(tomorrow) &&
            DateTime.parse(row['starts_at'] as String).toUtc() ==
                DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day, 8),
      ),
      hasLength(1),
    );

    final planner = const LocalPlanningEngine();
    final proposalSnapshot = Map<String, Object?>.from(localSnapshot)
      ..['version'] = serverSnapshot['snapshot_version']
      ..['source'] = 'server_snapshot_preview'
      ..['provisional'] = false;
    final planning = planner.preview(proposalSnapshot);
    expect(planning['ok'], isTrue);
    expect(planning['outcome'], 'found_feasible');
    final scheduleResult = Map<String, dynamic>.from(
      planning['schedule'] as Map,
    );
    final blocks = (scheduleResult['blocks'] as List).cast<Map>();
    expect(blocks, isNotEmpty);
    for (final block in blocks) {
      final start = DateTime.parse(block['starts_at'] as String).toUtc();
      final end = DateTime.parse(block['ends_at'] as String).toUtc();
      for (final remoteCourse in remoteOccurrences.cast<Map>()) {
        final classStart = DateTime.parse(
          remoteCourse['starts_at'] as String,
        ).toUtc();
        final classEnd = DateTime.parse(
          remoteCourse['ends_at'] as String,
        ).toUtc();
        expect(start.isBefore(classEnd) && classStart.isBefore(end), isFalse);
      }
      expect(
        (block['planned_seconds'] as num).toInt(),
        end.difference(start).inSeconds,
      );
      final localEndDate = end
          .subtract(const Duration(microseconds: 1))
          .toLocal();
      expect(
        dateKey(
          localEndDate,
        ).compareTo(dateKey(today.add(const Duration(days: 5)))),
        lessThanOrEqualTo(0),
      );
    }

    final changes = blocks
        .map(
          (block) => {
            'task_id': block['task_id'],
            'starts_at': block['starts_at'],
            'ends_at': block['ends_at'],
            'planned_seconds': block['planned_seconds'],
          },
        )
        .toList(growable: false);
    final proposal = Map<String, dynamic>.from(
      await client.rpc(
            'create_agent_plan_proposal',
            params: {
              'p_from': from,
              'p_through': throughKey,
              'p_expected_snapshot_version': serverSnapshot['snapshot_version'],
              'p_device_id': localWatermark.deviceId,
              'p_local_generation': localWatermark.localGeneration,
              'p_rules_version': 'planning_rules_v1',
              'p_idempotency_key': 'android-e2e-proposal-$suffix',
              'p_changes': changes,
            },
          )
          as Map,
    );
    expect(proposal['status'], 'proposed');
    expect(proposal['execution_eligible'], isFalse);
    final proposalId = proposal['proposal_id'] as String;
    final approval = Map<String, dynamic>.from(
      await client.rpc(
            'approve_agent_plan_proposal',
            params: {'p_proposal_id': proposalId},
          )
          as Map,
    );
    expect(approval['status'], 'approved');
    expect(approval['simulated_approval'], isTrue);
    final applyKey = 'android-e2e-apply-$suffix';
    final applied = Map<String, dynamic>.from(
      await client.rpc(
            'apply_approved_plan',
            params: {
              'p_proposal_id': proposalId,
              'p_approval_id': approval['approval_id'],
              'p_idempotency_key': applyKey,
            },
          )
          as Map,
    );
    expect(applied['readback_verified'], isTrue);
    final replay = Map<String, dynamic>.from(
      await client.rpc(
            'apply_approved_plan',
            params: {
              'p_proposal_id': proposalId,
              'p_approval_id': approval['approval_id'],
              'p_idempotency_key': applyKey,
            },
          )
          as Map,
    );
    expect(replay, applied);

    final applyReadback = await client
        .from('task_time_blocks')
        .select('id,task_id,starts_at,ends_at')
        .eq('user_id', userId)
        .eq('task_id', taskId);
    expect(applyReadback, hasLength(blocks.length));

    final download = SyncDownloadExecutor(
      database: database,
      remote: SupabaseSyncRemoteReader(client),
      applyScope: SyncApplyScope(),
      currentUserId: () => client.auth.currentUser?.id,
    );
    final downloaded = await download.reconcile();
    expect(downloaded.succeeded, isTrue, reason: '${downloaded.error}');
    final localPlans = await PlanningPlanRepository(
      database: database,
      userId: userId,
    ).loadPlans(startsOnOrBefore: through, endsOnOrAfter: today);
    expect(localPlans, hasLength(1));
    expect(localPlans.single.status, LocalPlanStatus.applied);
    expect(localPlans.single.blocks, hasLength(blocks.length));

    final changedSnapshot = Map<String, dynamic>.from(
      await client.rpc(
            'build_agent_planning_snapshot',
            params: {'p_from': from, 'p_through': throughKey},
          )
          as Map,
    );
    final changedContext = await context.load(
      from: today,
      through: through,
      now: DateTime.now(),
    );
    final changedPlanning = planner.preview({
      ...changedContext,
      'version': changedSnapshot['snapshot_version'],
    });
    final changedBlocks =
        (Map<String, dynamic>.from(changedPlanning['schedule'] as Map)['blocks']
                as List)
            .cast<Map>();
    expect(changedBlocks, isNotEmpty);
    final staleProposal = await client.rpc(
      'create_agent_plan_proposal',
      params: {
        'p_from': from,
        'p_through': throughKey,
        'p_expected_snapshot_version': changedSnapshot['snapshot_version'],
        'p_device_id': localWatermark.deviceId,
        'p_local_generation': localWatermark.localGeneration,
        'p_rules_version': 'planning_rules_v1',
        'p_idempotency_key': 'android-e2e-stale-$suffix',
        'p_changes': changedBlocks
            .map(
              (block) => {
                'task_id': block['task_id'],
                'starts_at': block['starts_at'],
                'ends_at': block['ends_at'],
                'planned_seconds': block['planned_seconds'],
              },
            )
            .toList(),
      },
    );
    final staleId = (staleProposal as Map)['proposal_id'] as String;
    await tasks.saveOneTimeReminder(
      OneTimeReminderDraft(
        name: 'E2E 合成实验报告（修改后）',
        colorValue: 0xff887766,
        availableFrom: today,
        plannedDate: tomorrow,
        dueDate: today.add(const Duration(days: 5)),
      ),
      taskId: taskId,
    );
    final updateFlush = await upload.flush(force: true);
    expect(updateFlush.failed, 0);
    expect(updateFlush.watermarkFailed, isFalse);
    await expectLater(
      client.rpc(
        'approve_agent_plan_proposal',
        params: {'p_proposal_id': staleId},
      ),
      throwsA(isA<PostgrestException>()),
    );
    final staleRows = await client
        .from('agent_plan_proposals')
        .select('status')
        .eq('user_id', userId)
        .eq('id', staleId);
    expect(staleRows.single['status'], 'superseded');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planningContextRepositoryProvider.overrideWithValue(context),
          planningPlanRepositoryProvider.overrideWithValue(
            PlanningPlanRepository(database: database, userId: userId),
          ),
        ],
        child: const MaterialApp(home: PlanningPreviewPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('智能规划预览'), findsOneWidget);
    expect(find.textContaining('applied'), findsOneWidget);
    expect(find.textContaining('个时间块'), findsWidgets);
  });
}
