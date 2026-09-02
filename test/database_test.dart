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
}
