import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/holiday/holiday_calendar.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/plan_models.dart';

class PlanRepository {
  PlanRepository({
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

  Stream<List<PlanDetails>> watchPlans() {
    final query = _database.select(_database.planRecords)
      ..where((row) => row.userId.equals(userId) & row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.startsOn)]);
    return query.watch().asyncMap(
      (plans) => Future.wait(plans.map(_toDetails)),
    );
  }

  Future<String> save(PlanDraft draft, {String? planId}) async {
    _validateDraft(draft);
    await _validateTasks(draft.taskIds);
    final now = DateTime.now().toUtc();
    final id = planId ?? _uuid.v4();
    final existing = planId == null
        ? null
        : await (_database.select(_database.planRecords)..where(
                (row) => row.id.equals(planId) & row.userId.equals(userId),
              ))
              .getSingleOrNull();
    if (planId != null && existing == null) throw StateError('计划不存在');

    await _database.transaction(() async {
      await _database
          .into(_database.planRecords)
          .insertOnConflictUpdate(
            PlanRecordsCompanion.insert(
              id: id,
              userId: userId,
              name: draft.name.trim(),
              type: draft.type.name,
              colorValue: draft.colorValue,
              goal: Value(_cleanGoal(draft.goal)),
              startsOn: localDateKey(draft.startsOn),
              endsOn: localDateKey(draft.endsOn),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await (_database.delete(
        _database.planTaskRecords,
      )..where((row) => row.planId.equals(id))).go();
      for (final taskId in draft.taskIds) {
        await _database
            .into(_database.planTaskRecords)
            .insert(
              PlanTaskRecordsCompanion.insert(
                planId: id,
                taskId: taskId,
                userId: userId,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      final payload = _payload(id, draft, now);
      await _syncQueue.enqueue(
        entityType: 'plans',
        entityId: id,
        operation: SyncOperationType.upsert,
        payload: payload,
        userId: userId,
      );
      await _syncQueue.enqueue(
        entityType: 'plan_tasks',
        entityId: id,
        operation: SyncOperationType.upsert,
        payload: {
          'plan_id': id,
          'user_id': userId,
          'task_ids': draft.taskIds.toList()..sort(),
          'updated_at': now.toIso8601String(),
        },
        userId: userId,
      );
    });
    return id;
  }

  Future<void> archive(String planId) async {
    final now = DateTime.now().toUtc();
    final count =
        await (_database.update(_database.planRecords)..where(
              (row) => row.id.equals(planId) & row.userId.equals(userId),
            ))
            .write(
              PlanRecordsCompanion(
                deletedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
    if (count != 1) throw StateError('计划不存在');
    await _syncQueue.enqueue(
      entityType: 'plans',
      entityId: planId,
      operation: SyncOperationType.archive,
      payload: {'id': planId, 'deleted_at': now.toIso8601String()},
      userId: userId,
    );
  }

  Future<PlanDetails> _toDetails(PlanRecord plan) async {
    final links =
        await (_database.select(_database.planTaskRecords)..where(
              (row) => row.planId.equals(plan.id) & row.userId.equals(userId),
            ))
            .get();
    final taskIds = links.map((link) => link.taskId).toSet();
    if (taskIds.isEmpty) return _details(plan, taskIds, 0, 0);

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
    final completions =
        await (_database.select(_database.taskCompletionRecords)..where(
              (row) => row.userId.equals(userId) & row.isSuccess.equals(true),
            ))
            .get();
    final scheduleByTask = {
      for (final schedule in schedules) schedule.taskId: schedule,
    };
    final longTermByTask = {for (final goal in longTerms) goal.taskId: goal};
    final completionKeys = {
      for (final completion in completions)
        '${completion.taskId}:${completion.localDate}',
    };
    final end = dateOnly(plan.endsOnDate).isAfter(dateOnly(DateTime.now()))
        ? dateOnly(DateTime.now())
        : dateOnly(plan.endsOnDate);
    var dueCount = 0;
    var completedCount = 0;
    for (final task in tasks) {
      if (!taskIds.contains(task.id) ||
          task.taskType != TaskKind.recurring.name) {
        continue;
      }
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
      final start = _maxDate(
        dateOnly(plan.startsOnDate),
        DateTime.parse(schedule.startsOn),
      );
      final scheduleEnd = schedule.endsOn == null
          ? end
          : _minDate(end, DateTime.parse(schedule.endsOn!));
      for (
        var day = start;
        !day.isAfter(scheduleEnd);
        day = day.add(const Duration(days: 1))
      ) {
        if (await isRecurringTaskDue(
          schedule: rule,
          holidayPause: longTerm.holidayPause,
          date: day,
          holidayCalendar: _holidayCalendar,
        )) {
          dueCount++;
          if (completionKeys.contains('${task.id}:${localDateKey(day)}')) {
            completedCount++;
          }
        }
      }
    }
    return _details(plan, taskIds, dueCount, completedCount);
  }

  PlanDetails _details(
    PlanRecord plan,
    Set<String> taskIds,
    int dueCount,
    int completedCount,
  ) => PlanDetails(
    id: plan.id,
    name: plan.name,
    type: PlanType.values.byName(plan.type),
    colorValue: plan.colorValue,
    goal: plan.goal,
    startsOn: plan.startsOnDate,
    endsOn: plan.endsOnDate,
    taskIds: taskIds,
    dueCount: dueCount,
    completedCount: completedCount,
  );

  Future<void> _validateTasks(Set<String> taskIds) async {
    if (taskIds.isEmpty) return;
    final tasks = await (_database.select(
      _database.localTasks,
    )..where((row) => row.userId.equals(userId))).get();
    final recurringIds = tasks
        .where((task) => task.taskType == TaskKind.recurring.name)
        .map((task) => task.id)
        .toSet();
    if (!taskIds.every(recurringIds.contains)) {
      throw ArgumentError('计划只能关联现有的周期任务');
    }
  }

  void _validateDraft(PlanDraft draft) {
    if (draft.name.trim().isEmpty) throw ArgumentError('请填写计划名称');
    if (dateOnly(draft.endsOn).isBefore(dateOnly(draft.startsOn))) {
      throw ArgumentError('结束日期不能早于开始日期');
    }
  }

  String? _cleanGoal(String? goal) {
    final value = goal?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Map<String, Object?> _payload(String id, PlanDraft draft, DateTime now) => {
    'id': id,
    'user_id': userId,
    'name': draft.name.trim(),
    'type': draft.type.name,
    'color': draft.colorValue,
    'goal': _cleanGoal(draft.goal),
    'starts_on': localDateKey(draft.startsOn),
    'ends_on': localDateKey(draft.endsOn),
    'updated_at': now.toIso8601String(),
  };

  DateTime _maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
}

extension on PlanRecord {
  DateTime get startsOnDate => DateTime.parse(startsOn);
  DateTime get endsOnDate => DateTime.parse(endsOn);
}
