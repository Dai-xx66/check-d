enum TaskKind { longTerm, oneTime }

enum TaskLifecycle { active, paused, archived }

enum LongTermCheckMode { timer, simple }

enum SchedulePreset { daily, weekdays, weekends, custom }

abstract final class WeekdayMask {
  static const everyDay = 0x7F;
  static const weekdays = 0x1F;
  static const weekends = 0x60;

  static int fromDays(Iterable<int> weekdays) {
    return weekdays.fold(0, (mask, day) => mask | (1 << (day - 1)));
  }

  static Set<int> toDays(int mask) {
    return {
      for (var day = DateTime.monday; day <= DateTime.sunday; day++)
        if (mask & (1 << (day - 1)) != 0) day,
    };
  }

  static bool contains(int mask, int weekday) {
    return mask & (1 << (weekday - 1)) != 0;
  }
}

class TaskScheduleRule {
  const TaskScheduleRule({
    required this.preset,
    required this.weekdaysMask,
    required this.startsOn,
    this.endsOn,
  });

  final SchedulePreset preset;
  final int weekdaysMask;
  final DateTime startsOn;
  final DateTime? endsOn;

  bool isDueOn(DateTime date) {
    final day = dateOnly(date);
    if (day.isBefore(dateOnly(startsOn))) return false;
    if (endsOn != null && day.isAfter(dateOnly(endsOn!))) return false;
    return WeekdayMask.contains(weekdaysMask, day.weekday);
  }
}

class LongTermTaskDraft {
  const LongTermTaskDraft({
    required this.name,
    required this.colorValue,
    required this.checkMode,
    required this.schedulePreset,
    required this.weekdays,
    required this.startsOn,
    required this.holidayPause,
    this.notes,
    this.targetDurationSeconds,
    this.targetDays,
    this.endsOn,
  });

  final String name;
  final int colorValue;
  final String? notes;
  final LongTermCheckMode checkMode;
  final int? targetDurationSeconds;
  final int? targetDays;
  final SchedulePreset schedulePreset;
  final Set<int> weekdays;
  final DateTime startsOn;
  final DateTime? endsOn;
  final bool holidayPause;
}

class OneTimeReminderDraft {
  const OneTimeReminderDraft({
    required this.name,
    required this.colorValue,
    required this.scheduledAt,
    this.remindBeforeMinutes,
    this.notes,
  });

  final String name;
  final int colorValue;
  final DateTime scheduledAt;
  final int? remindBeforeMinutes;
  final String? notes;
}

class TaskDetails {
  const TaskDetails({
    required this.id,
    required this.name,
    required this.kind,
    required this.colorValue,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.checkMode,
    this.targetDurationSeconds,
    this.targetDays,
    this.holidayPause = false,
    this.schedule,
    this.scheduledAt,
    this.remindBeforeMinutes,
    this.oneTimeCompletedAt,
    this.todayProgressPercent = 0,
    this.todayCompleted = false,
  });

  final String id;
  final String name;
  final TaskKind kind;
  final int colorValue;
  final TaskLifecycle status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;
  final LongTermCheckMode? checkMode;
  final int? targetDurationSeconds;
  final int? targetDays;
  final bool holidayPause;
  final TaskScheduleRule? schedule;
  final DateTime? scheduledAt;
  final int? remindBeforeMinutes;
  final DateTime? oneTimeCompletedAt;
  final double todayProgressPercent;
  final bool todayCompleted;

  bool get isTimer => checkMode == LongTermCheckMode.timer;

  bool get isCompleted =>
      kind == TaskKind.oneTime ? oneTimeCompletedAt != null : todayCompleted;
}

class CompletionHistoryEntry {
  const CompletionHistoryEntry({
    required this.localDate,
    required this.progressPercent,
    required this.isSuccess,
    required this.actualDurationSeconds,
    this.completedAt,
  });

  final String localDate;
  final double progressPercent;
  final bool isSuccess;
  final int actualDurationSeconds;
  final DateTime? completedAt;
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String localDateKey(DateTime value) {
  final date = dateOnly(value);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
