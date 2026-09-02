import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../domain/task_models.dart';

class TaskRepository {
  TaskRepository({
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required String userId,
  }) : _database = database,
       _syncQueue = syncQueue,
       _userId = userId;

  final AppDatabase _database;
  final SyncQueueService _syncQueue;
  final String _userId;
  final Uuid _uuid = const Uuid();

  Stream<List<TaskDetails>> watchTasksForDate(DateTime date) {
    final query = _database.select(_database.localTasks)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.status.equals(TaskLifecycle.active.name) &
            row.deletedAt.isNull(),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);

    return query.watch().asyncMap((tasks) async {
      final details = await Future.wait(
        tasks.map((task) => _loadDetails(task, date)),
      );
      return details.where((task) {
        if (task.kind == TaskKind.oneTime) {
          return task.scheduledAt != null &&
              localDateKey(task.scheduledAt!.toLocal()) == localDateKey(date);
        }
        return task.schedule?.isDueOn(date) ?? false;
      }).toList();
    });
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
              completedAt: row.completedAt?.toLocal(),
            ),
          )
          .toList(),
    );
  }

  Stream<TaskTimerState> watchTimerState(String taskId, DateTime date) {
    final query = _database.select(_database.timerSessionRecords)
      ..where((row) => row.taskId.equals(taskId) & row.userId.equals(_userId))
      ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]);
    return query.watch().map(
      (rows) => TaskTimerState(
        localDate: dateOnly(date),
        sessions: rows
            .map(
              (row) => TimerSessionEntry(
                id: row.id,
                startedAt: row.startedAt.toLocal(),
                endedAt: row.endedAt?.toLocal(),
                durationSeconds: row.durationSeconds,
                status: TimerSessionStatus.values.byName(row.state),
              ),
            )
            .toList(),
      ),
    );
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

  Future<String> saveLongTermTask(
    LongTermTaskDraft draft, {
    String? taskId,
  }) async {
    _validateLongTermDraft(draft);
    final id = taskId ?? _uuid.v4();
    final now = DateTime.now().toUtc();
    final existing = taskId == null ? null : await getTask(taskId);
    if (existing?.isTimer == true &&
        draft.checkMode != LongTermCheckMode.timer) {
      final latest = await _latestTimerSession(id);
      if (latest != null && latest.state != TimerSessionStatus.finished.name) {
        throw StateError('End the active timer before changing task mode.');
      }
    }
    final payload = _longTermPayload(id, draft, now);

    await _database.transaction(() async {
      if (existing == null) {
        await _database
            .into(_database.localTasks)
            .insert(
              LocalTasksCompanion.insert(
                id: id,
                userId: Value(_userId),
                name: draft.name.trim(),
                taskType: TaskKind.longTerm.name,
                colorValue: draft.colorValue,
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
              checkMode: draft.checkMode.name,
              targetDurationSeconds: Value(draft.targetDurationSeconds),
              targetDays: Value(draft.targetDays),
              holidayPause: Value(draft.holidayPause),
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
    return id;
  }

  Future<String> saveOneTimeReminder(
    OneTimeReminderDraft draft, {
    String? taskId,
  }) async {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name', 'Task name is required.');
    }
    final id = taskId ?? _uuid.v4();
    final now = DateTime.now().toUtc();
    final existing = taskId == null ? null : await getTask(taskId);
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
              scheduledAt: draft.scheduledAt.toUtc(),
              remindBeforeMinutes: Value(draft.remindBeforeMinutes),
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
    return id;
  }

  Future<void> toggleSimpleCompletion(String taskId, DateTime date) async {
    final task = await getTask(taskId, date: date);
    if (task == null || task.checkMode != LongTermCheckMode.simple) {
      throw StateError('Only simple long-term tasks can be toggled.');
    }
    final key = localDateKey(date);
    final existingQuery = _database.select(_database.taskCompletionRecords)
      ..where((row) => row.taskId.equals(taskId) & row.localDate.equals(key));
    final existing = await existingQuery.getSingleOrNull();
    final shouldComplete = !(existing?.isSuccess ?? false);
    final now = DateTime.now().toUtc();

    await _database.transaction(() async {
      await _database
          .into(_database.taskCompletionRecords)
          .insertOnConflictUpdate(
            TaskCompletionRecordsCompanion.insert(
              id: existing?.id ?? _uuid.v4(),
              taskId: taskId,
              userId: _userId,
              localDate: key,
              progressPercent: Value(shouldComplete ? 100 : 0),
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
          'progress_percent': shouldComplete ? 100 : 0,
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
          'progress_percent': shouldComplete ? 100 : 0,
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
    await _requireTimerTask(taskId);
    final timestamp = (now ?? DateTime.now()).toUtc();
    final sessionId = _uuid.v4();
    await _database.transaction(() async {
      final latest = await _latestTimerSession(taskId);
      if (latest != null && latest.state != TimerSessionStatus.finished.name) {
        throw StateError('Timer is already active.');
      }
      if (await _runningTimerSession() != null) {
        throw StateError('Another timer is already running.');
      }
      await _database
          .into(_database.timerSessionRecords)
          .insert(
            TimerSessionRecordsCompanion.insert(
              id: sessionId,
              taskId: taskId,
              userId: _userId,
              startedAt: timestamp,
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
    await _requireTimerTask(taskId);
    final timestamp = (now ?? DateTime.now()).toUtc();
    final sessionId = _uuid.v4();
    await _database.transaction(() async {
      final paused = await _latestTimerSession(taskId);
      if (paused == null || paused.state != TimerSessionStatus.paused.name) {
        throw StateError('Only a paused timer can be resumed.');
      }
      if (await _runningTimerSession() != null) {
        throw StateError('Another timer is already running.');
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
              userId: _userId,
              startedAt: timestamp,
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

  Future<void> archiveTask(String taskId) async {
    final task = await getTask(taskId);
    if (task == null) return;
    final now = DateTime.now().toUtc();
    final activeTimer = task.isTimer ? await _latestTimerSession(taskId) : null;
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
  }

  Future<TaskDetails> _loadDetails(LocalTask task, DateTime date) async {
    final kind = TaskKind.values.byName(task.taskType);
    if (kind == TaskKind.longTerm) {
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
      final actualDuration =
          LongTermCheckMode.values.byName(longTerm.checkMode) ==
              LongTermCheckMode.timer
          ? await _durationForDay(
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
        status: TaskLifecycle.values.byName(task.status),
        notes: task.notes,
        createdAt: task.createdAt,
        updatedAt: task.updatedAt,
        checkMode: LongTermCheckMode.values.byName(longTerm.checkMode),
        targetDurationSeconds: longTerm.targetDurationSeconds,
        targetDays: longTerm.targetDays,
        holidayPause: longTerm.holidayPause,
        schedule: TaskScheduleRule(
          preset: SchedulePreset.values.byName(schedule.scheduleType),
          weekdaysMask: schedule.weekdaysMask,
          startsOn: DateTime.parse(schedule.startsOn),
          endsOn: schedule.endsOn == null
              ? null
              : DateTime.parse(schedule.endsOn!),
        ),
        todayProgressPercent:
            LongTermCheckMode.values.byName(longTerm.checkMode) ==
                LongTermCheckMode.timer
            ? timerProgress
            : completion?.progressPercent ?? 0,
        todayActualDurationSeconds: actualDuration,
        todayCompleted:
            LongTermCheckMode.values.byName(longTerm.checkMode) ==
                LongTermCheckMode.timer
            ? targetDuration > 0 && actualDuration >= targetDuration
            : completion?.isSuccess ?? false,
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
      status: TaskLifecycle.values.byName(task.status),
      notes: task.notes,
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      scheduledAt: reminder.scheduledAt.toLocal(),
      remindBeforeMinutes: reminder.remindBeforeMinutes,
      oneTimeCompletedAt: reminder.completedAt?.toLocal(),
    );
  }

  Future<void> _touchTask(String taskId, DateTime now) {
    return (_database.update(_database.localTasks)
          ..where((row) => row.id.equals(taskId)))
        .write(LocalTasksCompanion(updatedAt: Value(now)));
  }

  Future<TaskDetails> _requireTimerTask(String taskId) async {
    final task = await getTask(taskId);
    if (task == null ||
        task.kind != TaskKind.longTerm ||
        task.checkMode != LongTermCheckMode.timer ||
        task.status != TaskLifecycle.active) {
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

  Future<TimerSessionRecord?> _runningTimerSession() {
    final query = _database.select(_database.timerSessionRecords)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.state.equals(TimerSessionStatus.running.name),
      )
      ..limit(1);
    return query.getSingleOrNull();
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
    var day = dateOnly(startedAt.toLocal());
    final lastDay = dateOnly(endedAt.toLocal());
    while (!day.isAfter(lastDay)) {
      await _upsertTimerCompletion(task, day, endedAt);
      day = day.add(const Duration(days: 1));
    }
  }

  Future<void> _upsertTimerCompletion(
    TaskDetails task,
    DateTime day,
    DateTime nowUtc,
  ) async {
    final key = localDateKey(day);
    final duration = await _durationForDay(task.id, day, nowUtc);
    final target = task.targetDurationSeconds ?? 0;
    final progress = target <= 0
        ? 0.0
        : (duration / target * 100).clamp(0, 100).toDouble();
    final success = target > 0 && duration >= target;
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
            isSuccess: Value(success),
            completedAt: Value(
              success ? existing?.completedAt ?? nowUtc : null,
            ),
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
        'is_success': success,
      },
      userId: _userId,
    );
  }

  Future<int> _durationForDay(
    String taskId,
    DateTime day,
    DateTime nowUtc,
  ) async {
    final sessions =
        await (_database.select(_database.timerSessionRecords)..where(
              (row) => row.taskId.equals(taskId) & row.userId.equals(_userId),
            ))
            .get();
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
  }) {
    return _syncQueue.enqueue(
      entityType: 'timer_sessions',
      entityId: sessionId,
      operation: SyncOperationType.upsert,
      payload: {
        'id': sessionId,
        'task_id': taskId,
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

  void _validateLongTermDraft(LongTermTaskDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name', 'Task name is required.');
    }
    if (draft.weekdays.isEmpty) {
      throw ArgumentError('At least one weekday is required.');
    }
    if (draft.checkMode == LongTermCheckMode.timer &&
        (draft.targetDurationSeconds ?? 0) <= 0) {
      throw ArgumentError('Timer tasks require a positive duration.');
    }
  }

  String? _normalizedNotes(String? notes) {
    final value = notes?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Map<String, Object?> _longTermPayload(
    String id,
    LongTermTaskDraft draft,
    DateTime updatedAt,
  ) {
    return {
      'id': id,
      'user_id': _userId,
      'name': draft.name.trim(),
      'type': 'long_term',
      'color': draft.colorValue,
      'notes': _normalizedNotes(draft.notes),
      'check_mode': draft.checkMode.name,
      'target_duration_seconds': draft.targetDurationSeconds,
      'target_days': draft.targetDays,
      'holiday_pause': draft.holidayPause,
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
      'notes': _normalizedNotes(draft.notes),
      'scheduled_at': draft.scheduledAt.toUtc().toIso8601String(),
      'remind_before_minutes': draft.remindBeforeMinutes,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, Object?> _detailsToJson(TaskDetails task) {
    return {
      'id': task.id,
      'name': task.name,
      'type': task.kind.name,
      'color': task.colorValue,
      'status': task.status.name,
      'notes': task.notes,
      'check_mode': task.checkMode?.name,
      'target_duration_seconds': task.targetDurationSeconds,
      'target_days': task.targetDays,
      'holiday_pause': task.holidayPause,
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
      'updated_at': task.updatedAt.toIso8601String(),
    };
  }

  List<int> _sortedWeekdays(Iterable<int> weekdays) {
    final values = weekdays.toList()..sort();
    return values;
  }
}
