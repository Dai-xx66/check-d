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
  List<SemesterDetails> semesters = const [],
}) {
  final day = calendarDateOnly(date);
  final result = <CalendarOccurrence>[
    ...buildCourseOccurrencesForDate(
      date: day,
      courses: courses,
      overrides: overrides,
      templates: templates,
      semesters: semesters,
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
  List<SemesterDetails> semesters = const [],
}) {
  final day = calendarDateOnly(date);
  final templateById = {
    for (final template in templates) template.id: template,
  };
  final semesterById = {
    for (final semester in semesters) semester.id: semester,
  };
  final overrideById = <String, DailyItemOverride>{
    for (final value in overrides)
      if (value.itemType == DayItemType.course) value.itemId: value,
  };
  final result = <CalendarOccurrence>[];

  // Extra lessons are date-specific course occurrences. They intentionally
  // share DailyItemOverride storage with a one-off reschedule/cancellation so
  // every calendar view consumes one effective occurrence stream.
  for (final override in overrides) {
    if (override.itemType != DayItemType.course ||
        override.action != DayOverrideAction.extraCourse ||
        override.plannedStartMinute == null ||
        override.plannedEndMinute == null ||
        override.plannedEndMinute! <= override.plannedStartMinute!) {
      continue;
    }
    final course = courses
        .where((item) => item.id == override.itemId)
        .firstOrNull;
    if (course == null) continue;
    result.add(
      CalendarOccurrence(
        id: 'course-extra:${override.id}',
        type: CalendarOccurrenceType.course,
        title: '${course.name}补课',
        date: day,
        colorValue: course.colorValue,
        startMinute: override.plannedStartMinute,
        endMinute: override.plannedEndMinute,
        subtitle: [
          if ((override.temporaryClassroom ?? course.classroom)
                  ?.trim()
                  .isNotEmpty ??
              false)
            (override.temporaryClassroom ?? course.classroom)!.trim(),
          if (override.notes?.trim().isNotEmpty ?? false)
            override.notes!.trim(),
        ].join(' · '),
        course: course,
        classroom: override.temporaryClassroom ?? course.classroom,
        courseTiming: CourseOccurrenceTiming.single(
          startMinute: override.plannedStartMinute!,
          endMinute: override.plannedEndMinute!,
          id: 'extra:${override.id}',
          label: '${course.name}补课',
        ),
      ),
    );
  }

  for (final course in courses) {
    final semester = course.semesterId == null
        ? null
        : semesterById[course.semesterId];

    for (final rule in course.rules) {
      final semesterWeek = courseWeekNumberForDate(
        course: course,
        semester: semester,
        date: day,
      );
      if (semesterWeek == null ||
          !isCourseRuleActiveOnDate(
            rule: rule,
            semesterWeek: semesterWeek,
            date: day,
          )) {
        continue;
      }
      final override = overrideById[rule.id] ?? overrideById[course.id];
      if (override?.action == DayOverrideAction.skip) continue;

      var timing = CourseOccurrenceTiming.single(
        startMinute: rule.startsAtMinute,
        endMinute: rule.endsAtMinute,
        id: rule.id,
        label: course.name,
      );
      final template =
          rule.timeMode != CourseScheduleTimeMode.periods ||
              rule.scheduleTemplateId == null
          ? null
          : templateById[rule.scheduleTemplateId!];
      if (template != null && rule.sectionIds.isNotEmpty) {
        final selected =
            template.segments
                .where(
                  (segment) =>
                      rule.sectionIds.contains(segment.id) &&
                      segment.segmentType == ScheduleSegmentType.classTime,
                )
                .toList()
              ..sort((a, b) => a.startsAtMinute.compareTo(b.startsAtMinute));
        if (selected.isNotEmpty) {
          timing = CourseOccurrenceTiming.fromTeachingSegments(
            selected
                .map(
                  (segment) => CourseTeachingSegment(
                    id: segment.id,
                    label: segment.name,
                    startMinute: segment.startsAtMinute,
                    endMinute: segment.endsAtMinute,
                    index: 0,
                    total: selected.length,
                  ),
                )
                .toList(),
          );
        }
      }
      if (override?.plannedStartMinute != null ||
          override?.plannedEndMinute != null) {
        final startMinute = override?.plannedStartMinute;
        final endMinute = override?.plannedEndMinute;
        if (startMinute == null ||
            endMinute == null ||
            endMinute <= startMinute) {
          continue;
        }
        timing = CourseOccurrenceTiming.single(
          startMinute: startMinute,
          endMinute: endMinute,
          id: 'override:${override!.id}',
          label: course.name,
        );
      }
      final startMinute = timing.startMinute;
      final endMinute = timing.endMinute;
      if (endMinute <= startMinute) continue;

      final classroom =
          override?.temporaryClassroom ??
          rule.classroomOverride ??
          course.classroom;
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
          classroom: classroom,
          courseTiming: timing,
        ),
      );
    }
  }
  result.sort((a, b) => (a.startMinute ?? 0).compareTo(b.startMinute ?? 0));
  return result;
}

bool isCourseRuleActiveOnDate({
  required CourseScheduleRule rule,
  required int semesterWeek,
  required DateTime date,
}) =>
    rule.weekday == calendarDateOnly(date).weekday &&
    rule.isDueInWeek(semesterWeek);

/// Applies an explicit semester first-week date. Courses created before the
/// semester model retain their former bounded time-only behavior.
int? courseWeekNumberForDate({
  required CourseDetails course,
  required SemesterDetails? semester,
  required DateTime date,
}) {
  final day = calendarDateOnly(date);
  if (semester != null) {
    final start = calendarDateOnly(semester.firstWeekStartDate);
    final end = start.add(Duration(days: semester.totalWeeks * 7 - 1));
    if (day.isBefore(start) || day.isAfter(end)) return null;
    return semester.weekNumberFor(day);
  }
  if (course.semesterStartsOn != null &&
      day.isBefore(calendarDateOnly(course.semesterStartsOn!)))
    return null;
  if (course.semesterEndsOn != null &&
      day.isAfter(calendarDateOnly(course.semesterEndsOn!)))
    return null;
  return course.semesterStartsOn == null
      ? _fallbackIsoWeekNumber(day)
      : semesterWeekNumberFor(day, course.semesterStartsOn!);
}
