import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
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
}
