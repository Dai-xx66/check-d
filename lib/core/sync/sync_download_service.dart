import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'sync_apply_scope.dart';

abstract interface class SyncRemoteReader {
  Future<List<Map<String, Object?>>> readTable(
    String table, {
    required String userId,
  });
}

class SupabaseSyncRemoteReader implements SyncRemoteReader {
  const SupabaseSyncRemoteReader(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, Object?>>> readTable(
    String table, {
    required String userId,
  }) async {
    final response = await _client.from(table).select().eq('user_id', userId);
    return [for (final row in response) Map<String, Object?>.from(row as Map)];
  }
}

class SyncDownloadResult {
  const SyncDownloadResult({
    required this.applied,
    required this.skipped,
    this.unauthenticated = false,
    this.error,
  });

  final int applied;
  final int skipped;
  final bool unauthenticated;
  final Object? error;

  bool get succeeded => !unauthenticated && error == null;
}

class SyncRestoreSnapshotException implements Exception {
  const SyncRestoreSnapshotException(this.message);

  final String message;

  @override
  String toString() => 'SyncRestoreSnapshotException: $message';
}

/// Downloads a complete authenticated-user snapshot before applying it to
/// Drift. Local writes remain the runtime source of truth; this only applies
/// a remote row when it is demonstrably newer than its local counterpart.
class SyncDownloadExecutor {
  SyncDownloadExecutor({
    required AppDatabase database,
    required SyncRemoteReader remote,
    required SyncApplyScope applyScope,
    required String? Function() currentUserId,
  }) : _database = database,
       _remote = remote,
       _applyScope = applyScope,
       _currentUserId = currentUserId;

  static const _tables = <String>[
    'tags',
    'schedule_templates',
    'semesters',
    'schedule_template_segments',
    'courses',
    'tasks',
    'long_term_tasks',
    'task_schedules',
    'one_time_reminders',
    'course_schedule_rules',
    'daily_item_overrides',
    'task_completions',
    'timer_sessions',
    'ad_hoc_timers',
    'ad_hoc_timer_intervals',
    'reminder_rules',
    'alarm_rules',
    'plans',
    'plan_tasks',
    'reviews',
    'tag_revisions',
    'user_preferences',
  ];

  final AppDatabase _database;
  final SyncRemoteReader _remote;
  final SyncApplyScope _applyScope;
  final String? Function() _currentUserId;
  bool _isReconciling = false;

  Future<SyncDownloadResult> reconcile() async {
    if (_isReconciling) {
      return const SyncDownloadResult(applied: 0, skipped: 0);
    }
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) {
      return const SyncDownloadResult(
        applied: 0,
        skipped: 0,
        unauthenticated: true,
      );
    }

    _isReconciling = true;
    try {
      // Fetch first. A failed network request must not leave a partially
      // restored parent/child graph in Drift.
      final snapshot = <String, List<Map<String, Object?>>>{};
      for (final table in _tables) {
        snapshot[table] = await _remote.readTable(table, userId: userId);
      }
      _validateTimerSnapshot(snapshot['timer_sessions'] ?? const [], userId);
      return await _applyScope.run(
        () => _database.transaction(() => _applySnapshot(snapshot, userId)),
      );
    } on Object catch (error) {
      return SyncDownloadResult(applied: 0, skipped: 0, error: error);
    } finally {
      _isReconciling = false;
    }
  }

  void _validateTimerSnapshot(List<Map<String, Object?>> rows, String userId) {
    final unfinishedByTask = <String, int>{};
    for (final row in rows) {
      if (_stringOrNull(row, 'user_id') != userId) continue;
      if (_deleted(row)) continue;
      final state = _stringOr(row, 'state', 'finished');
      if (state == 'finished') continue;
      final taskId = _string(row, 'task_id');
      final count = (unfinishedByTask[taskId] ?? 0) + 1;
      unfinishedByTask[taskId] = count;
      if (count > 1) {
        throw SyncRestoreSnapshotException(
          'Cloud snapshot has more than one unfinished timer for task $taskId.',
        );
      }
    }
  }

  Future<SyncDownloadResult> _applySnapshot(
    Map<String, List<Map<String, Object?>>> snapshot,
    String userId,
  ) async {
    var applied = 0;
    var skipped = 0;

    Future<void> applyRows(
      String table,
      Future<bool> Function(Map<String, Object?> row) apply,
    ) async {
      for (final row in snapshot[table] ?? const []) {
        if (_stringOrNull(row, 'user_id') != userId) {
          skipped++;
          continue;
        }
        if (await apply(row)) {
          applied++;
        } else {
          skipped++;
        }
      }
    }

    // Parents first. This ordering matches the actual Drift foreign keys,
    // rather than merely the visual feature hierarchy.
    await applyRows('tags', (row) => _applyTag(row, userId));
    await applyRows('schedule_templates', (row) => _applyTemplate(row, userId));
    await applyRows('semesters', (row) => _applySemester(row, userId));
    await applyRows(
      'schedule_template_segments',
      (row) => _applyTemplateSegment(row, userId),
    );
    await applyRows('courses', (row) => _applyCourse(row, userId));
    await applyRows('tasks', (row) => _applyTask(row, userId));
    await applyRows(
      'long_term_tasks',
      (row) => _applyLongTermTask(row, userId),
    );
    await applyRows('task_schedules', (row) => _applyTaskSchedule(row, userId));
    await applyRows(
      'one_time_reminders',
      (row) => _applyOneTimeReminder(row, userId),
    );
    await applyRows(
      'course_schedule_rules',
      (row) => _applyCourseRule(row, userId),
    );
    await applyRows(
      'daily_item_overrides',
      (row) => _applyOverride(row, userId),
    );
    await applyRows('task_completions', (row) => _applyCompletion(row, userId));
    await applyRows('timer_sessions', (row) => _applyTimerSession(row, userId));
    await applyRows('ad_hoc_timers', (row) => _applyAdHocTimer(row, userId));
    await applyRows(
      'ad_hoc_timer_intervals',
      (row) => _applyAdHocInterval(row, userId),
    );
    await applyRows('reminder_rules', (row) => _applyReminderRule(row, userId));
    await applyRows('alarm_rules', (row) => _applyAlarmRule(row, userId));
    await applyRows('plans', (row) => _applyPlan(row, userId));
    await applyRows('plan_tasks', (row) => _applyPlanTask(row, userId));
    await applyRows('reviews', (row) => _applyReview(row, userId));
    await applyRows('tag_revisions', (row) => _applyTagRevision(row, userId));
    await applyRows('user_preferences', (row) => _applyPreference(row, userId));

    return SyncDownloadResult(applied: applied, skipped: skipped);
  }

  bool _isRemoteNewer({
    required DateTime? localUpdatedAt,
    required Map<String, Object?> remote,
    int? localSyncVersion,
  }) {
    if (localUpdatedAt == null) return true;
    final remoteUpdatedAt = _dateTime(remote, 'updated_at');
    if (remoteUpdatedAt.isAfter(localUpdatedAt)) return true;
    if (remoteUpdatedAt.isBefore(localUpdatedAt)) return false;
    final remoteVersion = _intOrNull(remote['sync_version']);
    return remoteVersion != null &&
        localSyncVersion != null &&
        remoteVersion > localSyncVersion;
  }

  Future<bool> _applyTag(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local = await _tag(id, userId);
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.tagRecords)
        .insertOnConflictUpdate(
          TagRecordsCompanion.insert(
            id: id,
            userId: userId,
            name: _string(row, 'name'),
            colorValue: _int(row, 'color'),
            archived: Value(_bool(row, 'archived') || _deleted(row)),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<bool> _applyTemplate(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local = await _template(id, userId);
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.scheduleTemplateRecords)
        .insertOnConflictUpdate(
          ScheduleTemplateRecordsCompanion.insert(
            id: id,
            userId: userId,
            name: _string(row, 'name'),
            timezone: Value(_stringOr(row, 'timezone', 'Asia/Shanghai')),
            isDefault: Value(_bool(row, 'is_default')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applySemester(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local = await _semester(id, userId);
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.semesterRecords)
        .insertOnConflictUpdate(
          SemesterRecordsCompanion.insert(
            id: id,
            userId: userId,
            name: _string(row, 'name'),
            firstWeekStartDate: _dateTime(row, 'first_week_start_date'),
            totalWeeks: _int(row, 'total_weeks'),
            scheduleTemplateId: Value(
              _stringOrNull(row, 'schedule_template_id'),
            ),
            isCurrent: Value(_bool(row, 'is_current')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyTemplateSegment(
    Map<String, Object?> row,
    String userId,
  ) async {
    final id = _id(row);
    final local = await _segment(id, userId);
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.scheduleTemplateSegmentRecords)
        .insertOnConflictUpdate(
          ScheduleTemplateSegmentRecordsCompanion.insert(
            id: id,
            templateId: _string(row, 'template_id'),
            userId: userId,
            name: _string(row, 'name'),
            startsAtMinute: _int(row, 'starts_at_minute'),
            endsAtMinute: _int(row, 'ends_at_minute'),
            segmentType: Value(_stringOr(row, 'segment_type', 'classTime')),
            sortOrder: Value(_intOr(row, 'sort_order', 0)),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyCourse(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local = await _course(id, userId);
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.courseRecords)
        .insertOnConflictUpdate(
          CourseRecordsCompanion.insert(
            id: id,
            userId: userId,
            name: _string(row, 'name'),
            colorValue: _int(row, 'color'),
            teacher: Value(_stringOrNull(row, 'teacher')),
            classroom: Value(_stringOrNull(row, 'classroom')),
            semester: Value(_stringOrNull(row, 'semester')),
            semesterId: Value(_stringOrNull(row, 'semester_id')),
            semesterStartsOn: Value(_dateTimeOrNull(row, 'semester_starts_on')),
            semesterEndsOn: Value(_dateTimeOrNull(row, 'semester_ends_on')),
            notes: Value(_stringOrNull(row, 'notes')),
            status: Value(_stringOr(row, 'status', 'active')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyTask(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local = await _task(id, userId);
    if (!_isRemoteNewer(
      localUpdatedAt: local?.updatedAt,
      localSyncVersion: local?.syncVersion,
      remote: row,
    )) {
      return false;
    }
    await _database
        .into(_database.localTasks)
        .insertOnConflictUpdate(
          LocalTasksCompanion.insert(
            id: id,
            userId: Value(userId),
            name: _string(row, 'name'),
            taskType: _string(row, 'type') == 'long_term'
                ? 'recurring'
                : 'oneTime',
            colorValue: _int(row, 'color'),
            iconName: Value(_stringOr(row, 'icon_name', 'target')),
            tagId: Value(_stringOrNull(row, 'tag_id')),
            notes: Value(_stringOrNull(row, 'notes')),
            status: Value(
              _deleted(row) ? 'archived' : _stringOr(row, 'status', 'active'),
            ),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            syncVersion: Value(_intOr(row, 'sync_version', 0)),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyLongTermTask(
    Map<String, Object?> row,
    String userId,
  ) async {
    final taskId = _string(row, 'task_id');
    if (await _task(taskId, userId) == null) return false;
    final local =
        await (_database.select(_database.longTermTaskRecords)
              ..where((r) => r.taskId.equals(taskId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.longTermTaskRecords)
        .insertOnConflictUpdate(
          LongTermTaskRecordsCompanion.insert(
            taskId: taskId,
            userId: userId,
            checkMode: _string(row, 'check_mode') == 'timer'
                ? 'timed'
                : 'untimed',
            targetDurationSeconds: Value(
              _intOrNull(row['target_duration_seconds']),
            ),
            targetDays: Value(_intOrNull(row['target_days'])),
            holidayPause: Value(_bool(row, 'holiday_pause')),
            scheduledMinuteOfDay: Value(
              _intOrNull(row['scheduled_minute_of_day']),
            ),
            reminderMinuteOfDay: Value(
              _intOrNull(row['reminder_minute_of_day']),
            ),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<bool> _applyTaskSchedule(
    Map<String, Object?> row,
    String userId,
  ) async {
    final id = _id(row);
    final taskId = _string(row, 'task_id');
    if (await _task(taskId, userId) == null) return false;
    final local =
        await (_database.select(_database.taskScheduleRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.taskScheduleRecords)
        .insertOnConflictUpdate(
          TaskScheduleRecordsCompanion.insert(
            id: id,
            taskId: taskId,
            userId: userId,
            scheduleType: _string(row, 'schedule_type'),
            weekdaysMask: _intOr(
              row,
              'weekdays_mask',
              _weekdayMask(row['weekdays']),
            ),
            startsOn: _string(row, 'starts_on'),
            endsOn: Value(_stringOrNull(row, 'ends_on')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<bool> _applyOneTimeReminder(
    Map<String, Object?> row,
    String userId,
  ) async {
    final taskId = _string(row, 'task_id');
    final localTask = await _task(taskId, userId);
    if (localTask == null || _deleted(row)) return false;
    final local =
        await (_database.select(_database.oneTimeReminderRecords)
              ..where((r) => r.taskId.equals(taskId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.oneTimeReminderRecords)
        .insertOnConflictUpdate(
          OneTimeReminderRecordsCompanion.insert(
            taskId: taskId,
            userId: userId,
            scheduledAt: _dateTime(row, 'scheduled_at'),
            hasScheduledDate: Value(_boolOr(row, 'has_scheduled_date', true)),
            remindBeforeMinutes: Value(
              _intOrNull(row['remind_before_minutes']),
            ),
            isTimed: Value(_boolOr(row, 'is_timed', false)),
            completedAt: Value(_dateTimeOrNull(row, 'completed_at')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<bool> _applyCourseRule(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final courseId = _string(row, 'course_id');
    if (await _course(courseId, userId) == null) return false;
    final local =
        await (_database.select(_database.courseScheduleRuleRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.courseScheduleRuleRecords)
        .insertOnConflictUpdate(
          CourseScheduleRuleRecordsCompanion.insert(
            id: id,
            courseId: courseId,
            userId: userId,
            weekday: _int(row, 'weekday'),
            weekRuleType: _string(row, 'week_rule_type'),
            startWeek: Value(_intOrNull(row['start_week'])),
            endWeek: Value(_intOrNull(row['end_week'])),
            intervalWeeks: Value(_intOrNull(row['interval_weeks'])),
            weekNumbersJson: Value(_json(row['week_numbers'], fallback: '[]')),
            scheduleTemplateId: Value(
              _stringOrNull(row, 'schedule_template_id'),
            ),
            sectionIdsJson: Value(_json(row['section_ids'], fallback: '[]')),
            timeMode: Value(_stringOr(row, 'time_mode', 'customTime')),
            startsAtMinute: _int(row, 'starts_at_minute'),
            endsAtMinute: _int(row, 'ends_at_minute'),
            classroomOverride: Value(_stringOrNull(row, 'classroom_override')),
            notes: Value(_stringOrNull(row, 'notes')),
            remindBeforeMinutes: Value(
              _intOrNull(row['remind_before_minutes']),
            ),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyOverride(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local =
        await (_database.select(_database.dailyItemOverrideRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.dailyItemOverrideRecords)
        .insertOnConflictUpdate(
          DailyItemOverrideRecordsCompanion.insert(
            id: id,
            userId: userId,
            itemType: _string(row, 'item_type'),
            itemId: _string(row, 'item_id'),
            localDate: _string(row, 'local_date'),
            action: _string(row, 'action'),
            plannedStartMinute: Value(_intOrNull(row['planned_start_minute'])),
            plannedEndMinute: Value(_intOrNull(row['planned_end_minute'])),
            reminderMinuteOfDay: Value(
              _intOrNull(row['reminder_minute_of_day']),
            ),
            targetDurationSeconds: Value(
              _intOrNull(row['target_duration_seconds']),
            ),
            temporaryClassroom: Value(
              _stringOrNull(row, 'temporary_classroom'),
            ),
            notes: Value(_stringOrNull(row, 'notes')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyCompletion(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local =
        await (_database.select(_database.taskCompletionRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    if (_deleted(row)) {
      await _recordTombstone('task_completions', id, userId, row);
      return true;
    }
    if (await _hasNewerTombstone('task_completions', id, userId, row)) {
      return false;
    }
    if (await _task(_string(row, 'task_id'), userId) == null) return false;
    await _database
        .into(_database.taskCompletionRecords)
        .insertOnConflictUpdate(
          TaskCompletionRecordsCompanion.insert(
            id: id,
            taskId: _string(row, 'task_id'),
            userId: userId,
            localDate: _string(row, 'local_date'),
            actualDurationSeconds: Value(
              _intOr(row, 'actual_duration_seconds', 0),
            ),
            progressPercent: Value(_doubleOr(row, 'progress_percent', 0)),
            targetReached: Value(_boolOr(row, 'target_reached', false)),
            isSuccess: Value(_boolOr(row, 'is_success', false)),
            exclusionReason: Value(_stringOrNull(row, 'exclusion_reason')),
            completedAt: Value(_dateTimeOrNull(row, 'completed_at')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<bool> _applyTimerSession(
    Map<String, Object?> row,
    String userId,
  ) async {
    final id = _id(row);
    final local =
        await (_database.select(_database.timerSessionRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    if (_deleted(row)) {
      await _recordTombstone('timer_sessions', id, userId, row);
      return true;
    }
    if (await _hasNewerTombstone('timer_sessions', id, userId, row)) {
      return false;
    }
    if (await _task(_string(row, 'task_id'), userId) == null) return false;
    await _database
        .into(_database.timerSessionRecords)
        .insertOnConflictUpdate(
          TimerSessionRecordsCompanion.insert(
            id: id,
            taskId: _string(row, 'task_id'),
            tagId: Value(_stringOrNull(row, 'tag_id')),
            userId: userId,
            startedAt: _dateTime(row, 'started_at'),
            logicalDate: Value(_stringOrNull(row, 'logical_date')),
            endedAt: Value(_dateTimeOrNull(row, 'ended_at')),
            durationSeconds: Value(_intOr(row, 'duration_seconds', 0)),
            state: _string(row, 'state'),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<bool> _applyAdHocTimer(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local =
        await (_database.select(_database.adHocTimerRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.adHocTimerRecords)
        .insertOnConflictUpdate(
          AdHocTimerRecordsCompanion.insert(
            id: id,
            userId: userId,
            title: _string(row, 'title'),
            tagId: Value(_stringOrNull(row, 'tag_id')),
            colorValue: _int(row, 'color'),
            notes: Value(_stringOrNull(row, 'notes')),
            startedAt: _dateTime(row, 'started_at'),
            timerStatus: Value(_stringOr(row, 'timer_status', 'idle')),
            accumulatedDurationSeconds: Value(
              _intOr(row, 'accumulated_duration_seconds', 0),
            ),
            currentStartedAt: Value(_dateTimeOrNull(row, 'current_started_at')),
            endedAt: Value(_dateTimeOrNull(row, 'ended_at')),
            completedAt: Value(_dateTimeOrNull(row, 'completed_at')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyAdHocInterval(
    Map<String, Object?> row,
    String userId,
  ) async {
    final id = _id(row);
    final timerId = _string(row, 'timer_id');
    if (await _adHocTimer(timerId, userId) == null) return false;
    final local =
        await (_database.select(_database.adHocTimerIntervalRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.adHocTimerIntervalRecords)
        .insertOnConflictUpdate(
          AdHocTimerIntervalRecordsCompanion.insert(
            id: id,
            timerId: timerId,
            userId: userId,
            startedAt: _dateTime(row, 'started_at'),
            endedAt: Value(_dateTimeOrNull(row, 'ended_at')),
            durationSeconds: Value(_intOr(row, 'duration_seconds', 0)),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<bool> _applyReminderRule(
    Map<String, Object?> row,
    String userId,
  ) async {
    final id = _id(row);
    final local =
        await (_database.select(_database.reminderRuleRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.reminderRuleRecords)
        .insertOnConflictUpdate(
          ReminderRuleRecordsCompanion.insert(
            id: id,
            userId: userId,
            ownerType: _string(row, 'owner_type'),
            ownerId: _string(row, 'owner_id'),
            reminderKind: _string(row, 'reminder_kind'),
            enabled: Value(_boolOr(row, 'enabled', true)),
            scheduledMinuteOfDay: Value(
              _intOrNull(row['scheduled_minute_of_day']),
            ),
            remindBeforeMinutes: Value(
              _intOrNull(row['remind_before_minutes']),
            ),
            localDate: Value(_stringOrNull(row, 'local_date')),
            timezone: Value(_stringOr(row, 'timezone', 'Asia/Shanghai')),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyAlarmRule(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local =
        await (_database.select(_database.alarmRuleRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.alarmRuleRecords)
        .insertOnConflictUpdate(
          AlarmRuleRecordsCompanion.insert(
            id: id,
            userId: userId,
            ownerType: _string(row, 'owner_type'),
            ownerId: _string(row, 'owner_id'),
            enabled: Value(_boolOr(row, 'enabled', false)),
            behavior: Value(_stringOr(row, 'behavior', 'once')),
            soundName: Value(_stringOrNull(row, 'sound_name')),
            snoozeMinutes: Value(_intOrNull(row['snooze_minutes'])),
            repeatIntervalMinutes: Value(
              _intOrNull(row['repeat_interval_minutes']),
            ),
            maxRingSeconds: Value(_intOrNull(row['max_ring_seconds'])),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyPlan(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local =
        await (_database.select(_database.planRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.planRecords)
        .insertOnConflictUpdate(
          PlanRecordsCompanion.insert(
            id: id,
            userId: userId,
            name: _string(row, 'name'),
            type: _string(row, 'type'),
            colorValue: _int(row, 'color'),
            goal: Value(_stringOrNull(row, 'goal')),
            startsOn: _string(row, 'starts_on'),
            endsOn: _string(row, 'ends_on'),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyPlanTask(Map<String, Object?> row, String userId) async {
    final planId = _string(row, 'plan_id');
    final taskId = _string(row, 'task_id');
    if (await _plan(planId, userId) == null ||
        await _task(taskId, userId) == null) {
      return false;
    }
    final local =
        await (_database.select(_database.planTaskRecords)..where(
              (r) =>
                  r.planId.equals(planId) &
                  r.taskId.equals(taskId) &
                  r.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.planTaskRecords)
        .insertOnConflictUpdate(
          PlanTaskRecordsCompanion.insert(
            planId: planId,
            taskId: taskId,
            userId: userId,
            weight: Value(_doubleOr(row, 'weight', 1)),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<bool> _applyReview(Map<String, Object?> row, String userId) async {
    final id = _id(row);
    final local =
        await (_database.select(_database.reviewRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    await _database
        .into(_database.reviewRecords)
        .insertOnConflictUpdate(
          ReviewRecordsCompanion.insert(
            id: id,
            userId: userId,
            reviewType: _string(row, 'type'),
            periodStart: _string(row, 'period_start'),
            periodEnd: _string(row, 'period_end'),
            happenedText: Value(_stringOrNull(row, 'happened_text')),
            learnedText: Value(_stringOrNull(row, 'learned_text')),
            improveText: Value(_stringOrNull(row, 'improve_text')),
            mood: Value(_intOrNull(row['mood'])),
            objectiveSnapshotJson: Value(
              _json(row['objective_snapshot'], fallback: '{}'),
            ),
            createdAt: _dateTime(row, 'created_at'),
            updatedAt: _dateTime(row, 'updated_at'),
            deletedAt: Value(_dateTimeOrNull(row, 'deleted_at')),
          ),
        );
    return true;
  }

  Future<bool> _applyTagRevision(
    Map<String, Object?> row,
    String userId,
  ) async {
    final id = _id(row);
    final tagId = _string(row, 'tag_id');
    if (await _tag(tagId, userId) == null) return false;
    final local =
        await (_database.select(_database.tagRevisionRecords)
              ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
            .getSingleOrNull();
    final changedAt = _dateTime(row, 'changed_at');
    if (local != null && !changedAt.isAfter(local.changedAt)) return false;
    await _database
        .into(_database.tagRevisionRecords)
        .insertOnConflictUpdate(
          TagRevisionRecordsCompanion.insert(
            id: id,
            tagId: tagId,
            userId: userId,
            snapshotJson: _json(row['snapshot_json'], fallback: '{}'),
            changedAt: changedAt,
          ),
        );
    return true;
  }

  Future<bool> _applyPreference(Map<String, Object?> row, String userId) async {
    if (_stringOr(row, 'preference_key', '') != 'reminder_defaults') {
      return false;
    }
    final key = 'reminder-defaults:$userId';
    final local = await (_database.select(
      _database.appSettings,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    if (!_isRemoteNewer(localUpdatedAt: local?.updatedAt, remote: row)) {
      return false;
    }
    if (_deleted(row)) {
      // A deleted cloud preference intentionally falls back to the local app
      // default; device/UI preferences remain untouched.
      if (local != null) {
        await (_database.delete(
          _database.appSettings,
        )..where((r) => r.key.equals(key))).go();
      }
      return true;
    }
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: _json(row['value'], fallback: '{}'),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
    return true;
  }

  Future<TagRecord?> _tag(String id, String userId) => (_database.select(
    _database.tagRecords,
  )..where((r) => r.id.equals(id) & r.userId.equals(userId))).getSingleOrNull();

  Future<ScheduleTemplateRecord?> _template(String id, String userId) =>
      (_database.select(_database.scheduleTemplateRecords)
            ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
          .getSingleOrNull();

  Future<SemesterRecord?> _semester(String id, String userId) =>
      (_database.select(_database.semesterRecords)
            ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
          .getSingleOrNull();

  Future<ScheduleTemplateSegmentRecord?> _segment(String id, String userId) =>
      (_database.select(_database.scheduleTemplateSegmentRecords)
            ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
          .getSingleOrNull();

  Future<CourseRecord?> _course(String id, String userId) => (_database.select(
    _database.courseRecords,
  )..where((r) => r.id.equals(id) & r.userId.equals(userId))).getSingleOrNull();

  Future<LocalTask?> _task(String id, String userId) => (_database.select(
    _database.localTasks,
  )..where((r) => r.id.equals(id) & r.userId.equals(userId))).getSingleOrNull();

  Future<AdHocTimerRecord?> _adHocTimer(String id, String userId) =>
      (_database.select(_database.adHocTimerRecords)
            ..where((r) => r.id.equals(id) & r.userId.equals(userId)))
          .getSingleOrNull();

  Future<PlanRecord?> _plan(String id, String userId) => (_database.select(
    _database.planRecords,
  )..where((r) => r.id.equals(id) & r.userId.equals(userId))).getSingleOrNull();

  String _tombstoneKey(String table, String id, String userId) =>
      'sync-tombstone:$userId:$table:$id';

  Future<void> _recordTombstone(
    String table,
    String id,
    String userId,
    Map<String, Object?> row,
  ) {
    return _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _tombstoneKey(table, id, userId),
            value: _dateTime(row, 'deleted_at').toIso8601String(),
            updatedAt: _dateTime(row, 'updated_at'),
          ),
        );
  }

  Future<bool> _hasNewerTombstone(
    String table,
    String id,
    String userId,
    Map<String, Object?> row,
  ) async {
    final record =
        await (_database.select(_database.appSettings)
              ..where((r) => r.key.equals(_tombstoneKey(table, id, userId))))
            .getSingleOrNull();
    if (record == null) return false;
    final tombstoneAt = DateTime.tryParse(record.value)?.toUtc();
    return tombstoneAt != null &&
        !_dateTime(row, 'updated_at').isAfter(tombstoneAt);
  }

  String _id(Map<String, Object?> row) => _string(row, 'id');

  String _string(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Cloud row is missing $key.');
  }

  String _stringOr(Map<String, Object?> row, String key, String fallback) =>
      _stringOrNull(row, key) ?? fallback;

  String? _stringOrNull(Map<String, Object?> row, String key) {
    final value = row[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  int _int(Map<String, Object?> row, String key) =>
      _intOrNull(row[key]) ??
      (throw FormatException('Cloud row is missing $key.'));

  int _intOr(Map<String, Object?> row, String key, int fallback) =>
      _intOrNull(row[key]) ?? fallback;

  int? _intOrNull(Object? value) => switch (value) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };

  double _doubleOr(Map<String, Object?> row, String key, double fallback) {
    final value = row[key];
    return switch (value) {
      num value => value.toDouble(),
      String value => double.tryParse(value) ?? fallback,
      _ => fallback,
    };
  }

  bool _bool(Map<String, Object?> row, String key) => _boolOr(row, key, false);

  bool _boolOr(Map<String, Object?> row, String key, bool fallback) =>
      row[key] is bool ? row[key]! as bool : fallback;

  bool _deleted(Map<String, Object?> row) =>
      _dateTimeOrNull(row, 'deleted_at') != null;

  DateTime _dateTime(Map<String, Object?> row, String key) =>
      _dateTimeOrNull(row, key) ??
      (throw FormatException('Cloud row is missing $key.'));

  DateTime? _dateTimeOrNull(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  String _json(Object? value, {required String fallback}) {
    if (value == null) return fallback;
    return value is String ? value : jsonEncode(value);
  }

  int _weekdayMask(Object? weekdays) {
    if (weekdays is! List) return 0;
    return weekdays.fold<int>(0, (mask, day) {
      final weekday = _intOrNull(day);
      if (weekday == null || weekday < 1 || weekday > 7) return mask;
      return mask | (1 << (weekday - 1));
    });
  }
}

class SyncDownloadCoordinator {
  SyncDownloadCoordinator(this._executor);

  final SyncDownloadExecutor _executor;
  String? _lastUserId;
  DateTime? _lastReconcileAt;
  Future<SyncDownloadResult>? _inFlight;

  Future<SyncDownloadResult> onAuthenticated(String userId) {
    if (_lastUserId != userId) {
      _lastUserId = userId;
      _lastReconcileAt = null;
    }
    return reconcileIfDue(force: true);
  }

  Future<SyncDownloadResult> onAppResumed() => reconcileIfDue();

  Future<SyncDownloadResult> reconcileIfDue({bool force = false}) {
    final now = DateTime.now().toUtc();
    if (!force &&
        _lastReconcileAt != null &&
        now.difference(_lastReconcileAt!) < const Duration(minutes: 5)) {
      return Future.value(const SyncDownloadResult(applied: 0, skipped: 0));
    }
    return _inFlight ??= _reconcile().whenComplete(() => _inFlight = null);
  }

  Future<SyncDownloadResult> _reconcile() async {
    final result = await _executor.reconcile();
    if (result.succeeded) _lastReconcileAt = DateTime.now().toUtc();
    return result;
  }
}
