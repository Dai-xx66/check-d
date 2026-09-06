import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/calendar/domain/calendar_occurrence_builder.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late CourseRepository templates;
  late SemesterRepository semesters;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final syncQueue = SyncQueueService(database);
    templates = CourseRepository(
      database: database,
      syncQueue: syncQueue,
      userId: 'u1',
    );
    semesters = SemesterRepository(
      database: database,
      syncQueue: syncQueue,
      userId: 'u1',
    );
  });

  tearDown(() => database.close());

  test(
    'templates persist periods and reject invalid or overlapping times',
    () async {
      final templateId = await templates.saveScheduleTemplate(
        const ScheduleTemplateDraft(
          name: '秋季作息',
          isDefault: true,
          segments: [
            ScheduleTemplateSegmentDraft(
              name: '第一大节',
              startsAtMinute: 8 * 60,
              endsAtMinute: 9 * 60 + 40,
            ),
            ScheduleTemplateSegmentDraft(
              name: '第二大节',
              startsAtMinute: 10 * 60,
              endsAtMinute: 11 * 60 + 40,
            ),
          ],
        ),
      );

      final saved = await templates.loadScheduleTemplate(templateId);
      expect(saved?.name, '秋季作息');
      expect(saved?.segments, hasLength(2));
      expect(saved?.isDefault, isTrue);

      await expectLater(
        templates.saveScheduleTemplate(
          const ScheduleTemplateDraft(
            name: '重叠作息',
            segments: [
              ScheduleTemplateSegmentDraft(
                name: '第一节',
                startsAtMinute: 8 * 60,
                endsAtMinute: 9 * 60,
              ),
              ScheduleTemplateSegmentDraft(
                name: '第二节',
                startsAtMinute: 8 * 60 + 30,
                endsAtMinute: 9 * 60 + 30,
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        templates.saveScheduleTemplate(
          const ScheduleTemplateDraft(
            name: '错误时间',
            segments: [
              ScheduleTemplateSegmentDraft(
                name: '第一节',
                startsAtMinute: 9 * 60,
                endsAtMinute: 8 * 60,
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'only one semester is current and referenced templates stay protected',
    () async {
      final templateId = await templates.saveScheduleTemplate(
        const ScheduleTemplateDraft(name: '主校区作息'),
      );
      final firstId = await semesters.saveSemester(
        SemesterDraft(
          name: '2026 秋季学期',
          firstWeekStartDate: DateTime(2026, 9, 3),
          totalWeeks: 20,
          scheduleTemplateId: templateId,
          isCurrent: true,
        ),
      );
      await semesters.saveSemester(
        SemesterDraft(
          name: '2027 春季学期',
          firstWeekStartDate: DateTime(2027, 2, 25),
          totalWeeks: 18,
          isCurrent: true,
        ),
      );

      final saved = await semesters.watchSemesters().first;
      expect(saved.where((item) => item.isCurrent).single.name, '2027 春季学期');
      expect(
        saved.singleWhere((item) => item.id == firstId).isCurrent,
        isFalse,
      );
      await expectLater(
        templates.archiveScheduleTemplate(templateId),
        throwsStateError,
      );
    },
  );

  test(
    'editing a referenced template keeps period ids and blocks removal',
    () async {
      final templateId = await templates.saveScheduleTemplate(
        const ScheduleTemplateDraft(
          name: '稳定节次',
          segments: [
            ScheduleTemplateSegmentDraft(
              name: '第一节',
              startsAtMinute: 8 * 60,
              endsAtMinute: 8 * 60 + 45,
            ),
          ],
        ),
      );
      final template = (await templates.loadScheduleTemplate(templateId))!;
      final period = template.segments.single;
      final courseId = await templates.saveCourse(
        const CourseDraft(name: '离散数学', colorValue: 0xFF8FA7F5),
      );
      await templates.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: courseId,
          weekday: DateTime.monday,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: 8 * 60,
          endsAtMinute: 8 * 60 + 45,
          scheduleTemplateId: templateId,
          sectionIds: [period.id],
        ),
      );

      await templates.saveScheduleTemplate(
        ScheduleTemplateDraft(
          name: '稳定节次（已更新）',
          segments: [
            ScheduleTemplateSegmentDraft(
              id: period.id,
              name: '第一节',
              startsAtMinute: 8 * 60,
              endsAtMinute: 8 * 60 + 45,
            ),
          ],
        ),
        templateId: templateId,
      );
      expect(
        (await templates.loadScheduleTemplate(templateId))!.segments.single.id,
        period.id,
      );

      await expectLater(
        templates.saveScheduleTemplate(
          const ScheduleTemplateDraft(name: '删除被引用节次'),
          templateId: templateId,
        ),
        throwsStateError,
      );
    },
  );

  test('semantic weeks begin on the exact configured first-week date', () {
    final semester = SemesterDetails(
      id: 'semester',
      name: '2026 秋季',
      firstWeekStartDate: DateTime(
        2026,
        9,
        3,
      ), // Thursday, deliberately not Monday.
      totalWeeks: 2,
      isCurrent: true,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

    expect(semester.weekNumberFor(DateTime(2026, 9, 3)), 1);
    expect(semester.weekNumberFor(DateTime(2026, 9, 9)), 1);
    expect(semester.weekNumberFor(DateTime(2026, 9, 10)), 2);
    expect(semester.contains(DateTime(2026, 9, 16)), isTrue);
    expect(semester.contains(DateTime(2026, 9, 17)), isFalse);
    expect(
      semesterWeekNumberFor(DateTime(2026, 9, 10), DateTime(2026, 9, 3)),
      2,
    );
  });
}
