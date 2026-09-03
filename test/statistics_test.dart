import 'dart:convert';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/statistics/data/statistics_repository.dart';
import 'package:check_d/features/statistics/domain/statistics_models.dart';
import 'package:check_d/features/tags/data/tag_repository.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late TagRepository tags;
  late StatisticsRepository stats;
  final today = dateOnly(DateTime.now());
  final morning = DateTime(today.year, today.month, today.day, 8);

  RecurringTaskDraft draft({
    String? tagId,
    Set<int>? weekdays,
    DateTime? startsOn,
  }) => RecurringTaskDraft(
    name: '阅读',
    colorValue: 0xFF3D73E8,
    tagId: tagId,
    executionMode: RecurringExecutionMode.timed,
    targetDurationSeconds: 600,
    schedulePreset: SchedulePreset.custom,
    weekdays: weekdays ?? WeekdayMask.toDays(127),
    startsOn: startsOn ?? today,
    holidayPause: false,
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final queue = SyncQueueService(db);
    tasks = TaskRepository(database: db, syncQueue: queue, userId: 'a');
    tags = TagRepository(db, 'a', queue);
    stats = StatisticsRepository(db, 'a');
  });
  tearDown(() => db.close());

  test('defaults are idempotent and owner scoped', () async {
    await tags.ensureDefaults();
    await tags.ensureDefaults();
    final other = TagRepository(db, 'b', SyncQueueService(db));
    await other.ensureDefaults();
    expect(await tags.watchTags().first, hasLength(7));
    expect(await other.watchTags().first, hasLength(7));
    expect(await db.select(db.tagRevisionRecords).get(), hasLength(14));
  });

  test(
    'tag edits and archive retain history and reject duplicate names',
    () async {
      final id = await tags.save(name: '编程', colorValue: 1);
      await tags.save(id: id, name: '代码', colorValue: 2);
      await tags.setArchived(id, true);
      expect(await db.select(db.tagRevisionRecords).get(), hasLength(3));
      await expectLater(
        tags.save(name: '代码', colorValue: 3),
        throwsArgumentError,
      );
      await tags.setArchived(id, false);
      expect((await db.select(db.tagRecords).getSingle()).archived, false);
    },
  );

  test('cannot use or change another owners tag', () async {
    final other = TagRepository(db, 'b', SyncQueueService(db));
    final id = await other.save(name: '私有', colorValue: 1);
    await expectLater(
      tasks.saveRecurringTask(draft(tagId: id)),
      throwsArgumentError,
    );
    await expectLater(tags.setArchived(id, true), throwsStateError);
    await expectLater(
      tags.save(id: id, name: '更改', colorValue: 2),
      throwsStateError,
    );
    expect((await stats.load()).tags, isEmpty);
  });

  test(
    'tag snapshot survives edits and unfinished task contributes time only',
    () async {
      final a = await tags.save(name: '学习', colorValue: 1);
      final b = await tags.save(name: '工作', colorValue: 2);
      final id = await tasks.saveRecurringTask(draft(tagId: a));
      await tasks.startTimer(id, now: morning);
      await tasks.pauseTimer(id, now: morning.add(const Duration(minutes: 10)));
      await tasks.saveRecurringTask(draft(tagId: b), taskId: id);
      await tasks.resumeTimer(
        id,
        now: morning.add(const Duration(minutes: 20)),
      );
      await tasks.endTimer(id, now: morning.add(const Duration(minutes: 25)));
      await tags.setArchived(a, true);
      final data = await stats.load();
      final report = data.report(
        StatisticsPeriod.day,
        today,
        morning.add(const Duration(hours: 1)),
      );
      expect(report.secondsForTag(a), 600);
      expect(report.secondsForTag(b), 300);
      expect(report.completed, 0);
      expect(report.targetReached, 1);
      expect(report.tasks.single.expected, 1);
      final payloads = await (db.select(
        db.syncOperations,
      )..where((r) => r.entityType.equals('timer_sessions'))).get();
      expect((jsonDecode(payloads.first.payloadJson) as Map)['tag_id'], a);
      expect((jsonDecode(payloads.last.payloadJson) as Map)['tag_id'], b);
    },
  );

  test(
    'future reminder time belongs to actual day without long-term completion',
    () async {
      final id = await tasks.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: '作业',
          colorValue: 1,
          scheduledAt: today.add(const Duration(days: 3)),
          executionMode: OneTimeExecutionMode.timed,
        ),
      );
      await tasks.startTimer(id, now: morning);
      await tasks.endTimer(id, now: morning.add(const Duration(minutes: 20)));
      final report = (await stats.load()).report(
        StatisticsPeriod.day,
        today,
        morning.add(const Duration(hours: 1)),
      );
      expect(report.secondsForTag(null), 1200);
      expect(report.expected, 0);
      expect(report.completed, 0);
      expect(report.remindersCompleted, 0);
    },
  );

  test(
    'cross midnight splits precisely and archived task keeps timing history',
    () async {
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final id = await tasks.saveRecurringTask(draft(startsOn: yesterday));
      final start = DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
        23,
        50,
      );
      await tasks.startTimer(id, now: start);
      await tasks.endTimer(id, now: start.add(const Duration(minutes: 30)));
      await tasks.archiveTask(id);
      final data = await stats.load();
      expect(
        data.report(StatisticsPeriod.day, yesterday, morning).seconds,
        600,
      );
      expect(data.report(StatisticsPeriod.day, today, morning).seconds, 1200);
      expect(data.tasks, hasLength(1));
    },
  );

  test(
    'exclusions and non-execution days are excluded from denominator',
    () async {
      final id = await tasks.saveRecurringTask(
        draft(startsOn: DateTime(2026, 8, 1), weekdays: {1}),
      );
      await tasks.toggleRecurringCompletion(id, DateTime(2026, 8, 3));
      await (db.update(
        db.taskCompletionRecords,
      )..where((r) => r.taskId.equals(id))).write(
        const TaskCompletionRecordsCompanion(exclusionReason: Value('holiday')),
      );
      final report = (await stats.load()).report(
        StatisticsPeriod.month,
        DateTime(2026, 8),
        morning,
      );
      expect(report.expected, 4);
      expect(report.completed, 0);
    },
  );

  test('schedule edits do not rewrite earlier execution dates', () async {
    final id = await tasks.saveRecurringTask(
      draft(startsOn: DateTime(2026, 8, 1), weekdays: {1}),
    );
    final first = await db.select(db.taskRevisionRecords).getSingle();
    await (db.update(
      db.taskRevisionRecords,
    )..where((r) => r.id.equals(first.id))).write(
      TaskRevisionRecordsCompanion(
        changedAt: Value(DateTime(2026, 8, 1).toUtc()),
      ),
    );
    await tasks.saveRecurringTask(
      draft(startsOn: DateTime(2026, 8, 1), weekdays: {2}),
      taskId: id,
    );
    await (db.update(
      db.taskRevisionRecords,
    )..where((r) => r.id.equals(first.id).not())).write(
      TaskRevisionRecordsCompanion(
        changedAt: Value(DateTime(2026, 8, 18).toUtc()),
      ),
    );
    final data = await stats.load();
    final august = data.tasks.single.days
        .where((d) => d.date.month == 8)
        .map((d) => d.date.day)
        .toList();
    expect(august, [3, 10, 17, 18, 25]);
    final calendar = await tasks.watchCalendarMonth(DateTime(2026, 8)).first;
    expect(
      calendar.days.values
          .where((day) => day.scheduledCount > 0)
          .map((day) => day.date.day),
      august,
    );
  });

  test('running session uses wall clock and resumes without idle gap', () {
    final entry = TimeEntry(
      taskId: 'a',
      tagId: null,
      start: morning,
      end: null,
      durationSeconds: 0,
      running: true,
    );
    expect(
      entry.secondsBetween(
        today,
        today.add(const Duration(days: 1)),
        morning.add(const Duration(minutes: 5)),
      ),
      300,
    );
    final closed = TimeEntry(
      taskId: 'a',
      tagId: null,
      start: morning,
      end: morning.add(const Duration(minutes: 5)),
      durationSeconds: 300,
      running: false,
    );
    expect(
      closed.secondsBetween(
        today,
        today.add(const Duration(days: 1)),
        morning.add(const Duration(hours: 2)),
      ),
      300,
    );
  });

  test(
    'streak skips non-execution days and does not fail unfinished today',
    () {
      final task = StatisticsTask(
        id: 'a',
        name: 'a',
        iconName: 'target',
        colorValue: 1,
        days: [
          ExecutionDay(
            date: DateTime(2026, 8, 28),
            success: true,
            targetSeconds: null,
            storedTargetReached: false,
          ),
          ExecutionDay(
            date: DateTime(2026, 8, 31),
            success: true,
            targetSeconds: null,
            storedTargetReached: false,
          ),
          ExecutionDay(
            date: DateTime(2026, 9, 2),
            success: false,
            targetSeconds: null,
            storedTargetReached: false,
          ),
        ],
      );
      final data = StatisticsData(
        tags: [],
        sessions: [],
        tasks: [task],
        reminderCompletions: [],
      );
      final report = data.report(
        StatisticsPeriod.year,
        DateTime(2026),
        DateTime(2026, 9, 2, 18),
      );
      expect(report.tasks.single.currentStreak, 2);
      expect(report.tasks.single.longestStreak, 2);
      expect(report.rate, closeTo(2 / 3, 0.0001));
      expect(
        data
            .report(StatisticsPeriod.year, DateTime(2026), DateTime(2026, 9, 3))
            .tasks
            .single
            .currentStreak,
        0,
      );
    },
  );

  test('week starts Monday; leap month and year buckets cover boundaries', () {
    final week = StatisticsRange(StatisticsPeriod.week, DateTime(2026, 9, 2));
    expect(week.start, DateTime(2026, 8, 31));
    const data = StatisticsData(
      tags: [],
      sessions: [],
      tasks: [],
      reminderCompletions: [],
    );
    expect(
      data
          .report(StatisticsPeriod.month, DateTime(2024, 2), DateTime(2026))
          .buckets
          .length,
      29,
    );
    expect(
      data
          .report(StatisticsPeriod.year, DateTime(2026), DateTime(2026))
          .buckets
          .length,
      12,
    );
    expect(
      data.report(StatisticsPeriod.week, DateTime(2026), DateTime(2026)).rate,
      0,
    );
  });
}
