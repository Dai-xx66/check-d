import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late TaskRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(
      database: database,
      syncQueue: SyncQueueService(database),
      userId: 'user-1',
    );
  });

  tearDown(() => database.close());

  test('creates both task types for today', () async {
    final day = DateTime(2026, 9, 2);
    await repository.saveLongTermTask(_simpleDraft(day));
    await repository.saveOneTimeReminder(
      OneTimeReminderDraft(
        name: '项目会议',
        colorValue: 0xFFE69545,
        scheduledAt: DateTime(2026, 9, 2, 14),
        remindBeforeMinutes: 30,
      ),
    );

    final tasks = await repository.watchTasksForDate(day).first;

    expect(tasks, hasLength(2));
    expect(tasks.map((task) => task.kind), {
      TaskKind.longTerm,
      TaskKind.oneTime,
    });
  });

  test('simple completion toggles without deleting history', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_simpleDraft(day));

    await repository.toggleSimpleCompletion(taskId, day);
    expect((await repository.getTask(taskId, date: day))!.isCompleted, isTrue);

    await repository.toggleSimpleCompletion(taskId, day);
    final task = await repository.getTask(taskId, date: day);
    final completions = await database
        .select(database.taskCompletionRecords)
        .get();

    expect(task!.isCompleted, isFalse);
    expect(completions, hasLength(1));
    expect(completions.single.progressPercent, 0);
    expect(completions.single.isSuccess, isFalse);
  });

  test('custom schedule only returns tasks on selected weekdays', () async {
    final monday = DateTime(2026, 8, 31);
    final tuesday = DateTime(2026, 9, 1);
    await repository.saveLongTermTask(
      LongTermTaskDraft(
        name: '周一阅读',
        colorValue: 0xFF3D73E8,
        checkMode: LongTermCheckMode.simple,
        schedulePreset: SchedulePreset.custom,
        weekdays: const {DateTime.monday},
        startsOn: monday,
        holidayPause: false,
      ),
    );

    expect(await repository.watchTasksForDate(monday).first, hasLength(1));
    expect(await repository.watchTasksForDate(tuesday).first, isEmpty);
  });

  test('editing keeps task identity and adds a revision', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_simpleDraft(day));

    await repository.saveLongTermTask(
      LongTermTaskDraft(
        name: '英语精听',
        colorValue: 0xFF45A77A,
        checkMode: LongTermCheckMode.simple,
        targetDays: 100,
        schedulePreset: SchedulePreset.weekdays,
        weekdays: const {
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
        },
        startsOn: day,
        holidayPause: false,
      ),
      taskId: taskId,
    );

    final tasks = await database.select(database.localTasks).get();
    final revisions = await database.select(database.taskRevisionRecords).get();
    expect(tasks, hasLength(1));
    expect(tasks.single.id, taskId);
    expect(tasks.single.name, '英语精听');
    expect(revisions, hasLength(2));
  });

  test('one-time completion and undo are preserved as revisions', () async {
    final taskId = await repository.saveOneTimeReminder(
      OneTimeReminderDraft(
        name: '体检',
        colorValue: 0xFFD96060,
        scheduledAt: DateTime(2026, 9, 2, 9),
      ),
    );

    await repository.toggleOneTimeCompletion(taskId);
    expect((await repository.getTask(taskId))!.isCompleted, isTrue);
    await repository.toggleOneTimeCompletion(taskId);

    expect((await repository.getTask(taskId))!.isCompleted, isFalse);
    final revisions = await database.select(database.taskRevisionRecords).get();
    expect(revisions, hasLength(3));
  });

  test('archive hides task and preserves revisions', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_simpleDraft(day));

    await repository.archiveTask(taskId);

    expect(await repository.watchTasksForDate(day).first, isEmpty);
    expect(
      await repository.watchTasksByStatus(TaskLifecycle.archived).first,
      hasLength(1),
    );
    final revisions = await database.select(database.taskRevisionRecords).get();
    expect(revisions, hasLength(2));
    final task = await (database.select(
      database.localTasks,
    )..where((row) => row.id.equals(taskId))).getSingle();
    expect(task.status, TaskLifecycle.archived.name);
  });
}

LongTermTaskDraft _simpleDraft(DateTime startsOn) {
  return LongTermTaskDraft(
    name: '英语听力',
    colorValue: 0xFF3D73E8,
    checkMode: LongTermCheckMode.simple,
    targetDays: 365,
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
    startsOn: startsOn,
    holidayPause: true,
  );
}
