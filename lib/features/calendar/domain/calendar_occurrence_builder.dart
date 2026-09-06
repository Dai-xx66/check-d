import '../../courses/domain/course_models.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../tasks/domain/task_models.dart';
import 'calendar_models.dart';

DateTime calendarDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime mondayOfWeek(DateTime value) {
  final day = calendarDateOnly(value);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

int semesterWeekNumberFor(DateTime date, DateTime semesterStart) {
  final start = calendarDateOnly(semesterStart);
  final day = calendarDateOnly(date);
  return day.difference(start).inDays ~/ DateTime.daysPerWeek + 1;
}

int _fallbackIsoWeekNumber(DateTime date) {
  final thursday = calendarDateOnly(date).add(Duration(days: 4 - date.weekday));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstMonday = firstThursday.subtract(
    Duration(days: firstThursday.weekday - 1),
  );
  return calendarDateOnly(
            thursday,
          ).difference(calendarDateOnly(firstMonday)).inDays ~/
          7 +
      1;
}

List<CalendarOccurrence> buildCalendarOccurrencesForDate({
  required DateTime date,
  required List<TaskDetails> tasks,
  required List<CourseDetails> courses,
  required List<DailyItemOverride> overrides,
  List<ScheduleTemplateDetails> templates = const [],
}) {
  final day = calendarDateOnly(date);
  final result = <CalendarOccurrence>[
    ...buildCourseOccurrencesForDate(
      date: day,
      courses: courses,
      overrides: overrides,
      templates: templates,
    ),
  ];

  final overrideByTask = <String, DailyItemOverride>{
    for (final value in overrides)
      if (value.itemType == DayItemType.recurring ||
          value.itemType == DayItemType.oneTime)
        value.itemId: value,
  };

  for (final task in tasks) {
    final override = overrideByTask[task.id];
    if (override?.action == DayOverrideAction.skip) continue;
    final defaultMinute = task.kind == TaskKind.oneTime
        ? task.scheduledAt == null
              ? null
              : task.scheduledAt!.hour * 60 + task.scheduledAt!.minute
        : task.scheduledMinuteOfDay;
    final startMinute = override?.plannedStartMinute ?? defaultMinute;
    final endMinute = override?.plannedEndMinute;
    result.add(
      CalendarOccurrence(
        id: 'task:${task.id}:${day.toIso8601String()}',
        type: task.kind == TaskKind.recurring
            ? CalendarOccurrenceType.recurring
            : CalendarOccurrenceType.oneTime,
        title: task.name,
        date: day,
        colorValue: task.colorValue,
        startMinute: startMinute,
        endMinute: endMinute,
        subtitle: task.kind == TaskKind.recurring ? '重复事项' : '一次性事项',
        task: task,
      ),
    );
  }

  result.sort((a, b) {
    final aMinute = a.startMinute ?? 100000;
    final bMinute = b.startMinute ?? 100000;
    final byTime = aMinute.compareTo(bMinute);
    if (byTime != 0) return byTime;
    return a.title.compareTo(b.title);
  });
  return result;
}

List<CalendarOccurrence> buildCourseOccurrencesForDate({
  required DateTime date,
  required List<CourseDetails> courses,
  required List<DailyItemOverride> overrides,
  List<ScheduleTemplateDetails> templates = const [],
}) {
  final day = calendarDateOnly(date);
  final templateById = {
    for (final template in templates) template.id: template,
  };
  final overrideById = <String, DailyItemOverride>{
    for (final value in overrides)
      if (value.itemType == DayItemType.course) value.itemId: value,
  };
  final result = <CalendarOccurrence>[];

  for (final course in courses) {
    if (course.semesterStartsOn != null &&
        day.isBefore(calendarDateOnly(course.semesterStartsOn!))) {
      continue;
    }
    if (course.semesterEndsOn != null &&
        day.isAfter(calendarDateOnly(course.semesterEndsOn!))) {
      continue;
    }
    final semesterWeek = course.semesterStartsOn == null
        ? _fallbackIsoWeekNumber(day)
        : semesterWeekNumberFor(day, course.semesterStartsOn!);

    for (final rule in course.rules) {
      if (rule.weekday != day.weekday || !rule.isDueInWeek(semesterWeek)) {
        continue;
      }
      final override = overrideById[rule.id] ?? overrideById[course.id];
      if (override?.action == DayOverrideAction.skip) continue;

      var startMinute = rule.startsAtMinute;
      var endMinute = rule.endsAtMinute;
      final template = rule.scheduleTemplateId == null
          ? null
          : templateById[rule.scheduleTemplateId!];
      if (template != null && rule.sectionIds.isNotEmpty) {
        final selected =
            template.segments
                .where((segment) => rule.sectionIds.contains(segment.id))
                .toList()
              ..sort((a, b) => a.startsAtMinute.compareTo(b.startsAtMinute));
        if (selected.isNotEmpty) {
          startMinute = selected.first.startsAtMinute;
          endMinute = selected
              .map((segment) => segment.endsAtMinute)
              .reduce((a, b) => a > b ? a : b);
        }
      }
      startMinute = override?.plannedStartMinute ?? startMinute;
      endMinute = override?.plannedEndMinute ?? endMinute;
      if (endMinute <= startMinute) continue;

      final classroom = override?.temporaryClassroom ?? course.classroom;
      result.add(
        CalendarOccurrence(
          id: 'course:${rule.id}:${day.toIso8601String()}',
          type: CalendarOccurrenceType.course,
          title: course.name,
          date: day,
          colorValue: course.colorValue,
          startMinute: startMinute,
          endMinute: endMinute,
          subtitle: [
            if (classroom != null && classroom.trim().isNotEmpty)
              classroom.trim(),
            '第$semesterWeek周',
          ].join(' · '),
          course: course,
          courseRule: rule,
        ),
      );
    }
  }
  result.sort((a, b) => (a.startMinute ?? 0).compareTo(b.startMinute ?? 0));
  return result;
}
