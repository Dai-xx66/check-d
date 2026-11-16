import 'dart:convert';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/core/sync/sync_upload_service.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/planning/data/course_occurrence_snapshot.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const userId = 'user-1';
  late AppDatabase database;
  late SyncQueueService queue;
  late TaskRepository tasks;
  late _FakeRemoteStore remote;
  late String? authenticatedUserId;
  late SyncUploadExecutor executor;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueueService(database);
    tasks = TaskRepository(
      database: database,
      syncQueue: queue,
      userId: userId,
    );
    remote = _FakeRemoteStore();
    authenticatedUserId = userId;
    executor = SyncUploadExecutor(
      database: database,
      queue: queue,
      remote: remote,
      currentUserId: () => authenticatedUserId,
    );
  });

  tearDown(() => database.close());

  test('pending local task uploads with authenticated ownership', () async {
    final taskId = await tasks.saveRecurringTask(_timedDraft('阅读'));

    final result = await executor.flush();

    expect(result.uploaded, 1);
    expect(result.failed, 0);
    expect(
      statusFor(database, 'tasks', taskId, userId),
      completion('completed'),
    );
    expect(remote.value('tasks', taskId)?['user_id'], userId);
    final taskPayload = remote.value('tasks', taskId)!;
    expect(taskPayload, isNot(contains('pending')));
    expect(taskPayload, isNot(contains('carry_over')));
    expect(taskPayload, isNot(contains('overdue')));
    expect(remote.value('long_term_tasks', taskId)?['task_id'], taskId);
    final schedulePayload = remote.value('task_schedules', taskId)!;
    expect(schedulePayload['task_id'], taskId);
    expect(schedulePayload['weekdays'], isA<List<int>>());
    expect(schedulePayload['weekdays'], <int>[1, 2, 3, 4, 5, 6, 7]);
    expect(() => jsonEncode(schedulePayload), returnsNormally);
  });

  test(
    'failed operation is retained while a later operation uploads',
    () async {
      final taskId = await tasks.saveRecurringTask(_timedDraft('失败任务'));
      await queue.enqueue(
        entityType: 'user_preferences',
        entityId: userId,
        operation: SyncOperationType.upsert,
        payload: const {
          'id': userId,
          'preference_key': 'reminder_defaults',
          'value': <String, Object?>{},
        },
        userId: userId,
      );
      remote.failTables.add('tasks');

      final result = await executor.flush();

      expect(result.failed, 1);
      expect(result.uploaded, 1);
      final taskOperation = await operationFor(
        database,
        'tasks',
        taskId,
        userId,
      );
      expect(taskOperation.status, 'failed');
      expect(taskOperation.retryCount, 1);
      expect(remote.value('user_preferences', userId), isNotNull);
    },
  );

  test('unauthenticated and offline mode leave local work pending', () async {
    final taskId = await tasks.saveRecurringTask(_timedDraft('离线任务'));
    authenticatedUserId = null;

    final result = await executor.flush();

    expect(result.unauthenticated, isTrue);
    expect(await tasks.getTask(taskId), isNotNull);
    expect(
      (await operationFor(database, 'tasks', taskId, userId)).status,
      'pending',
    );
    expect(remote.upserts, isEmpty);
  });

  test('duplicate operations converge through idempotent upserts', () async {
    final taskId = await tasks.saveRecurringTask(_timedDraft('幂等任务'));
    await queue.enqueue(
      entityType: 'tasks',
      entityId: taskId,
      operation: SyncOperationType.upsert,
      payload: {'id': taskId},
      userId: userId,
    );

    final result = await executor.flush();

    expect(result.uploaded, 2);
    expect(remote.countFor('tasks', taskId), 2);
    expect(remote.value('tasks', taskId)?['name'], '幂等任务');
  });

  test(
    'server checkpoint is acknowledged only after the full outbox clears',
    () async {
      final taskId = await tasks.saveRecurringTask(_timedDraft('检查点任务'));
      final result = await executor.flush();

      expect(result.failed, 0);
      expect(result.checkpointAcknowledged, isTrue);
      expect(remote.checkpoints, hasLength(1));
      final state = await (database.select(
        database.syncDeviceStates,
      )..where((row) => row.userId.equals(userId))).getSingle();
      expect(state.localGeneration, 1);
      expect(state.acknowledgedGeneration, 1);
      expect(
        (await operationFor(database, 'tasks', taskId, userId)).localGeneration,
        1,
      );
    },
  );

  test('failed or unscoped pending work prevents device checkpoint', () async {
    final taskId = await tasks.saveRecurringTask(_timedDraft('失败不确认'));
    remote.failTables.add('tasks');
    final failed = await executor.flush();
    expect(failed.checkpointAcknowledged, isFalse);
    expect(remote.checkpoints, isEmpty);

    remote.failTables.clear();
    await queue.enqueue(
      entityType: 'legacy_unscoped',
      entityId: 'legacy',
      operation: SyncOperationType.upsert,
      payload: const {'id': 'legacy'},
    );
    final unsettled = await executor.flush(force: true);
    expect(unsettled.checkpointAcknowledged, isFalse);
    expect(remote.checkpoints, isEmpty);
    expect(
      (await operationFor(database, 'tasks', taskId, userId)).status,
      'completed',
    );
  });

  test(
    'device generation advances per user without crossing accounts',
    () async {
      await tasks.saveRecurringTask(_timedDraft('账户一'));
      final secondTasks = TaskRepository(
        database: database,
        syncQueue: queue,
        userId: 'user-2',
      );
      await secondTasks.saveRecurringTask(_timedDraft('账户二'));
      final rows = await database.select(database.syncDeviceStates).get();

      expect(rows.map((row) => row.userId), containsAll(['user-1', 'user-2']));
      expect(rows, hasLength(2));
      expect(rows.map((row) => row.localGeneration), everyElement(1));
      expect(rows.map((row) => row.deviceId).toSet(), hasLength(1));
    },
  );

  test(
    'local edit during checkpoint request is not locally acknowledged',
    () async {
      await tasks.saveRecurringTask(_timedDraft('检查点并发写'));
      remote.onAcknowledge = () => queue.enqueue(
        entityType: 'user_preferences',
        entityId: userId,
        operation: SyncOperationType.upsert,
        payload: const {'id': 'preference'},
        userId: userId,
      );

      final result = await executor.flush();

      expect(result.checkpointAcknowledged, isFalse);
      final state = await (database.select(
        database.syncDeviceStates,
      )..where((row) => row.userId.equals(userId))).getSingle();
      expect(state.localGeneration, 2);
      expect(state.acknowledgedGeneration, -1);
    },
  );

  test('old server checkpoint gets a fresh course snapshot and watermark', () async {
    final initial = await executor.flush();
    expect(initial.checkpointAcknowledged, isTrue);
    await (database.update(database.syncDeviceStates)
          ..where((row) => row.userId.equals(userId)))
        .write(
          SyncDeviceStatesCompanion(
            updatedAt: Value(DateTime.now().toUtc().subtract(const Duration(minutes: 11))),
          ),
        );
    remote.checkpoints.clear();

    final refreshed = await executor.flush();

    expect(refreshed.checkpointAcknowledged, isTrue);
    expect(remote.checkpoints, hasLength(1));
    expect(remote.checkpoints.single.$2, 0);
  });

  test('course snapshot uploads canonical Flutter occurrences', () async {
    final courseRepository = CourseRepository(
      database: database,
      syncQueue: queue,
      userId: userId,
    );
    final semesterRepository = SemesterRepository(
      database: database,
      syncQueue: queue,
      userId: userId,
    );
    final scheduleRepository = DayScheduleRepository(
      database: database,
      syncQueue: queue,
      userId: userId,
    );
    final courseId = await courseRepository.saveCourse(
      CourseDraft(
        name: '合成课程',
        colorValue: 1,
        semesterStartsOn: DateTime(2026, 11, 16),
        semesterEndsOn: DateTime(2026, 11, 23),
      ),
    );
    await courseRepository.saveScheduleRule(
      CourseScheduleRuleDraft(
        courseId: courseId,
        weekday: DateTime.monday,
        weekRuleType: CourseWeekRuleType.everyWeek,
        startsAtMinute: 9 * 60,
        endsAtMinute: 10 * 60 + 30,
      ),
      ruleId: 'rule-monday',
    );
    await courseRepository.saveScheduleRule(
      CourseScheduleRuleDraft(
        courseId: courseId,
        weekday: DateTime.tuesday,
        weekRuleType: CourseWeekRuleType.everyWeek,
        startsAtMinute: 11 * 60,
        endsAtMinute: 12 * 60,
      ),
      ruleId: 'rule-tuesday',
    );
    await scheduleRepository.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.course,
        itemId: 'rule-monday',
        localDate: DateTime(2026, 11, 16),
        action: DayOverrideAction.reschedule,
        plannedStartMinute: 14 * 60,
        plannedEndMinute: 15 * 60,
      ),
    );
    await scheduleRepository.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.course,
        itemId: 'rule-tuesday',
        localDate: DateTime(2026, 11, 17),
        action: DayOverrideAction.skip,
      ),
    );
    await scheduleRepository.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.course,
        itemId: courseId,
        localDate: DateTime(2026, 11, 18),
        action: DayOverrideAction.extraCourse,
        plannedStartMinute: 16 * 60,
        plannedEndMinute: 17 * 60,
      ),
    );
    final snapshotRepository = DriftCourseOccurrenceSnapshotRepository(
      userId: userId,
      courses: courseRepository,
      semesters: semesterRepository,
      schedule: scheduleRepository,
      syncQueue: queue,
    );
    executor = SyncUploadExecutor(
      database: database,
      queue: queue,
      remote: remote,
      currentUserId: () => authenticatedUserId,
      publishCourseOccurrenceSnapshot: (checkpoint) async {
        final snapshot = await snapshotRepository.build(
          from: DateTime(2026, 11, 16),
          through: DateTime(2026, 11, 24),
        );
        await remote.publishCourseOccurrenceSnapshot(
          deviceId: checkpoint.deviceId,
          snapshot: snapshot.toJson(),
        );
      },
    );

    final result = await executor.flush(force: true);

    expect(result.failed, 0);
    expect(result.checkpointAcknowledged, isTrue);
    expect(remote.courseSnapshots, hasLength(1));
    final payload = remote.courseSnapshots.single.$2;
    expect(payload['from_date'], '2026-11-16');
    expect(payload['through_date'], '2026-11-24');
    expect(payload['timezone'], 'Asia/Shanghai');
    expect(DateTime.tryParse(payload['generated_at']! as String), isNotNull);
    expect(payload['builder_version'], 'checkd_flutter_course_occurrence_v1');
    expect(payload['course_data_version'], startsWith('sha256:'));
    expect(payload['local_generation'], 6);
    final occurrences = payload['occurrences']! as List;
    expect(occurrences, hasLength(3));
    expect(occurrences.every((row) => row['course_id'] == courseId), isTrue);
    final byDate = {for (final row in occurrences) row['local_date']: row};
    expect(byDate['2026-11-16']['start_minute'], 840);
    expect(byDate['2026-11-16']['end_minute'], 900);
    expect(byDate['2026-11-18']['start_minute'], 960);
    expect(byDate['2026-11-18']['end_minute'], 1020);
    expect(byDate['2026-11-23']['start_minute'], 540);
    expect(byDate.containsKey('2026-11-17'), isFalse);
    expect(byDate.containsKey('2026-11-24'), isFalse);
  });

  test('archived task is uploaded as a soft archive', () async {
    final taskId = await tasks.saveRecurringTask(_timedDraft('归档任务'));
    await tasks.archiveTask(taskId);

    final result = await executor.flush();

    expect(result.failed, 0);
    expect(result.uploaded, 2);
    expect(remote.value('tasks', taskId)?['status'], 'archived');
  });

  test('two different running timers upload independently', () async {
    final first = await tasks.saveRecurringTask(_timedDraft('计时一'));
    final second = await tasks.saveRecurringTask(_timedDraft('计时二'));
    await tasks.startTimer(first, now: DateTime.utc(2026, 9, 10, 8));
    await tasks.startTimer(second, now: DateTime.utc(2026, 9, 10, 8, 5));

    final result = await executor.flush();

    expect(result.failed, 0);
    final runningSessions = remote.upserts.where(
      (write) =>
          write.table == 'timer_sessions' && write.values['state'] == 'running',
    );
    expect(runningSessions, hasLength(2));
    expect(
      runningSessions.map((write) => write.values['task_id']),
      containsAll(<String>[first, second]),
    );
  });

  test(
    'one-time upload keeps date-only and exact deadline shapes distinct',
    () async {
      final dateOnlyId = await tasks.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: '日期截止',
          colorValue: 1,
          availableFrom: DateTime(2026, 9, 18),
          plannedDate: DateTime(2026, 9, 19),
          deadline: TaskDeadline.dateOnly(DateTime(2026, 9, 20)),
        ),
      );
      final exactId = await tasks.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: '精确截止',
          colorValue: 1,
          scheduledAt: DateTime(2026, 9, 19, 14),
          deadline: TaskDeadline.exact(DateTime(2026, 9, 19, 18)),
        ),
      );

      expect((await executor.flush()).failed, 0);
      final dateOnly = remote.value('one_time_reminders', dateOnlyId)!;
      expect(dateOnly['available_from'], '2026-09-18');
      expect(dateOnly['planned_date'], '2026-09-19');
      expect(dateOnly['due_date'], '2026-09-20');
      expect(dateOnly['due_at'], isNull);
      final exact = remote.value('one_time_reminders', exactId)!;
      expect(exact['due_date'], isNull);
      expect(exact['due_at'], isNotNull);
    },
  );

  test('second task write records long-term table and SQLSTATE', () async {
    final taskId = await tasks.saveRecurringTask(_timedDraft('第二步失败'));
    remote.failures['long_term_tasks'] = const PostgrestException(
      message: 'sensitive database detail',
      code: '23514',
      details: 'must not be persisted',
    );

    final result = await executor.flush();
    final operation = await operationFor(database, 'tasks', taskId, userId);
    final diagnostic =
        (await queue.watchFailureDiagnosticsForUser(userId).first).single;

    expect(result.failed, 1);
    expect(remote.value('tasks', taskId), isNotNull);
    expect(remote.value('long_term_tasks', taskId), isNull);
    expect(diagnostic.failureStage, 'upsert');
    expect(diagnostic.failureTable, 'long_term_tasks');
    expect(diagnostic.errorCode, '23514');
    expect(diagnostic.errorCategory, '上传数据不符合云端约束');
    expect(operation.lastError, isNot(contains('sensitive database detail')));
    expect(operation.lastError, isNot(contains('must not be persisted')));
  });

  test('third task write records schedule table and SQLSTATE', () async {
    final taskId = await tasks.saveRecurringTask(_timedDraft('第三步失败'));
    remote.failures['task_schedules'] = const PostgrestException(
      message: 'foreign key detail',
      code: '23503',
    );

    final result = await executor.flush();
    final diagnostic =
        (await queue.watchFailureDiagnosticsForUser(userId).first).single;

    expect(result.failed, 1);
    expect(remote.value('tasks', taskId), isNotNull);
    expect(remote.value('long_term_tasks', taskId), isNotNull);
    expect(remote.value('task_schedules', taskId), isNull);
    expect(diagnostic.failureStage, 'upsert');
    expect(diagnostic.failureTable, 'task_schedules');
    expect(diagnostic.errorCode, '23503');
    expect(diagnostic.errorCategory, '云端关联数据缺失');
  });

  test('JSON serialization failures are safely classified', () async {
    final taskId = await tasks.saveRecurringTask(_timedDraft('序列化失败'));
    remote.failures['task_schedules'] = JsonUnsupportedObjectError(<int>{1});

    final result = await executor.flush();
    final operation = await operationFor(database, 'tasks', taskId, userId);
    final diagnostic =
        (await queue.watchFailureDiagnosticsForUser(userId).first).single;

    expect(result.failed, 1);
    expect(diagnostic.failureStage, 'upsert');
    expect(diagnostic.failureTable, 'task_schedules');
    expect(diagnostic.errorCode, isNull);
    expect(diagnostic.errorCategory, '同步数据序列化失败');
    expect(operation.lastError, isNot(contains('序列化失败')));
    expect(operation.lastError, isNot(contains('{1}')));
  });

  test('one-time child failure records its exact table', () async {
    final taskId = await tasks.saveOneTimeReminder(
      const OneTimeReminderDraft(name: '单次失败', colorValue: 1),
    );
    remote.failures['one_time_reminders'] = const PostgrestException(
      message: 'missing required value',
      code: '23502',
    );

    final result = await executor.flush();
    final diagnostic =
        (await queue.watchFailureDiagnosticsForUser(userId).first).single;

    expect(result.failed, 1);
    expect(remote.value('tasks', taskId), isNotNull);
    expect(remote.value('one_time_reminders', taskId), isNull);
    expect(diagnostic.failureStage, 'upsert');
    expect(diagnostic.failureTable, 'one_time_reminders');
    expect(diagnostic.errorCode, '23502');
    expect(diagnostic.errorCategory, '云端必填字段缺失');
  });
}

Future<SyncOperation> operationFor(
  AppDatabase database,
  String entityType,
  String entityId,
  String userId,
) {
  return (database.select(database.syncOperations)
        ..where(
          (row) =>
              row.entityType.equals(entityType) &
              row.entityId.equals(entityId) &
              row.userId.equals(userId),
        )
        ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
        ..limit(1))
      .getSingle();
}

Future<String> statusFor(
  AppDatabase database,
  String entityType,
  String entityId,
  String userId,
) async => (await operationFor(database, entityType, entityId, userId)).status;

RecurringTaskDraft _timedDraft(String name) => RecurringTaskDraft(
  name: name,
  colorValue: 0xFFFF6B9A,
  executionMode: RecurringExecutionMode.timed,
  targetDurationSeconds: 25 * 60,
  schedulePreset: SchedulePreset.daily,
  weekdays: const {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  },
  startsOn: DateTime(2026, 9, 1),
  holidayPause: false,
);

class _FakeRemoteStore implements SyncRemoteStore {
  final List<_Upsert> upserts = [];
  final List<(String, int)> checkpoints = [];
  final List<(String, Map<String, Object?>)> courseSnapshots = [];
  Future<void> Function()? onAcknowledge;
  final Set<String> failTables = {};
  final Map<String, Object> failures = {};
  final Map<String, Map<String, Object?>> _rows = {};

  @override
  Future<void> upsert(
    String table,
    Map<String, Object?> values, {
    required String onConflict,
  }) async {
    jsonEncode(values);
    final failure = failures[table];
    if (failure != null) throw failure;
    if (failTables.contains(table)) throw StateError('offline: $table');
    final copy = Map<String, Object?>.from(values);
    upserts.add(_Upsert(table, copy));
    _rows['$table:${_idFor(copy)}'] = copy;
  }

  @override
  Future<void> clearOtherActiveFlag(
    String table, {
    required String userId,
    required String id,
    required String flagColumn,
  }) async {}

  @override
  Future<void> replacePlanTasks({
    required String userId,
    required String planId,
    required List<Map<String, Object?>> rows,
  }) async {}

  @override
  Future<void> acknowledgeDeviceCheckpoint({
    required String deviceId,
    required int localGeneration,
  }) async {
    checkpoints.add((deviceId, localGeneration));
    await onAcknowledge?.call();
  }

  @override
  Future<void> publishCourseOccurrenceSnapshot({
    required String deviceId,
    required Map<String, Object?> snapshot,
  }) async {
    courseSnapshots.add((deviceId, snapshot));
  }

  Map<String, Object?>? value(String table, String id) => _rows['$table:$id'];

  int countFor(String table, String id) => upserts
      .where((write) => write.table == table && _idFor(write.values) == id)
      .length;

  String _idFor(Map<String, Object?> values) =>
      (values['id'] ?? values['task_id'] ?? values['plan_id'])! as String;
}

class _Upsert {
  const _Upsert(this.table, this.values);

  final String table;
  final Map<String, Object?> values;
}
