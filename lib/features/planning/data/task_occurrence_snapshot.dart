import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/holiday/holiday_calendar.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../tasks/domain/task_models.dart';

class TaskOccurrenceSnapshot {
  const TaskOccurrenceSnapshot({
    required this.userId,
    required this.deviceId,
    required this.localGeneration,
    required this.fromDate,
    required this.throughDate,
    required this.generatedAt,
    required this.taskDataVersion,
    required this.occurrences,
  });

  static const timezone = 'Asia/Shanghai';
  static const builderVersion = 'checkd_flutter_task_occurrence_v1';

  final String userId;
  final String deviceId;
  final int localGeneration;
  final String fromDate;
  final String throughDate;
  final DateTime generatedAt;
  final String taskDataVersion;
  final List<Map<String, Object?>> occurrences;

  Map<String, Object?> toJson() => {
    'from_date': fromDate,
    'through_date': throughDate,
    'timezone': timezone,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'builder_version': builderVersion,
    'task_data_version': taskDataVersion,
    'device_id': deviceId,
    'local_generation': localGeneration,
    'occurrences': occurrences,
  };
}

class TaskOccurrenceSnapshotException implements Exception {
  const TaskOccurrenceSnapshotException(this.code);

  final String code;

  @override
  String toString() => 'TaskOccurrenceSnapshotException($code)';
}

/// Builds the rolling window from CheckD's saved recurring plans. A checkpoint
/// binds the snapshot to an account and a settled local device generation.
class DriftTaskOccurrenceSnapshotRepository {
  DriftTaskOccurrenceSnapshotRepository({
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required HolidayCalendar holidayCalendar,
    DateTime Function()? clock,
  }) : _database = database,
       _syncQueue = syncQueue,
       _holidayCalendar = holidayCalendar,
       _clock = clock ?? DateTime.now;

  static const maximumDays = 31;
  static final _shanghai = _shanghaiLocation();

  final AppDatabase _database;
  final SyncQueueService _syncQueue;
  final HolidayCalendar _holidayCalendar;
  final DateTime Function() _clock;

  Future<TaskOccurrenceSnapshot> build(SyncDeviceCheckpoint checkpoint) async {
    if (checkpoint.userId.trim().isEmpty ||
        checkpoint.userId == 'offline-user' ||
        checkpoint.deviceId.trim().isEmpty ||
        checkpoint.localGeneration < 0) {
      throw const TaskOccurrenceSnapshotException('invalid_checkpoint');
    }
    final generatedAt = _clock().toUtc();
    final localNow = tz.TZDateTime.from(generatedAt, _shanghai);
    // UTC midnight is only a civil-date carrier here. It is not a planned
    // start time. Adding days cannot inherit the device's DST transitions.
    final from = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final through = from.add(const Duration(days: maximumDays - 1));
    final fromDate = localDateKey(from);
    final throughDate = localDateKey(through);
    final (plans, overrides) = await _database.transaction(() async {
      await _requireCheckpoint(checkpoint);
      final activePlans = await _loadPlans(checkpoint.userId);
      return (
        activePlans,
        await _loadOverrides(
          checkpoint.userId,
          activePlans.map((plan) => plan.taskId).toSet(),
        ),
      );
    });

    final rows = <Map<String, Object?>>[];
    final holidayCalendar = _SnapshotHolidayCalendar(_holidayCalendar);
    for (var day = from; !day.isAfter(through);) {
      final date = localDateKey(day);
      for (final plan in plans) {
        final override = overrides[(plan.taskId, date)];
        if (override?.action == DayOverrideAction.skip.name) continue;
        if (!await isRecurringTaskDue(
          schedule: plan.rule,
          holidayPause: plan.holidayPause,
          date: day,
          holidayCalendar: holidayCalendar,
        )) {
          continue;
        }
        rows.add(_normalizeOccurrence(plan, date, override));
      }
      day = day.add(const Duration(days: 1));
    }
    rows.sort((first, second) {
      final byDate = (first['local_date'] as String).compareTo(
        second['local_date'] as String,
      );
      if (byDate != 0) return byDate;
      final byMinute = (first['start_minute'] as int).compareTo(
        second['start_minute'] as int,
      );
      if (byMinute != 0) return byMinute;
      return (first['occurrence_id'] as String).compareTo(
        second['occurrence_id'] as String,
      );
    });

    await _requireCheckpoint(checkpoint);
    return TaskOccurrenceSnapshot(
      userId: checkpoint.userId,
      deviceId: checkpoint.deviceId,
      localGeneration: checkpoint.localGeneration,
      fromDate: fromDate,
      throughDate: throughDate,
      generatedAt: generatedAt,
      taskDataVersion: _taskDataVersion(plans, overrides.values),
      occurrences: List.unmodifiable(rows),
    );
  }

  Future<void> _requireCheckpoint(SyncDeviceCheckpoint expected) async {
    final current = await _syncQueue.settledCheckpoint(expected.userId);
    if (current == null ||
        current.deviceId != expected.deviceId ||
        current.localGeneration != expected.localGeneration) {
      throw const TaskOccurrenceSnapshotException('checkpoint_changed');
    }
  }

  Future<List<_RecurringPlan>> _loadPlans(String ownerId) async {
    final tasks = _database.localTasks;
    final settings = _database.longTermTaskRecords;
    final rules = _database.taskScheduleRecords;
    final rows =
        await (_database.select(tasks).join([
              leftOuterJoin(
                settings,
                settings.taskId.equalsExp(tasks.id) &
                    settings.userId.equals(ownerId),
              ),
              leftOuterJoin(
                rules,
                rules.taskId.equalsExp(tasks.id) & rules.userId.equals(ownerId),
              ),
            ])..where(
              tasks.userId.equals(ownerId) &
                  tasks.taskType.isIn([
                    TaskKind.recurring.name,
                    'longTerm',
                    'long_term',
                  ]) &
                  tasks.status.equals(TaskLifecycle.active.name) &
                  tasks.deletedAt.isNull(),
            ))
            .get();

    final plans = <_RecurringPlan>[];
    final seen = <String>{};
    for (final row in rows) {
      final task = row.readTable(tasks);
      final config = row.readTableOrNull(settings);
      final rule = row.readTableOrNull(rules);
      if (config == null || rule == null || !seen.add(task.id)) {
        throw const TaskOccurrenceSnapshotException(
          'incomplete_recurring_rule',
        );
      }
      final startsOn = _parseDate(rule.startsOn);
      final endsOn = _parseDate(rule.endsOn);
      final preset = SchedulePreset.values
          .where((value) => value.name == rule.scheduleType)
          .firstOrNull;
      if (startsOn == null ||
          (rule.endsOn != null &&
              (endsOn == null || endsOn.isBefore(startsOn))) ||
          preset == null ||
          rule.weekdaysMask <= 0 ||
          rule.weekdaysMask > WeekdayMask.everyDay) {
        throw const TaskOccurrenceSnapshotException('invalid_recurring_rule');
      }
      plans.add((
        taskId: task.id,
        rule: TaskScheduleRule(
          preset: preset,
          weekdaysMask: rule.weekdaysMask,
          startsOn: startsOn,
          endsOn: endsOn,
        ),
        holidayPause: config.holidayPause,
        scheduledMinute: config.scheduledMinuteOfDay,
      ));
    }
    return plans
      ..sort((first, second) => first.taskId.compareTo(second.taskId));
  }

  Future<Map<(String, String), DailyItemOverrideRecord>> _loadOverrides(
    String ownerId,
    Set<String> activeTaskIds,
  ) async {
    if (activeTaskIds.isEmpty) return {};
    final query = _database.select(_database.dailyItemOverrideRecords)
      ..where(
        (row) =>
            row.userId.equals(ownerId) &
            row.itemType.equals(DayItemType.recurring.name) &
            row.deletedAt.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.itemId),
        (row) => OrderingTerm.asc(row.localDate),
      ]);
    return {
      for (final row in await query.get())
        if (activeTaskIds.contains(row.itemId))
          (row.itemId, row.localDate): row,
    };
  }
}

typedef _RecurringPlan = ({
  String taskId,
  TaskScheduleRule rule,
  bool holidayPause,
  int? scheduledMinute,
});

String _taskDataVersion(
  List<_RecurringPlan> plans,
  Iterable<DailyItemOverrideRecord> overrides,
) {
  // Hash the rule inputs in canonical order. The generated date range and
  // output rows have their own fields and can change as the window rolls.
  final input = {
    'rules': [
      for (final plan in plans)
        {
          'task_id': plan.taskId,
          'schedule_preset': plan.rule.preset.name,
          'weekdays_mask': plan.rule.weekdaysMask,
          'starts_on': localDateKey(plan.rule.startsOn),
          'ends_on': plan.rule.endsOn == null
              ? null
              : localDateKey(plan.rule.endsOn!),
          'holiday_pause': plan.holidayPause,
          'scheduled_minute': plan.scheduledMinute,
        },
    ],
    'overrides': [
      for (final row in overrides)
        {
          'task_id': row.itemId,
          'local_date': row.localDate,
          'action': row.action,
          'start_minute': row.plannedStartMinute,
          'end_minute': row.plannedEndMinute,
        },
    ],
  };
  return 'sha256:${sha256.convert(utf8.encode(jsonEncode(input)))}';
}

Map<String, Object?> _normalizeOccurrence(
  _RecurringPlan plan,
  String date,
  DailyItemOverrideRecord? override,
) {
  final overrideStart = override?.plannedStartMinute;
  final end = override?.plannedEndMinute;
  if ((overrideStart == null) != (end == null)) {
    throw const TaskOccurrenceSnapshotException('invalid_occurrence_time');
  }
  final start = overrideStart ?? plan.scheduledMinute;
  // A default planned end is not stored on recurring tasks. Until the wire
  // contract specifies a fallback, a due item with unresolved time prevents
  // publication of the complete window for this generation.
  if (start == null || end == null) {
    throw const TaskOccurrenceSnapshotException('unresolved_occurrence_time');
  }
  if (start < 0 || start >= 1440 || end <= start || end > 1440) {
    throw const TaskOccurrenceSnapshotException('invalid_occurrence_time');
  }
  return Map.unmodifiable({
    'task_id': plan.taskId,
    'occurrence_id': 'task:${plan.taskId}:$date',
    'local_date': date,
    'timezone': TaskOccurrenceSnapshot.timezone,
    'start_minute': start,
    'end_minute': end,
  });
}

DateTime? _parseDate(String? date) {
  if (date == null) return null;
  final parsed = DateTime.tryParse(date);
  return parsed != null && localDateKey(parsed) == date ? parsed : null;
}

tz.Location _shanghaiLocation() {
  tzdata.initializeTimeZones();
  return tz.getLocation(TaskOccurrenceSnapshot.timezone);
}

class _SnapshotHolidayCalendar implements HolidayCalendar {
  _SnapshotHolidayCalendar(this._source);

  final HolidayCalendar _source;
  final _days = <DateTime, Future<ChinaDayKind>>{};

  @override
  Future<ChinaDayKind> kindFor(DateTime date) =>
      _days.putIfAbsent(date, () => _source.kindFor(date));
}
