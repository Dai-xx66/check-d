import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/holiday/holiday_calendar.dart';
import '../../tasks/data/task_history.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/statistics_models.dart';

class StatisticsRepository {
  StatisticsRepository(
    this.database,
    this.userId, {
    HolidayCalendar? holidayCalendar,
  }) : _holidayCalendar = holidayCalendar;
  final AppDatabase database;
  final String userId;
  final HolidayCalendar? _holidayCalendar;

  Stream<StatisticsData> watchData() => database
      .customSelect(
        'SELECT 1',
        readsFrom: {
          database.localTasks,
          database.longTermTaskRecords,
          database.taskScheduleRecords,
          database.taskCompletionRecords,
          database.timerSessionRecords,
          database.tagRecords,
          database.taskRevisionRecords,
          database.oneTimeReminderRecords,
        },
      )
      .watch()
      .asyncMap((_) => load());

  Future<StatisticsData> load({DateTime? now}) =>
      database.transaction(() async {
        final today = dateOnly(now ?? DateTime.now());
        final tasks = await (database.select(
          database.localTasks,
        )..where((r) => r.userId.equals(userId))).get();
        final goals = await (database.select(
          database.longTermTaskRecords,
        )..where((r) => r.userId.equals(userId))).get();
        final schedules = await (database.select(
          database.taskScheduleRecords,
        )..where((r) => r.userId.equals(userId))).get();
        final completions = await (database.select(
          database.taskCompletionRecords,
        )..where((r) => r.userId.equals(userId))).get();
        final sessions = await (database.select(
          database.timerSessionRecords,
        )..where((r) => r.userId.equals(userId))).get();
        final tags = await (database.select(
          database.tagRecords,
        )..where((r) => r.userId.equals(userId))).get();
        final revisions =
            await (database.select(database.taskRevisionRecords)
                  ..where((r) => r.userId.equals(userId))
                  ..orderBy([
                    (r) => OrderingTerm.asc(r.changedAt),
                    (r) => OrderingTerm.asc(r.rowId),
                  ]))
                .get();
        final reminders = await (database.select(
          database.oneTimeReminderRecords,
        )..where((r) => r.userId.equals(userId))).get();
        final goalById = {for (final row in goals) row.taskId: row};
        final scheduleById = {for (final row in schedules) row.taskId: row};
        final completionByKey = {
          for (final row in completions) '${row.taskId}:${row.localDate}': row,
        };
        final result = <StatisticsTask>[];
        for (final task in tasks.where(
          (t) => t.taskType == TaskKind.recurring.name,
        )) {
          final schedule = scheduleById[task.id];
          final goal = goalById[task.id];
          if (schedule == null || goal == null) continue;
          final history = TaskHistory(
            task,
            goal,
            schedule,
            revisions.where((r) => r.taskId == task.id).toList(),
          );
          final days = <ExecutionDay>[];
          for (
            var day = history.firstDay;
            !day.isAfter(today);
            day = DateTime(day.year, day.month, day.day + 1)
          ) {
            final snapshot = history.on(day);
            final key = localDateKey(day);
            final completion = completionByKey['${task.id}:$key'];
            if (completion?.exclusionReason != null) continue;
            final start = DateTime.parse(snapshot['starts_on'] as String);
            final end = DateTime.tryParse(snapshot['ends_on'] as String? ?? '');
            final weekdays = (snapshot['weekdays'] as List).cast<int>();
            final status = snapshot['status'];
            final due =
                status == 'active' &&
                !day.isBefore(start) &&
                (end == null || !day.isAfter(end)) &&
                weekdays.contains(day.weekday);
            if (!due ||
                !await isRecurringTaskDue(
                  schedule: TaskScheduleRule(
                    preset: SchedulePreset.values.byName(
                      snapshot['schedule_type'] as String,
                    ),
                    weekdaysMask: WeekdayMask.fromDays(weekdays),
                    startsOn: start,
                    endsOn: end,
                  ),
                  holidayPause: snapshot['holiday_pause'] as bool? ?? false,
                  date: day,
                  holidayCalendar: _holidayCalendar,
                )) {
              continue;
            }
            final mode = snapshot['check_mode'];
            final targetMode =
                mode == 'timed' ||
                mode == 'timer' ||
                mode == 'target_timer' ||
                mode == 'targetTimer' ||
                mode == 'free_timer' ||
                mode == 'freeTimer';
            final target = snapshot['target_duration_seconds'] as int?;
            days.add(
              ExecutionDay(
                date: day,
                success: completion?.isSuccess ?? false,
                targetSeconds: targetMode && target != null && target > 0
                    ? target
                    : null,
                storedTargetReached: completion?.targetReached ?? false,
              ),
            );
          }
          result.add(
            StatisticsTask(
              id: task.id,
              name: task.name,
              iconName: task.iconName,
              colorValue: task.colorValue,
              days: days,
            ),
          );
        }
        return StatisticsData(
          tags: tags.map((t) => TimeTag(t.id, t.name, t.colorValue)).toList(),
          sessions: sessions
              .map(
                (s) => TimeEntry(
                  taskId: s.taskId,
                  tagId: s.tagId,
                  start: s.startedAt.toLocal(),
                  end: s.endedAt?.toLocal(),
                  durationSeconds: s.durationSeconds,
                  running:
                      s.state == TimerSessionStatus.running.name &&
                      s.endedAt == null,
                ),
              )
              .toList(),
          tasks: result,
          reminderCompletions: reminders
              .where((r) => r.completedAt != null)
              .map((r) => r.completedAt!.toLocal())
              .toList(),
        );
      });
}
