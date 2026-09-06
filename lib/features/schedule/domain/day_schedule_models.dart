enum DayItemType { recurring, oneTime, course }

enum DayOverrideAction {
  none,
  skip,
  reschedule,
  retarget,
  reminder,
  courseChange,
  extraCourse,
}

enum ReminderKind { due, advance }

enum AlarmBehavior { once, duration, snooze, repeat }

enum AdHocTimerStatus { idle, running, paused, ended }

class DailyItemOverrideDraft {
  const DailyItemOverrideDraft({
    required this.itemType,
    required this.itemId,
    required this.localDate,
    required this.action,
    this.plannedStartMinute,
    this.plannedEndMinute,
    this.reminderMinuteOfDay,
    this.targetDurationSeconds,
    this.temporaryClassroom,
    this.notes,
  });

  final DayItemType itemType;
  final String itemId;
  final DateTime localDate;
  final DayOverrideAction action;
  final int? plannedStartMinute;
  final int? plannedEndMinute;
  final int? reminderMinuteOfDay;
  final int? targetDurationSeconds;
  final String? temporaryClassroom;
  final String? notes;
}

class DailyItemOverride {
  const DailyItemOverride({
    required this.id,
    required this.itemType,
    required this.itemId,
    required this.localDate,
    required this.action,
    required this.createdAt,
    required this.updatedAt,
    this.plannedStartMinute,
    this.plannedEndMinute,
    this.reminderMinuteOfDay,
    this.targetDurationSeconds,
    this.temporaryClassroom,
    this.notes,
  });

  final String id;
  final DayItemType itemType;
  final String itemId;
  final DateTime localDate;
  final DayOverrideAction action;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? plannedStartMinute;
  final int? plannedEndMinute;
  final int? reminderMinuteOfDay;
  final int? targetDurationSeconds;
  final String? temporaryClassroom;
  final String? notes;
}

class ReminderRuleDraft {
  const ReminderRuleDraft({
    required this.ownerType,
    required this.ownerId,
    required this.reminderKind,
    this.enabled = true,
    this.scheduledMinuteOfDay,
    this.remindBeforeMinutes,
    this.localDate,
    this.timezone = 'Asia/Shanghai',
  });

  final DayItemType ownerType;
  final String ownerId;
  final ReminderKind reminderKind;
  final bool enabled;
  final int? scheduledMinuteOfDay;
  final int? remindBeforeMinutes;
  final DateTime? localDate;
  final String timezone;
}

class ReminderRule {
  const ReminderRule({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.reminderKind,
    required this.enabled,
    required this.timezone,
    required this.createdAt,
    required this.updatedAt,
    this.scheduledMinuteOfDay,
    this.remindBeforeMinutes,
    this.localDate,
  });

  final String id;
  final DayItemType ownerType;
  final String ownerId;
  final ReminderKind reminderKind;
  final bool enabled;
  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? scheduledMinuteOfDay;
  final int? remindBeforeMinutes;
  final DateTime? localDate;
}

class AlarmRuleDraft {
  const AlarmRuleDraft({
    required this.ownerType,
    required this.ownerId,
    this.enabled = false,
    this.behavior = AlarmBehavior.once,
    this.soundName,
    this.snoozeMinutes,
    this.repeatIntervalMinutes,
    this.maxRingSeconds,
  });

  final DayItemType ownerType;
  final String ownerId;
  final bool enabled;
  final AlarmBehavior behavior;
  final String? soundName;
  final int? snoozeMinutes;
  final int? repeatIntervalMinutes;
  final int? maxRingSeconds;
}

class AlarmRule {
  const AlarmRule({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.enabled,
    required this.behavior,
    required this.createdAt,
    required this.updatedAt,
    this.soundName,
    this.snoozeMinutes,
    this.repeatIntervalMinutes,
    this.maxRingSeconds,
  });

  final String id;
  final DayItemType ownerType;
  final String ownerId;
  final bool enabled;
  final AlarmBehavior behavior;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? soundName;
  final int? snoozeMinutes;
  final int? repeatIntervalMinutes;
  final int? maxRingSeconds;
}

class AdHocTimerDraft {
  const AdHocTimerDraft({
    required this.title,
    required this.colorValue,
    required this.startedAt,
    this.tagId,
    this.notes,
    this.endedAt,
    this.completedAt,
    this.timerStatus = AdHocTimerStatus.idle,
    this.accumulatedDurationSeconds = 0,
    this.currentStartedAt,
  });

  final String title;
  final int colorValue;
  final DateTime startedAt;
  final String? tagId;
  final String? notes;
  final DateTime? endedAt;
  final DateTime? completedAt;
  final AdHocTimerStatus timerStatus;
  final int accumulatedDurationSeconds;
  final DateTime? currentStartedAt;
}

class AdHocTimerDetails {
  const AdHocTimerDetails({
    required this.id,
    required this.title,
    required this.colorValue,
    required this.startedAt,
    required this.createdAt,
    required this.updatedAt,
    this.tagId,
    this.notes,
    this.endedAt,
    this.completedAt,
    this.timerStatus = AdHocTimerStatus.idle,
    this.accumulatedDurationSeconds = 0,
    this.currentStartedAt,
  });

  final String id;
  final String title;
  final int colorValue;
  final DateTime startedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? tagId;
  final String? notes;
  final DateTime? endedAt;
  final DateTime? completedAt;
  final AdHocTimerStatus timerStatus;
  final int accumulatedDurationSeconds;
  final DateTime? currentStartedAt;

  int durationSecondsForDate(DateTime date, {DateTime? now}) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var seconds = 0;
    if (accumulatedDurationSeconds > 0 &&
        DateTime(startedAt.year, startedAt.month, startedAt.day) == dayStart) {
      seconds += accumulatedDurationSeconds;
    }
    if (timerStatus == AdHocTimerStatus.running && currentStartedAt != null) {
      final start = currentStartedAt!.isAfter(dayStart)
          ? currentStartedAt!
          : dayStart;
      final endValue = now ?? DateTime.now();
      final end = endValue.isBefore(dayEnd) ? endValue : dayEnd;
      if (end.isAfter(start)) seconds += end.difference(start).inSeconds;
    } else if (accumulatedDurationSeconds == 0 && endedAt != null) {
      final start = startedAt.isAfter(dayStart) ? startedAt : dayStart;
      final end = endedAt!.isBefore(dayEnd) ? endedAt! : dayEnd;
      if (end.isAfter(start)) seconds += end.difference(start).inSeconds;
    }
    return seconds;
  }
}
