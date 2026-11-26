import 'dart:async';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/holiday/holiday_calendar.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/planning/data/task_occurrence_snapshot.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = 'aaaaaaaa-1111-4111-8111-111111111111';
const _other = 'bbbbbbbb-2222-4222-8222-222222222222';
const _first = '2026-11-24';
const _last = '2026-12-24';
// Past midnight in Shanghai, while the UTC date is still Nov 23.
final _clock = DateTime.utc(2026, 11, 23, 16, 5);

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.database.close());

  test('Shanghai window includes today and day 30, with stable rows', () async {
    final second = _Fixture();
    addTearDown(second.database.close);
    await fixture.addTask('b', from: _first, through: _first);
    await fixture.addTask('a', from: _first, through: _last);
    await second.addTask('a', from: _first, through: _last);
    await second.addTask('b', from: _first, through: _first);

    for (final candidate in [fixture, second]) {
      await candidate.addOverride('b', localDate: _first, start: 540, end: 555);
      await candidate.addOverride('a', localDate: _first, start: 540, end: 560);
      await candidate.addOverride(
        'a',
        localDate: _last,
        start: 1430,
        end: 1440,
      );
      for (var offset = 1; offset < 30; offset++) {
        final date = DateTime.utc(2026, 11, 24 + offset);
        await candidate.addOverride(
          'a',
          localDate: localDateKey(date),
          action: DayOverrideAction.skip,
        );
      }
    }

    final result = await fixture.build();
    final otherDevice = await second.build(
      clock: () => _clock.add(const Duration(hours: 8)),
    );
    expect(result.fromDate, _first);
    expect(result.throughDate, _last);
    expect(result.deviceId, isNot(otherDevice.deviceId));
    expect(result.generatedAt, isNot(otherDevice.generatedAt));
    expect(result.occurrences, otherDevice.occurrences);
    expect(result.hasRecurringTasks, isTrue);
    expect(result.omissions, {
      TaskOccurrenceOmissionReason.skippedByOverride: 29,
    });
    expect(result.taskDataVersion, otherDevice.taskDataVersion);
    expect(result.taskDataVersion, matches(r'^sha256:[a-f0-9]{64}$'));
    expect(result.toJson(), {
      'from_date': _first,
      'through_date': _last,
      'timezone': 'Asia/Shanghai',
      'generated_at': _clock.toIso8601String(),
      'builder_version': 'checkd_flutter_task_occurrence_v1',
      'task_data_version': result.taskDataVersion,
      'device_id': result.deviceId,
      'local_generation': 0,
      'occurrences': [
        _occurrence('a', _first, 540, 560),
        _occurrence('b', _first, 540, 555),
        _occurrence('a', _last, 1430, 1440),
      ],
    });
  });

  test(
    'daily rule emits each explicitly timed date in its inclusive range',
    () async {
      const expectedDates = ['2026-11-25', '2026-11-26', '2026-11-27'];
      await fixture.addTask(
        'daily',
        from: expectedDates.first,
        through: expectedDates.last,
      );
      for (final date in ['2026-11-24', ...expectedDates, '2026-11-28']) {
        await fixture.addOverride(
          'daily',
          localDate: date,
          start: 540,
          end: 600,
        );
      }

      final result = await fixture.build();
      expect(result.hasRecurringTasks, isTrue);
      expect(result.omissions, isEmpty);
      expect(result.occurrences, [
        for (final date in expectedDates) _occurrence('daily', date, 540, 600),
      ]);
    },
  );

  test(
    'uses date-specific overrides and skips only unsupported instances',
    () async {
      await fixture.addTask(
        'read',
        from: _first,
        through: '2026-11-28',
        fixedStart: 540,
        goalSeconds: 2700,
      );
      await fixture.addOverride(
        'read',
        localDate: _first,
        start: 570,
        end: 630,
      );
      await fixture.addOverride(
        'read',
        localDate: '2026-11-25',
        action: DayOverrideAction.skip,
      );
      await fixture.addOverride('read', localDate: '2026-11-27', start: 600);
      await fixture.addOverride(
        'read',
        localDate: '2026-11-28',
        start: 630,
        end: 645,
      );
      await fixture.addOverride(
        'read',
        localDate: '2026-11-29',
        action: DayOverrideAction.skip,
      );

      final result = await fixture.build();
      expect(result.occurrences, [
        _occurrence('read', _first, 570, 630),
        _occurrence('read', '2026-11-28', 630, 645),
      ]);
      expect(result.omissions, {
        TaskOccurrenceOmissionReason.skippedByOverride: 1,
        TaskOccurrenceOmissionReason.missingPlannedEnd: 2,
      });
      expect(result.toJson(), isNot(contains('omissions')));
    },
  );

  test(
    'completion and exclusion apply only to the owner and local date',
    () async {
      const days = [_first, '2026-11-25', '2026-11-26', '2026-11-27'];
      await fixture.addTask('plan', from: days.first, through: days.last);
      for (final date in days) {
        await fixture.addOverride(
          'plan',
          localDate: date,
          start: 540,
          end: 600,
        );
      }
      final before = await fixture.build();
      await fixture.addCompletion('plan', date: days[0], completed: true);
      await fixture.addCompletion('plan', date: days[1], targetReached: true);
      await fixture.addCompletion(
        'plan',
        date: days[2],
        exclusionReason: 'skip',
      );
      await fixture.addCompletion(
        'plan',
        date: days[3],
        owner: _other,
        completed: true,
      );

      final result = await fixture.build();
      expect(result.occurrences, [
        // Timer-derived target progress is independent of explicit completion.
        _occurrence('plan', days[1], 540, 600),
        _occurrence('plan', days[3], 540, 600),
      ]);
      expect(result.omissions, {
        TaskOccurrenceOmissionReason.completed: 1,
        TaskOccurrenceOmissionReason.excluded: 1,
      });
      expect(result.taskDataVersion, isNot(before.taskDataVersion));
      final completion = fixture.database.taskCompletionRecords;
      await (fixture.database.update(completion)..where(
            (row) => row.taskId.equals('plan') & row.localDate.equals(days[0]),
          ))
          .write(
            const TaskCompletionRecordsCompanion(
              isSuccess: Value(false),
              completedAt: Value(null),
            ),
          );
      final undone = await fixture.build();
      expect(undone.occurrences.first, _occurrence('plan', days[0], 540, 600));
      expect(undone.taskDataVersion, isNot(result.taskDataVersion));
    },
  );

  test('reuses adjusted workdays and holiday pause before timing', () async {
    const madeUpWorkday = '2026-11-28'; // Saturday.
    const statutoryHoliday = '2026-11-29';
    await fixture.addTask(
      'weekday',
      from: madeUpWorkday,
      through: statutoryHoliday,
      preset: SchedulePreset.weekdays,
      mask: WeekdayMask.weekdays,
    );
    await fixture.addTask(
      'holiday-paused',
      from: statutoryHoliday,
      through: statutoryHoliday,
      holidayPause: true,
    );
    await fixture.addOverride(
      'weekday',
      localDate: madeUpWorkday,
      start: 630,
      end: 680,
    );
    final holidays = _HolidayCalendar(
      (date) => switch (localDateKey(date)) {
        madeUpWorkday => ChinaDayKind.adjustedWorkday,
        statutoryHoliday => ChinaDayKind.holiday,
        _ => ChinaDayKind.unknown,
      },
    );

    final result = await fixture.build(holidays: holidays);
    expect(result.occurrences, [
      _occurrence('weekday', madeUpWorkday, 630, 680),
    ]);
  });

  test(
    'rule version tracks rule edits independent of the rolling window',
    () async {
      await fixture.addTask('plan', from: _first, through: _first);
      await fixture.addOverride(
        'plan',
        localDate: _first,
        start: 540,
        end: 630,
      );
      final before = await fixture.build();
      final nextDay = await fixture.build(
        clock: () => _clock.add(const Duration(days: 1)),
      );
      expect(nextDay.occurrences, isEmpty);
      expect(nextDay.taskDataVersion, before.taskDataVersion);

      await (fixture.database.update(fixture.database.longTermTaskRecords)
            ..where((row) => row.taskId.equals('plan')))
          .write(const LongTermTaskRecordsCompanion(holidayPause: Value(true)));
      final edited = await fixture.build();
      expect(edited.occurrences, before.occurrences);
      expect(edited.taskDataVersion, isNot(before.taskDataVersion));
    },
  );

  test('filters out foreign, inactive, deleted, and one-time data', () async {
    await fixture.addTask('current', from: _first, through: _first);
    await fixture.addTask('foreign', owner: _other);
    await fixture.addTask('gone', status: TaskLifecycle.archived);
    await fixture.addTask('paused', status: TaskLifecycle.paused);
    await fixture.addTask('deleted', deleted: true);
    await fixture.addTask('single', kind: TaskKind.oneTime);

    await fixture.addOverride(
      'current',
      localDate: _first,
      start: 540,
      end: 630,
    );
    await fixture.addOverride(
      'current',
      localDate: _first,
      action: DayOverrideAction.skip,
      owner: _other,
    );
    await fixture.addOverride(
      'current',
      localDate: _first,
      action: DayOverrideAction.skip,
      type: DayItemType.oneTime,
    );

    final result = await fixture.build();
    expect(result.occurrences, [_occurrence('current', _first, 540, 630)]);
  });

  test(
    'active recurring items lacking a planned range yield an empty snapshot',
    () async {
      await fixture.addTask(
        'timed',
        from: _first,
        through: _first,
        fixedStart: 540,
        goalSeconds: 2700,
      );
      await fixture.addOverride(
        'timed',
        localDate: _first,
        start: 580,
        end: 590,
        deleted: true,
      );
      await fixture.addTask('free', from: _first, through: _first);
      await fixture.addTask('missing-start', from: _first, through: _first);
      await fixture.addOverride('missing-start', localDate: _first, end: 1440);

      final result = await fixture.build();
      expect(result.hasRecurringTasks, isTrue);
      expect(result.occurrences, isEmpty);
      expect(result.omissions, {
        TaskOccurrenceOmissionReason.missingPlannedStart: 1,
        TaskOccurrenceOmissionReason.missingPlannedEnd: 1,
        TaskOccurrenceOmissionReason.missingPlannedStartAndEnd: 1,
      });
    },
  );

  test('rejects malformed minutes and foreign required rule', () async {
    await fixture.addTask('plan', from: _first, through: _first);
    await fixture.addOverride('plan', localDate: _first, start: -1, end: 60);
    await expectLater(
      fixture.build(),
      throwsA(_snapshotFailure('invalid_occurrence_time')),
    );

    await (fixture.database.update(fixture.database.taskScheduleRecords)
          ..where((row) => row.taskId.equals('plan')))
        .write(const TaskScheduleRecordsCompanion(userId: Value(_other)));
    await expectLater(
      fixture.build(),
      throwsA(_snapshotFailure('incomplete_recurring_rule')),
    );
  });

  test(
    'rejects a checkpoint that becomes unsettled during generation',
    () async {
      await fixture.addTask('plan', from: _first, through: _first);
      await fixture.addOverride(
        'plan',
        localDate: _first,
        start: 540,
        end: 600,
      );
      var changed = false;
      final holidays = _HolidayCalendar((date) async {
        if (!changed) {
          changed = true;
          await fixture.queue.enqueue(
            entityType: 'tasks',
            entityId: 'plan',
            operation: SyncOperationType.upsert,
            payload: const {},
            userId: _owner,
          );
        }
        return ChinaDayKind.unknown;
      });

      await expectLater(
        fixture.build(holidays: holidays),
        throwsA(_snapshotFailure('checkpoint_changed')),
      );
    },
  );

  test(
    'distinguishes an empty account from active recurring items without rows',
    () async {
      final result = await fixture.build();
      expect(result.occurrences, isEmpty);
      expect(result.hasRecurringTasks, isFalse);
      expect(result.omissions, isEmpty);
      expect(result.fromDate, _first);
      expect(result.throughDate, _last);
    },
  );
}

Matcher _snapshotFailure(String code) => isA<TaskOccurrenceSnapshotException>()
    .having((error) => error.code, 'code', code);

Map<String, Object?> _occurrence(
  String task,
  String date,
  int start,
  int end,
) => {
  'task_id': task,
  'occurrence_id': 'task:$task:$date',
  'local_date': date,
  'timezone': 'Asia/Shanghai',
  'start_minute': start,
  'end_minute': end,
};

class _Fixture {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  late final queue = SyncQueueService(database);

  Future<TaskOccurrenceSnapshot> build({
    DateTime Function()? clock,
    HolidayCalendar? holidays,
  }) async {
    await queue.ensureDeviceState(_owner);
    final checkpoint = (await queue.settledCheckpoint(_owner))!;
    return DriftTaskOccurrenceSnapshotRepository(
      database: database,
      syncQueue: queue,
      holidayCalendar:
          holidays ?? _HolidayCalendar((_) => ChinaDayKind.unknown),
      clock: clock ?? () => _clock,
    ).build(checkpoint);
  }

  Future<void> addTask(
    String id, {
    String owner = _owner,
    String from = _first,
    String through = _last,
    TaskLifecycle status = TaskLifecycle.active,
    TaskKind kind = TaskKind.recurring,
    SchedulePreset preset = SchedulePreset.daily,
    int mask = WeekdayMask.everyDay,
    bool holidayPause = false,
    bool deleted = false,
    int? fixedStart,
    int? goalSeconds,
  }) async {
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: id,
            userId: Value(owner),
            name: 'Task $id',
            taskType: kind.name,
            status: Value(status.name),
            colorValue: 0,
            createdAt: _clock,
            updatedAt: _clock,
            deletedAt: Value(deleted ? _clock : null),
          ),
        );
    if (kind == TaskKind.oneTime) return;
    await database
        .into(database.longTermTaskRecords)
        .insert(
          LongTermTaskRecordsCompanion.insert(
            taskId: id,
            userId: owner,
            checkMode: RecurringExecutionMode.timed.name,
            scheduledMinuteOfDay: Value(fixedStart),
            targetDurationSeconds: Value(goalSeconds),
            holidayPause: Value(holidayPause),
            createdAt: _clock,
            updatedAt: _clock,
          ),
        );
    await database
        .into(database.taskScheduleRecords)
        .insert(
          TaskScheduleRecordsCompanion.insert(
            id: id,
            taskId: id,
            userId: owner,
            scheduleType: preset.name,
            weekdaysMask: mask,
            startsOn: from,
            endsOn: Value(through),
            createdAt: _clock,
            updatedAt: _clock,
          ),
        );
  }

  Future<void> addCompletion(
    String task, {
    required String date,
    String owner = _owner,
    bool completed = false,
    bool targetReached = false,
    String? exclusionReason,
  }) async {
    await database
        .into(database.taskCompletionRecords)
        .insert(
          TaskCompletionRecordsCompanion.insert(
            id: '$owner:$task:$date',
            taskId: task,
            userId: owner,
            localDate: date,
            isSuccess: Value(completed),
            targetReached: Value(targetReached),
            actualDurationSeconds: Value(targetReached ? 2700 : 0),
            completedAt: Value(completed ? _clock : null),
            exclusionReason: Value(exclusionReason),
            createdAt: _clock,
            updatedAt: _clock,
          ),
        );
  }

  Future<void> addOverride(
    String task, {
    required String localDate,
    String owner = _owner,
    DayItemType type = DayItemType.recurring,
    DayOverrideAction action = DayOverrideAction.reschedule,
    int? start,
    int? end,
    bool deleted = false,
  }) async {
    await database
        .into(database.dailyItemOverrideRecords)
        .insert(
          DailyItemOverrideRecordsCompanion.insert(
            id: '$owner:${type.name}:$task:$localDate',
            userId: owner,
            itemType: type.name,
            itemId: task,
            localDate: localDate,
            action: action.name,
            plannedStartMinute: Value(start),
            plannedEndMinute: Value(end),
            createdAt: _clock,
            updatedAt: _clock,
            deletedAt: Value(deleted ? _clock : null),
          ),
        );
  }
}

class _HolidayCalendar implements HolidayCalendar {
  _HolidayCalendar(this._lookup);

  final FutureOr<ChinaDayKind> Function(DateTime date) _lookup;

  @override
  Future<ChinaDayKind> kindFor(DateTime date) async => _lookup(date);
}
