import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('local task and its sync operation are persisted', () async {
    final now = DateTime.utc(2026, 9, 2);
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: 'task-1',
            userId: const Value('user-1'),
            name: '英语听力',
            taskType: 'long_term',
            colorValue: 0xFF3D73E8,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final queue = SyncQueueService(database);
    await queue.enqueue(
      entityType: 'tasks',
      entityId: 'task-1',
      operation: SyncOperationType.upsert,
      userId: 'user-1',
      payload: const {'name': '英语听力'},
    );

    final tasks = await database.select(database.localTasks).get();
    final operations = await queue.watchPending().first;

    expect(tasks.single.name, '英语听力');
    expect(operations.single.entityId, 'task-1');
    expect(operations.single.status, 'pending');
  });

  test('v4 migration preserves completion history and backfills target', () async {
    await database.close();
    database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (db) {
          db.execute('CREATE TABLE one_time_reminder_records (task_id TEXT)');
          db.execute('CREATE TABLE local_tasks (id TEXT PRIMARY KEY)');
          db.execute(
            'CREATE TABLE timer_session_records (id TEXT PRIMARY KEY)',
          );
          db.execute(
            'CREATE TABLE long_term_task_records '
            '(task_id TEXT, check_mode TEXT, target_duration_seconds INTEGER)',
          );
          db.execute(
            'CREATE TABLE task_completion_records '
            '(task_id TEXT, actual_duration_seconds INTEGER, is_success INTEGER, completed_at INTEGER)',
          );
          db.execute(
            "INSERT INTO long_term_task_records VALUES ('old-task', 'timer', 600)",
          );
          db.execute(
            "INSERT INTO task_completion_records VALUES ('old-task', 900, 1, 123)",
          );
          db.execute('PRAGMA user_version = 4');
        },
      ),
    );
    final mode = await database
        .customSelect('SELECT check_mode FROM long_term_task_records')
        .getSingle();
    final completion = await database
        .customSelect('SELECT * FROM task_completion_records')
        .getSingle();
    expect(mode.read<String>('check_mode'), 'timed');
    expect(completion.read<int>('target_reached'), 1);
    expect(completion.read<int>('is_success'), 1);
    expect(completion.read<int>('completed_at'), 123);
  });

  test('v5 migration retains sessions and leaves old tags unassigned', () async {
    await database.close();
    database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (db) {
          db.execute('CREATE TABLE local_tasks (id TEXT PRIMARY KEY)');
          db.execute(
            'CREATE TABLE timer_session_records (id TEXT PRIMARY KEY, duration_seconds INTEGER, state TEXT)',
          );
          db.execute("INSERT INTO local_tasks VALUES ('old')");
          db.execute(
            "INSERT INTO timer_session_records VALUES ('session', 1800, 'paused')",
          );
          db.execute('PRAGMA user_version = 5');
        },
      ),
    );
    final session = await database
        .customSelect('SELECT * FROM timer_session_records')
        .getSingle();
    expect(session.read<int>('duration_seconds'), 1800);
    expect(session.read<String>('state'), 'paused');
    expect(session.readNullable<String>('tag_id'), null);
    final task = await database
        .customSelect('SELECT * FROM local_tasks')
        .getSingle();
    expect(task.read<String>('id'), 'old');
    expect(task.readNullable<String>('tag_id'), null);
    expect(await database.select(database.tagRecords).get(), isEmpty);
  });
}
