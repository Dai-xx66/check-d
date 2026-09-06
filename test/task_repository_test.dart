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
    await repository.saveRecurringTask(_untimedDraft(day));
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
      TaskKind.recurring,
      TaskKind.oneTime,
    });
  });

  test('untimed completion toggles without deleting history', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveRecurringTask(_untimedDraft(day));

    await repository.toggleRecurringCompletion(taskId, day);
    expect((await repository.getTask(taskId, date: day))!.isCompleted, isTrue);

    await repository.toggleRecurringCompletion(taskId, day);
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
    await repository.saveRecurringTask(
      RecurringTaskDraft(
        name: '周一阅读',
        colorValue: 0xFF3D73E8,
        executionMode: RecurringExecutionMode.untimed,
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
    final taskId = await repository.saveRecurringTask(_untimedDraft(day));

    await repository.saveRecurringTask(
      RecurringTaskDraft(
        name: '英语精听',
        colorValue: 0xFF45A77A,
        executionMode: RecurringExecutionMode.untimed,
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
    final taskId = await repository.saveRecurringTask(_untimedDraft(day));

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
    final taskId = await repository.saveRecurringTask(_timerDraft(day));

    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 10));
    final timer = await repository.watchTimerState(taskId, day).first;

    expect(timer.isRunning, isTrue);
    expect(timer.elapsedSecondsAt(DateTime(2026, 9, 2, 10, 7)), 420);
  });

  test('reaching the duration target does not complete the task', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveRecurringTask(_timerDraft(day));

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

    await repository.toggleRecurringCompletion(taskId, day);

    expect((await repository.getTask(taskId, date: day))!.isCompleted, isTrue);
  });

  test('partial timer duration is retained as proportional progress', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveRecurringTask(_timerDraft(day));

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

  test('timed recurring task without a target records time only', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveRecurringTask(
      RecurringTaskDraft(
        name: '整理资料',
        colorValue: 0xFF3D73E8,
        executionMode: RecurringExecutionMode.timed,
        schedulePreset: SchedulePreset.daily,
        weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
        startsOn: day,
        holidayPause: false,
      ),
    );

    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 9));
    await repository.endTimer(taskId, now: DateTime(2026, 9, 2, 9, 12));

    final task = await repository.getTask(taskId, date: day);
    final completion = await database
        .select(database.taskCompletionRecords)
        .getSingle();
    expect(task!.hasDurationTarget, isFalse);
    expect(task.todayActualDurationSeconds, 720);
    expect(task.todayTargetReached, isFalse);
    expect(task.completionStatus, CompletionStatus.pending);
    expect(completion.progressPercent, 0);
    expect(completion.isSuccess, isFalse);
  });

  test('blank task names are rejected by the data layer', () async {
    final day = DateTime(2026, 9, 2);
    await expectLater(
      repository.saveRecurringTask(
        RecurringTaskDraft(
          name: '   ',
          colorValue: 0xFF3D73E8,
          executionMode: RecurringExecutionMode.untimed,
          schedulePreset: SchedulePreset.daily,
          weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
          startsOn: day,
          holidayPause: false,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: '   ',
          colorValue: 0xFF3D73E8,
          scheduledAt: day,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'timer crossing midnight remains on its logical occurrence day',
    () async {
      final firstDay = DateTime(2026, 9, 2);
      final taskId = await repository.saveRecurringTask(_timerDraft(firstDay));

      await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 23, 55));
      await repository.endTimer(taskId, now: DateTime(2026, 9, 3, 0, 10));

      final completions = await (database.select(
        database.taskCompletionRecords,
      )..orderBy([(row) => OrderingTerm.asc(row.localDate)])).get();
      expect(completions, hasLength(1));
      expect(completions[0].localDate, '2026-09-02');
      expect(completions[0].actualDurationSeconds, 900);
    },
  );

  test('invalid timer transitions are rejected', () async {
    final day = DateTime(2026, 9, 2);
    final taskId = await repository.saveRecurringTask(_timerDraft(day));

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

  test(
    'different tasks can run in parallel while one task stays unique',
    () async {
      final day = DateTime(2026, 9, 2);
      final firstId = await repository.saveRecurringTask(_timerDraft(day));
      final secondId = await repository.saveRecurringTask(
        RecurringTaskDraft(
          name: '运动',
          colorValue: 0xFF45A77A,
          executionMode: RecurringExecutionMode.timed,
          targetDurationSeconds: 1200,
          schedulePreset: SchedulePreset.daily,
          weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
          startsOn: day,
          holidayPause: false,
        ),
      );

      await repository.startTimer(firstId, now: DateTime(2026, 9, 2, 9));
      await repository.startTimer(secondId, now: DateTime(2026, 9, 2, 9, 1));

      var unfinished = await repository.getUnfinishedTimers();
      expect(unfinished, hasLength(2));
      expect(
        unfinished.where((timer) => timer.status == TimerSessionStatus.running),
        hasLength(2),
      );
      await expectLater(
        repository.startTimer(firstId, now: DateTime(2026, 9, 2, 9, 2)),
        throwsStateError,
      );

      await repository.pauseTimer(firstId, now: DateTime(2026, 9, 2, 9, 5));
      unfinished = await repository.getUnfinishedTimers();
      expect(
        unfinished.singleWhere((timer) => timer.taskId == firstId).status,
        TimerSessionStatus.paused,
      );
      expect(
        unfinished.singleWhere((timer) => timer.taskId == secondId).status,
        TimerSessionStatus.running,
      );

      await repository.endTimer(secondId, now: DateTime(2026, 9, 2, 9, 10));
      expect(await repository.getUnfinishedTimers(), hasLength(1));
      await repository.resumeTimer(firstId, now: DateTime(2026, 9, 2, 9, 12));
      await repository.endTimer(firstId, now: DateTime(2026, 9, 2, 9, 15));
      expect(await repository.getUnfinishedTimers(), isEmpty);
    },
  );

  test('archiving a running timer closes its active session', () async {
    final now = DateTime.now();
    final taskId = await repository.saveRecurringTask(
      _timerDraft(dateOnly(now)),
    );
    await repository.startTimer(
      taskId,
      now: now.subtract(const Duration(minutes: 2)),
    );

    await expectLater(
      () => repository.archiveTask(taskId),
      throwsA(isA<StateError>()),
    );
    await repository.archiveTask(taskId, endUnfinishedTimer: true);

    final session = await database
        .select(database.timerSessionRecords)
        .getSingle();
    expect(session.state, TimerSessionStatus.finished.name);
    expect(session.endedAt, isNotNull);
    expect(session.durationSeconds, greaterThanOrEqualTo(120));
  });

  test(
    'a recurring timer crossing midnight belongs to its start date',
    () async {
      final taskId = await repository.saveRecurringTask(
        _timerDraft(DateTime(2026, 9, 2)),
      );

      await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 23, 50));
      await repository.endTimer(taskId, now: DateTime(2026, 9, 3, 0, 20));

      final startedDay = await repository.getTask(
        taskId,
        date: DateTime(2026, 9, 2),
      );
      final nextDay = await repository.getTask(
        taskId,
        date: DateTime(2026, 9, 3),
      );
      expect(startedDay!.todayActualDurationSeconds, 30 * 60);
      expect(nextDay!.todayActualDurationSeconds, 0);

      final completions = await database
          .select(database.taskCompletionRecords)
          .get();
      expect(completions.map((item) => item.localDate), [
        localDateKey(DateTime(2026, 9, 2)),
      ]);
    },
  );

  test('calendar month combines partial timers and completed tasks', () async {
    final day = DateTime(2026, 9, 2);
    final simpleId = await repository.saveRecurringTask(_untimedDraft(day));
    final timerId = await repository.saveRecurringTask(_timerDraft(day));
    final reminderId = await repository.saveOneTimeReminder(
      OneTimeReminderDraft(
        name: '项目会议',
        colorValue: 0xFFE69545,
        scheduledAt: DateTime(2026, 9, 2, 14),
      ),
    );
    await repository.toggleRecurringCompletion(simpleId, day);
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

  test(
    'timed task without a target records time and requires manual completion',
    () async {
      final day = DateTime(2026, 9, 2);
      final taskId = await repository.saveRecurringTask(
        RecurringTaskDraft(
          name: '写作业',
          colorValue: 0xFF3D73E8,
          executionMode: RecurringExecutionMode.timed,
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

      await repository.toggleRecurringCompletion(taskId, day);
      expect(
        (await repository.getTask(taskId, date: day))!.isCompleted,
        isTrue,
      );
    },
  );

  test(
    'timed one-time reminder shares timer without auto completion',
    () async {
      final day = DateTime(2026, 9, 2);
      final taskId = await repository.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: '完成数据库作业',
          colorValue: 0xFFE69545,
          scheduledAt: DateTime(2026, 9, 2, 20),
          executionMode: OneTimeExecutionMode.timed,
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
    await repository.saveRecurringTask(
      RecurringTaskDraft(
        name: '周一阅读',
        colorValue: 0xFF3D73E8,
        executionMode: RecurringExecutionMode.untimed,
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
        executionMode: OneTimeExecutionMode.timed,
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
    final taskId = await repository.saveRecurringTask(_timerDraft(day));
    await repository.toggleRecurringCompletion(taskId, day);
    await repository.startTimer(taskId, now: DateTime(2026, 9, 2, 10));
    await repository.endTimer(taskId, now: DateTime(2026, 9, 2, 10, 20));
    expect((await repository.getTask(taskId, date: day))!.isCompleted, isTrue);
    await repository.toggleRecurringCompletion(taskId, day);
    final task = await repository.getTask(taskId, date: day);
    expect(task!.isCompleted, isFalse);
    expect(task.todayTargetReached, isTrue);
    expect(task.todayActualDurationSeconds, 1200);
  });

  test('calendar retains an archived task on its historical dates', () async {
    final today = dateOnly(DateTime.now());
    final taskId = await repository.saveRecurringTask(_untimedDraft(today));
    await repository.toggleRecurringCompletion(taskId, today);
    await repository.archiveTask(taskId);

    final month = await repository.watchCalendarMonth(today).first;

    expect(month.day(today).tasks.single.id, taskId);
    expect(month.day(today).tasks.single.isCompleted, isTrue);
  });
}

RecurringTaskDraft _untimedDraft(DateTime startsOn) {
  return RecurringTaskDraft(
    name: '英语听力',
    colorValue: 0xFF3D73E8,
    executionMode: RecurringExecutionMode.untimed,
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

RecurringTaskDraft _timerDraft(DateTime startsOn) {
  return RecurringTaskDraft(
    name: '英语听力',
    colorValue: 0xFF3D73E8,
    executionMode: RecurringExecutionMode.timed,
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
