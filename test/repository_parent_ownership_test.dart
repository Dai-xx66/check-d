import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/data/day_schedule_repository.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/tags/data/tag_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const original = 'account-a';
  const other = 'account-b';
  final date = DateTime(2026, 11, 23);
  late AppDatabase database;
  late SyncQueueService queue;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueueService(database);
  });
  tearDown(() => database.close());

  CourseRepository courses(String owner) =>
      CourseRepository(database: database, syncQueue: queue, userId: owner);
  DayScheduleRepository schedule(String owner) => DayScheduleRepository(
    database: database,
    syncQueue: queue,
    userId: owner,
  );

  Future<void> expectNoUploadsForOtherAccount() async {
    final uploads = await database.select(database.syncOperations).get();
    expect(uploads.where((row) => row.userId == other), isEmpty);
  }

  Future<String> task(DayItemType type) async {
    final id = '${type.name}-of-account-a';
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: id,
            userId: const Value(original),
            name: 'Task',
            taskType: type.name,
            colorValue: 1,
            createdAt: date,
            updatedAt: date,
          ),
        );
    return id;
  }

  CourseScheduleRuleDraft rule(
    String courseId, {
    String? templateId,
    List<String> sections = const [],
  }) => CourseScheduleRuleDraft(
    courseId: courseId,
    weekday: DateTime.monday,
    weekRuleType: CourseWeekRuleType.everyWeek,
    timeMode: templateId == null
        ? CourseScheduleTimeMode.customTime
        : CourseScheduleTimeMode.periods,
    scheduleTemplateId: templateId,
    sectionIds: sections,
    startsAtMinute: 540,
    endsAtMinute: 600,
  );

  const courseDraft = CourseDraft(name: 'Course', colorValue: 1);
  const templateDraft = ScheduleTemplateDraft(
    name: 'Template',
    segments: [
      ScheduleTemplateSegmentDraft(
        name: 'Class',
        startsAtMinute: 540,
        endsAtMinute: 600,
      ),
    ],
  );

  test(
    'new course rejects a foreign semester and preserves optional and owned semesters',
    () async {
      final semester =
          await SemesterRepository(
            database: database,
            syncQueue: queue,
            userId: original,
          ).saveSemester(
            SemesterDraft(
              name: 'Term',
              firstWeekStartDate: date,
              totalWeeks: 18,
            ),
          );
      final linked = CourseDraft(
        name: 'Course',
        colorValue: 1,
        semesterId: semester,
      );
      await expectLater(courses(other).saveCourse(linked), throwsStateError);
      await expectLater(
        courses(other).saveCourse(
          const CourseDraft(
            name: 'Missing term',
            colorValue: 1,
            semesterId: 'missing',
          ),
        ),
        throwsStateError,
      );
      expect(await database.select(database.courseRecords).get(), isEmpty);
      await expectNoUploadsForOtherAccount();
      await courses(original).saveCourse(linked);
      await courses(original).saveCourse(courseDraft);
      expect(
        (await database.select(database.courseRecords).get()).map(
          (row) => row.semesterId,
        ),
        unorderedEquals([semester, null]),
      );
    },
  );

  test(
    'new schedule rule rejects a foreign course before saving or enqueueing',
    () async {
      final course = await courses(original).saveCourse(courseDraft);
      await expectLater(
        courses(other).saveScheduleRule(rule(course)),
        throwsStateError,
      );
      expect(
        await database.select(database.courseScheduleRuleRecords).get(),
        isEmpty,
      );
      await expectNoUploadsForOtherAccount();
      await courses(original).saveScheduleRule(rule(course));
    },
  );

  test(
    'new schedule rule rejects a foreign template and its sections',
    () async {
      final foreignTemplate = await courses(
        original,
      ).saveScheduleTemplate(templateDraft);
      final segments = (await courses(
        original,
      ).watchScheduleTemplates().first).single.segments;
      final course = await courses(other).saveCourse(courseDraft);
      final before = await database.select(database.syncOperations).get();
      await expectLater(
        courses(other).saveScheduleRule(
          rule(
            course,
            templateId: foreignTemplate,
            sections: [segments.single.id],
          ),
        ),
        throwsStateError,
      );
      expect(
        await database.select(database.courseScheduleRuleRecords).get(),
        isEmpty,
      );
      expect(
        await database.select(database.syncOperations).get(),
        unorderedEquals(before),
      );
    },
  );

  test('sections must belong to the selected template and account', () async {
    final template = await courses(
      original,
    ).saveScheduleTemplate(templateDraft);
    final different = await courses(
      original,
    ).saveScheduleTemplate(templateDraft);
    final foreign = await courses(other).saveScheduleTemplate(templateDraft);
    final allSegments = await database
        .select(database.scheduleTemplateSegmentRecords)
        .get();
    String segmentOf(String id) =>
        allSegments.singleWhere((row) => row.templateId == id).id;
    final course = await courses(original).saveCourse(courseDraft);
    final before = await database.select(database.syncOperations).get();
    for (final invalid in [
      segmentOf(different),
      segmentOf(foreign),
      'missing',
    ]) {
      await expectLater(
        courses(original).saveScheduleRule(
          rule(
            course,
            templateId: template,
            sections: [segmentOf(template), invalid],
          ),
        ),
        throwsStateError,
      );
    }
    expect(
      await database.select(database.courseScheduleRuleRecords).get(),
      isEmpty,
    );
    expect(
      await database.select(database.syncOperations).get(),
      unorderedEquals(before),
    );
    await courses(original).saveScheduleRule(
      rule(course, templateId: template, sections: [segmentOf(template)]),
    );
    expect(
      (await database.select(database.courseScheduleRuleRecords).get())
          .single
          .scheduleTemplateId,
      template,
    );
  });

  for (final type in [
    DayItemType.recurring,
    DayItemType.oneTime,
    DayItemType.course,
  ]) {
    test(
      'all scheduling writes reject a foreign ${type.name} parent',
      () async {
        final id = type == DayItemType.course
            ? await courses(original).saveCourse(courseDraft)
            : await task(type);
        final draft = DailyItemOverrideDraft(
          itemType: type,
          itemId: id,
          localDate: date,
          action: DayOverrideAction.skip,
        );
        await expectLater(
          schedule(other).saveDailyOverride(draft),
          throwsStateError,
        );
        await expectLater(
          schedule(other).saveReminderRule(
            ReminderRuleDraft(
              ownerType: type,
              ownerId: id,
              reminderKind: ReminderKind.due,
              scheduledMinuteOfDay: 540,
            ),
          ),
          throwsStateError,
        );
        await expectLater(
          schedule(
            other,
          ).saveAlarmRule(AlarmRuleDraft(ownerType: type, ownerId: id)),
          throwsStateError,
        );
        await expectLater(
          schedule(other).replaceReminderConfiguration(
            ownerType: type,
            ownerId: id,
            advanceEnabled: true,
            advanceMinutes: 10,
            atTimeEnabled: true,
          ),
          throwsStateError,
        );
        expect(
          await database.select(database.dailyItemOverrideRecords).get(),
          isEmpty,
        );
        expect(
          await database.select(database.reminderRuleRecords).get(),
          isEmpty,
        );
        expect(await database.select(database.alarmRuleRecords).get(), isEmpty);
        await expectNoUploadsForOtherAccount();
        await schedule(original).saveDailyOverride(draft);
        await schedule(
          original,
        ).saveAlarmRule(AlarmRuleDraft(ownerType: type, ownerId: id));
        await schedule(original).replaceReminderConfiguration(
          ownerType: type,
          ownerId: id,
          advanceEnabled: true,
          advanceMinutes: 10,
          atTimeEnabled: true,
        );
        expect(
          (await database.select(database.reminderRuleRecords).get()).map(
            (row) => row.userId,
          ),
          everyElement(original),
        );
      },
    );
  }

  test(
    'course rules support own per-lesson changes but reject other accounts',
    () async {
      final course = await courses(original).saveCourse(courseDraft);
      final ruleId = await courses(original).saveScheduleRule(rule(course));
      final draft = DailyItemOverrideDraft(
        itemType: DayItemType.course,
        itemId: ruleId,
        localDate: date,
        action: DayOverrideAction.skip,
      );
      await expectLater(
        schedule(other).saveDailyOverride(draft),
        throwsStateError,
      );
      await expectLater(
        schedule(other).saveReminderRule(
          ReminderRuleDraft(
            ownerType: DayItemType.course,
            ownerId: ruleId,
            reminderKind: ReminderKind.due,
            scheduledMinuteOfDay: 540,
          ),
        ),
        throwsStateError,
      );
      expect(
        await database.select(database.dailyItemOverrideRecords).get(),
        isEmpty,
      );
      expect(
        await database.select(database.reminderRuleRecords).get(),
        isEmpty,
      );
      await expectNoUploadsForOtherAccount();
      await schedule(original).saveDailyOverride(draft);
      await schedule(original).replaceReminderConfiguration(
        ownerType: DayItemType.course,
        ownerId: ruleId,
        localDate: date,
        advanceEnabled: true,
        advanceMinutes: 10,
        atTimeEnabled: true,
      );
      expect(
        (await database.select(database.dailyItemOverrideRecords).get())
            .single
            .itemId,
        ruleId,
      );
      expect(
        (await database.select(database.reminderRuleRecords).get()).map(
          (r) => r.ownerId,
        ),
        everyElement(ruleId),
      );
    },
  );

  test(
    'reminder replacement rolls back when writing the outbox fails',
    () async {
      final id = await task(DayItemType.oneTime);
      await schedule(original).replaceReminderConfiguration(
        ownerType: DayItemType.oneTime,
        ownerId: id,
        advanceEnabled: true,
        advanceMinutes: 10,
        atTimeEnabled: true,
      );
      final beforeRules = await database
          .select(database.reminderRuleRecords)
          .get();
      final beforeOutbox = await database.select(database.syncOperations).get();
      final repository = DayScheduleRepository(
        database: database,
        syncQueue: _FailingSyncQueue(database),
        userId: original,
      );
      await expectLater(
        repository.replaceReminderConfiguration(
          ownerType: DayItemType.oneTime,
          ownerId: id,
          advanceEnabled: true,
          advanceMinutes: 20,
          atTimeEnabled: false,
        ),
        throwsStateError,
      );
      expect(
        await database.select(database.reminderRuleRecords).get(),
        unorderedEquals(beforeRules),
      );
      expect(
        await database.select(database.syncOperations).get(),
        unorderedEquals(beforeOutbox),
      );
    },
  );

  test(
    'new ad hoc timer rejects foreign tags and preserves owned or absent tags',
    () async {
      final tag = await TagRepository(
        database,
        original,
        queue,
      ).save(name: 'Focus', colorValue: 1);
      await expectLater(
        schedule(other).createAdHocTimer(title: 'Timer', tagId: tag),
        throwsStateError,
      );
      expect(await database.select(database.adHocTimerRecords).get(), isEmpty);
      await expectNoUploadsForOtherAccount();
      await schedule(original).createAdHocTimer(title: 'Tagged', tagId: tag);
      await schedule(original).createAdHocTimer(title: 'Untagged');
      expect(
        (await database.select(database.adHocTimerRecords).get()).map(
          (row) => row.tagId,
        ),
        unorderedEquals([tag, null]),
      );
    },
  );
}

class _FailingSyncQueue extends SyncQueueService {
  _FailingSyncQueue(super.database);

  @override
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperationType operation,
    required Map<String, Object?> payload,
    String? userId,
  }) async {
    await super.enqueue(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      userId: userId,
    );
    throw StateError('Test outbox error');
  }
}
