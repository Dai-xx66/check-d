import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late TaskRepository tasks;
  late DayScheduleRepository schedule;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final queue = SyncQueueService(database);
    tasks = TaskRepository(database: database, syncQueue: queue, userId: 'u1');
    schedule = DayScheduleRepository(
      database: database,
      syncQueue: queue,
      userId: 'u1',
    );
  });

  tearDown(() => database.close());

  test('one-day override does not mutate recurring rule', () async {
    final startsOn = DateTime(2026, 9, 7);
    final taskId = await tasks.saveRecurringTask(
      RecurringTaskDraft(
        name: '背单词',
        colorValue: 0xFF9B7AE5,
        executionMode: RecurringExecutionMode.timed,
        targetDurationSeconds: 30 * 60,
        schedulePreset: SchedulePreset.daily,
        weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
        startsOn: startsOn,
        holidayPause: false,
        scheduledMinuteOfDay: 20 * 60,
        reminderMinuteOfDay: 19 * 60 + 50,
      ),
    );

    final overrideId = await schedule.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.recurring,
        itemId: taskId,
        localDate: startsOn,
        action: DayOverrideAction.reschedule,
        plannedStartMinute: 21 * 60,
        plannedEndMinute: 21 * 60 + 30,
        reminderMinuteOfDay: 20 * 60 + 50,
      ),
    );

    final recurring = await tasks.getTask(taskId, date: startsOn);
    final overrides = await schedule.watchOverridesForDate(startsOn).first;
    expect(overrideId, isNotEmpty);
    expect(overrides.single.plannedStartMinute, 21 * 60);
    expect(recurring!.scheduledMinuteOfDay, 20 * 60);
    expect(recurring.reminderMinuteOfDay, 19 * 60 + 50);
  });

  test('due reminder, advance reminder and alarm are separate rules', () async {
    const ownerId = 'task-1';
    final dueId = await schedule.saveReminderRule(
      const ReminderRuleDraft(
        ownerType: DayItemType.oneTime,
        ownerId: ownerId,
        reminderKind: ReminderKind.due,
        scheduledMinuteOfDay: 20 * 60,
      ),
    );
    final advanceId = await schedule.saveReminderRule(
      const ReminderRuleDraft(
        ownerType: DayItemType.oneTime,
        ownerId: ownerId,
        reminderKind: ReminderKind.advance,
        scheduledMinuteOfDay: 20 * 60,
        remindBeforeMinutes: 10,
      ),
    );
    final alarmId = await schedule.saveAlarmRule(
      const AlarmRuleDraft(
        ownerType: DayItemType.oneTime,
        ownerId: ownerId,
        enabled: true,
        behavior: AlarmBehavior.snooze,
        snoozeMinutes: 5,
      ),
    );

    final reminders = await schedule
        .watchReminderRules(ownerType: DayItemType.oneTime, ownerId: ownerId)
        .first;
    final alarms = await database.select(database.alarmRuleRecords).get();

    expect({dueId, advanceId, alarmId}, hasLength(3));
    expect(reminders.map((rule) => rule.reminderKind).toSet(), {
      ReminderKind.due,
      ReminderKind.advance,
    });
    expect(alarms.single.behavior, AlarmBehavior.snooze.name);
  });

  test('ad hoc timer is queryable by date and splits cross-day duration', () async {
    final started = DateTime(2026, 9, 3, 23, 30);
    final ended = DateTime(2026, 9, 4, 0, 30);
    await schedule.saveAdHocTimer(
      AdHocTimerDraft(
        title: '临时专注',
        colorValue: 0xFFF17F9D,
        startedAt: started,
        endedAt: ended,
      ),
    );

    final firstDay = await schedule.watchAdHocTimersForDate(started).first;
    final secondDay = await schedule.watchAdHocTimersForDate(ended).first;
    expect(firstDay.single.durationSecondsForDate(started), 30 * 60);
    expect(secondDay.single.durationSecondsForDate(ended), 30 * 60);
  });
}
