import '../../features/calendar/domain/calendar_models.dart';
import '../../features/calendar/domain/calendar_occurrence_builder.dart';
import '../../features/courses/data/course_repository.dart';
import '../../features/courses/data/semester_repository.dart';
import '../../features/schedule/data/day_schedule_repository.dart';
import '../../features/schedule/domain/day_schedule_models.dart';
import '../../features/tasks/data/task_repository.dart';
import '../../features/tasks/domain/task_models.dart';
import 'notification_service.dart';

enum ScheduledReminderKind { advance, atTime }

class ReminderScheduler {
  ReminderScheduler({
    required NotificationPlatformService notifications,
    required TaskRepository tasks,
    required CourseRepository courses,
    required SemesterRepository semesters,
    required DayScheduleRepository schedule,
    this.horizonDays = 14,
  }) : _notifications = notifications,
       _tasks = tasks,
       _courses = courses,
       _semesters = semesters,
       _schedule = schedule;

  final NotificationPlatformService _notifications;
  final TaskRepository _tasks;
  final CourseRepository _courses;
  final SemesterRepository _semesters;
  final DayScheduleRepository _schedule;
  final int horizonDays;
  bool _refreshing = false;
  bool _refreshQueued = false;

  Future<void> refreshFuture({DateTime? now}) async {
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    try {
      NotificationPermissionState permission;
      try {
        permission = await _notifications.permissionState();
      } on Object {
        // The platform plugin can be unavailable in widget tests and on Web.
        // Keep saved settings and retry on the next lifecycle/data refresh.
        return;
      }
      if (permission != NotificationPermissionState.granted) return;
      final current = now ?? DateTime.now();
      final courses = await _courses.loadCourses();
      final templates = await _courses.watchScheduleTemplates().first;
      final semesters = await _semesters.watchSemesters().first;
      final rules = await _schedule.loadReminderRules();

      // This also removes legacy daily/weekly schedules made by pre-Stage 8
      // builds. Every future notification is immediately rebuilt below.
      await _notifications.cancelAllPending();
      for (var offset = 0; offset < horizonDays; offset++) {
        final day = calendarDateOnly(current).add(Duration(days: offset));
        final tasks = await _tasks.watchTasksForDate(day).first;
        final overrides = await _schedule.loadOverridesForDate(day);
        final occurrences = buildCalendarOccurrencesForDate(
          date: day,
          tasks: tasks,
          courses: courses,
          overrides: overrides,
          templates: templates,
          semesters: semesters,
        );
        for (final occurrence in occurrences) {
          await _scheduleOccurrence(
            occurrence: occurrence,
            overrides: overrides,
            rules: rules,
            now: current,
          );
        }
      }
    } finally {
      _refreshing = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        await refreshFuture(now: now);
      }
    }
  }

  Future<void> _scheduleOccurrence({
    required CalendarOccurrence occurrence,
    required List<DailyItemOverride> overrides,
    required List<ReminderRule> rules,
    required DateTime now,
  }) async {
    final minute = occurrence.startMinute;
    if (minute == null) return;
    final start = DateTime(
      occurrence.date.year,
      occurrence.date.month,
      occurrence.date.day,
      minute ~/ 60,
      minute % 60,
    );
    final config = _configurationFor(occurrence, overrides, rules);
    for (final kind in ScheduledReminderKind.values) {
      final advance = kind == ScheduledReminderKind.advance
          ? config.advanceMinutes
          : 0;
      if (kind == ScheduledReminderKind.advance && advance == null) continue;
      if (kind == ScheduledReminderKind.atTime && !config.atTimeEnabled) {
        continue;
      }
      final when = start.subtract(Duration(minutes: advance ?? 0));
      // No catch-up: a past advance notification is never recreated.
      if (!when.isAfter(now)) continue;
      final id = notificationId(
        entityType: occurrence.type.name,
        entityId: _ownerId(occurrence),
        occurrenceId: occurrence.id,
        date: occurrence.date,
        kind: kind,
      );
      await _notifications.scheduleAt(
        id: id,
        when: when,
        title: occurrence.title,
        body: _bodyFor(occurrence, kind, advance),
      );
    }
  }

  _ReminderConfiguration _configurationFor(
    CalendarOccurrence occurrence,
    List<DailyItemOverride> overrides,
    List<ReminderRule> rules,
  ) {
    final ownerType = switch (occurrence.type) {
      CalendarOccurrenceType.course => DayItemType.course,
      CalendarOccurrenceType.recurring => DayItemType.recurring,
      CalendarOccurrenceType.oneTime => DayItemType.oneTime,
    };
    final ownerId = _ownerId(occurrence);
    final occurrenceOverride = overrides.where((override) {
      if (override.itemType != ownerType ||
          calendarDateOnly(override.localDate) !=
              calendarDateOnly(occurrence.date)) {
        return false;
      }
      if (occurrence.type == CalendarOccurrenceType.course) {
        return override.itemId == ownerId ||
            override.itemId == occurrence.course?.id ||
            occurrence.id == 'course-extra:${override.id}';
      }
      return override.itemId == ownerId;
    }).firstOrNull;
    final overrideMinute = occurrenceOverride?.reminderMinuteOfDay;
    if (overrideMinute != null && occurrence.startMinute != null) {
      final startMinute = occurrence.startMinute!;
      if (overrideMinute <= startMinute) {
        return _ReminderConfiguration(
          advanceMinutes: overrideMinute == startMinute
              ? null
              : startMinute - overrideMinute,
          atTimeEnabled: overrideMinute == startMinute,
        );
      }
    }
    final dateRules = rules
        .where(
          (rule) =>
              rule.ownerType == ownerType &&
              rule.ownerId == ownerId &&
              calendarDateOnly(rule.localDate ?? DateTime(1)) ==
                  calendarDateOnly(occurrence.date),
        )
        .toList();
    final defaultRules = rules
        .where(
          (rule) =>
              rule.ownerType == ownerType &&
              rule.ownerId == ownerId &&
              rule.localDate == null,
        )
        .toList();
    final selected = dateRules.isNotEmpty ? dateRules : defaultRules;
    if (selected.isNotEmpty) {
      final advance = selected.where(
        (rule) => rule.reminderKind == ReminderKind.advance && rule.enabled,
      );
      final atTime = selected.any(
        (rule) => rule.reminderKind == ReminderKind.due && rule.enabled,
      );
      return _ReminderConfiguration(
        advanceMinutes: advance.isEmpty
            ? null
            : advance.first.remindBeforeMinutes,
        atTimeEnabled: atTime,
      );
    }

    // Legacy fields remain a read-only compatibility fallback. New edits use
    // ReminderRule and therefore always distinguish advance and at-time.
    if (occurrence.type == CalendarOccurrenceType.course) {
      return _ReminderConfiguration(
        advanceMinutes: occurrence.courseRule?.remindBeforeMinutes,
      );
    }
    final task = occurrence.task;
    if (task == null) return const _ReminderConfiguration();
    if (task.kind == TaskKind.oneTime) {
      return _ReminderConfiguration(advanceMinutes: task.remindBeforeMinutes);
    }
    final legacyMinute = task.reminderMinuteOfDay;
    final start = occurrence.startMinute;
    if (legacyMinute == null || start == null || legacyMinute > start) {
      return const _ReminderConfiguration();
    }
    return _ReminderConfiguration(
      advanceMinutes: legacyMinute == start ? null : start - legacyMinute,
      atTimeEnabled: legacyMinute == start,
    );
  }

  String _ownerId(CalendarOccurrence occurrence) =>
      occurrence.type == CalendarOccurrenceType.course
      ? occurrence.courseRule?.id ?? occurrence.course?.id ?? occurrence.id
      : occurrence.task?.id ?? occurrence.id;

  String _bodyFor(
    CalendarOccurrence occurrence,
    ScheduledReminderKind kind,
    int? advance,
  ) {
    final isCourse = occurrence.type == CalendarOccurrenceType.course;
    if (kind == ScheduledReminderKind.advance) {
      return '${occurrence.title}将在${advance ?? 0}分钟后开始';
    }
    return isCourse ? '${occurrence.title}开始了' : '该开始${occurrence.title}了';
  }
}

int notificationId({
  required String entityType,
  required String entityId,
  required String occurrenceId,
  required DateTime date,
  required ScheduledReminderKind kind,
}) {
  final value =
      '$entityType:$entityId:$occurrenceId:'
      '${date.year}-${date.month}-${date.day}:${kind.name}';
  var hash = 0x811c9dc5;
  for (final code in value.codeUnits) {
    hash ^= code;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

class _ReminderConfiguration {
  const _ReminderConfiguration({
    this.advanceMinutes,
    this.atTimeEnabled = false,
  });
  final int? advanceMinutes;
  final bool atTimeEnabled;
}
