import 'package:check_d/features/courses/application/course_import_pipeline.dart';
import 'package:check_d/features/courses/domain/course_import_models.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/courses/domain/course_schedule_import_models.dart';
import 'package:check_d/features/courses/domain/course_share_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unified import pipeline', () {
    test('single and multiple OCR courses normalize into one draft', () async {
      final pipeline = CourseImportPipeline.standard();
      final single = await pipeline.prepare(
        source: _ocrSource([_recognized('高等数学')]),
        semester: _semesterCandidate,
        targetTemplate: _template,
      );
      expect(single.draft.courses.single.title, '高等数学');
      expect(single.draft.sourceType, CourseImportSourceType.imageOcr);
      expect(single.draft.semester?.matchedLocalSemesterId, 'semester-local');

      final multiple = await pipeline.prepare(
        source: _ocrSource([_recognized('高等数学'), _recognized('英语')]),
        semester: _semesterCandidate,
        targetTemplate: _template,
      );
      expect(multiple.draft.courses, hasLength(2));
    });

    test('week ranges and every week mode survive normalization', () async {
      final result = await CourseImportPipeline.standard().prepare(
        source: _ocrSource([
          _recognized(
            '算法',
            rule: _recognizedRule(
              type: CourseWeekRuleType.everyWeek,
              startWeek: 2,
              endWeek: 16,
            ),
          ),
        ]),
        semester: _semesterCandidate,
        targetTemplate: _template,
      );
      final rule = result.draft.courses.single.scheduleRules.single;
      expect(rule.weekRuleType, CourseWeekRuleType.everyWeek);
      expect(rule.startWeek, 2);
      expect(rule.endWeek, 16);
      expect(result.draft.canConfirm, isTrue);
    });

    test('odd even everyN and custom week modes remain explicit', () async {
      for (final entry in <CourseWeekRuleType, RecognizedScheduleRuleDraft>{
        CourseWeekRuleType.oddWeeks: _recognizedRule(
          type: CourseWeekRuleType.oddWeeks,
        ),
        CourseWeekRuleType.evenWeeks: _recognizedRule(
          type: CourseWeekRuleType.evenWeeks,
        ),
        CourseWeekRuleType.everyNWeeks: _recognizedRule(
          type: CourseWeekRuleType.everyNWeeks,
          intervalWeeks: 3,
        ),
        CourseWeekRuleType.custom: _recognizedRule(
          type: CourseWeekRuleType.custom,
          weeks: {1, 4, 7},
        ),
      }.entries) {
        final result = await CourseImportPipeline.standard().prepare(
          source: _ocrSource([_recognized(entry.key.name, rule: entry.value)]),
          semester: _semesterCandidate,
          targetTemplate: _template,
        );
        final rule = result.draft.courses.single.scheduleRules.single;
        expect(rule.weekRuleType, entry.key);
        if (entry.key == CourseWeekRuleType.everyNWeeks) {
          expect(rule.intervalWeeks, 3);
        }
        if (entry.key == CourseWeekRuleType.custom) {
          expect(rule.customWeeks, {1, 4, 7});
        }
      }
    });

    test(
      'portable segments match local template without sharing local IDs',
      () {
        final resolved = CourseImportTemplateResolver.resolve(
          _draftWithRule(
            CourseImportScheduleRuleDraft(
              weekday: DateTime.monday,
              startsAtMinute: 480,
              endsAtMinute: 525,
              weekRuleType: CourseWeekRuleType.everyWeek,
              timeMode: CourseScheduleTimeMode.periods,
              segments: const [
                CourseImportSegmentCandidate(
                  label: '第1节',
                  order: 0,
                  startsAtMinute: 480,
                  endsAtMinute: 525,
                ),
              ],
            ),
          ),
          _template,
        );
        final rule = resolved.courses.single.scheduleRules.single;
        expect(rule.timeMode, CourseScheduleTimeMode.periods);
        expect(rule.segments.single.matchedLocalSegmentId, 'segment-local');
      },
    );

    test('unmatched portable segment falls back to custom time', () {
      final resolved = CourseImportTemplateResolver.resolve(
        _draftWithRule(
          CourseImportScheduleRuleDraft(
            weekday: DateTime.tuesday,
            startsAtMinute: 600,
            endsAtMinute: 645,
            weekRuleType: CourseWeekRuleType.everyWeek,
            timeMode: CourseScheduleTimeMode.periods,
            segments: const [
              CourseImportSegmentCandidate(
                label: '午间课',
                order: 99,
                startsAtMinute: 600,
                endsAtMinute: 645,
              ),
            ],
          ),
        ),
        _template,
      );
      final rule = resolved.courses.single.scheduleRules.single;
      expect(rule.timeMode, CourseScheduleTimeMode.customTime);
      expect(rule.startsAtMinute, 600);
      expect(rule.endsAtMinute, 645);
      expect(
        rule.issues.any(
          (issue) => issue.state == CourseImportFieldState.sourceWarning,
        ),
        isTrue,
      );
    });

    test(
      'invalid week range is reported without inventing replacement data',
      () {
        final validated = const CourseImportValidator().validate(
          _draftWithRule(
            const CourseImportScheduleRuleDraft(
              weekday: DateTime.monday,
              startsAtMinute: 540,
              endsAtMinute: 500,
              weekRuleType: CourseWeekRuleType.custom,
              startWeek: 10,
              endWeek: 2,
              customWeeks: {21},
            ),
          ),
        );
        final issues = validated.courses.single.scheduleRules.single.issues;
        expect(
          issues.where(
            (issue) => issue.state == CourseImportFieldState.invalid,
          ),
          isNotEmpty,
        );
        expect(validated.canConfirm, isFalse);
      },
    );

    test('conflict checker reports existing and intra-import conflicts', () {
      final draft = CourseImportDraft(
        schemaVersion: 1,
        sourceType: CourseImportSourceType.csv,
        semester: _semesterCandidate,
        courses: [_course('a', '数学', 480, 540), _course('b', '英语', 500, 560)],
      );
      final conflicts = const CourseImportConflictChecker().check(
        draft,
        existingCourses: [_existingCourse],
      );
      expect(
        conflicts.map((item) => item.type),
        containsAll([
          CourseImportConflictType.duplicateCandidate,
          CourseImportConflictType.existingCourseTime,
          CourseImportConflictType.importedCourseTime,
        ]),
      );
    });
  });

  group('share schema', () {
    test('classifies current and future schema compatibility', () {
      expect(
        ShareSchemaVersion.compatibility(ShareSchemaVersion.current),
        ShareSchemaCompatibility.supported,
      );
      expect(
        ShareSchemaVersion.compatibility(ShareSchemaVersion.current + 1),
        ShareSchemaCompatibility.unsupported,
      );
    });

    test('single and semester-wide packages round trip portably', () {
      final draft = CourseImportDraft(
        schemaVersion: 1,
        sourceType: CourseImportSourceType.backup,
        semester: _semesterCandidate,
        courses: [
          _course('local-course-id', '数学', 480, 540),
          _course('second-local-id', '英语', 600, 660),
        ],
      );
      final package = SharePackage.fromDraft(
        draft,
        exportedAt: DateTime.utc(2026, 9, 14),
      );
      final encoded = package.encode();
      final restored = SharePackage.decode(encoded).toImportDraft();

      expect(restored.courses, hasLength(2));
      expect(restored.semester?.name, '2026 秋');
      expect(restored.semester?.matchedLocalSemesterId, isNull);
      expect(encoded, isNot(contains('local-course-id')));
      expect(encoded, isNot(contains('semester-local')));
      expect(encoded, isNot(contains('segment-local')));
    });

    test('share payload excludes private activity and sync data', () {
      final encoded = SharePackage.fromDraft(
        _draftWithRule(
          const CourseImportScheduleRuleDraft(
            weekday: DateTime.monday,
            startsAtMinute: 480,
            endsAtMinute: 540,
            weekRuleType: CourseWeekRuleType.everyWeek,
            reminder: CourseImportReminderDraft(
              advanceMinutes: 10,
              atTime: true,
              explicitlyIncludedBySource: true,
            ),
          ),
        ),
      ).encode();
      for (final privateKey in [
        'userId',
        'TimerSession',
        'Completion',
        'Statistics',
        'syncVersion',
        'reminder',
      ]) {
        expect(encoded, isNot(contains(privateKey)));
      }
    });

    test('notes can be excluded before sharing', () {
      final draft = _draftWithRule(
        const CourseImportScheduleRuleDraft(
          weekday: DateTime.monday,
          startsAtMinute: 480,
          endsAtMinute: 540,
          weekRuleType: CourseWeekRuleType.everyWeek,
        ),
        note: '私人备注',
      );
      expect(
        SharePackage.fromDraft(draft, includeNotes: false).encode(),
        isNot(contains('私人备注')),
      );
    });

    test(
      'invalid payload and unsupported schema version are distinguished',
      () {
        expect(
          () => SharePackage.decode('not-json'),
          throwsA(
            isA<CourseImportException>().having(
              (error) => error.category,
              'category',
              CourseImportErrorCategory.parseFailed,
            ),
          ),
        );
        expect(
          () => SharePackage.decode(
            '{"schemaVersion":99,"sourceApp":"Check D",'
            '"exportedAt":"2026-09-14T00:00:00Z","courses":[]}',
          ),
          throwsA(
            isA<CourseImportException>().having(
              (error) => error.category,
              'category',
              CourseImportErrorCategory.unsupportedFormat,
            ),
          ),
        );
      },
    );
  });
}

final _semesterCandidate = CourseImportSemesterCandidate(
  name: '2026 秋',
  firstWeekStartDate: DateTime(2026, 9, 7),
  totalWeeks: 20,
  matchedLocalSemesterId: 'semester-local',
);

final _template = ScheduleTemplateDetails(
  id: 'template-local',
  name: '大学作息',
  timezone: 'Asia/Shanghai',
  isDefault: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  segments: [
    ScheduleTemplateSegment(
      id: 'segment-local',
      templateId: 'template-local',
      name: '第1节',
      startsAtMinute: 480,
      endsAtMinute: 525,
      segmentType: ScheduleSegmentType.classTime,
      sortOrder: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ],
);

CourseImportSource _ocrSource(List<RecognizedCourseDraft> courses) =>
    CourseImportSource(
      type: CourseImportSourceType.imageOcr,
      payload: CourseScheduleRecognitionResult(courses: courses),
    );

RecognizedCourseDraft _recognized(
  String name, {
  RecognizedScheduleRuleDraft? rule,
}) => RecognizedCourseDraft(
  id: 'draft-$name',
  name: name,
  rules: [rule ?? _recognizedRule(type: CourseWeekRuleType.everyWeek)],
);

RecognizedScheduleRuleDraft _recognizedRule({
  required CourseWeekRuleType type,
  int? startWeek = 1,
  int? endWeek = 16,
  int? intervalWeeks,
  Set<int> weeks = const {},
}) => RecognizedScheduleRuleDraft(
  weekday: DateTime.monday,
  recognizedSectionNumbers: const [1],
  weekRuleType: type,
  startWeek: startWeek,
  endWeek: endWeek,
  intervalWeeks: intervalWeeks,
  weekNumbers: weeks,
);

CourseImportDraft _draftWithRule(
  CourseImportScheduleRuleDraft rule, {
  String? note,
}) => CourseImportDraft(
  schemaVersion: 1,
  sourceType: CourseImportSourceType.csv,
  semester: _semesterCandidate,
  courses: [
    CourseImportCourseDraft(
      importKey: 'local-course-id',
      title: '数学',
      colorValue: 0xFF8FA7F5,
      note: note,
      scheduleRules: [rule],
    ),
  ],
);

CourseImportCourseDraft _course(String key, String title, int start, int end) =>
    CourseImportCourseDraft(
      importKey: key,
      title: title,
      colorValue: 0xFF8FA7F5,
      scheduleRules: [
        CourseImportScheduleRuleDraft(
          weekday: DateTime.monday,
          startsAtMinute: start,
          endsAtMinute: end,
          weekRuleType: CourseWeekRuleType.everyWeek,
        ),
      ],
    );

final _existingCourse = CourseDetails(
  id: 'existing-course-id',
  name: '数学',
  colorValue: 0xFF8FA7F5,
  status: CourseStatus.active,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  rules: [
    CourseScheduleRule(
      id: 'existing-rule-id',
      courseId: 'existing-course-id',
      weekday: DateTime.monday,
      weekRuleType: CourseWeekRuleType.everyWeek,
      startsAtMinute: 490,
      endsAtMinute: 550,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ],
);
