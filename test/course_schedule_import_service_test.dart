import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/application/course_schedule_import_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/courses/domain/course_schedule_import_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late CourseRepository courses;
  late SemesterRepository semesters;
  late CourseScheduleImportService importer;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final queue = SyncQueueService(database);
    courses = CourseRepository(
      database: database,
      syncQueue: queue,
      userId: 'u1',
    );
    semesters = SemesterRepository(
      database: database,
      syncQueue: queue,
      userId: 'u1',
    );
    importer = CourseScheduleImportService(
      courses: courses,
      semesters: semesters,
    );
  });

  tearDown(() => database.close());

  test('recognition stays a draft until the user confirms import', () async {
    final templateId = await courses.saveScheduleTemplate(
      const ScheduleTemplateDraft(
        name: '秋季作息',
        segments: [
          ScheduleTemplateSegmentDraft(
            name: '第1节',
            startsAtMinute: 480,
            endsAtMinute: 525,
          ),
          ScheduleTemplateSegmentDraft(
            name: '第2节',
            startsAtMinute: 535,
            endsAtMinute: 580,
          ),
        ],
      ),
    );
    final semesterId = await semesters.saveSemester(
      SemesterDraft(
        name: '2026 秋',
        firstWeekStartDate: DateTime(2026, 9, 7),
        totalWeeks: 20,
        scheduleTemplateId: templateId,
        isCurrent: true,
      ),
    );
    final semester = (await semesters.watchSemesters().first).singleWhere(
      (item) => item.id == semesterId,
    );
    final template = (await courses.loadScheduleTemplate(templateId))!;
    final plan = await importer.prepare(
      semester: semester,
      template: template,
      result: CourseScheduleRecognitionResult(
        courses: [
          RecognizedCourseDraft(
            id: 'draft-1',
            name: '高等数学',
            rules: [
              RecognizedScheduleRuleDraft(
                weekday: DateTime.monday,
                recognizedSectionNumbers: [1, 2],
                weekRuleType: CourseWeekRuleType.everyWeek,
                startWeek: 1,
                endWeek: 16,
              ),
            ],
          ),
        ],
      ),
    );

    expect(await courses.loadCourses(), isEmpty);
    expect(
      plan.courses.single.rules.single.mappedSegmentIds,
      template.segments.map((item) => item.id),
    );

    await importer.confirm(plan: plan, createRecognizedTemplate: false);
    final saved = (await courses.loadCourses()).single;
    expect(saved.name, '高等数学');
    expect(saved.rules, hasLength(1));
    expect(
      saved.rules.single.sectionIds,
      template.segments.map((item) => item.id),
    );
  });

  test(
    'missing template never guesses periods and only creates one after confirmation',
    () async {
      final semesterId = await semesters.saveSemester(
        SemesterDraft(
          name: '2026 秋',
          firstWeekStartDate: DateTime(2026, 9, 7),
          totalWeeks: 20,
          isCurrent: true,
        ),
      );
      final semester = (await semesters.watchSemesters().first).singleWhere(
        (item) => item.id == semesterId,
      );
      final plan = await importer.prepare(
        semester: semester,
        template: null,
        result: CourseScheduleRecognitionResult(
          courses: [
            RecognizedCourseDraft(
              id: 'draft-1',
              name: '数据结构',
              rules: [
                RecognizedScheduleRuleDraft(
                  weekday: DateTime.wednesday,
                  recognizedSectionNumbers: [1],
                  weekRuleType: CourseWeekRuleType.oddWeeks,
                ),
              ],
            ),
          ],
          detectedSegments: const [
            RecognizedScheduleSegmentDraft(
              number: 1,
              startsAtMinute: 480,
              endsAtMinute: 525,
            ),
          ],
        ),
      );

      expect(plan.template, isNull);
      expect(plan.templateDraft, isNotNull);
      expect(await courses.watchScheduleTemplates().first, isEmpty);
      await expectLater(
        importer.confirm(plan: plan, createRecognizedTemplate: false),
        throwsStateError,
      );

      await importer.confirm(plan: plan, createRecognizedTemplate: true);
      final templates = await courses.watchScheduleTemplates().first;
      expect(templates, hasLength(1));
      final updatedSemester = (await semesters.watchSemesters().first).single;
      expect(updatedSemester.scheduleTemplateId, templates.single.id);
    },
  );

  test(
    'recognized times never overwrite an existing semester template',
    () async {
      final templateId = await courses.saveScheduleTemplate(
        const ScheduleTemplateDraft(
          name: '已有作息',
          segments: [
            ScheduleTemplateSegmentDraft(
              name: '第1节',
              startsAtMinute: 480,
              endsAtMinute: 525,
            ),
          ],
        ),
      );
      final semesterId = await semesters.saveSemester(
        SemesterDraft(
          name: '2026 秋',
          firstWeekStartDate: DateTime(2026, 9, 7),
          totalWeeks: 20,
          scheduleTemplateId: templateId,
          isCurrent: true,
        ),
      );
      final semester = (await semesters.watchSemesters().first).singleWhere(
        (item) => item.id == semesterId,
      );
      final template = (await courses.loadScheduleTemplate(templateId))!;
      final plan = await importer.prepare(
        semester: semester,
        template: template,
        result: const CourseScheduleRecognitionResult(
          courses: [],
          detectedSegments: [
            RecognizedScheduleSegmentDraft(
              number: 1,
              startsAtMinute: 510,
              endsAtMinute: 555,
            ),
          ],
        ),
      );

      expect(plan.templateTimeConflict, isTrue);
      final untouched = (await courses.loadScheduleTemplate(templateId))!;
      expect(untouched.segments.single.startsAtMinute, 480);
      expect(untouched.segments.single.endsAtMinute, 525);
    },
  );
}
