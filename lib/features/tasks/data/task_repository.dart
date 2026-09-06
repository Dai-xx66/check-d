import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/holiday/holiday_calendar.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../domain/task_models.dart';
import 'task_history.dart';

class TaskRepository {
  TaskRepository({
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required String userId,
    HolidayCalendar? holidayCalendar,
    NotificationService? notifications,
  }) : _database = database,
       _syncQueue = syncQueue,
       _userId = userId,
       _holidayCalendar = holidayCalendar,
       _notifications = notifications;

  final AppDatabase _database;
  final SyncQueueService _syncQueue;
  final String _userId;
  final HolidayCalendar? _holidayCalendar;
  final NotificationService? _notifications;
  final Uuid _uuid = const Uuid();

  Future<String?> runningTimerTaskId() async {
    final timers = await getUnfinishedTimers();
    return timers
        .where((timer) => timer.status == TimerSessionStatus.running)
        .firstOrNull
        ?.taskId;
  }

  /// Compatibility helper for older callers. Multi-timer consumers should use
  /// [getUnfinishedTimers] or [watchUnfinishedTimers] instead.
  Future<List<TimerSessionEntry>> getUnfinishedTimers() async {
    final rows =
        await (_database.select(_database.timerSessionRecords)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.state.equals(TimerSessionStatus.finished.name).not(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
            .get();
    return _latestUnfinishedByTask(rows);
  }

  Stream<List<TimerSessionEntry>> watchUnfinishedTimers() async* {
    final query = _database.select(_database.timerSessionRecords)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.state.equals(TimerSessionStatus.finished.name).not(),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]);
    yield _latestUnfinishedByTask(await query.get());
    yield* query.watch().map(_latestUnfinishedByTask);
  }

  Stream<List<TaskDetails>> watchTasksForDate(DateTime date) async* {
    final query = _database.select(_database.localTasks)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.status.equals(TaskLifecycle.active.name) &
            row.deletedAt.isNull(),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);

    Future<List<TaskDetails>> load(List<LocalTask> tasks) async {
      final details = await Future.wait(
        tasks.map((task) => _loadDetails(task, date)),
      );
      final visible = await Future.wait(
        details.map((task) async {
          if (task.kind == TaskKind.oneTime) {
            return task.scheduledAt == null ||
                localDateKey(task.scheduledAt!.toLocal()) == localDateKey(date);
          }
          return task.schedule != null &&
              await _isDueOn(task.schedule!, task.holidayPause, date);
        }),
      );
      return [
        for (var index = 0; index < details.length; index++)
          if (visible[index]) details[index],
      ];
    }

    // Drift's Web worker can delay the first watch event until a write occurs.
    // Emit an immediate snapshot so consumers never stay in AsyncLoading.
    yield await load(await query.get());
    yield* query.watch().asyncMap(load);
  }

  Stream<List<TaskDetails>> watchTasksByStatus(TaskLifecycle status) {
    final query = _database.select(_database.localTasks)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.status.equals(status.name) &
            row.deletedAt.isNull(),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.watch().asyncMap(
      (tasks) =>
          Future.wait(tasks.map((task) => _loadDetails(task, DateTime.now()))),
    );
  }

  Stream<TaskDetails?> watchTask(String taskId) {
    final query = _database.select(_database.localTasks)
      ..where(
        (row) =>
            row.id.equals(taskId) &
            row.userId.equals(_userId) &
            row.deletedAt.isNull(),
      );
    return query.watchSingleOrNull().asyncMap(
      (task) => task == null ? null : _loadDetails(task, DateTime.now()),
    );
  }

  Stream<List<CompletionHistoryEntry>> watchCompletionHistory(String taskId) {
    final query = _database.select(_database.taskCompletionRecords)
      ..where((row) => row.taskId.equals(taskId) & row.userId.equals(_userId))
      ..orderBy([(row) => OrderingTerm.desc(row.localDate)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => CompletionHistoryEntry(
              localDate: row.localDate,
              progressPercent: row.progressPercent,
              isSuccess: row.isSuccess,
              actualDurationSeconds: row.actualDurationSeconds,
              targetReached: row.targetReached,
              completedAt: row.completedAt?.toLocal(),
            ),
          )
          .toList(),
    );
  }

  Stream<TaskTimerState> watchTimerState(String? taskId, DateTime date) {
    final query = _database.select(_database.timerSessionRecords)
      ..where((row) => row.userId.equals(_userId));
    if (taskId != null) query.where((row) => row.taskId.equals(taskId));
    query.orderBy([(row) => OrderingTerm.desc(row.startedAt)]);
    return query.watch().map(
      (rows) => TaskTimerState(
        localDate: dateOnly(date),
        sessions: rows
            .map(
              (row) => TimerSessionEntry(
                id: row.id,
                taskId: row.taskId,
                startedAt: row.startedAt.toLocal(),
                logicalDate: row.logicalDate,
                endedAt: row.endedAt?.toLocal(),
                durationSeconds: row.durationSeconds,
                status: TimerSessionStatus.values.byName(row.state),
              ),
            )
            .toList(),
      ),
    );
  }

  Stream<CalendarMonthData> watchCalendarMonth(DateTime month) {
    final trigger = _database.customSelect(
      'SELECT 1',
      readsFrom: {
        _database.localTasks,
        _database.longTermTaskRecords,
        _database.taskScheduleRecords,
        _database.oneTimeReminderRecords,
        _database.taskCompletionRecords,
        _database.timerSessionRecords,
        _database.taskRevisionRecords,
      },
    );
    final normalizedMonth = DateTime(month.year, month.month);
    return trigger.watch().asyncMap((_) => _loadCalendarMonth(normalizedMonth));
  }

  Future<TaskDetails?> getTask(String taskId, {DateTime? date}) async {
    final query = _database.select(_database.localTasks)
      ..where(
        (row) =>
            row.id.equals(taskId) &
            row.userId.equals(_userId) &
            row.deletedAt.isNull(),
      );
    final task = await query.getSingleOrNull();
    return task == null ? null : _loadDetails(task, date ?? DateTime.now());
  }

  Future<CalendarMonthData> _loadCalendarMonth(DateTime month) async {
    final monthStart = DateTime(month.year, month.month);
    final monthEnd = DateTime(month.year, month.month + 1);
    final tasks =
        await (_database.select(_database.localTasks)
              ..where(
                (row) => row.userId.equals(_userId) & row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    final longTerms = await (_database.select(
      _database.longTermTaskRecords,
    )..where((row) => row.userId.equals(_userId))).get();
    final schedules = await (_database.select(
      _database.taskScheduleRecords,
    )..where((row) => row.userId.equals(_userId))).get();
    final reminders = await (_database.select(
      _database.oneTimeReminderRecords,
    )..where((row) => row.userId.equals(_userId))).get();
    final completions =
        await (_database.select(_database.taskCompletionRecords)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.localDate.isBiggerOrEqualValue(localDateKey(monthStart)) &
                  row.localDate.isSmallerThanValue(localDateKey(monthEnd)),
            ))
            .get();
    final sessions =
        await (_database.select(_database.timerSessionRecords)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.startedAt.isSmallerThanValue(monthEnd.toUtc()) &
                  (row.endedAt.isNull() |
                      row.endedAt.isBiggerOrEqualValue(monthStart.toUtc())),
            ))
            .get();

    final longTermByTask = {for (final row in longTerms) row.taskId: row};
    final scheduleByTask = {for (final row in schedules) row.taskId: row};
    final revisions =
        await (_database.select(_database.taskRevisionRecords)
              ..where((row) => row.userId.equals(_userId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.changedAt),
                (row) => OrderingTerm.asc(row.rowId),
              ]))
            .get();
    final histories = {
      for (final task in tasks)
        if (longTermByTask.containsKey(task.id) &&
            scheduleByTask.containsKey(task.id))
          task.id: TaskHistory(
            task,
            longTermByTask[task.id]!,
            scheduleByTask[task.id]!,
            revisions.where((row) => row.taskId == task.id).toList(),
          ),
    };
    final reminderByTask = {for (final row in reminders) row.taskId: row};
    final completionByTaskAndDay = {
      for (final row in completions) '${row.taskId}:${row.localDate}': row,
    };
    final sessionsByTask = <String, List<TimerSessionRecord>>{};
    for (final session in sessions) {
      sessionsByTask.putIfAbsent(session.taskId, () => []).add(session);
    }

    final days = <CalendarDayData>[];
    final nowUtc = DateTime.now().toUtc();
    for (
      var day = monthStart;
      day.isBefore(monthEnd);
      day = day.add(const Duration(days: 1))
    ) {
      final dayTasks = <TaskDetails>[];
      for (final task in tasks) {
        final status = TaskLifecycle.values.byName(task.status);
        if (task.taskType == TaskKind.oneTime.name &&
            status != TaskLifecycle.active &&
            day.isAfter(dateOnly(task.updatedAt.toLocal()))) {
          continue;
        }
        final kind = _taskKind(task.taskType);
        if (kind == TaskKind.oneTime) {
          final reminder = reminderByTask[task.id];
          if (reminder == null ||
              !reminder.hasScheduledDate ||
              localDateKey(reminder.scheduledAt.toLocal()) !=
                  localDateKey(day)) {
            continue;
          }
          dayTasks.add(
            TaskDetails(
              id: task.id,
              name: task.name,
              kind: kind,
              colorValue: task.colorValue,
              iconName: task.iconName,
              status: status,
              createdAt: task.createdAt,
              updatedAt: task.updatedAt,
              notes: task.notes,
              scheduledAt: reminder.scheduledAt.toLocal(),
              remindBeforeMinutes: reminder.remindBeforeMinutes,
              oneTimeExecutionMode: reminder.isTimed
                  ? OneTimeExecutionMode.timed
                  : OneTimeExecutionMode.untimed,
              oneTimeCompletedAt: reminder.completedAt?.toLocal(),
              todayActualDurationSeconds: reminder.isTimed
                  ? _durationFromSessionsForDay(
                      sessionsByTask[task.id] ?? const [],
                      day,
                      nowUtc,
                    )
                  : 0,
            ),
          );
          continue;
        }

        final longTerm = longTermByTask[task.id];
        final scheduleRow = scheduleByTask[task.id];
        if (longTerm == null || scheduleRow == null) continue;
        final snapshot = histories[task.id]!.on(day);
        if (snapshot['status'] != 'active') continue;
        final schedule = TaskScheduleRule(
          preset: SchedulePreset.values.byName(
            snapshot['schedule_type'] as String,
          ),
          weekdaysMask: WeekdayMask.fromDays(
            (snapshot['weekdays'] as List).cast<int>(),
          ),
          startsOn: DateTime.parse(snapshot['starts_on'] as String),
          endsOn: DateTime.tryParse(snapshot['ends_on'] as String? ?? ''),
        );
        final holidayPause = snapshot['holiday_pause'] as bool? ?? false;
        if (!await _isDueOn(schedule, holidayPause, day)) continue;
        final executionMode = _recurringMode(snapshot['check_mode'] as String);
        final completion =
            completionByTaskAndDay['${task.id}:${localDateKey(day)}'];
        if (completion?.exclusionReason != null) continue;
        final actualDuration = executionMode != RecurringExecutionMode.untimed
            ? _durationFromSessionsForDay(
                sessionsByTask[task.id] ?? const [],
                day,
                nowUtc,
              )
            : completion?.actualDurationSeconds ?? 0;
        final targetDuration = snapshot['target_duration_seconds'] as int? ?? 0;
        final progress = executionMode == RecurringExecutionMode.timed
            ? targetDuration <= 0
                  ? 0.0
                  : (actualDuration / targetDuration * 100)
                        .clamp(0, 100)
                        .toDouble()
            : completion?.progressPercent ?? 0;
        dayTasks.add(
          TaskDetails(
            id: task.id,
            name: task.name,
            kind: kind,
            colorValue: task.colorValue,
            iconName: task.iconName,
            status: status,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            notes: task.notes,
            recurringMode: executionMode,
            targetDurationSeconds: snapshot['target_duration_seconds'] as int?,
            targetDays: longTerm.targetDays,
            holidayPause: holidayPause,
            scheduledMinuteOfDay: longTerm.scheduledMinuteOfDay,
            reminderMinuteOfDay: longTerm.reminderMinuteOfDay,
            schedule: schedule,
            todayProgressPercent: progress,
            todayActualDurationSeconds: actualDuration,
            todayCompleted: completion?.isSuccess ?? false,
            todayTargetReached:
                completion?.targetReached ??
                (executionMode == RecurringExecutionMode.timed &&
                    targetDuration > 0 &&
                    actualDuration >= targetDuration),
          ),
        );
      }
      days.add(
        CalendarDayData(
          date: day,
          tasks: dayTasks,
          recordedTimedSeconds: _durationFromSessionsForDay(
            sessions,
            day,
            nowUtc,
          ),
        ),
      );
    }
    return CalendarMonthData(month: monthStart, days: days);
  }

  Future<String> saveRecurringTask(
    RecurringTaskDraft draft, {
    String? taskId,
  }) async {
    _validateRecurringDraft(draft);
    final id = taskId ?? _uuid.v4();
    final now = DateTime.now().toUtc();
    final existing = taskId == null ? null : await getTask(taskId);
    await _validateTag(draft.tagId);
    if (taskId != null && existing == null) throw StateError('Task not found');
    if (existing?.hasTimer == true &&
        draft.executionMode == RecurringExecutionMode.untimed) {
      final latest = await _latestTimerSession(id);
      if (latest != null && latest.state != TimerSessionStatus.finished.name) {
        throw StateError('End the active timer before changing task mode.');
      }
    }
    final payload = _recurringPayload(id, draft, now);

    await _database.transaction(() async {
      if (existing == null) {
        await _database
            .into(_database.localTasks)
            .insert(
              LocalTasksCompanion.insert(
                id: id,
                userId: Value(_userId),
                name: draft.name.trim(),
                taskType: TaskKind.recurring.name,
                colorValue: draft.colorValue,
                iconName: Value(draft.iconName),
                notes: Value(_normalizedNotes(draft.notes)),
                tagId: Value(draft.tagId),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (_database.update(
          _database.localTasks,
        )..where((row) => row.id.equals(id))).write(
          LocalTasksCompanion(
            name: Value(draft.name.trim()),
            colorValue: Value(draft.colorValue),
            iconName: Value(draft.iconName),
            tagId: Value(draft.tagId),
            notes: Value(_normalizedNotes(draft.notes)),
            updatedAt: Value(now),
          ),
        );
      }

      await _database
          .into(_database.longTermTaskRecords)
          .insertOnConflictUpdate(
            LongTermTaskRecordsCompanion.insert(
              taskId: id,
              userId: _userId,
              checkMode: draft.executionMode.name,
              targetDurationSeconds: Value(draft.targetDurationSeconds),
              targetDays: Value(draft.targetDays),
              holidayPause: Value(draft.holidayPause),
              scheduledMinuteOfDay: Value(draft.scheduledMinuteOfDay),
              reminderMinuteOfDay: Value(draft.reminderMinuteOfDay),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );

      await _database
          .into(_database.taskScheduleRecords)
          .insertOnConflictUpdate(
            TaskScheduleRecordsCompanion.insert(
              id: id,
              taskId: id,
              userId: _userId,
              scheduleType: draft.schedulePreset.name,
              weekdaysMask: WeekdayMask.fromDays(draft.weekdays),
              startsOn: localDateKey(draft.startsOn),
              endsOn: Value(
                draft.endsOn == null ? null : localDateKey(draft.endsOn!),
              ),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );

      await _writeRevision(
        taskId: id,
        before: existing == null ? null : _detailsToJson(existing),
        after: payload,
        changedAt: now,
      );
      await _syncQueue.enqueue(
        entityType: 'tasks',
        entityId: id,
        operation: SyncOperationType.upsert,
        payload: payload,
        userId: _userId,
      );
    });
    await _syncRecurringReminder(id, draft);
    return id;
  }

  Future<String> saveOneTimeReminder(
    OneTimeReminderDraft draft, {
    String? taskId,
  }) async {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name', '请填写任务名称');
    }
    final id = taskId ?? _uuid.v4();
    final now = DateTime.now().toUtc();
    final existing = taskId == null ? null : await getTask(taskId);
    await _validateTag(draft.tagId);
    if (taskId != null && existing == null) throw StateError('Task not found');
    if (existing?.hasTimer == true &&
        draft.executionMode == OneTimeExecutionMode.untimed) {
      final latest = await _latestTimerSession(id);
      if (latest != null && latest.state != TimerSessionStatus.finished.name) {
        throw StateError('End the active timer before changing task mode.');
      }
    }
    final payload = _oneTimePayload(id, draft, now);

    await _database.transaction(() async {
      if (existing == null) {
        await _database
            .into(_database.localTasks)
            .insert(
              LocalTasksCompanion.insert(
                id: id,
                userId: Value(_userId),
                name: draft.name.trim(),
                taskType: TaskKind.oneTime.name,
                colorValue: draft.colorValue,
                iconName: Value(draft.iconName),
                tagId: Value(draft.tagId),
                notes: Value(_normalizedNotes(draft.notes)),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (_database.update(
          _database.localTasks,
        )..where((row) => row.id.equals(id))).write(
          LocalTasksCompanion(
            name: Value(draft.name.trim()),
            colorValue: Value(draft.colorValue),
            iconName: Value(draft.iconName),
            tagId: Value(draft.tagId),
            notes: Value(_normalizedNotes(draft.notes)),
            updatedAt: Value(now),
          ),
        );
      }

      await _database
          .into(_database.oneTimeReminderRecords)
          .insertOnConflictUpdate(
            OneTimeReminderRecordsCompanion.insert(
              taskId: id,
              userId: _userId,
              scheduledAt: (draft.scheduledAt ?? DateTime.now()).toUtc(),
              hasScheduledDate: Value(draft.scheduledAt != null),
              remindBeforeMinutes: Value(draft.remindBeforeMinutes),
              isTimed: Value(draft.executionMode == OneTimeExecutionMode.timed),
              completedAt: Value(existing?.oneTimeCompletedAt),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );

      await _writeRevision(
        taskId: id,
        before: existing == null ? null : _detailsToJson(existing),
        after: payload,
        changedAt: now,
      );
      await _syncQueue.enqueue(
        entityType: 'tasks',
        entityId: id,
        operation: SyncOperationType.upsert,
        payload: payload,
        userId: _userId,
      );
    });
    await _syncOneTimeReminder(id, draft);
    return id;
  }

  Future<void> toggleRecurringCompletion(String taskId, DateTime date) async {
    final task = await getTask(taskId, date: date);
    if (task == null || task.kind != TaskKind.recurring) {
      throw StateError('Only recurring tasks can be toggled.');
    }
    if (task.schedule == null ||
        !await _isDueOn(task.schedule!, task.holidayPause, date)) {
      throw StateError('Task is not scheduled for this day.');
    }
    final key = localDateKey(date);
    final existingQuery = _database.select(_database.taskCompletionRecords)
      ..where((row) => row.taskId.equals(taskId) & row.localDate.equals(key));
    final existing = await existingQuery.getSingleOrNull();
    final shouldComplete = !(existing?.isSuccess ?? false);
    final now = DateTime.now().toUtc();
    final actualDuration = task.hasTimer
        ? await _durationForLogicalDate(taskId, dateOnly(date), now)
        : 0;
    final target = task.targetDurationSeconds ?? 0;
    final targetReached =
        task.hasDurationTarget && target > 0 && actualDuration >= target;
    final progress = task.hasDurationTarget
        ? (actualDuration / target * 100).clamp(0, 100).toDouble()
        : shouldComplete
        ? 100.0
        : 0.0;

    await _database.transaction(() async {
      await _database
          .into(_database.taskCompletionRecords)
          .insertOnConflictUpdate(
            TaskCompletionRecordsCompanion.insert(
              id: existing?.id ?? _uuid.v4(),
              taskId: taskId,
              userId: _userId,
              localDate: key,
              actualDurationSeconds: Value(actualDuration),
              progressPercent: Value(progress),
              targetReached: Value(targetReached),
              isSuccess: Value(shouldComplete),
              completedAt: Value(shouldComplete ? now : null),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _touchTask(taskId, now);
      await _writeRevision(
        taskId: taskId,
        before: _detailsToJson(task),
        after: {
          ..._detailsToJson(task),
          'local_date': key,
          'is_success': shouldComplete,
          'progress_percent': progress,
          'target_reached': targetReached,
        },
        changedAt: now,
      );
      await _syncQueue.enqueue(
        entityType: 'task_completions',
        entityId: '$taskId:$key',
        operation: SyncOperationType.upsert,
        payload: {
          'task_id': taskId,
          'local_date': key,
          'actual_duration_seconds': actualDuration,
          'progress_percent': progress,
          'target_reached': targetReached,
          'is_success': shouldComplete,
          'completed_at': shouldComplete ? now.toIso8601String() : null,
        },
        userId: _userId,
      );
    });
  }

  Future<void> toggleOneTimeCompletion(String taskId) async {
    final task = await getTask(taskId);
    if (task == null || task.kind != TaskKind.oneTime) {
      throw StateError('Only one-time reminders can be toggled.');
    }
    final now = DateTime.now().toUtc();
    final completedAt = task.oneTimeCompletedAt == null ? now : null;
    await _database.transaction(() async {
      await (_database.update(
        _database.oneTimeReminderRecords,
      )..where((row) => row.taskId.equals(taskId))).write(
        OneTimeReminderRecordsCompanion(
          completedAt: Value(completedAt),
          updatedAt: Value(now),
        ),
      );
      await _touchTask(taskId, now);
      await _writeRevision(
        taskId: taskId,
        before: _detailsToJson(task),
        after: {
          ..._detailsToJson(task),
          'completed_at': completedAt?.toIso8601String(),
        },
        changedAt: now,
      );
      await _syncQueue.enqueue(
        entityType: 'one_time_reminders',
        entityId: taskId,
        operation: SyncOperationType.upsert,
        payload: {
          'task_id': taskId,
          'completed_at': completedAt?.toIso8601String(),
        },
        userId: _userId,
      );
    });
  }

  Future<void> startTimer(String taskId, {DateTime? now}) async {
    final task = await _requireTimerTask(taskId);
    final timestamp = (now ?? DateTime.now()).toUtc();
    final logicalDate = localDateKey(timestamp.toLocal());
    final sessionId = _uuid.v4();
    await _database.transaction(() async {
      final latest = await _latestTimerSession(taskId);
      if (latest != null && latest.state != TimerSessionStatus.finished.name) {
        throw StateError('Timer is already active.');
      }
      await _database
          .into(_database.timerSessionRecords)
          .insert(
            TimerSessionRecordsCompanion.insert(
              id: sessionId,
              taskId: taskId,
              tagId: Value(task.tagId),
              userId: _userId,
              startedAt: timestamp,
              logicalDate: Value(logicalDate),
              state: TimerSessionStatus.running.name,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      await _touchTask(taskId, timestamp);
      await _enqueueTimerSession(
        sessionId: sessionId,
        taskId: taskId,
        startedAt: timestamp,
        status: TimerSessionStatus.running,
      );
    });
  }

  Future<void> pauseTimer(String taskId, {DateTime? now}) async {
    final task = await _requireTimerTask(taskId);
    final timestamp = (now ?? DateTime.now()).toUtc();
    await _database.transaction(() async {
      final session = await _latestTimerSession(taskId);
      if (session == null ||
          session.state != TimerSessionStatus.running.name ||
          session.endedAt != null) {
        throw StateError('Only a running timer can be paused.');
      }
      await _closeTimerSession(session, timestamp, TimerSessionStatus.paused);
      await _refreshTimerCompletions(task, session.startedAt, timestamp);
      await _touchTask(taskId, timestamp);
    });
  }

  Future<void> resumeTimer(String taskId, {DateTime? now}) async {
    final task = await _requireTimerTask(taskId);
    final timestamp = (now ?? DateTime.now()).toUtc();
    final sessionId = _uuid.v4();
    await _database.transaction(() async {
      final paused = await _latestTimerSession(taskId);
      if (paused == null || paused.state != TimerSessionStatus.paused.name) {
        throw StateError('Only a paused timer can be resumed.');
      }
      await (_database.update(
        _database.timerSessionRecords,
      )..where((row) => row.id.equals(paused.id))).write(
        TimerSessionRecordsCompanion(
          state: Value(TimerSessionStatus.finished.name),
          updatedAt: Value(timestamp),
        ),
      );
      await _database
          .into(_database.timerSessionRecords)
          .insert(
            TimerSessionRecordsCompanion.insert(
              id: sessionId,
              taskId: taskId,
              tagId: Value(task.tagId),
              userId: _userId,
              startedAt: timestamp,
              logicalDate: Value(
                paused.logicalDate ?? localDateKey(paused.startedAt.toLocal()),
              ),
              state: TimerSessionStatus.running.name,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      await _touchTask(taskId, timestamp);
      await _enqueueTimerSession(
        sessionId: paused.id,
        taskId: taskId,
        startedAt: paused.startedAt,
        endedAt: paused.endedAt,
        durationSeconds: paused.durationSeconds,
        status: TimerSessionStatus.finished,
      );
      await _enqueueTimerSession(
        sessionId: sessionId,
        taskId: taskId,
        startedAt: timestamp,
        status: TimerSessionStatus.running,
      );
    });
  }

  Future<void> endTimer(String taskId, {DateTime? now}) async {
    final task = await _requireTimerTask(taskId);
    final timestamp = (now ?? DateTime.now()).toUtc();
    await _database.transaction(() async {
      final session = await _latestTimerSession(taskId);
      if (session == null ||
          session.state == TimerSessionStatus.finished.name) {
        throw StateError('There is no active timer to end.');
      }
      if (session.state == TimerSessionStatus.running.name) {
        await _closeTimerSession(
          session,
          timestamp,
          TimerSessionStatus.finished,
        );
        await _refreshTimerCompletions(task, session.startedAt, timestamp);
      } else {
        await (_database.update(
          _database.timerSessionRecords,
        )..where((row) => row.id.equals(session.id))).write(
          TimerSessionRecordsCompanion(
            state: Value(TimerSessionStatus.finished.name),
            updatedAt: Value(timestamp),
          ),
        );
        await _enqueueTimerSession(
          sessionId: session.id,
          taskId: taskId,
          startedAt: session.startedAt,
          endedAt: session.endedAt,
          durationSeconds: session.durationSeconds,
          status: TimerSessionStatus.finished,
        );
      }
      await _touchTask(taskId, timestamp);
    });
  }

  Future<void> archiveTask(
    String taskId, {
    bool endUnfinishedTimer = false,
  }) async {
    final task = await getTask(taskId);
    if (task == null) return;
    final now = DateTime.now().toUtc();
    final activeTimer = task.hasTimer
        ? await _latestTimerSession(taskId)
        : null;
    if (activeTimer != null &&
        activeTimer.state != TimerSessionStatus.finished.name &&
        !endUnfinishedTimer) {
      throw StateError('请先结束计时，再删除事项。');
    }
    await _database.transaction(() async {
      if (activeTimer != null &&
          activeTimer.state == TimerSessionStatus.running.name) {
        await _closeTimerSession(activeTimer, now, TimerSessionStatus.finished);
        await _refreshTimerCompletions(task, activeTimer.startedAt, now);
      } else if (activeTimer != null &&
          activeTimer.state == TimerSessionStatus.paused.name) {
        await (_database.update(
          _database.timerSessionRecords,
        )..where((row) => row.id.equals(activeTimer.id))).write(
          TimerSessionRecordsCompanion(
            state: Value(TimerSessionStatus.finished.name),
            updatedAt: Value(now),
          ),
        );
        await _enqueueTimerSession(
          sessionId: activeTimer.id,
          taskId: taskId,
          startedAt: activeTimer.startedAt,
          endedAt: activeTimer.endedAt,
          durationSeconds: activeTimer.durationSeconds,
          status: TimerSessionStatus.finished,
        );
      }
      await (_database.update(
        _database.localTasks,
      )..where((row) => row.id.equals(taskId))).write(
        LocalTasksCompanion(
          status: Value(TaskLifecycle.archived.name),
          updatedAt: Value(now),
        ),
      );
      await _writeRevision(
        taskId: taskId,
        before: _detailsToJson(task),
        after: {..._detailsToJson(task), 'status': 'archived'},
        changedAt: now,
      );
      await _syncQueue.enqueue(
        entityType: 'tasks',
        entityId: taskId,
        operation: SyncOperationType.archive,
        payload: {'id': taskId, 'status': 'archived'},
        userId: _userId,
      );
    });
    await _cancelReminder(taskId);
  }

  Future<bool> _isDueOn(
    TaskScheduleRule schedule,
    bool holidayPause,
    DateTime date,
  ) {
    return isRecurringTaskDue(
      schedule: schedule,
      holidayPause: holidayPause,
      date: date,
      holidayCalendar: _holidayCalendar,
    );
  }

  Future<void> _syncRecurringReminder(
    String taskId,
    RecurringTaskDraft draft,
  ) async {
    await _cancelReminder(taskId);
    if (_notifications == null || draft.reminderMinuteOfDay == null) return;
    try {
      await _notifications.requestPermissions();
      if (draft.schedulePreset == SchedulePreset.daily) {
        await _notifications.scheduleDaily(
          id: _notificationId(taskId),
          minuteOfDay: draft.reminderMinuteOfDay!,
          title: '任务提醒',
          body: '今天的${draft.name.trim()}还没有完成。',
        );
      } else {
        for (final weekday in draft.weekdays) {
          await _notifications.scheduleWeekly(
            id: _notificationId(taskId, weekday),
            weekday: weekday,
            minuteOfDay: draft.reminderMinuteOfDay!,
            title: '任务提醒',
            body: '今天的${draft.name.trim()}还没有完成。',
          );
        }
      }
    } on Object {
      // A denied system permission must not prevent local task persistence.
    }
  }

  Future<void> _syncOneTimeReminder(
    String taskId,
    OneTimeReminderDraft draft,
  ) async {
    await _cancelReminder(taskId);
    if (_notifications == null ||
        draft.remindBeforeMinutes == null ||
        draft.scheduledAt == null) {
      return;
    }
    try {
      await _notifications.requestPermissions();
      await _notifications.scheduleAt(
        id: _notificationId(taskId),
        when: draft.scheduledAt!.subtract(
          Duration(minutes: draft.remindBeforeMinutes!),
        ),
        title: '事项提醒',
        body: '${draft.name.trim()}即将开始。',
      );
    } on Object {
      // A denied system permission must not prevent local task persistence.
    }
  }

  Future<void> _cancelReminder(String taskId) async {
    if (_notifications == null) return;
    try {
      for (var variant = 0; variant <= DateTime.sunday; variant++) {
        await _notifications.cancel(_notificationId(taskId, variant));
      }
    } on Object {
      // The database remains the source of truth if the OS scheduler fails.
    }
  }

  int _notificationId(String taskId, [int variant = 0]) {
    var value = 2166136261;
    for (final unit in '$taskId:$variant'.codeUnits) {
      value = (value ^ unit) * 16777619 & 0x7fffffff;
    }
    return value;
  }

  Future<TaskDetails> _loadDetails(LocalTask task, DateTime date) async {
    final kind = _taskKind(task.taskType);
    if (kind == TaskKind.recurring) {
      final longTermQuery = _database.select(_database.longTermTaskRecords)
        ..where((row) => row.taskId.equals(task.id));
      final scheduleQuery = _database.select(_database.taskScheduleRecords)
        ..where((row) => row.taskId.equals(task.id));
      final completionQuery = _database.select(_database.taskCompletionRecords)
        ..where(
          (row) =>
              row.taskId.equals(task.id) &
              row.localDate.equals(localDateKey(date)),
        );
      final results = await Future.wait([
        longTermQuery.getSingle(),
        scheduleQuery.getSingle(),
        completionQuery.getSingleOrNull(),
      ]);
      final longTerm = results[0] as LongTermTaskRecord;
      final schedule = results[1] as TaskScheduleRecord;
      final completion = results[2] as TaskCompletionRecord?;
      final executionMode = _recurringMode(longTerm.checkMode);
      final actualDuration = executionMode != RecurringExecutionMode.untimed
          ? await _durationForLogicalDate(
              task.id,
              dateOnly(date),
              DateTime.now().toUtc(),
            )
          : completion?.actualDurationSeconds ?? 0;
      final targetDuration = longTerm.targetDurationSeconds ?? 0;
      final timerProgress = targetDuration <= 0
          ? 0.0
          : (actualDuration / targetDuration * 100).clamp(0, 100).toDouble();
      return TaskDetails(
        id: task.id,
        name: task.name,
        kind: kind,
        colorValue: task.colorValue,
        iconName: task.iconName,
        tagId: task.tagId,
        status: TaskLifecycle.values.byName(task.status),
        notes: task.notes,
        createdAt: task.createdAt,
        updatedAt: task.updatedAt,
        recurringMode: executionMode,
        targetDurationSeconds: longTerm.targetDurationSeconds,
        targetDays: longTerm.targetDays,
        holidayPause: longTerm.holidayPause,
        scheduledMinuteOfDay: longTerm.scheduledMinuteOfDay,
        reminderMinuteOfDay: longTerm.reminderMinuteOfDay,
        schedule: TaskScheduleRule(
          preset: SchedulePreset.values.byName(schedule.scheduleType),
          weekdaysMask: schedule.weekdaysMask,
          startsOn: DateTime.parse(schedule.startsOn),
          endsOn: schedule.endsOn == null
              ? null
              : DateTime.parse(schedule.endsOn!),
        ),
        todayProgressPercent: executionMode == RecurringExecutionMode.timed
            ? timerProgress
            : completion?.progressPercent ?? 0,
        todayActualDurationSeconds: actualDuration,
        todayCompleted: completion?.isSuccess ?? false,
        todayTargetReached:
            completion?.targetReached ??
            (executionMode == RecurringExecutionMode.timed &&
                targetDuration > 0 &&
                actualDuration >= targetDuration),
      );
    }

    final reminderQuery = _database.select(_database.oneTimeReminderRecords)
      ..where((row) => row.taskId.equals(task.id));
    final reminder = await reminderQuery.getSingle();
    return TaskDetails(
      id: task.id,
      name: task.name,
      kind: kind,
      colorValue: task.colorValue,
      iconName: task.iconName,
      tagId: task.tagId,
      status: TaskLifecycle.values.byName(task.status),
      notes: task.notes,
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      scheduledAt: reminder.hasScheduledDate
          ? reminder.scheduledAt.toLocal()
          : null,
      remindBeforeMinutes: reminder.remindBeforeMinutes,
      oneTimeExecutionMode: reminder.isTimed
          ? OneTimeExecutionMode.timed
          : OneTimeExecutionMode.untimed,
      oneTimeCompletedAt: reminder.completedAt?.toLocal(),
      todayActualDurationSeconds: reminder.isTimed
          ? await _durationForLogicalDate(
              task.id,
              dateOnly(date),
              DateTime.now().toUtc(),
            )
          : 0,
    );
  }

  Future<void> _touchTask(String taskId, DateTime now) {
    return (_database.update(_database.localTasks)
          ..where((row) => row.id.equals(taskId)))
        .write(LocalTasksCompanion(updatedAt: Value(now)));
  }

  Future<TaskDetails> _requireTimerTask(String taskId) async {
    final task = await getTask(taskId);
    if (task == null || !task.hasTimer || task.status != TaskLifecycle.active) {
      throw StateError('Only active timer tasks can be timed.');
    }
    return task;
  }

  Future<TimerSessionRecord?> _latestTimerSession(String taskId) {
    final query = _database.select(_database.timerSessionRecords)
      ..where((row) => row.taskId.equals(taskId) & row.userId.equals(_userId))
      ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  List<TimerSessionEntry> _latestUnfinishedByTask(
    List<TimerSessionRecord> rows,
  ) {
    final seenTaskIds = <String>{};
    final timers = <TimerSessionEntry>[];
    for (final row in rows) {
      if (!seenTaskIds.add(row.taskId)) continue;
      timers.add(
        TimerSessionEntry(
          id: row.id,
          taskId: row.taskId,
          startedAt: row.startedAt.toLocal(),
          logicalDate: row.logicalDate,
          endedAt: row.endedAt?.toLocal(),
          durationSeconds: row.durationSeconds,
          status: TimerSessionStatus.values.byName(row.state),
        ),
      );
    }
    return timers;
  }

  Future<void> _closeTimerSession(
    TimerSessionRecord session,
    DateTime endedAt,
    TimerSessionStatus status,
  ) async {
    final duration = endedAt
        .difference(session.startedAt)
        .inSeconds
        .clamp(0, 1 << 31);
    await (_database.update(
      _database.timerSessionRecords,
    )..where((row) => row.id.equals(session.id))).write(
      TimerSessionRecordsCompanion(
        endedAt: Value(endedAt),
        durationSeconds: Value(duration),
        state: Value(status.name),
        updatedAt: Value(endedAt),
      ),
    );
    await _enqueueTimerSession(
      sessionId: session.id,
      taskId: session.taskId,
      startedAt: session.startedAt,
      endedAt: endedAt,
      durationSeconds: duration,
      status: status,
    );
  }

  Future<void> _refreshTimerCompletions(
    TaskDetails task,
    DateTime startedAt,
    DateTime endedAt,
  ) async {
    if (task.kind != TaskKind.recurring) return;
    final session = await _latestTimerSession(task.id);
    final logicalDate =
        session?.logicalDate ?? localDateKey(startedAt.toLocal());
    await _upsertTimerCompletion(task, DateTime.parse(logicalDate), endedAt);
  }

  Future<void> _upsertTimerCompletion(
    TaskDetails task,
    DateTime day,
    DateTime nowUtc,
  ) async {
    final key = localDateKey(day);
    final duration = await _durationForLogicalDate(task.id, day, nowUtc);
    final target = task.targetDurationSeconds ?? 0;
    final progress = target <= 0
        ? 0.0
        : (duration / target * 100).clamp(0, 100).toDouble();
    final targetReached =
        task.hasDurationTarget && target > 0 && duration >= target;
    final query = _database.select(_database.taskCompletionRecords)
      ..where(
        (row) =>
            row.taskId.equals(task.id) &
            row.userId.equals(_userId) &
            row.localDate.equals(key),
      );
    final existing = await query.getSingleOrNull();
    await _database
        .into(_database.taskCompletionRecords)
        .insertOnConflictUpdate(
          TaskCompletionRecordsCompanion.insert(
            id: existing?.id ?? _uuid.v4(),
            taskId: task.id,
            userId: _userId,
            localDate: key,
            actualDurationSeconds: Value(duration),
            progressPercent: Value(progress),
            targetReached: Value(targetReached),
            isSuccess: Value(existing?.isSuccess ?? false),
            completedAt: Value(existing?.completedAt),
            createdAt: existing?.createdAt ?? nowUtc,
            updatedAt: nowUtc,
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'task_completions',
      entityId: '${task.id}:$key',
      operation: SyncOperationType.upsert,
      payload: {
        'task_id': task.id,
        'local_date': key,
        'actual_duration_seconds': duration,
        'progress_percent': progress,
        'target_reached': targetReached,
        'is_success': existing?.isSuccess ?? false,
      },
      userId: _userId,
    );
  }

  Future<int> _durationForLogicalDate(
    String taskId,
    DateTime day,
    DateTime nowUtc,
  ) async {
    final sessions =
        await (_database.select(_database.timerSessionRecords)..where(
              (row) => row.taskId.equals(taskId) & row.userId.equals(_userId),
            ))
            .get();
    final key = localDateKey(day);
    return sessions
        .where(
          (session) =>
              (session.logicalDate ??
                  localDateKey(session.startedAt.toLocal())) ==
              key,
        )
        .fold<int>(
          0,
          (total, session) =>
              total +
              (session.endedAt ?? nowUtc)
                  .difference(session.startedAt)
                  .inSeconds
                  .clamp(0, 1 << 31),
        );
  }

  int _durationFromSessionsForDay(
    List<TimerSessionRecord> sessions,
    DateTime day,
    DateTime nowUtc,
  ) {
    final dayStart = dateOnly(day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var total = 0;
    for (final session in sessions) {
      final start = session.startedAt.toLocal();
      final end = (session.endedAt ?? nowUtc).toLocal();
      final overlapStart = start.isAfter(dayStart) ? start : dayStart;
      final overlapEnd = end.isBefore(dayEnd) ? end : dayEnd;
      if (overlapEnd.isAfter(overlapStart)) {
        total += overlapEnd.difference(overlapStart).inSeconds;
      }
    }
    return total;
  }

  Future<void> _enqueueTimerSession({
    required String sessionId,
    required String taskId,
    required DateTime startedAt,
    required TimerSessionStatus status,
    DateTime? endedAt,
    int durationSeconds = 0,
  }) async {
    final session =
        await (_database.select(_database.timerSessionRecords)..where(
              (row) => row.id.equals(sessionId) & row.userId.equals(_userId),
            ))
            .getSingle();
    return _syncQueue.enqueue(
      entityType: 'timer_sessions',
      entityId: sessionId,
      operation: SyncOperationType.upsert,
      payload: {
        'id': sessionId,
        'task_id': taskId,
        'tag_id': session.tagId,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'duration_seconds': durationSeconds,
        'state': status.name,
      },
      userId: _userId,
    );
  }

  Future<void> _writeRevision({
    required String taskId,
    required Map<String, Object?>? before,
    required Map<String, Object?> after,
    required DateTime changedAt,
  }) {
    return _database
        .into(_database.taskRevisionRecords)
        .insert(
          TaskRevisionRecordsCompanion.insert(
            id: _uuid.v4(),
            taskId: taskId,
            userId: _userId,
            beforeJson: Value(before == null ? null : jsonEncode(before)),
            afterJson: jsonEncode(after),
            changedAt: changedAt,
          ),
        );
  }

  Future<void> _validateTag(String? tagId) async {
    if (tagId == null) return;
    final tag =
        await (_database.select(_database.tagRecords)..where(
              (row) => row.id.equals(tagId) & row.userId.equals(_userId),
            ))
            .getSingleOrNull();
    if (tag == null) throw ArgumentError('Unknown tag');
  }

  void _validateRecurringDraft(RecurringTaskDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name', '请填写任务名称');
    }
    if (draft.weekdays.isEmpty) {
      throw ArgumentError('At least one weekday is required.');
    }
    if (draft.executionMode == RecurringExecutionMode.untimed &&
        draft.targetDurationSeconds != null) {
      throw ArgumentError('Untimed tasks cannot set a target duration.');
    }
    if (draft.targetDurationSeconds != null &&
        draft.targetDurationSeconds! <= 0) {
      throw ArgumentError('Target duration must be positive.');
    }
  }

  String? _normalizedNotes(String? notes) {
    final value = notes?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Map<String, Object?> _recurringPayload(
    String id,
    RecurringTaskDraft draft,
    DateTime updatedAt,
  ) {
    return {
      'id': id,
      'user_id': _userId,
      'name': draft.name.trim(),
      'type': 'long_term',
      'color': draft.colorValue,
      'icon_name': draft.iconName,
      'tag_id': draft.tagId,
      'notes': _normalizedNotes(draft.notes),
      'check_mode': _recurringModeWireValue(draft.executionMode),
      'target_duration_seconds': draft.targetDurationSeconds,
      'target_days': draft.targetDays,
      'holiday_pause': draft.holidayPause,
      'scheduled_minute_of_day': draft.scheduledMinuteOfDay,
      'reminder_minute_of_day': draft.reminderMinuteOfDay,
      'schedule_type': draft.schedulePreset.name,
      'weekdays': _sortedWeekdays(draft.weekdays),
      'starts_on': localDateKey(draft.startsOn),
      'ends_on': draft.endsOn == null ? null : localDateKey(draft.endsOn!),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, Object?> _oneTimePayload(
    String id,
    OneTimeReminderDraft draft,
    DateTime updatedAt,
  ) {
    return {
      'id': id,
      'user_id': _userId,
      'name': draft.name.trim(),
      'type': 'one_time',
      'color': draft.colorValue,
      'icon_name': draft.iconName,
      'tag_id': draft.tagId,
      'notes': _normalizedNotes(draft.notes),
      'scheduled_at': draft.scheduledAt?.toUtc().toIso8601String(),
      'has_scheduled_date': draft.scheduledAt != null,
      'remind_before_minutes': draft.remindBeforeMinutes,
      'is_timed': draft.executionMode == OneTimeExecutionMode.timed,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, Object?> _detailsToJson(TaskDetails task) {
    return {
      'id': task.id,
      'name': task.name,
      'type': task.kind.name,
      'color': task.colorValue,
      'icon_name': task.iconName,
      'tag_id': task.tagId,
      'status': task.status.name,
      'notes': task.notes,
      'check_mode': task.recurringMode == null
          ? null
          : _recurringModeWireValue(task.recurringMode!),
      'target_duration_seconds': task.targetDurationSeconds,
      'target_days': task.targetDays,
      'holiday_pause': task.holidayPause,
      'scheduled_minute_of_day': task.scheduledMinuteOfDay,
      'reminder_minute_of_day': task.reminderMinuteOfDay,
      'schedule_type': task.schedule?.preset.name,
      'weekdays': task.schedule == null
          ? null
          : _sortedWeekdays(WeekdayMask.toDays(task.schedule!.weekdaysMask)),
      'starts_on': task.schedule == null
          ? null
          : localDateKey(task.schedule!.startsOn),
      'ends_on': task.schedule?.endsOn == null
          ? null
          : localDateKey(task.schedule!.endsOn!),
      'scheduled_at': task.scheduledAt?.toUtc().toIso8601String(),
      'remind_before_minutes': task.remindBeforeMinutes,
      'is_timed': task.oneTimeExecutionMode == OneTimeExecutionMode.timed,
      'updated_at': task.updatedAt.toIso8601String(),
    };
  }

  List<int> _sortedWeekdays(Iterable<int> weekdays) {
    final values = weekdays.toList()..sort();
    return values;
  }

  TaskKind _taskKind(String value) {
    return switch (value) {
      'longTerm' || 'long_term' => TaskKind.recurring,
      _ => TaskKind.values.byName(value),
    };
  }

  RecurringExecutionMode _recurringMode(String value) {
    return switch (value) {
      'timer' ||
      'target_timer' ||
      'targetTimer' ||
      'free_timer' ||
      'freeTimer' ||
      'timed' => RecurringExecutionMode.timed,
      'simple' || 'untimed' => RecurringExecutionMode.untimed,
      _ => RecurringExecutionMode.values.byName(value),
    };
  }

  String _recurringModeWireValue(RecurringExecutionMode mode) {
    return switch (mode) {
      RecurringExecutionMode.timed => 'timed',
      RecurringExecutionMode.untimed => 'untimed',
    };
  }
}
