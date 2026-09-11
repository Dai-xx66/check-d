import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../../features/tasks/domain/task_models.dart';
import 'sync_queue_service.dart';

abstract interface class SyncRemoteStore {
  Future<void> upsert(
    String table,
    Map<String, Object?> values, {
    required String onConflict,
  });

  Future<void> clearOtherActiveFlag(
    String table, {
    required String userId,
    required String id,
    required String flagColumn,
  });

  Future<void> replacePlanTasks({
    required String userId,
    required String planId,
    required List<Map<String, Object?>> rows,
  });
}

class SupabaseSyncRemoteStore implements SyncRemoteStore {
  const SupabaseSyncRemoteStore(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upsert(
    String table,
    Map<String, Object?> values, {
    required String onConflict,
  }) async {
    await _client.from(table).upsert(values, onConflict: onConflict);
  }

  @override
  Future<void> clearOtherActiveFlag(
    String table, {
    required String userId,
    required String id,
    required String flagColumn,
  }) async {
    await _client
        .from(table)
        .update({flagColumn: false})
        .eq('user_id', userId)
        .neq('id', id)
        .isFilter('deleted_at', null);
  }

  @override
  Future<void> replacePlanTasks({
    required String userId,
    required String planId,
    required List<Map<String, Object?>> rows,
  }) async {
    await _client
        .from('plan_tasks')
        .delete()
        .eq('user_id', userId)
        .eq('plan_id', planId);
    if (rows.isNotEmpty) {
      await _client
          .from('plan_tasks')
          .upsert(rows, onConflict: 'plan_id,task_id');
    }
  }
}

class SyncFlushResult {
  const SyncFlushResult({
    required this.uploaded,
    required this.failed,
    required this.skipped,
    this.unauthenticated = false,
  });

  final int uploaded;
  final int failed;
  final int skipped;
  final bool unauthenticated;
}

/// Upload-only durable outbox processor. Drift remains authoritative until a
/// future download/reconciliation stage is introduced.
class SyncUploadExecutor {
  SyncUploadExecutor({
    required AppDatabase database,
    required SyncQueueService queue,
    required SyncRemoteStore remote,
    required String? Function() currentUserId,
  }) : _database = database,
       _queue = queue,
       _remote = remote,
       _currentUserId = currentUserId;

  final AppDatabase _database;
  final SyncQueueService _queue;
  final SyncRemoteStore _remote;
  final String? Function() _currentUserId;
  bool _isFlushing = false;

  Future<SyncFlushResult> flush({bool force = false, int limit = 100}) async {
    if (_isFlushing) {
      return const SyncFlushResult(uploaded: 0, failed: 0, skipped: 0);
    }
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) {
      return const SyncFlushResult(
        uploaded: 0,
        failed: 0,
        skipped: 0,
        unauthenticated: true,
      );
    }

    _isFlushing = true;
    try {
      final operations = await _queue.loadRetryableForUser(
        userId,
        limit: limit,
      );
      final ready =
          operations
              .where((operation) => force || _isReadyForRetry(operation))
              .toList()
            ..sort(_compareOperations);
      var uploaded = 0;
      var failed = 0;
      var skipped = operations.length - ready.length;

      for (final operation in ready) {
        try {
          final writes = await _writesFor(operation, userId);
          for (final write in writes) {
            if (write.clearOtherActiveFlag != null) {
              await _remote.clearOtherActiveFlag(
                write.table,
                userId: userId,
                id: write.values['id']! as String,
                flagColumn: write.clearOtherActiveFlag!,
              );
            }
            if (write.planTaskRows != null) {
              await _remote.replacePlanTasks(
                userId: userId,
                planId: write.values['plan_id']! as String,
                rows: write.planTaskRows!,
              );
            } else {
              await _remote.upsert(
                write.table,
                write.values,
                onConflict: write.onConflict,
              );
            }
          }
          await _queue.markCompleted(operation.id);
          uploaded++;
        } on Object catch (error) {
          await _queue.markFailed(operation.id, error);
          failed++;
        }
      }
      return SyncFlushResult(
        uploaded: uploaded,
        failed: failed,
        skipped: skipped,
      );
    } finally {
      _isFlushing = false;
    }
  }

  bool _isReadyForRetry(SyncOperation operation) {
    if (operation.status != 'failed') return true;
    final seconds = 5 * (1 << operation.retryCount.clamp(0, 6));
    return DateTime.now().toUtc().difference(operation.updatedAt).inSeconds >=
        seconds;
  }

  int _compareOperations(SyncOperation a, SyncOperation b) {
    final priority = _priority(a.entityType).compareTo(_priority(b.entityType));
    return priority != 0 ? priority : a.createdAt.compareTo(b.createdAt);
  }

  int _priority(String entityType) => switch (entityType) {
    'tags' => 0,
    'schedule_templates' || 'schedule_template_segments' => 1,
    'semesters' => 2,
    'courses' => 3,
    'course_schedule_rules' => 4,
    'tasks' => 5,
    'plan_tasks' || 'task_completions' || 'one_time_reminders' => 6,
    'timer_sessions' ||
    'daily_item_overrides' ||
    'reminder_rules' ||
    'alarm_rules' => 7,
    'ad_hoc_timers' => 8,
    'ad_hoc_timer_intervals' => 9,
    _ => 10,
  };

  Future<List<_CloudWrite>> _writesFor(
    SyncOperation operation,
    String userId,
  ) async {
    final payload = _payload(operation);
    return switch (operation.entityType) {
      'semesters' => _semesterWrites(operation, payload, userId),
      'schedule_templates' => _scheduleTemplateWrites(
        operation,
        payload,
        userId,
      ),
      'schedule_template_segments' => _segmentWrites(
        operation,
        payload,
        userId,
      ),
      'courses' => _courseWrites(operation, payload, userId),
      'course_schedule_rules' => _courseRuleWrites(operation, payload, userId),
      'daily_item_overrides' => _overrideWrites(operation, payload, userId),
      'tasks' => _taskWrites(operation, payload, userId),
      'one_time_reminders' => _oneTimeWrites(operation, payload, userId),
      'task_completions' => _completionWrites(operation, payload, userId),
      'timer_sessions' => _timerSessionWrites(operation, payload, userId),
      'ad_hoc_timers' => _adHocTimerWrites(operation, payload, userId),
      'ad_hoc_timer_intervals' => _adHocIntervalWrites(
        operation,
        payload,
        userId,
      ),
      'tags' => _tagWrites(operation, payload, userId),
      'tag_revisions' => _tagRevisionWrites(operation, payload, userId),
      'reminder_rules' => _reminderWrites(operation, payload, userId),
      'alarm_rules' => _alarmWrites(operation, payload, userId),
      'plans' => _planWrites(operation, payload, userId),
      'plan_tasks' => _planTaskWrites(operation, payload, userId),
      'reviews' => _reviewWrites(operation, payload, userId),
      'user_preferences' => _preferenceWrites(operation, payload, userId),
      _ => throw UnsupportedError(
        'Unsupported sync entity: ${operation.entityType}',
      ),
    };
  }

  Future<List<_CloudWrite>> _semesterWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.semesterRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) return [_archive('semesters', op, payload, userId)];
    return [
      _CloudWrite(
        'semesters',
        _owned(userId, {
          'id': row.id,
          'name': row.name,
          'first_week_start_date': row.firstWeekStartDate.toIso8601String(),
          'total_weeks': row.totalWeeks,
          'schedule_template_id': row.scheduleTemplateId,
          'is_current': row.isCurrent,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
        clearOtherActiveFlag: row.isCurrent && row.deletedAt == null
            ? 'is_current'
            : null,
      ),
    ];
  }

  Future<List<_CloudWrite>> _scheduleTemplateWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.scheduleTemplateRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) {
      return [_archive('schedule_templates', op, payload, userId)];
    }
    final segments =
        await (_database.select(_database.scheduleTemplateSegmentRecords)
              ..where(
                (r) => r.templateId.equals(row.id) & r.userId.equals(userId),
              ))
            .get();
    return [
      _CloudWrite(
        'schedule_templates',
        _owned(userId, {
          'id': row.id,
          'name': row.name,
          'timezone': row.timezone,
          'is_default': row.isDefault,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
        clearOtherActiveFlag: row.isDefault && row.deletedAt == null
            ? 'is_default'
            : null,
      ),
      ...segments.map((segment) => _segmentWrite(segment, userId)),
    ];
  }

  Future<List<_CloudWrite>> _segmentWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.scheduleTemplateSegmentRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    return row == null
        ? [_archive('schedule_template_segments', op, payload, userId)]
        : [_segmentWrite(row, userId)];
  }

  _CloudWrite _segmentWrite(ScheduleTemplateSegmentRecord row, String userId) =>
      _CloudWrite(
        'schedule_template_segments',
        _owned(userId, {
          'id': row.id,
          'template_id': row.templateId,
          'name': row.name,
          'starts_at_minute': row.startsAtMinute,
          'ends_at_minute': row.endsAtMinute,
          'segment_type': row.segmentType,
          'sort_order': row.sortOrder,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      );

  Future<List<_CloudWrite>> _courseWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.courseRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) return [_archive('courses', op, payload, userId)];
    return [
      _CloudWrite(
        'courses',
        _owned(userId, {
          'id': row.id,
          'name': row.name,
          'color': row.colorValue,
          'teacher': row.teacher,
          'classroom': row.classroom,
          'semester': row.semester,
          'semester_id': row.semesterId,
          'semester_starts_on': _isoOrNull(row.semesterStartsOn),
          'semester_ends_on': _isoOrNull(row.semesterEndsOn),
          'notes': row.notes,
          'status': row.status,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _courseRuleWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.courseScheduleRuleRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) {
      return [_archive('course_schedule_rules', op, payload, userId)];
    }
    return [
      _CloudWrite(
        'course_schedule_rules',
        _owned(userId, {
          'id': row.id,
          'course_id': row.courseId,
          'weekday': row.weekday,
          'week_rule_type': row.weekRuleType,
          'start_week': row.startWeek,
          'end_week': row.endWeek,
          'interval_weeks': row.intervalWeeks,
          'week_numbers': jsonDecode(row.weekNumbersJson),
          'schedule_template_id': row.scheduleTemplateId,
          'section_ids': jsonDecode(row.sectionIdsJson),
          'time_mode': row.timeMode,
          'starts_at_minute': row.startsAtMinute,
          'ends_at_minute': row.endsAtMinute,
          'classroom_override': row.classroomOverride,
          'notes': row.notes,
          'remind_before_minutes': row.remindBeforeMinutes,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _overrideWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.dailyItemOverrideRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) {
      return [_archive('daily_item_overrides', op, payload, userId)];
    }
    return [
      _CloudWrite(
        'daily_item_overrides',
        _owned(userId, {
          'id': row.id,
          'item_type': row.itemType,
          'item_id': row.itemId,
          'local_date': row.localDate,
          'action': row.action,
          'planned_start_minute': row.plannedStartMinute,
          'planned_end_minute': row.plannedEndMinute,
          'reminder_minute_of_day': row.reminderMinuteOfDay,
          'target_duration_seconds': row.targetDurationSeconds,
          'temporary_classroom': row.temporaryClassroom,
          'notes': row.notes,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _taskWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final task =
        await (_database.select(
              _database.localTasks,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (task == null) {
      return [_archive('tasks', op, payload, userId, archived: true)];
    }
    final writes = <_CloudWrite>[
      _CloudWrite(
        'tasks',
        _owned(userId, {
          'id': task.id,
          'name': task.name,
          'type': task.taskType == 'recurring' ? 'long_term' : 'one_time',
          'color': task.colorValue,
          'icon_name': task.iconName,
          'tag_id': task.tagId,
          'notes': task.notes,
          'status': task.status,
          'created_at': _iso(task.createdAt),
          'updated_at': _iso(task.updatedAt),
          'deleted_at': _isoOrNull(task.deletedAt),
        }),
        'id',
      ),
    ];
    if (task.taskType == 'recurring') {
      final longTerm =
          await (_database.select(_database.longTermTaskRecords)..where(
                (r) => r.taskId.equals(task.id) & r.userId.equals(userId),
              ))
              .getSingleOrNull();
      final schedule =
          await (_database.select(_database.taskScheduleRecords)..where(
                (r) => r.taskId.equals(task.id) & r.userId.equals(userId),
              ))
              .getSingleOrNull();
      if (longTerm != null) {
        writes.add(
          _CloudWrite(
            'long_term_tasks',
            _owned(userId, {
              'task_id': task.id,
              'check_mode': longTerm.checkMode,
              'target_duration_seconds': longTerm.targetDurationSeconds,
              'target_days': longTerm.targetDays,
              'holiday_pause': longTerm.holidayPause,
              'tag_id': task.tagId,
              'scheduled_minute_of_day': longTerm.scheduledMinuteOfDay,
              'reminder_minute_of_day': longTerm.reminderMinuteOfDay,
              'created_at': _iso(longTerm.createdAt),
              'updated_at': _iso(longTerm.updatedAt),
            }),
            'task_id',
          ),
        );
      }
      if (schedule != null) {
        writes.add(
          _CloudWrite(
            'task_schedules',
            _owned(userId, {
              'id': schedule.id,
              'task_id': schedule.taskId,
              'schedule_type': schedule.scheduleType,
              'weekdays': WeekdayMask.toDays(schedule.weekdaysMask),
              'weekdays_mask': schedule.weekdaysMask,
              'starts_on': schedule.startsOn,
              'ends_on': schedule.endsOn,
              'created_at': _iso(schedule.createdAt),
              'updated_at': _iso(schedule.updatedAt),
            }),
            'id',
          ),
        );
      }
    } else {
      final oneTime =
          await (_database.select(_database.oneTimeReminderRecords)..where(
                (r) => r.taskId.equals(task.id) & r.userId.equals(userId),
              ))
              .getSingleOrNull();
      if (oneTime != null) {
        writes.add(
          _CloudWrite(
            'one_time_reminders',
            _owned(userId, {
              'task_id': task.id,
              'scheduled_at': _iso(oneTime.scheduledAt),
              'has_scheduled_date': oneTime.hasScheduledDate,
              'remind_before_minutes': oneTime.remindBeforeMinutes,
              'is_timed': oneTime.isTimed,
              'completed_at': _isoOrNull(oneTime.completedAt),
              'created_at': _iso(oneTime.createdAt),
              'updated_at': _iso(oneTime.updatedAt),
            }),
            'task_id',
          ),
        );
      }
    }
    return writes;
  }

  Future<List<_CloudWrite>> _oneTimeWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(_database.oneTimeReminderRecords)..where(
              (r) => r.taskId.equals(op.entityId) & r.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (row == null) {
      return [
        _archive(
          'one_time_reminders',
          op,
          payload,
          userId,
          idColumn: 'task_id',
        ),
      ];
    }
    return [
      _CloudWrite(
        'one_time_reminders',
        _owned(userId, {
          'task_id': row.taskId,
          'scheduled_at': _iso(row.scheduledAt),
          'has_scheduled_date': row.hasScheduledDate,
          'remind_before_minutes': row.remindBeforeMinutes,
          'is_timed': row.isTimed,
          'completed_at': _isoOrNull(row.completedAt),
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
        }),
        'task_id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _completionWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final taskId = payload['task_id'] as String?;
    final localDate = payload['local_date'] as String?;
    if (taskId == null || localDate == null) {
      throw FormatException('Completion payload is missing identity.');
    }
    final row =
        await (_database.select(_database.taskCompletionRecords)..where(
              (r) =>
                  r.taskId.equals(taskId) &
                  r.localDate.equals(localDate) &
                  r.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (row == null) throw StateError('Completion no longer exists locally.');
    return [
      _CloudWrite(
        'task_completions',
        _owned(userId, {
          'id': row.id,
          'task_id': row.taskId,
          'local_date': row.localDate,
          'timezone': 'Asia/Shanghai',
          'actual_duration_seconds': row.actualDurationSeconds,
          'progress_percent': row.progressPercent,
          'target_reached': row.targetReached,
          'is_success': row.isSuccess,
          'exclusion_reason': row.exclusionReason,
          'completed_at': _isoOrNull(row.completedAt),
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
        }),
        'task_id,local_date',
      ),
    ];
  }

  Future<List<_CloudWrite>> _timerSessionWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.timerSessionRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('Timer session no longer exists locally.');
    }
    return [
      _CloudWrite(
        'timer_sessions',
        _owned(userId, {
          'id': row.id,
          'task_id': row.taskId,
          'tag_id': row.tagId,
          'started_at': _iso(row.startedAt),
          'logical_date': row.logicalDate,
          'ended_at': _isoOrNull(row.endedAt),
          'duration_seconds': row.durationSeconds,
          'state': row.state,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _adHocTimerWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.adHocTimerRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) return [_archive('ad_hoc_timers', op, payload, userId)];
    return [
      _CloudWrite(
        'ad_hoc_timers',
        _owned(userId, {
          'id': row.id,
          'title': row.title,
          'tag_id': row.tagId,
          'color': row.colorValue,
          'notes': row.notes,
          'started_at': _iso(row.startedAt),
          'timer_status': row.timerStatus,
          'accumulated_duration_seconds': row.accumulatedDurationSeconds,
          'current_started_at': _isoOrNull(row.currentStartedAt),
          'ended_at': _isoOrNull(row.endedAt),
          'completed_at': _isoOrNull(row.completedAt),
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _adHocIntervalWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.adHocTimerIntervalRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('Ad-hoc interval no longer exists locally.');
    }
    return [
      _CloudWrite(
        'ad_hoc_timer_intervals',
        _owned(userId, {
          'id': row.id,
          'timer_id': row.timerId,
          'started_at': _iso(row.startedAt),
          'ended_at': _isoOrNull(row.endedAt),
          'duration_seconds': row.durationSeconds,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _tagWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.tagRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) throw StateError('Tag no longer exists locally.');
    return [
      _CloudWrite(
        'tags',
        _owned(userId, {
          'id': row.id,
          'name': row.name,
          'color': row.colorValue,
          'archived': row.archived,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _tagRevisionWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.tagRevisionRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) throw StateError('Tag revision no longer exists locally.');
    return [
      _CloudWrite(
        'tag_revisions',
        _owned(userId, {
          'id': row.id,
          'tag_id': row.tagId,
          'snapshot_json': jsonDecode(row.snapshotJson),
          'changed_at': _iso(row.changedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _reminderWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.reminderRuleRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) return [_archive('reminder_rules', op, payload, userId)];
    return [
      _CloudWrite(
        'reminder_rules',
        _owned(userId, {
          'id': row.id,
          'owner_type': row.ownerType,
          'owner_id': row.ownerId,
          'reminder_kind': row.reminderKind,
          'enabled': row.enabled,
          'scheduled_minute_of_day': row.scheduledMinuteOfDay,
          'remind_before_minutes': row.remindBeforeMinutes,
          'local_date': row.localDate,
          'timezone': row.timezone,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _alarmWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.alarmRuleRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) return [_archive('alarm_rules', op, payload, userId)];
    return [
      _CloudWrite(
        'alarm_rules',
        _owned(userId, {
          'id': row.id,
          'owner_type': row.ownerType,
          'owner_id': row.ownerId,
          'enabled': row.enabled,
          'behavior': row.behavior,
          'sound_name': row.soundName,
          'snooze_minutes': row.snoozeMinutes,
          'repeat_interval_minutes': row.repeatIntervalMinutes,
          'max_ring_seconds': row.maxRingSeconds,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _planWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.planRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) return [_archive('plans', op, payload, userId)];
    return [
      _CloudWrite(
        'plans',
        _owned(userId, {
          'id': row.id,
          'name': row.name,
          'type': row.type,
          'color': row.colorValue,
          'goal': row.goal,
          'starts_on': row.startsOn,
          'ends_on': row.endsOn,
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _planTaskWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final planId = payload['plan_id'] as String? ?? op.entityId;
    final rows = await (_database.select(
      _database.planTaskRecords,
    )..where((r) => r.planId.equals(planId) & r.userId.equals(userId))).get();
    return [
      _CloudWrite(
        'plan_tasks',
        {'plan_id': planId},
        'plan_id,task_id',
        planTaskRows: [
          for (final row in rows)
            _owned(userId, {
              'plan_id': row.planId,
              'task_id': row.taskId,
              'weight': row.weight,
              'created_at': _iso(row.createdAt),
              'updated_at': _iso(row.updatedAt),
            }),
        ],
      ),
    ];
  }

  Future<List<_CloudWrite>> _reviewWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    final row =
        await (_database.select(
              _database.reviewRecords,
            )..where((r) => r.id.equals(op.entityId) & r.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) return [_archive('reviews', op, payload, userId)];
    return [
      _CloudWrite(
        'reviews',
        _owned(userId, {
          'id': row.id,
          'type': row.reviewType,
          'period_start': row.periodStart,
          'period_end': row.periodEnd,
          'happened_text': row.happenedText,
          'learned_text': row.learnedText,
          'improve_text': row.improveText,
          'mood': row.mood,
          'objective_snapshot': jsonDecode(row.objectiveSnapshotJson),
          'created_at': _iso(row.createdAt),
          'updated_at': _iso(row.updatedAt),
          'deleted_at': _isoOrNull(row.deletedAt),
        }),
        'id',
      ),
    ];
  }

  Future<List<_CloudWrite>> _preferenceWrites(
    SyncOperation op,
    Map<String, Object?> payload,
    String userId,
  ) async {
    return [
      _CloudWrite(
        'user_preferences',
        _owned(userId, {
          'id': payload['id'] ?? op.entityId,
          'preference_key': payload['preference_key'] ?? 'reminder_defaults',
          'value': payload['value'] ?? const <String, Object?>{},
          'updated_at': payload['updated_at'] ?? _iso(DateTime.now()),
          'deleted_at': payload['deleted_at'],
        }),
        'id',
      ),
    ];
  }

  Map<String, Object?> _payload(SyncOperation operation) {
    final decoded = jsonDecode(operation.payloadJson);
    if (decoded is! Map) throw const FormatException('Invalid sync payload.');
    return Map<String, Object?>.from(decoded);
  }

  _CloudWrite _archive(
    String table,
    SyncOperation operation,
    Map<String, Object?> payload,
    String userId, {
    String idColumn = 'id',
    bool archived = false,
  }) => _CloudWrite(
    table,
    _owned(userId, {
      idColumn: payload[idColumn] ?? operation.entityId,
      if (archived) 'status': 'archived',
      if (!archived)
        'deleted_at': payload['deleted_at'] ?? _iso(DateTime.now()),
    }),
    idColumn,
  );

  Map<String, Object?> _owned(String userId, Map<String, Object?> values) {
    final owned = Map<String, Object?>.from(values)..remove('user_id');
    owned['user_id'] = userId;
    return owned;
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();
  String? _isoOrNull(DateTime? value) => value == null ? null : _iso(value);
}

class SyncUploadCoordinator {
  SyncUploadCoordinator(this._executor, this._queue);

  final SyncUploadExecutor _executor;
  final SyncQueueService _queue;
  StreamSubscription<List<SyncOperation>>? _subscription;
  Timer? _retryTimer;
  bool _active = false;

  void setActive(bool active, String? userId) {
    if (!active || userId == null || userId.isEmpty) {
      _stop();
      return;
    }
    if (_active) return;
    _active = true;
    _subscription = _queue.watchRetryableForUser(userId).listen((_) => flush());
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
    unawaited(flush(force: true));
  }

  void onAppResumed() {
    if (_active) unawaited(flush(force: true));
  }

  Future<SyncFlushResult> flush({bool force = false}) =>
      _executor.flush(force: force);

  void _stop() {
    _active = false;
    _subscription?.cancel();
    _subscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void dispose() => _stop();
}

class _CloudWrite {
  const _CloudWrite(
    this.table,
    this.values,
    this.onConflict, {
    this.clearOtherActiveFlag,
    this.planTaskRows,
  });

  final String table;
  final Map<String, Object?> values;
  final String onConflict;
  final String? clearOtherActiveFlag;
  final List<Map<String, Object?>>? planTaskRows;
}
