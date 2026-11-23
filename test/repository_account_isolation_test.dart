import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late SyncQueueService queue;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueueService(database);
  });
  tearDown(() => database.close());

  CourseRepository courses(String owner) =>
      CourseRepository(database: database, syncQueue: queue, userId: owner);
  SemesterRepository semesters(String owner) =>
      SemesterRepository(database: database, syncQueue: queue, userId: owner);
  DayScheduleRepository schedule(String owner) => DayScheduleRepository(
    database: database,
    syncQueue: queue,
    userId: owner,
  );

  test('course edit cannot take ownership of another account record', () async {
    const draft = CourseDraft(name: 'Account A course', colorValue: 1);
    final id = await courses('account-a').saveCourse(draft);
    await expectLater(
      courses('account-b').saveCourse(draft, courseId: id),
      throwsStateError,
    );
    final row = (await database.select(database.courseRecords).get()).single;
    expect(row.userId, 'account-a');
    expect(await courses('account-b').loadCourses(), isEmpty);
  });

  test('explicit import identity remains supported for a new record', () async {
    final id = await courses('account-a').saveCourse(
      const CourseDraft(name: 'Imported course', colorValue: 1),
      courseId: 'imported-course',
    );
    expect(id, 'imported-course');
    expect((await courses('account-a').loadCourses()).single.id, id);
  });

  test(
    'same owner can edit a course without replacing its creation time',
    () async {
      final id = await courses(
        'account-a',
      ).saveCourse(const CourseDraft(name: 'Original', colorValue: 1));
      final created = (await database.select(database.courseRecords).get())
          .single
          .createdAt;
      await courses('account-a').saveCourse(
        const CourseDraft(name: 'Edited', colorValue: 2),
        courseId: id,
      );
      final row = (await database.select(database.courseRecords).get()).single;
      expect(row.name, 'Edited');
      expect(row.colorValue, 2);
      expect(row.createdAt, created);
      expect(row.userId, 'account-a');
    },
  );

  test(
    'concurrent explicit identity imports cannot steal the winning owner',
    () async {
      Future<bool> save(String owner) async {
        try {
          await courses(owner).saveCourse(
            CourseDraft(name: owner, colorValue: 1),
            courseId: 'same-import-id',
          );
          return true;
        } on StateError {
          return false;
        }
      }

      final results = await Future.wait([save('account-a'), save('account-b')]);
      expect(results.where((saved) => saved), hasLength(1));
      final row = (await database.select(database.courseRecords).get()).single;
      expect(row.name, row.userId);
      expect(row.userId, results.first ? 'account-a' : 'account-b');
    },
  );

  test(
    'course rule edit cannot take ownership of another account record',
    () async {
      final courseId = await courses(
        'account-a',
      ).saveCourse(const CourseDraft(name: 'Course', colorValue: 1));
      final draft = CourseScheduleRuleDraft(
        courseId: courseId,
        weekday: 1,
        weekRuleType: CourseWeekRuleType.everyWeek,
        startsAtMinute: 540,
        endsAtMinute: 600,
      );
      final id = await courses('account-a').saveScheduleRule(draft);
      await expectLater(
        courses('account-b').saveScheduleRule(draft, ruleId: id),
        throwsStateError,
      );
      final row =
          (await database.select(database.courseScheduleRuleRecords).get())
              .single;
      expect(row.userId, 'account-a');
    },
  );

  test('template edit cannot replace another account segments', () async {
    const draft = ScheduleTemplateDraft(
      name: 'Template',
      segments: [
        ScheduleTemplateSegmentDraft(
          name: 'Class',
          startsAtMinute: 540,
          endsAtMinute: 600,
        ),
      ],
    );
    final id = await courses('account-a').saveScheduleTemplate(draft);
    await expectLater(
      courses('account-b').saveScheduleTemplate(draft, templateId: id),
      throwsStateError,
    );
    expect(
      (await database.select(database.scheduleTemplateRecords).get())
          .single
          .userId,
      'account-a',
    );
    expect(
      (await database.select(database.scheduleTemplateSegmentRecords).get())
          .single
          .userId,
      'account-a',
    );
  });

  test('semester edit cannot transfer another account semester', () async {
    final draft = SemesterDraft(
      name: 'Semester',
      firstWeekStartDate: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );
    final id = await semesters('account-a').saveSemester(draft);
    await expectLater(
      semesters('account-b').saveSemester(draft, semesterId: id),
      throwsStateError,
    );
    expect(
      (await database.select(database.semesterRecords).get()).single.userId,
      'account-a',
    );
  });

  test(
    'daily override edit cannot transfer another account exception',
    () async {
      final draft = DailyItemOverrideDraft(
        itemType: DayItemType.recurring,
        itemId: 'task',
        localDate: DateTime(2026, 11, 23),
        action: DayOverrideAction.skip,
      );
      final id = await schedule('account-a').saveDailyOverride(draft);
      await expectLater(
        schedule('account-b').saveDailyOverride(draft, overrideId: id),
        throwsStateError,
      );
      expect(
        (await database.select(database.dailyItemOverrideRecords).get())
            .single
            .userId,
        'account-a',
      );
    },
  );

  test('reminder edit cannot transfer another account rule', () async {
    const draft = ReminderRuleDraft(
      ownerType: DayItemType.oneTime,
      ownerId: 'task',
      reminderKind: ReminderKind.due,
      scheduledMinuteOfDay: 540,
    );
    final id = await schedule('account-a').saveReminderRule(draft);
    await expectLater(
      schedule('account-b').saveReminderRule(draft, ruleId: id),
      throwsStateError,
    );
    expect(
      (await database.select(database.reminderRuleRecords).get()).single.userId,
      'account-a',
    );
  });

  test('alarm edit cannot transfer another account rule', () async {
    const draft = AlarmRuleDraft(
      ownerType: DayItemType.oneTime,
      ownerId: 'task',
    );
    final id = await schedule('account-a').saveAlarmRule(draft);
    await expectLater(
      schedule('account-b').saveAlarmRule(draft, ruleId: id),
      throwsStateError,
    );
    expect(
      (await database.select(database.alarmRuleRecords).get()).single.userId,
      'account-a',
    );
  });

  test('ad hoc timer edit cannot transfer another account history', () async {
    final draft = AdHocTimerDraft(
      title: 'Focus',
      colorValue: 1,
      startedAt: DateTime(2026, 11, 23, 9),
    );
    final id = await schedule('account-a').saveAdHocTimer(draft);
    await expectLater(
      schedule('account-b').saveAdHocTimer(draft, timerId: id),
      throwsStateError,
    );
    expect(
      (await database.select(database.adHocTimerRecords).get()).single.userId,
      'account-a',
    );
  });
}
