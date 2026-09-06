import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/notifications/notification_service.dart';
import 'package:check_d/core/notifications/reminder_scheduler.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tasks/data/task_repository.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late TaskRepository tasks;
  late DayScheduleRepository schedule;
  late _FakeNotifications notifications;
  late ReminderScheduler scheduler;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final sync = SyncQueueService(database);
    tasks = TaskRepository(database: database, syncQueue: sync, userId: 'user');
    schedule = DayScheduleRepository(
      database: database,
      syncQueue: sync,
      userId: 'user',
    );
    notifications = _FakeNotifications();
    scheduler = ReminderScheduler(
      notifications: notifications,
      tasks: tasks,
      courses: CourseRepository(
        database: database,
        syncQueue: sync,
        userId: 'user',
      ),
      semesters: SemesterRepository(
        database: database,
        syncQueue: sync,
        userId: 'user',
      ),
      schedule: schedule,
    );
  });

  tearDown(() => database.close());

  test(
    'skips a past advance reminder but schedules the future at-time reminder',
    () async {
      final day = DateTime(2026, 9, 8);
      final id = await tasks.saveOneTimeReminder(
        OneTimeReminderDraft(
          name: '项目会议',
          colorValue: 0xFFEF8FA8,
          scheduledAt: DateTime(2026, 9, 8, 14),
        ),
      );
      await schedule.replaceReminderConfiguration(
        ownerType: DayItemType.oneTime,
        ownerId: id,
        advanceEnabled: true,
        advanceMinutes: 10,
        atTimeEnabled: true,
      );

      await scheduler.refreshFuture(now: DateTime(2026, 9, 8, 13, 55));

      expect(notifications.scheduled, hasLength(1));
      expect(notifications.scheduled.single.when, DateTime(2026, 9, 8, 14));
      expect(notifications.scheduled.single.body, '该开始项目会议了');
      expect(notifications.cancelledAll, isTrue);
      expect(day, isNotNull);
    },
  );

  test('does not schedule exact reminders for an untimed item', () async {
    final day = DateTime(2026, 9, 8);
    final id = await tasks.saveOneTimeReminder(
      OneTimeReminderDraft(name: '整理资料', colorValue: 0xFF9B8BE8),
    );
    await schedule.replaceReminderConfiguration(
      ownerType: DayItemType.oneTime,
      ownerId: id,
      advanceEnabled: true,
      advanceMinutes: 10,
      atTimeEnabled: true,
    );

    await scheduler.refreshFuture(now: day);
    expect(notifications.scheduled, isEmpty);
  });

  test(
    'a recurring occurrence override can disable advance without changing tomorrow',
    () async {
      final day = DateTime(2026, 9, 8);
      final id = await tasks.saveRecurringTask(
        RecurringTaskDraft(
          name: '背单词',
          colorValue: 0xFF9B8BE8,
          executionMode: RecurringExecutionMode.untimed,
          schedulePreset: SchedulePreset.daily,
          weekdays: WeekdayMask.toDays(WeekdayMask.everyDay),
          startsOn: day,
          holidayPause: false,
          scheduledMinuteOfDay: 20 * 60,
        ),
      );
      await schedule.replaceReminderConfiguration(
        ownerType: DayItemType.recurring,
        ownerId: id,
        advanceEnabled: true,
        advanceMinutes: 10,
        atTimeEnabled: true,
      );
      await schedule.replaceReminderConfiguration(
        ownerType: DayItemType.recurring,
        ownerId: id,
        localDate: day,
        advanceEnabled: false,
        atTimeEnabled: true,
      );

      await scheduler.refreshFuture(now: DateTime(2026, 9, 8, 9));

      expect(
        notifications.scheduled.where((item) => item.when.day == 8),
        hasLength(1),
      );
      expect(
        notifications.scheduled.where((item) => item.when.day == 9),
        hasLength(2),
      );
    },
  );

  test('notification identity is stable for a rebuilt occurrence', () {
    final first = notificationId(
      entityType: 'course',
      entityId: 'rule-1',
      occurrenceId: 'course:rule-1:2026-09-08T00:00:00.000',
      date: DateTime(2026, 9, 8),
      kind: ScheduledReminderKind.advance,
    );
    final second = notificationId(
      entityType: 'course',
      entityId: 'rule-1',
      occurrenceId: 'course:rule-1:2026-09-08T00:00:00.000',
      date: DateTime(2026, 9, 8),
      kind: ScheduledReminderKind.advance,
    );
    expect(first, second);
  });

  test(
    'course advance and at-time reminder settings are independent',
    () async {
      final day = DateTime(2026, 9, 7); // Monday
      final courses = CourseRepository(
        database: database,
        syncQueue: SyncQueueService(database),
        userId: 'user',
      );
      final courseId = await courses.saveCourse(
        CourseDraft(
          name: '线性代数',
          colorValue: 0xFF80A8F5,
          semesterStartsOn: day,
          semesterEndsOn: day.add(const Duration(days: 90)),
        ),
      );
      final ruleId = await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: DateTime.monday,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: 8 * 60,
          endsAtMinute: 9 * 60,
        ),
      );

      Future<Set<DateTime>> scheduledForToday({
        required bool advanceEnabled,
        required bool atTimeEnabled,
      }) async {
        await schedule.replaceReminderConfiguration(
          ownerType: DayItemType.course,
          ownerId: ruleId,
          advanceEnabled: advanceEnabled,
          advanceMinutes: 10,
          atTimeEnabled: atTimeEnabled,
        );
        await scheduler.refreshFuture(now: DateTime(2026, 9, 7, 7));
        return notifications.scheduled
            .where((item) => item.when.day == day.day)
            .map((item) => item.when)
            .toSet();
      }

      expect(
        await scheduledForToday(advanceEnabled: true, atTimeEnabled: false),
        {DateTime(2026, 9, 7, 7, 50)},
      );
      expect(
        await scheduledForToday(advanceEnabled: false, atTimeEnabled: true),
        {DateTime(2026, 9, 7, 8)},
      );
      expect(
        await scheduledForToday(advanceEnabled: true, atTimeEnabled: true),
        {DateTime(2026, 9, 7, 7, 50), DateTime(2026, 9, 7, 8)},
      );
      expect(
        await scheduledForToday(advanceEnabled: false, atTimeEnabled: false),
        isEmpty,
      );
    },
  );

  test('course occurrence reminder override affects only that date', () async {
    final day = DateTime(2026, 9, 7); // Monday
    final courses = CourseRepository(
      database: database,
      syncQueue: SyncQueueService(database),
      userId: 'user',
    );
    final courseId = await courses.saveCourse(
      CourseDraft(
        name: '大学英语',
        colorValue: 0xFF80A8F5,
        semesterStartsOn: day,
        semesterEndsOn: day.add(const Duration(days: 90)),
      ),
    );
    final ruleId = await courses.saveScheduleRule(
      CourseScheduleRuleDraft(
        courseId: courseId,
        weekday: DateTime.monday,
        weekRuleType: CourseWeekRuleType.everyWeek,
        startsAtMinute: 8 * 60,
        endsAtMinute: 9 * 60,
      ),
    );
    await schedule.replaceReminderConfiguration(
      ownerType: DayItemType.course,
      ownerId: ruleId,
      advanceEnabled: true,
      advanceMinutes: 10,
      atTimeEnabled: true,
    );
    await schedule.replaceReminderConfiguration(
      ownerType: DayItemType.course,
      ownerId: ruleId,
      localDate: day,
      advanceEnabled: false,
      atTimeEnabled: true,
    );

    await scheduler.refreshFuture(now: DateTime(2026, 9, 7, 7));

    expect(
      notifications.scheduled
          .where((item) => item.when.day == 7)
          .map((item) => item.when),
      {DateTime(2026, 9, 7, 8)},
    );
    expect(
      notifications.scheduled
          .where((item) => item.when.day == 14)
          .map((item) => item.when),
      {DateTime(2026, 9, 14, 7, 50), DateTime(2026, 9, 14, 8)},
    );
  });

  test(
    'course reschedule and cancellation rebuild the effective occurrence reminders',
    () async {
      final day = DateTime(2026, 9, 7); // Monday
      final courses = CourseRepository(
        database: database,
        syncQueue: SyncQueueService(database),
        userId: 'user',
      );
      final courseId = await courses.saveCourse(
        CourseDraft(
          name: '高等数学',
          colorValue: 0xFF80A8F5,
          semesterStartsOn: day,
          semesterEndsOn: day.add(const Duration(days: 90)),
        ),
      );
      final ruleId = await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: DateTime.monday,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: 8 * 60,
          endsAtMinute: 9 * 60 + 30,
        ),
      );
      await schedule.replaceReminderConfiguration(
        ownerType: DayItemType.course,
        ownerId: ruleId,
        advanceEnabled: true,
        advanceMinutes: 10,
        atTimeEnabled: true,
      );
      final overrideId = await schedule.saveDailyOverride(
        DailyItemOverrideDraft(
          itemType: DayItemType.course,
          itemId: ruleId,
          localDate: day,
          action: DayOverrideAction.reschedule,
          plannedStartMinute: 14 * 60,
          plannedEndMinute: 15 * 60 + 30,
        ),
      );

      await scheduler.refreshFuture(now: DateTime(2026, 9, 7, 9));
      expect(
        notifications.scheduled
            .where((item) => item.when.day == 7)
            .map((item) => item.when),
        {DateTime(2026, 9, 7, 13, 50), DateTime(2026, 9, 7, 14)},
      );

      await schedule.saveDailyOverride(
        DailyItemOverrideDraft(
          itemType: DayItemType.course,
          itemId: ruleId,
          localDate: day,
          action: DayOverrideAction.skip,
        ),
        overrideId: overrideId,
      );
      await scheduler.refreshFuture(now: DateTime(2026, 9, 7, 9));
      expect(
        notifications.scheduled.where((item) => item.when.day == 7),
        isEmpty,
      );
    },
  );
}

class _FakeNotifications implements NotificationPlatformService {
  final scheduled = <_Scheduled>[];
  bool cancelledAll = false;

  @override
  Future<void> cancelAllPending() async {
    cancelledAll = true;
    scheduled.clear();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionState> permissionState() async =>
      NotificationPermissionState.granted;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    scheduled.add(_Scheduled(id: id, when: when, title: title, body: body));
  }
}

class _Scheduled {
  const _Scheduled({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });
  final int id;
  final DateTime when;
  final String title;
  final String body;
}
