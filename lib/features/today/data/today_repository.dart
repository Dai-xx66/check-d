import 'dart:async';

import '../../calendar/domain/calendar_occurrence_builder.dart';
import '../../courses/data/course_repository.dart';
import '../../courses/data/semester_repository.dart';
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
    required SemesterRepository semesters,
    required DayScheduleRepository schedule,
  }) : _tasks = tasks,
       _courses = courses,
       _semesters = semesters,
       _schedule = schedule;

  final TaskRepository _tasks;
  final CourseRepository _courses;
  final SemesterRepository _semesters;
  final DayScheduleRepository _schedule;

  Stream<TodaySnapshot> watch(DateTime date) {
    final controller = StreamController<TodaySnapshot>();
    List<TaskDetails>? tasks;
    List<CourseDetails>? courses;
    List<SemesterDetails>? semesters;
    List<ScheduleTemplateDetails>? templates;
    List<DailyItemOverride>? overrides;

    void emitIfReady() {
      if (tasks == null ||
          courses == null ||
          semesters == null ||
          templates == null ||
          overrides == null)
        return;
      controller.add(
        TodaySnapshot(
          date: dateOnly(date),
          tasks: tasks!,
          courses: buildCourseItemsForDate(
            date,
            courses!,
            overrides!,
            semesters!,
            templates!,
          ),
          overrides: overrides!,
        ),
      );
    }

    late final StreamSubscription<List<TaskDetails>> taskSub;
    late final StreamSubscription<List<CourseDetails>> courseSub;
    late final StreamSubscription<List<SemesterDetails>> semesterSub;
    late final StreamSubscription<List<ScheduleTemplateDetails>> templateSub;
    late final StreamSubscription<List<DailyItemOverride>> overrideSub;
    taskSub = _tasks.watchTasksForDate(date).listen((value) {
      tasks = value;
      emitIfReady();
    }, onError: controller.addError);
    courseSub = _courses.watchCourses().listen((value) {
      courses = value;
      emitIfReady();
    }, onError: controller.addError);
    semesterSub = _semesters.watchSemesters().listen((value) {
      semesters = value;
      emitIfReady();
    }, onError: controller.addError);
    templateSub = _courses.watchScheduleTemplates().listen((value) {
      templates = value;
      emitIfReady();
    }, onError: controller.addError);
    overrideSub = _schedule.watchOverridesForDate(date).listen((value) {
      overrides = value;
      emitIfReady();
    }, onError: controller.addError);
    controller.onCancel = () async {
      await taskSub.cancel();
      await courseSub.cancel();
      await semesterSub.cancel();
      await templateSub.cancel();
      await overrideSub.cancel();
      await controller.close();
    };
    return controller.stream;
  }
}

/// Today deliberately reuses the Calendar occurrence builder so a course has
/// identical week, segment, cancellation and temporary-edit semantics everywhere.
List<TodayCourseItem> buildCourseItemsForDate(
  DateTime date,
  List<CourseDetails> courses,
  List<DailyItemOverride> overrides, [
  List<SemesterDetails> semesters = const [],
  List<ScheduleTemplateDetails> templates = const [],
]) =>
    buildCourseOccurrencesForDate(
          date: date,
          courses: courses,
          overrides: overrides,
          semesters: semesters,
          templates: templates,
        )
        .map(
          (item) => TodayCourseItem(
            course: item.course!,
            rule: item.courseRule,
            startMinute: item.startMinute!,
            endMinute: item.endMinute!,
            classroom: item.classroom,
          ),
        )
        .toList();
