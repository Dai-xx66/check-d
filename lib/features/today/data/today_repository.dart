import 'dart:async';

import '../../courses/data/course_repository.dart';
import '../../courses/domain/course_models.dart';
import '../../schedule/data/day_schedule_repository.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/today_models.dart';

class TodayRepository {
  TodayRepository({
    required TaskRepository tasks,
    required CourseRepository courses,
    required DayScheduleRepository schedule,
  }) : _tasks = tasks,
       _courses = courses,
       _schedule = schedule;

  final TaskRepository _tasks;
  final CourseRepository _courses;
  final DayScheduleRepository _schedule;

  Stream<TodaySnapshot> watch(DateTime date) {
    final controller = StreamController<TodaySnapshot>();
    List<TaskDetails>? tasks;
    List<CourseDetails>? courses;
    List<DailyItemOverride>? overrides;

    void emitIfReady() {
      if (tasks == null || courses == null || overrides == null) return;
      controller.add(
        TodaySnapshot(
          date: dateOnly(date),
          tasks: tasks!,
          courses: buildCourseItemsForDate(date, courses!, overrides!),
          overrides: overrides!,
        ),
      );
    }

    late final StreamSubscription<List<TaskDetails>> taskSub;
    late final StreamSubscription<List<CourseDetails>> courseSub;
    late final StreamSubscription<List<DailyItemOverride>> overrideSub;
    taskSub = _tasks.watchTasksForDate(date).listen((value) {
      tasks = value;
      emitIfReady();
    }, onError: controller.addError);
    courseSub = _courses.watchCourses().listen((value) {
      courses = value;
      emitIfReady();
    }, onError: controller.addError);
    overrideSub = _schedule.watchOverridesForDate(date).listen((value) {
      overrides = value;
      emitIfReady();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await taskSub.cancel();
      await courseSub.cancel();
      await overrideSub.cancel();
      await controller.close();
    };
    return controller.stream;
  }
}

List<TodayCourseItem> buildCourseItemsForDate(
  DateTime date,
  List<CourseDetails> courses,
  List<DailyItemOverride> overrides,
) {
  final byRule = {
    for (final override in overrides)
      if (override.itemType == DayItemType.course) override.itemId: override,
  };
  final weekNumber = _isoWeekNumber(date);
  final items = <TodayCourseItem>[];
  for (final course in courses) {
    final day = dateOnly(date);
    if (course.semesterStartsOn != null &&
        day.isBefore(dateOnly(course.semesterStartsOn!))) {
      continue;
    }
    if (course.semesterEndsOn != null &&
        day.isAfter(dateOnly(course.semesterEndsOn!))) {
      continue;
    }
    for (final rule in course.rules) {
      if (rule.weekday != date.weekday || !rule.isDueInWeek(weekNumber)) {
        continue;
      }
      final override = byRule[rule.id] ?? byRule[course.id];
      if (override?.action == DayOverrideAction.skip) continue;
      final start = override?.plannedStartMinute ?? rule.startsAtMinute;
      final end = override?.plannedEndMinute ?? rule.endsAtMinute;
      if (end <= start) continue;
      items.add(
        TodayCourseItem(
          course: course,
          rule: rule,
          startMinute: start,
          endMinute: end,
          classroom: override?.temporaryClassroom ?? course.classroom,
        ),
      );
    }
  }
  return items;
}

int _isoWeekNumber(DateTime date) {
  final thursday = dateOnly(date).add(Duration(days: 4 - date.weekday));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstMonday = firstThursday.subtract(
    Duration(days: firstThursday.weekday - 1),
  );
  return (dateOnly(thursday).difference(dateOnly(firstMonday)).inDays ~/ 7) + 1;
}
