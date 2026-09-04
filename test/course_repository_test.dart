import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:check_d/features/today/data/today_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late CourseRepository courses;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    courses = CourseRepository(
      database: database,
      syncQueue: SyncQueueService(database),
      userId: 'u1',
    );
  });

  tearDown(() => database.close());

  test(
    'course is stored separately from tasks and supports multiple rules',
    () async {
      final courseId = await courses.saveCourse(
        const CourseDraft(
          name: '高等数学',
          colorValue: 0xFFF47BA2,
          teacher: '王老师',
          classroom: 'A101',
          semester: '2026 秋',
        ),
      );
      await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: DateTime.monday,
          weekRuleType: CourseWeekRuleType.oddWeeks,
          startsAtMinute: 8 * 60,
          endsAtMinute: 9 * 60 + 40,
          remindBeforeMinutes: 10,
        ),
      );
      await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: DateTime.wednesday,
          weekRuleType: CourseWeekRuleType.evenWeeks,
          startsAtMinute: 14 * 60,
          endsAtMinute: 15 * 60 + 40,
        ),
      );

      final saved = (await courses.watchCourses().first).single;
      expect(saved.name, '高等数学');
      expect(saved.rules, hasLength(2));
      expect(saved.rules.first.remindBeforeMinutes, 10);
      expect(saved.rules.first.isDueInWeek(1), isTrue);
      expect(saved.rules.first.isDueInWeek(2), isFalse);
      expect(await database.select(database.localTasks).get(), isEmpty);
    },
  );

  test('schedule template preserves class and break segments', () async {
    final templateId = await courses.saveScheduleTemplate(
      const ScheduleTemplateDraft(
        name: '主校区秋季作息',
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
            sortOrder: 1,
          ),
        ],
      ),
    );

    final rows = await database
        .select(database.scheduleTemplateSegmentRecords)
        .get();
    expect(templateId, isNotEmpty);
    expect(rows, hasLength(2));
    expect(rows.last.segmentType, ScheduleSegmentType.breakTime.name);
  });

  test('today course projection applies week rules and one-day overrides', () {
    final date = DateTime(2026, 9, 3); // ISO week 36, Thursday.
    final course = CourseDetails(
      id: 'course-1',
      name: '数据结构',
      colorValue: 0xFFF47BA2,
      status: CourseStatus.active,
      createdAt: date,
      updatedAt: date,
      classroom: 'B201',
      rules: [
        CourseScheduleRule(
          id: 'rule-1',
          courseId: 'course-1',
          weekday: DateTime.thursday,
          weekRuleType: CourseWeekRuleType.evenWeeks,
          startsAtMinute: 10 * 60,
          endsAtMinute: 11 * 60 + 40,
          createdAt: date,
          updatedAt: date,
        ),
      ],
    );

    final moved = buildCourseItemsForDate(
      date,
      [course],
      [
        DailyItemOverride(
          id: 'override-1',
          itemType: DayItemType.course,
          itemId: 'rule-1',
          localDate: date,
          action: DayOverrideAction.reschedule,
          plannedStartMinute: 14 * 60,
          plannedEndMinute: 15 * 60 + 40,
          createdAt: date,
          updatedAt: date,
        ),
      ],
    );
    expect(moved.single.startMinute, 14 * 60);
    expect(moved.single.endMinute, 15 * 60 + 40);
    expect(moved.single.classroom, 'B201');

    final skipped = buildCourseItemsForDate(
      date,
      [course],
      [
        DailyItemOverride(
          id: 'override-2',
          itemType: DayItemType.course,
          itemId: 'rule-1',
          localDate: date,
          action: DayOverrideAction.skip,
          createdAt: date,
          updatedAt: date,
        ),
      ],
    );
    expect(skipped, isEmpty);
  });

  test('today course projection respects semester date boundaries', () {
    final date = DateTime(2026, 9, 3);
    final course = CourseDetails(
      id: 'course-semester',
      name: '线性代数',
      colorValue: 0xFF8FA7F5,
      status: CourseStatus.active,
      createdAt: date,
      updatedAt: date,
      semesterStartsOn: DateTime(2026, 9, 7),
      semesterEndsOn: DateTime(2027, 1, 10),
      rules: [
        CourseScheduleRule(
          id: 'rule-semester',
          courseId: 'course-semester',
          weekday: DateTime.thursday,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: 8 * 60,
          endsAtMinute: 9 * 60,
          createdAt: date,
          updatedAt: date,
        ),
      ],
    );
    expect(buildCourseItemsForDate(date, [course], []), isEmpty);
    expect(
      buildCourseItemsForDate(DateTime(2027, 1, 14), [course], []),
      isEmpty,
    );
  });
}
