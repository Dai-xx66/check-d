import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/drift.dart' hide isNotNull;
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

  test('running timer derives elapsed time from its start timestamp', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_timerDraft(day));

    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 10));
    final timer = await repository.watchTimerState(taskId, day).first;

    expect(timer.isRunning, isTrue);
    expect(timer.elapsedSecondsAt(DateTime(2026, 9, 2, 10, 7)), 420);
  });

  test('reaching the duration target does not complete the task', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_timerDraft(day));

    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 10));
    await repository.pauseTimer(taskId, now: DateTime(2026, 9, 2, 10, 4));
    expect(
      (await repository.watchTimerState(taskId, day).first).isPaused,
      isTrue,
    );
    await repository.resumeTimer(taskId, now: DateTime(2026, 9, 2, 10, 10));
    await repository.endTimer(taskId, now: DateTime(2026, 9, 2, 10, 16));

    final timer = await repository.watchTimerState(taskId, day).first;
    final completion = await database
        .select(database.taskCompletionRecords)
        .getSingle();
    expect(timer.canStart, isTrue);
    expect(timer.sessions, hasLength(2));
    expect(timer.elapsedSecondsAt(DateTime(2026, 9, 2, 11)), 600);
    expect(completion.actualDurationSeconds, 600);
    expect(completion.progressPercent, 100);
    expect(completion.targetReached, isTrue);
    expect(completion.isSuccess, isFalse);
    expect((await repository.getTask(taskId, date: day))!.isCompleted, isFalse);

    await repository.toggleLongTermCompletion(taskId, day);

    expect((await repository.getTask(taskId, date: day))!.isCompleted, isTrue);
  });

  test('partial timer duration is retained as proportional progress', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_timerDraft(day));

    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 8));
    await repository.endTimer(taskId, now: DateTime(2026, 9, 2, 8, 5));

    final completion = await database
        .select(database.taskCompletionRecords)
        .getSingle();
    expect(completion.actualDurationSeconds, 300);
    expect(completion.progressPercent, 50);
    expect(completion.targetReached, isFalse);
    expect(completion.isSuccess, isFalse);
  });

  test('timer crossing midnight is aggregated into both local days', () async {
    final firstDay = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_timerDraft(firstDay));

    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 23, 55));
    await repository.endTimer(taskId, now: DateTime(2026, 9, 3, 0, 10));

    final completions = await (database.select(
      database.taskCompletionRecords,
    )..orderBy([(row) => OrderingTerm.asc(row.localDate)])).get();
    expect(completions, hasLength(2));
    expect(completions[0].localDate, '2026-09-02');
    expect(completions[0].actualDurationSeconds, 300);
    expect(completions[1].localDate, '2026-09-03');
    expect(completions[1].actualDurationSeconds, 600);
  });

  test('invalid timer transitions are rejected', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_timerDraft(day));

    await expectLater(
      repository.pauseTimer(taskId, now: day),
      throwsStateError,
    );
    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 9));
    await expectLater(
      repository.startTimer(taskId, now: DateTime(2026, 9, 2, 9, 1)),
      throwsStateError,
    );
  });

  test('only one timer can run for the same user', () async {
    final day = DateTime(2026, 9, 2);
    final firstId = await repository.saveLongTermTask(_timerDraft(day));
    final secondId = await repository.saveLongTermTask(
      LongTermTaskDraft(
        name: '运动',
        colorValue: 0xFF45A77A,
        checkMode: LongTermCheckMode.targetTimer,
        targetDurationSeconds: 1200,
        schedulePreset: SchedulePreset.daily,
        weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
        startsOn: day,
        holidayPause: false,
      ),
    );

    await repository.startTimer(firstId, now: DateTime(2026, 9, 2, 9));

    await expectLater(
      repository.startTimer(secondId, now: DateTime(2026, 9, 2, 9, 1)),
      throwsStateError,
    );
  });

  test('archiving a running timer closes its active session', () async {
    final now = DateTime.now();
    final taskId = await repository.saveLongTermTask(
      _timerDraft(dateOnly(now)),
    );
    await repository.startTimer(
      taskId,
      now: now.subtract(const Duration(minutes: 2)),
    );

    await repository.archiveTask(taskId);

    final session = await database
        .select(database.timerSessionRecords)
        .getSingle();
    expect(session.state, TimerSessionStatus.finished.name);
    expect(session.endedAt, isNotNull);
    expect(session.durationSeconds, greaterThanOrEqualTo(120));
  });

  test('calendar month combines partial timers and completed tasks', () async {
    final day = DateTime(2026, 9, 2);
    final simpleId = await repository.saveLongTermTask(_simpleDraft(day));
    final timerId = await repository.saveLongTermTask(_timerDraft(day));
    final reminderId = await repository.saveOneTimeReminder(
      OneTimeReminderDraft(
        name: '项目会议',
        colorValue: 0xFFE69545,
        scheduledAt: DateTime(2026, 9, 2, 14),
      ),
    );
    await repository.toggleSimpleCompletion(simpleId, day);
    await repository.startTimer(timerId, now: DateTime(2026, 9, 2, 8));
    await repository.endTimer(timerId, now: DateTime(2026, 9, 2, 8, 5));
    await repository.toggleOneTimeCompletion(reminderId);

    final month = await repository.watchCalendarMonth(day).first;
    final details = month.day(day);

    expect(details.scheduledCount, 3);
    expect(details.completedCount, 2);
    expect(details.timedSeconds, 300);
    expect(details.completionPercent, closeTo(66.67, 0.01));
  });

  test('free timer records time and requires manual completion', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(
      LongTermTaskDraft(
        name: '写作业',
        colorValue: 0xFF3D73E8,
        checkMode: LongTermCheckMode.freeTimer,
        schedulePreset: SchedulePreset.daily,
        weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
        startsOn: day,
        holidayPause: false,
      ),
    );

    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 18));
    await repository.endTimer(taskId, now: DateTime(2026, 9, 2, 18, 40));

    final completion = await database
        .select(database.taskCompletionRecords)
        .getSingle();
    expect(completion.actualDurationSeconds, 2400);
    expect(completion.targetReached, isFalse);
    expect(completion.isSuccess, isFalse);

    await repository.toggleLongTermCompletion(taskId, day);
    expect((await repository.getTask(taskId, date: day))!.isCompleted, isTrue);
  });

  test(
    'timed one-time reminder shares timer without auto completion',
    () async {
      final day = DateTime(2026, 9, 2);
      final taskId = await repository.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: '完成数据库作业',
          colorValue: 0xFFE69545,
          scheduledAt: DateTime(2026, 9, 2, 20),
          executionMode: OneTimeExecutionMode.timer,
        ),
      );

      await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 18));
      await repository.pauseTimer(taskId, now: DateTime(2026, 9, 2, 18, 40));
      await repository.resumeTimer(taskId, now: DateTime(2026, 9, 2, 19));
      await repository.endTimer(taskId, now: DateTime(2026, 9, 2, 19, 50));

      final task = await repository.getTask(taskId, date: day);
      expect(task!.hasTimer, isTrue);
      expect(task.todayActualDurationSeconds, 5400);
      expect(task.isCompleted, isFalse);
      expect(
        await database.select(database.taskCompletionRecords).get(),
        isEmpty,
      );

      await repository.toggleOneTimeCompletion(taskId);
      expect((await repository.getTask(taskId))!.isCompleted, isTrue);
    },
  );

  test('calendar excludes non-scheduled weekdays', () async {
    final monday = DateTime(2026, 8, 3);
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

    final month = await repository.watchCalendarMonth(monday).first;

    expect(month.day(monday).scheduledCount, 1);
    expect(month.day(DateTime(2026, 8, 4)).scheduledCount, 0);
  });

  test('time on a future reminder counts on the day it was spent', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveOneTimeReminder(
      OneTimeReminderDraft(
        name: '未来事项',
        colorValue: 0xFF3D73E8,
        scheduledAt: DateTime(2026, 9, 5),
        executionMode: OneTimeExecutionMode.timer,
      ),
    );
    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 10));
    await repository.endTimer(taskId, now: DateTime(2026, 9, 2, 10, 15));
    final month = await repository.watchCalendarMonth(day).first;
    expect(month.day(day).scheduledCount, 0);
    expect(month.day(day).timedSeconds, 900);
    expect(month.day(day).completedCount, 0);
    final timer = await repository.watchTimerState(null, day).first;
    expect(timer.elapsedSecondsAt(DateTime(2026, 9, 2, 11)), 900);
  });

  test('further timer sessions preserve manual completion and undo', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveLongTermTask(_timerDraft(day));
    await repository.toggleLongTermCompletion(taskId, day);
    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 10));
    await repository.endTimer(taskId, now: DateTime(2026, 9, 2, 10, 20));
    expect((await repository.getTask(taskId, date: day))!.isCompleted, isTrue);
    await repository.toggleLongTermCompletion(taskId, day);
    final task = await repository.getTask(taskId, date: day);
    expect(task!.isCompleted, isFalse);
    expect(task.todayTargetReached, isTrue);
    expect(task.todayActualDurationSeconds, 1200);
  });

  test('calendar retains an archived task on its historical dates', () async {
    final today = dateOnly(DateTime.now());
    final taskId = await repository.saveLongTermTask(_simpleDraft(today));
    await repository.toggleSimpleCompletion(taskId, today);
    await repository.archiveTask(taskId);

    final month = await repository.watchCalendarMonth(today).first;

    expect(month.day(today).tasks.single.id, taskId);
    expect(month.day(today).tasks.single.isCompleted, isTrue);
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

LongTermTaskDraft _timerDraft(DateTime startsOn) {
  return LongTermTaskDraft(
    name: '英语听力',
    colorValue: 0xFF3D73E8,
    checkMode: LongTermCheckMode.targetTimer,
    targetDurationSeconds: 600,
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
