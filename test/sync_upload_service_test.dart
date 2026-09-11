import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/core/sync/sync_upload_service.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(remote.value('long_term_tasks', taskId)?['task_id'], taskId);
    expect(remote.value('task_schedules', taskId)?['task_id'], taskId);
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
  final Map<String, Map<String, Object?>> _rows = {};

  @override
  Future<void> upsert(
    String table,
    Map<String, Object?> values, {
    required String onConflict,
  }) async {
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
