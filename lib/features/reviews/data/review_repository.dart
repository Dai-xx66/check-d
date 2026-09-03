import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/holiday/holiday_calendar.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/review_models.dart';

class ReviewRepository {
  ReviewRepository({
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required this.userId,
    HolidayCalendar? holidayCalendar,
  }) : _database = database,
       _syncQueue = syncQueue,
       _holidayCalendar = holidayCalendar;

  final AppDatabase _database;
  final SyncQueueService _syncQueue;
  final String userId;
  final HolidayCalendar? _holidayCalendar;
  final Uuid _uuid = const Uuid();

  Stream<ReviewDetails?> watchReview(ReviewPeriod period) {
    final query = _database.select(_database.reviewRecords)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            row.reviewType.equals(period.type.name) &
            row.periodStart.equals(localDateKey(period.startsOn)) &
            row.deletedAt.isNull(),
      );
    return query.watchSingleOrNull().map(
      (record) => record == null ? null : _toDetails(record),
    );
  }

  Future<ReviewSnapshot> loadSnapshot(ReviewPeriod period) async {
    final start = dateOnly(period.startsOn);
    final end = dateOnly(period.endsOn).isAfter(dateOnly(DateTime.now()))
        ? dateOnly(DateTime.now())
        : dateOnly(period.endsOn);
    if (end.isBefore(start)) {
      return const ReviewSnapshot(
        dueCount: 0,
        completedCount: 0,
        timedSeconds: 0,
      );
    }

    final tasks =
        await (_database.select(_database.localTasks)..where(
              (row) => row.userId.equals(userId) & row.deletedAt.isNull(),
            ))
            .get();
    final schedules = await (_database.select(
      _database.taskScheduleRecords,
    )..where((row) => row.userId.equals(userId))).get();
    final longTerms = await (_database.select(
      _database.longTermTaskRecords,
    )..where((row) => row.userId.equals(userId))).get();
    final reminders = await (_database.select(
      _database.oneTimeReminderRecords,
    )..where((row) => row.userId.equals(userId))).get();
    final completions =
        await (_database.select(_database.taskCompletionRecords)..where(
              (row) => row.userId.equals(userId) & row.isSuccess.equals(true),
            ))
            .get();
    final sessions = await (_database.select(
      _database.timerSessionRecords,
    )..where((row) => row.userId.equals(userId))).get();
    final scheduleByTask = {for (final item in schedules) item.taskId: item};
    final longTermByTask = {for (final item in longTerms) item.taskId: item};
    final completionKeys = {
      for (final item in completions) '${item.taskId}:${item.localDate}',
    };
    var dueCount = 0;
    var completedCount = 0;

    for (final task in tasks) {
      if (task.taskType != TaskKind.recurring.name) continue;
      final schedule = scheduleByTask[task.id];
      final longTerm = longTermByTask[task.id];
      if (schedule == null || longTerm == null) continue;
      final rule = TaskScheduleRule(
        preset: SchedulePreset.values.byName(schedule.scheduleType),
        weekdaysMask: schedule.weekdaysMask,
        startsOn: DateTime.parse(schedule.startsOn),
        endsOn: schedule.endsOn == null
            ? null
            : DateTime.parse(schedule.endsOn!),
      );
      final taskStart = DateTime.parse(schedule.startsOn);
      final taskEnd = schedule.endsOn == null
          ? end
          : _minDate(end, DateTime.parse(schedule.endsOn!));
      for (
        var day = _maxDate(start, taskStart);
        !day.isAfter(taskEnd);
        day = day.add(const Duration(days: 1))
      ) {
        if (!await isRecurringTaskDue(
          schedule: rule,
          holidayPause: longTerm.holidayPause,
          date: day,
          holidayCalendar: _holidayCalendar,
        )) {
          continue;
        }
        dueCount++;
        if (completionKeys.contains('${task.id}:${localDateKey(day)}')) {
          completedCount++;
        }
      }
    }
    for (final reminder in reminders) {
      final scheduled = dateOnly(reminder.scheduledAt.toLocal());
      if (scheduled.isBefore(start) || scheduled.isAfter(end)) continue;
      dueCount++;
      if (reminder.completedAt != null) completedCount++;
    }
    return ReviewSnapshot(
      dueCount: dueCount,
      completedCount: completedCount,
      timedSeconds: _timedSecondsInRange(sessions, start, end),
    );
  }

  Future<void> save(ReviewDraft draft) async {
    final now = DateTime.now().toUtc();
    final period = draft.period;
    final existing =
        await (_database.select(_database.reviewRecords)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.reviewType.equals(period.type.name) &
                  row.periodStart.equals(localDateKey(period.startsOn)),
            ))
            .getSingleOrNull();
    final id = existing?.id ?? _uuid.v4();
    final snapshot = {
      'due_count': draft.snapshot.dueCount,
      'completed_count': draft.snapshot.completedCount,
      'timed_seconds': draft.snapshot.timedSeconds,
    };
    await _database.transaction(() async {
      await _database
          .into(_database.reviewRecords)
          .insertOnConflictUpdate(
            ReviewRecordsCompanion.insert(
              id: id,
              userId: userId,
              reviewType: period.type.name,
              periodStart: localDateKey(period.startsOn),
              periodEnd: localDateKey(period.endsOn),
              happenedText: Value(_clean(draft.happenedText)),
              learnedText: Value(_clean(draft.learnedText)),
              improveText: Value(_clean(draft.improveText)),
              mood: Value(draft.mood),
              objectiveSnapshotJson: Value(jsonEncode(snapshot)),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _syncQueue.enqueue(
        entityType: 'reviews',
        entityId: id,
        operation: SyncOperationType.upsert,
        payload: {
          'id': id,
          'user_id': userId,
          'type': period.type.name,
          'period_start': localDateKey(period.startsOn),
          'period_end': localDateKey(period.endsOn),
          'happened_text': _clean(draft.happenedText),
          'learned_text': _clean(draft.learnedText),
          'improve_text': _clean(draft.improveText),
          'mood': draft.mood,
          'objective_snapshot': snapshot,
          'updated_at': now.toIso8601String(),
        },
        userId: userId,
      );
    });
  }

  ReviewDetails _toDetails(ReviewRecord record) {
    final snapshot =
        jsonDecode(record.objectiveSnapshotJson) as Map<String, dynamic>;
    return ReviewDetails(
      id: record.id,
      period: ReviewPeriod(
        type: ReviewType.values.byName(record.reviewType),
        startsOn: DateTime.parse(record.periodStart),
        endsOn: DateTime.parse(record.periodEnd),
      ),
      snapshot: ReviewSnapshot(
        dueCount: snapshot['due_count'] as int? ?? 0,
        completedCount: snapshot['completed_count'] as int? ?? 0,
        timedSeconds: snapshot['timed_seconds'] as int? ?? 0,
      ),
      happenedText: record.happenedText,
      learnedText: record.learnedText,
      improveText: record.improveText,
      mood: record.mood,
      createdAt: record.createdAt.toLocal(),
      updatedAt: record.updatedAt.toLocal(),
    );
  }

  int _timedSecondsInRange(
    List<TimerSessionRecord> sessions,
    DateTime start,
    DateTime end,
  ) {
    final rangeStart = dateOnly(start);
    final rangeEnd = dateOnly(end).add(const Duration(days: 1));
    final now = DateTime.now();
    var total = 0;
    for (final session in sessions) {
      final sessionStart = session.startedAt.toLocal();
      final sessionEnd = (session.endedAt?.toLocal() ?? now);
      final overlapStart = sessionStart.isAfter(rangeStart)
          ? sessionStart
          : rangeStart;
      final overlapEnd = sessionEnd.isBefore(rangeEnd) ? sessionEnd : rangeEnd;
      if (overlapEnd.isAfter(overlapStart)) {
        total += overlapEnd.difference(overlapStart).inSeconds;
      }
    }
    return total;
  }

  String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  DateTime _maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
}
