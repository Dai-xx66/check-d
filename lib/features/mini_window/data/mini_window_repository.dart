import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../calendar/domain/calendar_models.dart';
import '../../calendar/domain/calendar_occurrence_builder.dart';
import '../../courses/data/course_repository.dart';
import '../../courses/data/semester_repository.dart';
import '../../schedule/data/day_schedule_repository.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/mini_window_models.dart';

class MiniWindowRepository {
  MiniWindowRepository({
    required this.database,
    required this.userId,
    required this.tasks,
    required this.courses,
    required this.semesters,
    required this.schedule,
  });

  final AppDatabase database;
  final String userId;
  final TaskRepository tasks;
  final CourseRepository courses;
  final SemesterRepository semesters;
  final DayScheduleRepository schedule;

  Future<MiniWindowSnapshot> load({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final activeTasks = await tasks
        .watchTasksByStatus(TaskLifecycle.active)
        .first;
    final dateTasks = await tasks.watchTasksForDate(current).first;
    final unfinished = await tasks.getUnfinishedTimers();
    final taskById = {for (final task in activeTasks) task.id: task};
    final timerItems = <MiniTimerItem>[];
    for (final entry in unfinished) {
      final task = taskById[entry.taskId];
      if (task == null) continue;
      final state = await tasks.watchTimerState(entry.taskId, current).first;
      timerItems.add(
        MiniTimerItem(
          id: task.id,
          kind: MiniTimerKind.task,
          title: task.name,
          status: state.timerStatus,
          elapsedSeconds: state.elapsedSecondsAt(current),
          targetSeconds: task.targetDurationSeconds,
          lastActivity: entry.endedAt ?? entry.startedAt,
        ),
      );
    }
    final adHocTimers = await schedule.watchUnfinishedAdHocTimers().first;
    for (final timer in adHocTimers) {
      final status = switch (timer.timerStatus) {
        AdHocTimerStatus.running => TimerStatus.running,
        AdHocTimerStatus.paused => TimerStatus.paused,
        _ => TimerStatus.idle,
      };
      timerItems.add(
        MiniTimerItem(
          id: timer.id,
          kind: MiniTimerKind.adHoc,
          title: timer.title,
          status: status,
          elapsedSeconds: timer.durationSecondsForDate(current, now: current),
          lastActivity: timer.updatedAt,
        ),
      );
    }
    timerItems.sort((a, b) {
      final byState = _timerRank(a.status).compareTo(_timerRank(b.status));
      if (byState != 0) return byState;
      return b.lastActivity.compareTo(a.lastActivity);
    });
    final timedTaskIds = timerItems
        .where((item) => item.kind == MiniTimerKind.task)
        .map((item) => item.id)
        .toSet();

    final effectiveCourses = await _effectiveCoursesForDay(current);
    final courseItems = effectiveCourses
        .map((course) => _toCourseItem(course, current))
        .toList();
    final minute = current.hour * 60 + current.minute;
    final currentCourses = courseItems
        .where((item) => minute >= item.startMinute && minute < item.endMinute)
        .toList();
    var nextCourse = courseItems
        .where((item) => item.startMinute > minute)
        .cast<MiniCourseItem?>()
        .firstOrNull;
    if (nextCourse == null) {
      final tomorrowCourses = await _effectiveCoursesForDay(
        current.add(const Duration(days: 1)),
      );
      nextCourse = tomorrowCourses
          .map((course) => _toCourseItem(course, current))
          .cast<MiniCourseItem?>()
          .firstOrNull;
    }
    return MiniWindowSnapshot(
      now: current,
      currentCourses: currentCourses,
      timers: timerItems,
      nextCourse: nextCourse,
      pendingItems: dateTasks
          .where(
            (task) => !task.isCompleted && !timedTaskIds.contains(task.id),
          )
          .map(
            (task) => MiniPendingItem(
              id: task.id,
              title: task.name,
              targetSeconds: task.targetDurationSeconds,
            ),
          )
          .toList(),
      completedTaskCount: dateTasks.where((task) => task.isCompleted).length,
      totalTaskCount: dateTasks.length,
    );
  }

  Future<List<CalendarOccurrence>> _effectiveCoursesForDay(
    DateTime date,
  ) async {
    final loadedCourses = await courses.loadCourses();
    final templates = await courses.watchScheduleTemplates().first;
    final loadedSemesters = await semesters.watchSemesters().first;
    final overrides = await schedule.loadOverridesForDate(date);
    final occurrences = buildCourseOccurrencesForDate(
      date: date,
      courses: loadedCourses,
      overrides: overrides,
      templates: templates,
      semesters: loadedSemesters,
    );
    return occurrences;
  }

  MiniCourseItem _toCourseItem(CalendarOccurrence occurrence, DateTime now) {
    final start = occurrence.startMinute!;
    final end = occurrence.endMinute!;
    final minute = now.hour * 60 + now.minute;
    final timing =
        occurrence.courseTiming ??
        CourseOccurrenceTiming.single(
          startMinute: start,
          endMinute: end,
          id: occurrence.id,
          label: occurrence.title,
        );
    final phase = timing.phaseAt(minute);
    return MiniCourseItem(
      id: occurrence.id,
      title: occurrence.title,
      date: occurrence.date,
      startMinute: start,
      endMinute: end,
      phase: phase.kind == CourseOccurrencePhaseKind.breakTime
          ? MiniCoursePhase.breakTime
          : MiniCoursePhase.active,
      progress: timing.overallProgressAt(minute),
      timing: timing,
      currentPhase: phase,
      nextSegmentMinute: phase.nextTeachingSegment?.startMinute,
      classroom: occurrence.classroom,
    );
  }

  Future<MiniWindowPreferences> loadPreferences() async {
    final record = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(_preferencesKey))).getSingleOrNull();
    if (record == null) return const MiniWindowPreferences();
    try {
      final value = jsonDecode(record.value) as Map<String, dynamic>;
      return MiniWindowPreferences(
        compact: value['compact'] == true,
        x: (value['x'] as num?)?.toDouble(),
        y: (value['y'] as num?)?.toDouble(),
      );
    } on Object {
      return const MiniWindowPreferences();
    }
  }

  Future<void> savePreferences(MiniWindowPreferences value) {
    return database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _preferencesKey,
            value: jsonEncode({
              'compact': value.compact,
              'x': value.x,
              'y': value.y,
            }),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  String get _preferencesKey => 'mini-window-preferences:$userId';

  static int _timerRank(TimerStatus status) => switch (status) {
    TimerStatus.running => 0,
    TimerStatus.paused => 1,
    TimerStatus.idle => 2,
  };
}
