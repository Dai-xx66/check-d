import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/courses/application/course_share_package_builder.dart';
import 'package:check_d/features/courses/application/course_schedule_import_service.dart';
import 'package:check_d/features/courses/data/course_repository.dart';
import 'package:check_d/features/courses/data/course_share_repository.dart';
import 'package:check_d/features/courses/data/semester_repository.dart';
import 'package:check_d/features/courses/domain/course_import_models.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/courses/domain/course_share_models.dart';
import 'package:check_d/features/courses/domain/course_share_schema.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('course share repository', () {
    test('local IDs and private notes are excluded by default', () {
      final now = DateTime.utc(2026, 9, 14);
      final template = ScheduleTemplateDetails(
        id: 'local-template-id',
        name: '本地模板',
        timezone: 'Asia/Shanghai',
        isDefault: true,
        createdAt: now,
        updatedAt: now,
        segments: [
          ScheduleTemplateSegment(
            id: 'local-segment-id',
            templateId: 'local-template-id',
            name: '第一节',
            startsAtMinute: 480,
            endsAtMinute: 525,
            segmentType: ScheduleSegmentType.classTime,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      final semester = SemesterDetails(
        id: 'local-semester-id',
        name: '2026 秋',
        firstWeekStartDate: DateTime(2026, 9, 7),
        totalWeeks: 20,
        scheduleTemplateId: template.id,
        isCurrent: true,
        createdAt: now,
        updatedAt: now,
      );
      final package = CourseSharePackageBuilder.build(
        courses: [
          CourseDetails(
            id: 'local-course-id',
            name: '高等数学',
            colorValue: 0xFFF28BA8,
            status: CourseStatus.active,
            createdAt: now,
            updatedAt: now,
            semesterId: semester.id,
            notes: '私人备注',
            rules: [
              CourseScheduleRule(
                id: 'local-rule-id',
                courseId: 'local-course-id',
                weekday: DateTime.monday,
                weekRuleType: CourseWeekRuleType.everyWeek,
                startsAtMinute: 480,
                endsAtMinute: 525,
                createdAt: now,
                updatedAt: now,
                scheduleTemplateId: template.id,
                sectionIds: const ['local-segment-id'],
                timeMode: CourseScheduleTimeMode.periods,
              ),
            ],
          ),
        ],
        semester: semester,
        template: template,
      );
      final encoded = package.encode();
      expect(encoded, isNot(contains('local-course-id')));
      expect(encoded, isNot(contains('local-semester-id')));
      expect(encoded, isNot(contains('local-segment-id')));
      expect(encoded, isNot(contains('私人备注')));
      expect(
        package.payload.courses.single.scheduleRules.single.segments,
        hasLength(1),
      );
    });

    test('single course encode store fetch decode round trip', () async {
      final remote = _FakeRemoteStore();
      final repository = DefaultCourseShareRepository(remote: remote);
      final created = await repository.createShare(_package(courseCount: 1));
      final fetched = await repository.fetchShare(created.code.toLowerCase());

      expect(CourseShareCode.isValid(created.code), isTrue);
      expect(created.code, contains('-'));
      expect(fetched.package.payload.courses.single.title, '课程 1');
      expect(fetched.package.payload.courses.single.note, isNull);
    });

    test('multi-course package remains complete', () async {
      final repository = DefaultCourseShareRepository(
        remote: _FakeRemoteStore(),
      );
      final created = await repository.createShare(_package(courseCount: 3));
      final fetched = await repository.fetchShare(created.code);
      expect(fetched.package.payload.courses, hasLength(3));
    });

    test('invalid, missing and expired codes stay distinct', () async {
      final remote = _FakeRemoteStore();
      final repository = DefaultCourseShareRepository(remote: remote);
      await expectLater(
        repository.fetchShare('O0I1'),
        throwsA(_category(CourseShareErrorCategory.invalidCode)),
      );
      await expectLater(
        repository.fetchShare('ABCD-2345'),
        throwsA(_category(CourseShareErrorCategory.notFound)),
      );
      remote.records['ABCD2345'] = const CourseShareRemoteRecord(
        status: CourseShareRemoteStatus.expired,
      );
      await expectLater(
        repository.fetchShare('abcd2345'),
        throwsA(_category(CourseShareErrorCategory.expired)),
      );
    });

    test('corrupted and unsupported payloads stay distinct', () async {
      final remote = _FakeRemoteStore();
      final repository = DefaultCourseShareRepository(remote: remote);
      remote.records['ABCD2345'] = CourseShareRemoteRecord(
        status: CourseShareRemoteStatus.found,
        expiresAt: DateTime(2026, 9, 20),
        payload: '{broken',
      );
      await expectLater(
        repository.fetchShare('ABCD2345'),
        throwsA(_category(CourseShareErrorCategory.corruptedPayload)),
      );
      remote.records['EFGH6789'] = CourseShareRemoteRecord(
        status: CourseShareRemoteStatus.found,
        expiresAt: DateTime(2026, 9, 20),
        payload:
            '{"schemaVersion":999,"sourceApp":"Check D",'
            '"exportedAt":"2026-09-14T00:00:00Z","courses":[]}',
      );
      await expectLater(
        repository.fetchShare('EFGH6789'),
        throwsA(_category(CourseShareErrorCategory.unsupportedSchema)),
      );
    });

    test('offline fetch returns a network-specific error', () async {
      final remote = _FakeRemoteStore()..networkUnavailable = true;
      final repository = DefaultCourseShareRepository(remote: remote);
      await expectLater(
        repository.fetchShare('ABCD2345'),
        throwsA(_category(CourseShareErrorCategory.networkUnavailable)),
      );
    });

    test('creating requires authentication-capable remote', () async {
      final repository = DefaultCourseShareRepository(
        remote: _FakeRemoteStore(canCreate: false),
      );
      await expectLater(
        repository.createShare(_package(courseCount: 1)),
        throwsA(_category(CourseShareErrorCategory.authenticationRequired)),
      );
    });

    test('course count and payload size limits are enforced', () async {
      final countRepository = DefaultCourseShareRepository(
        remote: _FakeRemoteStore(),
        config: const CourseShareConfig(maxCourses: 1),
      );
      await expectLater(
        countRepository.createShare(_package(courseCount: 2)),
        throwsA(_category(CourseShareErrorCategory.tooManyCourses)),
      );
      final sizeRepository = DefaultCourseShareRepository(
        remote: _FakeRemoteStore(),
        config: const CourseShareConfig(maxPayloadBytes: 10),
      );
      await expectLater(
        sizeRepository.createShare(_package(courseCount: 1)),
        throwsA(_category(CourseShareErrorCategory.packageTooLarge)),
      );
    });

    test('QR payload parses deep links and rejects unrelated links', () {
      expect(
        CourseShareCode.fromQrValue('checkd://share/abcd2345'),
        'ABCD2345',
      );
      expect(
        () => CourseShareCode.fromQrValue('https://example.com/ABCD2345'),
        throwsA(_category(CourseShareErrorCategory.invalidCode)),
      );
    });
  });

  group('shared course import confirmation', () {
    late AppDatabase database;
    late CourseRepository courses;
    late SemesterRepository semesters;
    late CourseScheduleImportService service;

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
      service = CourseScheduleImportService(
        courses: courses,
        semesters: semesters,
      );
    });

    tearDown(() => database.close());

    test(
      'preview writes nothing and confirm imports selected courses',
      () async {
        final templateId = await courses.saveScheduleTemplate(
          const ScheduleTemplateDraft(
            name: '本地作息',
            segments: [
              ScheduleTemplateSegmentDraft(
                name: '第一节',
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
        final result = await service.prepareShare(
          package: _package(courseCount: 2),
          semester: semester,
          template: template,
        );

        expect(await courses.loadCourses(), isEmpty);
        final draft = result.draft.copyWith(
          courses: [
            result.draft.courses.first,
            result.draft.courses.last.copyWith(selected: false),
          ],
        );
        final count = await service.confirmDraft(
          draft: draft,
          semester: semester,
          template: template,
        );
        final imported = await courses.loadCourses();
        expect(count, 1);
        expect(imported.single.name, '课程 1');
        expect(imported.single.rules.single.sectionIds, hasLength(1));
      },
    );

    test('existing duplicate is reported but never auto-merged', () async {
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
      final existingId = await courses.saveCourse(
        CourseDraft(
          name: '课程 1',
          colorValue: 0xFFF28BA8,
          semesterId: semester.id,
        ),
      );
      await courses.saveScheduleRule(
        CourseScheduleRuleDraft(
          courseId: existingId,
          weekday: DateTime.monday,
          weekRuleType: CourseWeekRuleType.everyWeek,
          startsAtMinute: 480,
          endsAtMinute: 525,
        ),
      );
      final result = await service.prepareShare(
        package: _package(courseCount: 1),
        semester: semester,
        template: null,
      );
      expect(
        result.conflicts.map((item) => item.type),
        contains(CourseImportConflictType.duplicateCandidate),
      );
      expect(await courses.loadCourses(), hasLength(1));
    });
  });
}

Matcher _category(CourseShareErrorCategory category) =>
    isA<CourseShareException>().having(
      (error) => error.category,
      'category',
      category,
    );

SharePackage _package({required int courseCount}) => SharePackage(
  SharePayload(
    schemaVersion: ShareSchemaVersion.current,
    sourceApp: 'Check D',
    exportedAt: DateTime.utc(2026, 9, 14),
    semester: ShareSemester(
      name: '2026 秋',
      firstWeekStartDate: DateTime(2026, 9, 7),
      totalWeeks: 20,
    ),
    courses: [
      for (var index = 1; index <= courseCount; index++)
        ShareCourse(
          title: '课程 $index',
          colorValue: 0xFFF28BA8,
          scheduleRules: const [
            ShareScheduleRule(
              weekday: DateTime.monday,
              startsAtMinute: 480,
              endsAtMinute: 525,
              weekRuleType: CourseWeekRuleType.everyWeek,
              startWeek: 1,
              endWeek: 16,
              segments: [
                ShareScheduleSegment(
                  label: '第一节',
                  startsAtMinute: 480,
                  endsAtMinute: 525,
                  order: 0,
                ),
              ],
            ),
          ],
        ),
    ],
  ),
);

class _FakeRemoteStore implements CourseShareRemoteStore {
  _FakeRemoteStore({this.canCreate = true});

  @override
  final bool canCreate;
  bool networkUnavailable = false;
  final Map<String, CourseShareRemoteRecord> records = {};

  @override
  Future<bool> create({
    required String code,
    required int schemaVersion,
    required String payload,
    required DateTime expiresAt,
  }) async {
    if (networkUnavailable) {
      throw const CourseShareRemoteException(networkUnavailable: true);
    }
    if (records.containsKey(code)) return false;
    records[code] = CourseShareRemoteRecord(
      status: CourseShareRemoteStatus.found,
      code: code,
      expiresAt: expiresAt,
      payload: payload,
    );
    return true;
  }

  @override
  Future<CourseShareRemoteRecord> fetch(String code) async {
    if (networkUnavailable) {
      throw const CourseShareRemoteException(networkUnavailable: true);
    }
    return records[code] ??
        const CourseShareRemoteRecord(status: CourseShareRemoteStatus.notFound);
  }

  @override
  Future<void> delete(String code) async {
    records.remove(code);
  }
}
