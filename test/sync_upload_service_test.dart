import 'dart:convert';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/core/sync/sync_upload_service.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
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

  test('failed batch cannot starve a later pending task', () async {
    final old = DateTime.utc(2020);
    for (var index = 0; index < 2; index++) {
      await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: 'failed-$index',
              userId: const Value(userId),
              entityType: 'timer_sessions',
              entityId: 'missing-$index',
              operation: 'upsert',
              payloadJson: '{}',
              status: const Value('failed'),
              createdAt: old.add(Duration(seconds: index)),
              updatedAt: old.add(Duration(seconds: index)),
            ),
          );
    }
    final taskId = await tasks.saveRecurringTask(_timedDraft('后续正常任务'));

    final result = await executor.flush(force: true, limit: 2);

    expect(result.uploaded, 1);
    expect(remote.value('tasks', taskId)?['name'], '后续正常任务');
    expect(await statusFor(database, 'tasks', taskId, userId), 'completed');
  });

  test('failed operations rotate after an attempted retry', () async {
    final old = DateTime.utc(2020);
    for (var index = 0; index < 3; index++) {
      await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: 'failed-$index',
              userId: const Value(userId),
              entityType: 'timer_sessions',
              entityId: 'missing-$index',
              operation: 'upsert',
              payloadJson: '{}',
              status: const Value('failed'),
              createdAt: old.add(Duration(seconds: index)),
              updatedAt: old.add(Duration(seconds: index)),
            ),
          );
    }

    await executor.flush(force: true, limit: 1);
    await executor.flush(force: true, limit: 1);

    final rows = await (database.select(
      database.syncOperations,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
    expect(rows.map((row) => row.retryCount), [1, 1, 0]);
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
