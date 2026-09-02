enum TaskKind { longTerm, oneTime }

enum TaskLifecycle { active, paused, archived }

enum LongTermCheckMode { timer, simple }

enum TimerSessionStatus { running, paused, finished }

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
    this.todayActualDurationSeconds = 0,
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
  final int todayActualDurationSeconds;
  final bool todayCompleted;

  bool get isTimer => checkMode == LongTermCheckMode.timer;

  bool get isCompleted =>
      kind == TaskKind.oneTime ? oneTimeCompletedAt != null : todayCompleted;
}

class TimerSessionEntry {
  const TimerSessionEntry({
    required this.id,
    required this.startedAt,
    required this.durationSeconds,
    required this.status,
    this.endedAt,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final TimerSessionStatus status;

  int elapsedSecondsAt(DateTime now) {
    if (status != TimerSessionStatus.running || endedAt != null) {
      return durationSeconds;
    }
    return now.difference(startedAt).inSeconds.clamp(0, 1 << 31);
  }
}

class TaskTimerState {
  const TaskTimerState({required this.sessions, required this.localDate});

  final List<TimerSessionEntry> sessions;
  final DateTime localDate;

  TimerSessionEntry? get latest => sessions.isEmpty ? null : sessions.first;
  bool get isRunning => latest?.status == TimerSessionStatus.running;
  bool get isPaused => latest?.status == TimerSessionStatus.paused;
  bool get canStart => !isRunning && !isPaused;

  int elapsedSecondsAt(DateTime now) {
    final dayStart = dateOnly(localDate);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var total = 0;
    for (final session in sessions) {
      final end = session.status == TimerSessionStatus.running
          ? now
          : session.endedAt ?? session.startedAt;
      final overlapStart = session.startedAt.isAfter(dayStart)
          ? session.startedAt
          : dayStart;
      final overlapEnd = end.isBefore(dayEnd) ? end : dayEnd;
      if (overlapEnd.isAfter(overlapStart)) {
        total += overlapEnd.difference(overlapStart).inSeconds;
      }
    }
    return total;
  }

  double progressAt(DateTime now, int targetDurationSeconds) {
    if (targetDurationSeconds <= 0) return 0;
    return (elapsedSecondsAt(now) / targetDurationSeconds * 100).clamp(0, 100);
  }
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

String formatDuration(int totalSeconds) {
  final safeSeconds = totalSeconds.clamp(0, 1 << 31);
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final seconds = safeSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
