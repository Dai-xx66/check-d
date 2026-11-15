import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../calendar/domain/calendar_models.dart';
import '../../calendar/domain/calendar_occurrence_builder.dart';
import '../../courses/data/course_repository.dart';
import '../../courses/data/semester_repository.dart';
import '../../schedule/data/day_schedule_repository.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/domain/task_models.dart';
import 'planning_snapshot_adapter.dart';

/// Read-only aggregation over existing user-scoped repositories and Drift.
/// It does not access Supabase and never claims that cloud data is current.
class PlanningContextRepository {
  PlanningContextRepository({
    required AppDatabase database,
    required TaskRepository tasks,
    required CourseRepository courses,
    required SemesterRepository semesters,
    required DayScheduleRepository schedule,
    required String authenticatedUserId,
    PlanningSnapshotAdapter adapter = const PlanningSnapshotAdapter(),
  }) : _database = database,
       _tasks = tasks,
       _courses = courses,
       _semesters = semesters,
       _schedule = schedule,
       _userId = authenticatedUserId,
       _adapter = adapter;

  final AppDatabase _database;
  final TaskRepository _tasks;
  final CourseRepository _courses;
  final SemesterRepository _semesters;
  final DayScheduleRepository _schedule;
  final String _userId;
  final PlanningSnapshotAdapter _adapter;

  Future<Map<String, Object?>> load({
    required DateTime from,
    required DateTime through,
    required DateTime now,
  }) async {
    if (_userId.trim().isEmpty) throw StateError('authenticated user required');
    if (through.isBefore(from)) {
      throw ArgumentError('through must not precede from');
    }
    final requestedDays = DateTime(
      through.year,
      through.month,
      through.day,
    ).difference(DateTime(from.year, from.month, from.day)).inDays;
    if (requestedDays > 90) {
      throw ArgumentError('planning range cannot exceed 91 local dates');
    }
    return _database.transaction(() async {
      final taskStatuses = await Future.wait([
        _tasks.watchTasksByStatus(TaskLifecycle.active).first,
        _tasks.watchTasksByStatus(TaskLifecycle.paused).first,
      ]);
      final tasks = taskStatuses
          .expand((items) => items)
          .toList(growable: false);
      final courses = await _courses.loadCourses();
      final templates = await _courses.watchScheduleTemplates().first;
      final semesters = await _semesters.loadSemesters();
      final overrides = <DailyItemOverride>[];
      final resolvedOccurrences = <CalendarOccurrence>[];
      final recurringOccurrences = <Map<String, Object?>>[];
      final unmodeledRecurringOccurrenceIds = <String>[];
      final occupied = <Map<String, Object?>>[];
      for (
        var day = DateTime(from.year, from.month, from.day);
        !day.isAfter(DateTime(through.year, through.month, through.day));
        day = day.add(const Duration(days: 1))
      ) {
        final dayOverrides = await _schedule.loadOverridesForDate(day);
        overrides.addAll(dayOverrides);
        final dateTasks = await _tasks.watchTasksForDate(day).first;
        final occurrences = buildCalendarOccurrencesForDate(
          date: day,
          tasks: dateTasks,
          courses: courses,
          overrides: dayOverrides,
          templates: templates,
          semesters: semesters,
        );
        resolvedOccurrences.addAll(
          occurrences.where(
            (occurrence) => occurrence.type == CalendarOccurrenceType.course,
          ),
        );
        for (final occurrence in occurrences.where(
          (item) => item.type == CalendarOccurrenceType.recurring,
        )) {
          final task = occurrence.task;
          final duration = task?.targetDurationSeconds;
          final startMinute = occurrence.startMinute;
          final id = occurrence.id;
          if (task == null || task.isCompleted) continue;
          final recurringDto = <String, Object?>{
            'occurrence_id': id,
            'task_id': task.id,
            'date': _date(occurrence.date),
            'scheduled_minute': startMinute,
            'duration_target_seconds': duration,
            'completion_status': task.completionStatus.name,
          };
          recurringOccurrences.add(recurringDto);
          if (startMinute == null || duration == null || duration <= 0) {
            unmodeledRecurringOccurrenceIds.add(id);
            continue;
          }
          occupied.add({
            'source_id': id,
            'source_type': 'recurring_occurrence',
            'task_id': task.id,
            'starts_at': _shanghaiBoundary(
              occurrence.date,
              startMinute,
            ).toIso8601String(),
            'ends_at': _shanghaiBoundary(
              occurrence.date,
              startMinute,
            ).add(Duration(seconds: duration)).toIso8601String(),
            'kind': 'recurring_task_plan',
          });
        }
      }

      final queue =
          await (_database.select(_database.syncOperations)..where(
                (row) =>
                    row.userId.equals(_userId) &
                    (row.status.equals('pending') |
                        row.status.equals('failed')),
              ))
              .get();
      final effortRows =
          await (_database.select(_database.taskEffortRecords)..where(
                (row) => row.userId.equals(_userId) & row.deletedAt.isNull(),
              ))
              .get();
      final remainingSecondsByTask = <String, int?>{
        for (final row in effortRows) row.taskId: row.remainingSeconds,
      };
      // Both queued and failed operations represent local changes not
      // acknowledged by the server. A failed upload is still unsynced.
      final hasUnacknowledgedChanges = queue.isNotEmpty;
      final syncState = hasUnacknowledgedChanges
          ? 'pending_local_changes'
          : 'unknown';

      final timers =
          await (_database.select(_database.timerSessionRecords)
                ..where(
                  (row) =>
                      row.userId.equals(_userId) &
                      row.state.equals(TimerSessionStatus.finished.name) &
                      row.startedAt.isBiggerOrEqualValue(
                        _shanghaiBoundary(from, 0).toUtc(),
                      ) &
                      row.startedAt.isSmallerThanValue(
                        _shanghaiBoundary(
                          through.add(const Duration(days: 1)),
                          0,
                        ).toUtc(),
                      ),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.startedAt)])
                ..limit(500))
              .get();
      final timerFacts = timers
          .map(
            (row) => <String, Object?>{
              'task_id': row.taskId,
              'started_at': row.startedAt.toUtc().toIso8601String(),
              'ended_at': row.endedAt?.toUtc().toIso8601String(),
              'duration_seconds': row.durationSeconds,
              'logical_date': row.logicalDate,
              'source': 'drift_timer_session',
            },
          )
          .toList(growable: false);

      for (final override in overrides) {
        if (override.plannedStartMinute == null ||
            override.plannedEndMinute == null) {
          continue;
        }
        if (override.plannedEndMinute! <= override.plannedStartMinute!) {
          continue;
        }
        final day = DateTime(
          override.localDate.year,
          override.localDate.month,
          override.localDate.day,
        );
        occupied.add({
          'source_id': override.id,
          'source_type': override.itemType.name,
          'task_id':
              override.itemType == DayItemType.oneTime ||
                  override.itemType == DayItemType.recurring
              ? override.itemId
              : null,
          'starts_at': _shanghaiBoundary(
            day,
            override.plannedStartMinute!,
          ).toIso8601String(),
          'ends_at': _shanghaiBoundary(
            day,
            override.plannedEndMinute!,
          ).toIso8601String(),
          'kind': 'existing_override',
        });
      }

      final localDate = DateTime(now.year, now.month, now.day);
      final result = _adapter.build(
        subjectRef: _userId,
        source: 'flutter_drift',
        capturedAt: DateTime.now().toUtc(),
        version: 'pending-content-hash',
        syncState: syncState,
        now: now,
        horizonEnd: _shanghaiBoundary(
          through.add(const Duration(days: 1)),
          0,
        ).subtract(const Duration(minutes: 1)),
        date: localDate,
        tasks: tasks,
        courses: courses,
        overrides: overrides.cast(),
        templates: templates,
        semesters: semesters,
        resolvedCourseOccurrences: resolvedOccurrences,
        remainingSecondsByTask: remainingSecondsByTask,
        occupiedBlocks: occupied,
        timerFacts: timerFacts,
        recurringOccurrences: recurringOccurrences,
        unmodeledRecurringOccurrenceIds: unmodeledRecurringOccurrenceIds,
        // Give the user enough time to review and confirm so the first
        // candidate does not become past while the confirmation dialog opens.
        previewSafetyLead: const Duration(minutes: 15),
      );
      // Version is a deterministic digest of planning-relevant content; time
      // of collection is deliberately excluded so identical data has a stable version.
      final versionInput = Map<String, Object?>.from(result)
        ..remove('version')
        ..remove('captured_at')
        ..remove('now');
      // earliest_start defaults to the collection clock in the DTO, not a
      // persisted CheckD field. Excluding it keeps the content version stable
      // while still hashing actual task fields, occurrence data and timers.
      final versionTasks = versionInput['tasks'];
      if (versionTasks is List) {
        // Clone nested task maps before normalizing the digest input. The
        // shallow top-level copy shares `tasks` with `result`; mutating it
        // would strip required planning fields from the returned snapshot.
        final digestTasks = versionTasks
            .whereType<Map>()
            .map((task) => Map<String, Object?>.from(task))
            .toList(growable: false);
        versionInput['tasks'] = digestTasks;
        for (final task in digestTasks) {
          task.remove('earliest_start');
        }
      }
      result['version'] = _contentVersion(jsonEncode(versionInput));
      result['sync_queue_pending_count'] = queue
          .where((row) => row.status == 'pending')
          .length;
      result['sync_queue_failed_count'] = queue
          .where((row) => row.status == 'failed')
          .length;
      result['range'] = {'from': _date(from), 'through': _date(through)};
      result['planning_only'] = true;
      result['execution_eligible'] = false;
      result['provisional'] =
          true; // No server watermark is currently available.
      return result;
    });
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static DateTime _shanghaiBoundary(DateTime value, int minute) => DateTime.utc(
    value.year,
    value.month,
    value.day,
    0,
    minute,
  ).subtract(const Duration(hours: 8));

  static String _contentVersion(String input) {
    // Stable FNV-1a 64-bit content version; not a security digest or server token.
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final byte in utf8.encode(input)) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    return 'local-fnv64-${hash.toRadixString(16).padLeft(16, '0')}';
  }
}
