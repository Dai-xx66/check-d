import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_queue_service.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/day_schedule_models.dart';

class DayScheduleRepository {
  DayScheduleRepository({
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

  Stream<List<DailyItemOverride>> watchOverridesForDate(DateTime date) {
    final query = _database.select(_database.dailyItemOverrideRecords)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.localDate.equals(localDateKey(date)) &
            row.deletedAt.isNull(),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.updatedAt)]);
    return query.watch().map((rows) => rows.map(_toOverride).toList());
  }

  Future<List<DailyItemOverride>> loadOverridesForDate(DateTime date) async {
    final rows =
        await (_database.select(_database.dailyItemOverrideRecords)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.localDate.equals(localDateKey(date)) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.updatedAt)]))
            .get();
    return rows.map(_toOverride).toList();
  }

  Future<String> saveDailyOverride(
    DailyItemOverrideDraft draft, {
    String? overrideId,
  }) async {
    _validateOverride(draft);
    final now = DateTime.now().toUtc();
    final id = overrideId ?? _uuid.v4();
    final localDate = localDateKey(draft.localDate);
    await _database
        .into(_database.dailyItemOverrideRecords)
        .insertOnConflictUpdate(
          DailyItemOverrideRecordsCompanion.insert(
            id: id,
            userId: _userId,
            itemType: draft.itemType.name,
            itemId: draft.itemId,
            localDate: localDate,
            action: draft.action.name,
            plannedStartMinute: Value(draft.plannedStartMinute),
            plannedEndMinute: Value(draft.plannedEndMinute),
            reminderMinuteOfDay: Value(draft.reminderMinuteOfDay),
            targetDurationSeconds: Value(draft.targetDurationSeconds),
            temporaryClassroom: Value(_clean(draft.temporaryClassroom)),
            notes: Value(_clean(draft.notes)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'daily_item_overrides',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: {
        'id': id,
        'item_type': draft.itemType.name,
        'item_id': draft.itemId,
        'local_date': localDate,
        'action': draft.action.name,
        'planned_start_minute': draft.plannedStartMinute,
        'planned_end_minute': draft.plannedEndMinute,
        'reminder_minute_of_day': draft.reminderMinuteOfDay,
        'target_duration_seconds': draft.targetDurationSeconds,
        'temporary_classroom': _clean(draft.temporaryClassroom),
        'notes': _clean(draft.notes),
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  Stream<List<ReminderRule>> watchReminderRules({
    DayItemType? ownerType,
    String? ownerId,
  }) {
    final query = _database.select(_database.reminderRuleRecords)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.deletedAt.isNull() &
            row.enabled.equals(true),
      );
    if (ownerType != null) {
      query.where((row) => row.ownerType.equals(ownerType.name));
    }
    if (ownerId != null) query.where((row) => row.ownerId.equals(ownerId));
    query.orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query.watch().map((rows) => rows.map(_toReminderRule).toList());
  }

  Future<String> saveReminderRule(
    ReminderRuleDraft draft, {
    String? ruleId,
  }) async {
    _validateReminderRule(draft);
    final now = DateTime.now().toUtc();
    final id = ruleId ?? _uuid.v4();
    await _database
        .into(_database.reminderRuleRecords)
        .insertOnConflictUpdate(
          ReminderRuleRecordsCompanion.insert(
            id: id,
            userId: _userId,
            ownerType: draft.ownerType.name,
            ownerId: draft.ownerId,
            reminderKind: draft.reminderKind.name,
            enabled: Value(draft.enabled),
            scheduledMinuteOfDay: Value(draft.scheduledMinuteOfDay),
            remindBeforeMinutes: Value(draft.remindBeforeMinutes),
            localDate: Value(
              draft.localDate == null ? null : localDateKey(draft.localDate!),
            ),
            timezone: Value(draft.timezone),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'reminder_rules',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: {
        'id': id,
        'owner_type': draft.ownerType.name,
        'owner_id': draft.ownerId,
        'reminder_kind': draft.reminderKind.name,
        'enabled': draft.enabled,
        'scheduled_minute_of_day': draft.scheduledMinuteOfDay,
        'remind_before_minutes': draft.remindBeforeMinutes,
        'local_date': draft.localDate == null
            ? null
            : localDateKey(draft.localDate!),
        'timezone': draft.timezone,
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  Future<String> saveAlarmRule(AlarmRuleDraft draft, {String? ruleId}) async {
    _validateAlarmRule(draft);
    final now = DateTime.now().toUtc();
    final id = ruleId ?? _uuid.v4();
    await _database
        .into(_database.alarmRuleRecords)
        .insertOnConflictUpdate(
          AlarmRuleRecordsCompanion.insert(
            id: id,
            userId: _userId,
            ownerType: draft.ownerType.name,
            ownerId: draft.ownerId,
            enabled: Value(draft.enabled),
            behavior: Value(draft.behavior.name),
            soundName: Value(_clean(draft.soundName)),
            snoozeMinutes: Value(draft.snoozeMinutes),
            repeatIntervalMinutes: Value(draft.repeatIntervalMinutes),
            maxRingSeconds: Value(draft.maxRingSeconds),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'alarm_rules',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: {
        'id': id,
        'owner_type': draft.ownerType.name,
        'owner_id': draft.ownerId,
        'enabled': draft.enabled,
        'behavior': draft.behavior.name,
        'sound_name': _clean(draft.soundName),
        'snooze_minutes': draft.snoozeMinutes,
        'repeat_interval_minutes': draft.repeatIntervalMinutes,
        'max_ring_seconds': draft.maxRingSeconds,
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  Future<String> saveAdHocTimer(
    AdHocTimerDraft draft, {
    String? timerId,
  }) async {
    if (draft.title.trim().isEmpty) {
      throw ArgumentError.value(draft.title, 'title', '请填写计时名称');
    }
    final now = DateTime.now().toUtc();
    final id = timerId ?? _uuid.v4();
    await _database
        .into(_database.adHocTimerRecords)
        .insertOnConflictUpdate(
          AdHocTimerRecordsCompanion.insert(
            id: id,
            userId: _userId,
            title: draft.title.trim(),
            tagId: Value(draft.tagId),
            colorValue: draft.colorValue,
            notes: Value(_clean(draft.notes)),
            startedAt: draft.startedAt.toUtc(),
            endedAt: Value(draft.endedAt?.toUtc()),
            completedAt: Value(draft.completedAt?.toUtc()),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _syncQueue.enqueue(
      entityType: 'ad_hoc_timers',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: {
        'id': id,
        'title': draft.title.trim(),
        'tag_id': draft.tagId,
        'color': draft.colorValue,
        'notes': _clean(draft.notes),
        'started_at': draft.startedAt.toUtc().toIso8601String(),
        'ended_at': draft.endedAt?.toUtc().toIso8601String(),
        'completed_at': draft.completedAt?.toUtc().toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      userId: _userId,
    );
    return id;
  }

  DailyItemOverride _toOverride(DailyItemOverrideRecord row) {
    return DailyItemOverride(
      id: row.id,
      itemType: DayItemType.values.byName(row.itemType),
      itemId: row.itemId,
      localDate: DateTime.parse(row.localDate),
      action: DayOverrideAction.values.byName(row.action),
      plannedStartMinute: row.plannedStartMinute,
      plannedEndMinute: row.plannedEndMinute,
      reminderMinuteOfDay: row.reminderMinuteOfDay,
      targetDurationSeconds: row.targetDurationSeconds,
      temporaryClassroom: row.temporaryClassroom,
      notes: row.notes,
      createdAt: row.createdAt.toLocal(),
      updatedAt: row.updatedAt.toLocal(),
    );
  }

  ReminderRule _toReminderRule(ReminderRuleRecord row) {
    return ReminderRule(
      id: row.id,
      ownerType: DayItemType.values.byName(row.ownerType),
      ownerId: row.ownerId,
      reminderKind: ReminderKind.values.byName(row.reminderKind),
      enabled: row.enabled,
      scheduledMinuteOfDay: row.scheduledMinuteOfDay,
      remindBeforeMinutes: row.remindBeforeMinutes,
      localDate: row.localDate == null ? null : DateTime.parse(row.localDate!),
      timezone: row.timezone,
      createdAt: row.createdAt.toLocal(),
      updatedAt: row.updatedAt.toLocal(),
    );
  }

  void _validateOverride(DailyItemOverrideDraft draft) {
    if (draft.itemId.trim().isEmpty) {
      throw ArgumentError.value(draft.itemId, 'itemId', '事项 ID 不能为空');
    }
    if (draft.plannedStartMinute != null || draft.plannedEndMinute != null) {
      if (draft.plannedStartMinute == null || draft.plannedEndMinute == null) {
        throw ArgumentError('开始和结束时间必须同时设置');
      }
      _validateMinuteRange(draft.plannedStartMinute!, draft.plannedEndMinute!);
    }
    if (draft.reminderMinuteOfDay != null &&
        !_isMinuteOfDay(draft.reminderMinuteOfDay!)) {
      throw ArgumentError.value(
        draft.reminderMinuteOfDay,
        'reminderMinuteOfDay',
        '提醒时间无效',
      );
    }
    if (draft.targetDurationSeconds != null &&
        draft.targetDurationSeconds! <= 0) {
      throw ArgumentError.value(
        draft.targetDurationSeconds,
        'targetDurationSeconds',
        '目标时长必须大于 0',
      );
    }
  }

  void _validateReminderRule(ReminderRuleDraft draft) {
    if (draft.ownerId.trim().isEmpty) {
      throw ArgumentError.value(draft.ownerId, 'ownerId', '提醒对象不能为空');
    }
    if (draft.reminderKind == ReminderKind.due &&
        draft.scheduledMinuteOfDay == null) {
      throw ArgumentError.value(
        draft.scheduledMinuteOfDay,
        'scheduledMinuteOfDay',
        '到点提醒必须有固定时间',
      );
    }
    if (draft.scheduledMinuteOfDay != null &&
        !_isMinuteOfDay(draft.scheduledMinuteOfDay!)) {
      throw ArgumentError.value(
        draft.scheduledMinuteOfDay,
        'scheduledMinuteOfDay',
        '固定时间无效',
      );
    }
    if (draft.remindBeforeMinutes != null && draft.remindBeforeMinutes! < 0) {
      throw ArgumentError.value(
        draft.remindBeforeMinutes,
        'remindBeforeMinutes',
        '提前提醒不能小于 0',
      );
    }
  }

  void _validateAlarmRule(AlarmRuleDraft draft) {
    if (draft.ownerId.trim().isEmpty) {
      throw ArgumentError.value(draft.ownerId, 'ownerId', '闹钟对象不能为空');
    }
    if (draft.snoozeMinutes != null && draft.snoozeMinutes! <= 0) {
      throw ArgumentError.value(draft.snoozeMinutes, 'snoozeMinutes');
    }
    if (draft.repeatIntervalMinutes != null &&
        draft.repeatIntervalMinutes! <= 0) {
      throw ArgumentError.value(
        draft.repeatIntervalMinutes,
        'repeatIntervalMinutes',
      );
    }
    if (draft.maxRingSeconds != null && draft.maxRingSeconds! <= 0) {
      throw ArgumentError.value(draft.maxRingSeconds, 'maxRingSeconds');
    }
  }

  void _validateMinuteRange(int start, int end) {
    if (!_isMinuteOfDay(start) || end < 1 || end > 1440 || end <= start) {
      throw ArgumentError('时间段无效');
    }
  }

  bool _isMinuteOfDay(int minute) => minute >= 0 && minute <= 1439;

  String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
