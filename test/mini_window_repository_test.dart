import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/mini_window/data/mini_window_repository.dart';
import 'package:check_d/features/mini_window/domain/mini_window_models.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late SyncQueueService syncQueue;
  late CourseRepository courses;
  late SemesterRepository semesters;
  late DayScheduleRepository schedule;
  late TaskRepository tasks;
  late MiniWindowRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    syncQueue = SyncQueueService(database);
    courses = CourseRepository(
      database: database,
      syncQueue: syncQueue,
      userId: 'mini-user',
    );
    semesters = SemesterRepository(
      database: database,
      syncQueue: syncQueue,
      userId: 'mini-user',
    );
    schedule = DayScheduleRepository(
      database: database,
      syncQueue: syncQueue,
      userId: 'mini-user',
    );
    tasks = TaskRepository(
      database: database,
      syncQueue: syncQueue,
      userId: 'mini-user',
    );
    repository = MiniWindowRepository(
      database: database,
      userId: 'mini-user',
      tasks: tasks,
      courses: courses,
      semesters: semesters,
      schedule: schedule,
    );
  });

  tearDown(() => database.close());

  test(
    'keeps running timers before paused timers in stable activity order',
    () async {
      final day = DateTime(2026, 9, 8);
      final first = await _saveTimerTask(tasks, '第一项', day);
      final second = await _saveTimerTask(tasks, '第二项', day);

      await tasks.startTimer(first, now: DateTime(2026, 9, 8, 10));
      await tasks.startTimer(second, now: DateTime(2026, 9, 8, 10, 1));
      await tasks.pauseTimer(second, now: DateTime(2026, 9, 8, 10, 3));

      final snapshot = await repository.load(now: DateTime(2026, 9, 8, 10, 5));

      expect(snapshot.timers.map((item) => item.title), ['第一项', '第二项']);
      expect(snapshot.timers.first.status, TimerStatus.running);
      expect(snapshot.timers.last.status, TimerStatus.paused);
      expect(snapshot.timers.first.hoverAction, MiniTimerQuickAction.pause);
      expect(snapshot.timers.last.hoverAction, MiniTimerQuickAction.resume);
      expect(snapshot.pendingItems, isEmpty);
      expect(snapshot.completedTaskCount, 0);
      expect(snapshot.totalTaskCount, 2);
    },
  );

  test('filters running and paused task occurrences from next items', () async {
    final day = DateTime(2026, 9, 8);
    final running = await _saveTimerTask(tasks, '正在计时', day);
    await _saveTimerTask(tasks, '仍待完成', day);
    final paused = await _saveTimerTask(tasks, '已经暂停', day);

    await tasks.startTimer(running, now: DateTime(2026, 9, 8, 10));
    await tasks.startTimer(paused, now: DateTime(2026, 9, 8, 10, 1));
    await tasks.pauseTimer(paused, now: DateTime(2026, 9, 8, 10, 2));

    final snapshot = await repository.load(now: DateTime(2026, 9, 8, 10, 5));

    expect(snapshot.runningTimers.map((item) => item.title), ['正在计时']);
    expect(snapshot.pausedTimers.map((item) => item.title), ['已经暂停']);
    expect(snapshot.pendingItems.map((item) => item.title), ['仍待完成']);
  });

  test(
    'shows a period course gap as a break and honors a time override',
    () async {
      final day = DateTime(2026, 9, 8);
      final templateId = await courses.saveScheduleTemplate(
        const ScheduleTemplateDraft(
          name: '测试作息',
          segments: [
            ScheduleTemplateSegmentDraft(
              name: '第1节',
              startsAtMinute: 8 * 60,
              endsAtMinute: 8 * 60 + 45,
            ),
            ScheduleTemplateSegmentDraft(
              name: '课间',
              startsAtMinute: 8 * 60 + 45,
              endsAtMinute: 8 * 60 + 55,
              segmentType: ScheduleSegmentType.breakTime,
            ),
            ScheduleTemplateSegmentDraft(
              name: '第2节',
              startsAtMinute: 8 * 60 + 55,
              endsAtMinute: 9 * 60 + 40,
            ),
          ],
        ),
      );
      final template = (await courses.watchScheduleTemplates().first).single;
      final classSegments = template.segments
          .where(
            (segment) => segment.segmentType == ScheduleSegmentType.classTime,
          )
          .toList();
      final semesterId = await semesters.saveSemester(
        SemesterDraft(
          name: '测试学期',
          firstWeekStartDate: DateTime(2026, 9, 7),
          totalWeeks: 20,
          scheduleTemplateId: templateId,
          isCurrent: true,
        ),
      );
      final courseId = await courses.saveCourse(
        CourseDraft(
          name: '数据结构',
          colorValue: 0xff8ba9f0,
          semesterId: semesterId,
        ),
      );
      final ruleId = await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: DateTime.tuesday,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: 8 * 60,
          endsAtMinute: 9 * 60 + 40,
          scheduleTemplateId: templateId,
          sectionIds: classSegments.map((segment) => segment.id).toList(),
          timeMode: CourseScheduleTimeMode.periods,
        ),
      );

      final duringBreak = await repository.load(
        now: DateTime(2026, 9, 8, 8, 50),
      );
      expect(duringBreak.currentCourses, hasLength(1));
      expect(
        duringBreak.currentCourses.single.phase,
        MiniCoursePhase.breakTime,
      );
      expect(duringBreak.currentCourses.single.nextSegmentMinute, 8 * 60 + 55);

      await schedule.saveDailyOverride(
        DailyItemOverrideDraft(
          itemType: DayItemType.course,
          itemId: ruleId,
          localDate: day,
          action: DayOverrideAction.reschedule,
          plannedStartMinute: 14 * 60,
          plannedEndMinute: 15 * 60,
        ),
      );
      final rescheduled = await repository.load(
        now: DateTime(2026, 9, 8, 14, 30),
      );
      expect(rescheduled.currentCourses.single.phase, MiniCoursePhase.active);
    },
  );
}

Future<String> _saveTimerTask(
  TaskRepository repository,
  String name,
  DateTime startsOn,
) => repository.saveRecurringTask(
  RecurringTaskDraft(
    name: name,
    colorValue: 0xfff47ba2,
    executionMode: RecurringExecutionMode.timed,
    schedulePreset: SchedulePreset.daily,
    weekdays: const {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
      DateTime.sunday,
    },
    startsOn: startsOn,
    holidayPause: false,
  ),
);
