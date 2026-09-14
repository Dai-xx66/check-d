import '../data/ocr_course_import_adapter.dart';
import '../data/share_package_import_adapter.dart';
import '../data/course_spreadsheet_import_adapter.dart';
import '../data/course_document_import_adapter.dart';
import '../domain/course_import_models.dart';
import '../domain/course_models.dart';

class CourseImportPipeline {
  CourseImportPipeline({
    required List<CourseImportAdapter> adapters,
    CourseImportValidator validator = const CourseImportValidator(),
    CourseImportConflictChecker conflictChecker =
        const CourseImportConflictChecker(),
  }) : _adapters = adapters,
       _validator = validator,
       _conflictChecker = conflictChecker;

  factory CourseImportPipeline.standard() => CourseImportPipeline(
    adapters: const [
      OcrCourseImportAdapter(),
      SharePackageImportAdapter(),
      CourseSpreadsheetImportAdapter(),
      CourseDocumentImportAdapter(),
    ],
  );

  final List<CourseImportAdapter> _adapters;
  final CourseImportValidator _validator;
  final CourseImportConflictChecker _conflictChecker;

  Future<CourseImportPipelineResult> prepare({
    required CourseImportSource source,
    required CourseImportSemesterCandidate semester,
    ScheduleTemplateDetails? targetTemplate,
    List<CourseDetails> existingCourses = const [],
  }) async {
    final adapter = _adapters
        .where((item) => item.supports(source))
        .firstOrNull;
    if (adapter == null) {
      throw CourseImportException(
        CourseImportErrorCategory.unsupportedFormat,
        '暂不支持 ${source.type.name} 导入。',
      );
    }
    var draft = (await adapter.parse(source)).copyWith(semester: semester);
    draft = CourseImportTemplateResolver.resolve(draft, targetTemplate);
    draft = _validator.validate(draft, targetTemplate: targetTemplate);
    final conflicts = _conflictChecker.check(
      draft,
      existingCourses: existingCourses,
    );
    if (conflicts.isNotEmpty) {
      draft = _attachConflicts(draft, conflicts);
    }
    return CourseImportPipelineResult(draft: draft, conflicts: conflicts);
  }

  CourseImportDraft _attachConflicts(
    CourseImportDraft draft,
    List<CourseImportConflict> conflicts,
  ) => draft.copyWith(
    courses: [
      for (final course in draft.courses)
        course.copyWith(
          issues: [
            ...course.issues,
            for (final conflict in conflicts)
              if (conflict.courseImportKey == course.importKey)
                CourseImportIssue(
                  state: CourseImportFieldState.conflict,
                  path: 'course.scheduleRules',
                  message: conflict.message,
                ),
          ],
        ),
    ],
  );
}

abstract final class CourseImportTemplateResolver {
  static CourseImportDraft resolve(
    CourseImportDraft draft,
    ScheduleTemplateDetails? template,
  ) => draft.copyWith(
    courses: [
      for (final course in draft.courses)
        course.copyWith(
          scheduleRules: [
            for (final rule in course.scheduleRules)
              _resolveRule(rule, template),
          ],
        ),
    ],
  );

  static CourseImportScheduleRuleDraft _resolveRule(
    CourseImportScheduleRuleDraft rule,
    ScheduleTemplateDetails? template,
  ) {
    if (rule.segments.isEmpty) return rule;
    final resolved = <CourseImportSegmentCandidate>[];
    for (final candidate in rule.segments) {
      final match = template == null ? null : _match(candidate, template);
      resolved.add(
        match == null
            ? candidate
            : candidate.copyWith(
                startsAtMinute: match.startsAtMinute,
                endsAtMinute: match.endsAtMinute,
                matchedLocalSegmentId: match.id,
              ),
      );
    }
    final allMatched =
        template != null &&
        resolved.every((segment) => segment.matchedLocalSegmentId != null);
    final starts = resolved
        .map((segment) => segment.startsAtMinute)
        .whereType<int>()
        .toList();
    final ends = resolved
        .map((segment) => segment.endsAtMinute)
        .whereType<int>()
        .toList();
    final hasPortableTimes =
        starts.length == resolved.length && ends.length == resolved.length;
    if (allMatched) {
      return rule.copyWith(
        startsAtMinute: _minimum(starts),
        endsAtMinute: _maximum(ends),
        timeMode: CourseScheduleTimeMode.periods,
        segments: resolved,
      );
    }
    return rule.copyWith(
      startsAtMinute: rule.startsAtMinute ?? _minimum(starts),
      endsAtMinute: rule.endsAtMinute ?? _maximum(ends),
      timeMode: CourseScheduleTimeMode.customTime,
      segments: resolved,
      issues: [
        ...rule.issues,
        CourseImportIssue(
          state: hasPortableTimes
              ? CourseImportFieldState.sourceWarning
              : CourseImportFieldState.missing,
          path: 'rule.segments',
          message: hasPortableTimes
              ? '接收方作息模板没有匹配节次，已保留为自定义时间。'
              : '节次无法匹配且缺少可重建的时间，请在预览中确认。',
        ),
      ],
    );
  }

  static ScheduleTemplateSegment? _match(
    CourseImportSegmentCandidate candidate,
    ScheduleTemplateDetails template,
  ) {
    final classSegments =
        template.segments
            .where(
              (segment) => segment.segmentType == ScheduleSegmentType.classTime,
            )
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final hasPortableTime =
        candidate.startsAtMinute != null && candidate.endsAtMinute != null;
    if (hasPortableTime) {
      for (final segment in classSegments) {
        if (segment.startsAtMinute == candidate.startsAtMinute &&
            segment.endsAtMinute == candidate.endsAtMinute) {
          return segment;
        }
      }
      return null;
    }
    final normalizedLabel = _normalize(candidate.label);
    for (final segment in classSegments) {
      if (_normalize(segment.name) == normalizedLabel) return segment;
    }
    if (candidate.order >= 0 && candidate.order < classSegments.length) {
      return classSegments[candidate.order];
    }
    return null;
  }

  static int? _minimum(List<int> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a < b ? a : b);
  static int? _maximum(List<int> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

class CourseImportValidator {
  const CourseImportValidator();

  static CourseImportDraft validateForConfirm(
    CourseImportDraft draft, {
    ScheduleTemplateDetails? targetTemplate,
  }) => const CourseImportValidator().validate(
    draft,
    targetTemplate: targetTemplate,
  );

  CourseImportDraft validate(
    CourseImportDraft draft, {
    ScheduleTemplateDetails? targetTemplate,
  }) {
    final semesterIssues = <CourseImportIssue>[];
    final semester = draft.semester;
    if (semester == null || semester.name.trim().isEmpty) {
      semesterIssues.add(
        const CourseImportIssue(
          state: CourseImportFieldState.missing,
          path: 'semester',
          message: '请选择或创建目标学期。',
        ),
      );
    } else if (semester.totalWeeks <= 0) {
      semesterIssues.add(
        const CourseImportIssue(
          state: CourseImportFieldState.invalid,
          path: 'semester.totalWeeks',
          message: '学期周数无效。',
        ),
      );
    }
    return draft.copyWith(
      issues: [...draft.issues, ...semesterIssues],
      courses: [
        for (
          var courseIndex = 0;
          courseIndex < draft.courses.length;
          courseIndex++
        )
          _validateCourse(
            draft.courses[courseIndex],
            courseIndex,
            semester,
            targetTemplate,
          ),
      ],
    );
  }

  CourseImportCourseDraft _validateCourse(
    CourseImportCourseDraft course,
    int courseIndex,
    CourseImportSemesterCandidate? semester,
    ScheduleTemplateDetails? targetTemplate,
  ) {
    final issues = [...course.issues];
    if (course.title.trim().isEmpty) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.missing,
          path: 'courses[$courseIndex].title',
          message: '缺少课程名称。',
        ),
      );
    }
    if (course.scheduleRules.isEmpty) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.missing,
          path: 'courses[$courseIndex].scheduleRules',
          message: '课程至少需要一条安排。',
        ),
      );
    }
    return course.copyWith(
      issues: issues,
      scheduleRules: [
        for (
          var ruleIndex = 0;
          ruleIndex < course.scheduleRules.length;
          ruleIndex++
        )
          _validateRule(
            course.scheduleRules[ruleIndex],
            courseIndex,
            ruleIndex,
            semester,
            targetTemplate,
          ),
      ],
    );
  }

  CourseImportScheduleRuleDraft _validateRule(
    CourseImportScheduleRuleDraft rule,
    int courseIndex,
    int ruleIndex,
    CourseImportSemesterCandidate? semester,
    ScheduleTemplateDetails? targetTemplate,
  ) {
    final path = 'courses[$courseIndex].scheduleRules[$ruleIndex]';
    final issues = [...rule.issues];
    if (rule.weekday == null || rule.weekRuleType == null) {
      if (rule.weekday == null) {
        issues.add(
          CourseImportIssue(
            state: CourseImportFieldState.missing,
            path: '$path.weekday',
            message: '缺少星期。',
          ),
        );
      }
      if (rule.weekRuleType == null) {
        issues.add(
          CourseImportIssue(
            state: CourseImportFieldState.ambiguous,
            path: '$path.weekRule',
            message: '周次规则需要确认。',
          ),
        );
      }
      return rule.copyWith(issues: issues);
    }
    if (rule.startsAtMinute == null || rule.endsAtMinute == null) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.missing,
          path: '$path.time',
          message: '缺少课程开始或结束时间。',
        ),
      );
      return rule.copyWith(issues: issues);
    }
    if (rule.startWeek != null &&
        (rule.startWeek! <= 0 ||
            semester != null && rule.startWeek! > semester.totalWeeks)) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.invalid,
          path: '$path.startWeek',
          message: '起始周不在目标学期范围内。',
        ),
      );
    }
    if (rule.endWeek != null &&
        (rule.endWeek! <= 0 ||
            rule.startWeek != null && rule.endWeek! < rule.startWeek! ||
            semester != null && rule.endWeek! > semester.totalWeeks)) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.invalid,
          path: '$path.endWeek',
          message: '结束周不在目标学期范围内。',
        ),
      );
    }
    if (semester != null &&
        rule.customWeeks.any(
          (week) => week <= 0 || week > semester.totalWeeks,
        )) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.invalid,
          path: '$path.customWeeks',
          message: '自定义周次包含学期范围外的周数。',
        ),
      );
    }
    final segmentIds = rule.segments
        .map((segment) => segment.matchedLocalSegmentId)
        .whereType<String>()
        .toList();
    try {
      validateCourseScheduleRuleDraft(
        CourseScheduleRuleDraft(
          courseId: 'import-preview',
          weekday: rule.weekday!,
          weekRuleType: rule.weekRuleType!,
          startsAtMinute: rule.startsAtMinute!,
          endsAtMinute: rule.endsAtMinute!,
          startWeek: rule.startWeek,
          endWeek: rule.endWeek,
          intervalWeeks: rule.intervalWeeks,
          weekNumbers: rule.customWeeks,
          scheduleTemplateId: rule.timeMode == CourseScheduleTimeMode.periods
              ? targetTemplate?.id
              : null,
          sectionIds: segmentIds,
          timeMode: rule.timeMode,
          classroomOverride: rule.classroomOverride,
          notes: rule.note,
        ),
      );
    } on ArgumentError catch (error) {
      issues.add(
        CourseImportIssue(
          state: CourseImportFieldState.invalid,
          path: path,
          message: error.message?.toString() ?? '课程安排无效。',
        ),
      );
    }
    return rule.copyWith(issues: issues);
  }
}

class CourseImportConflictChecker {
  const CourseImportConflictChecker();

  List<CourseImportConflict> check(
    CourseImportDraft draft, {
    List<CourseDetails> existingCourses = const [],
  }) {
    final conflicts = <CourseImportConflict>[];
    for (final course in draft.courses.where((item) => item.selected)) {
      for (final existing in existingCourses) {
        for (final rule in course.scheduleRules) {
          for (final existingRule in existing.rules) {
            if (!_overlaps(rule, existingRule, draft.semester?.totalWeeks)) {
              continue;
            }
            final duplicate =
                _normalize(course.title) == _normalize(existing.name);
            conflicts.add(
              CourseImportConflict(
                type: duplicate
                    ? CourseImportConflictType.duplicateCandidate
                    : CourseImportConflictType.existingCourseTime,
                courseImportKey: course.importKey,
                existingCourseId: existing.id,
                message: duplicate ? '可能与已有课程重复。' : '与已有课程时间冲突。',
              ),
            );
          }
        }
      }
    }
    for (var first = 0; first < draft.courses.length; first++) {
      final a = draft.courses[first];
      if (!a.selected) continue;
      for (var second = first + 1; second < draft.courses.length; second++) {
        final b = draft.courses[second];
        if (!b.selected) continue;
        if (a.scheduleRules.any(
          (aRule) => b.scheduleRules.any(
            (bRule) =>
                _overlapsDrafts(aRule, bRule, draft.semester?.totalWeeks),
          ),
        )) {
          conflicts.add(
            CourseImportConflict(
              type: CourseImportConflictType.importedCourseTime,
              courseImportKey: a.importKey,
              otherCourseImportKey: b.importKey,
              message: '导入课程“${a.title}”与“${b.title}”时间冲突。',
            ),
          );
        }
      }
    }
    return conflicts;
  }

  bool _overlaps(
    CourseImportScheduleRuleDraft imported,
    CourseScheduleRule existing,
    int? totalWeeks,
  ) =>
      imported.weekday == existing.weekday &&
      _timeOverlaps(
        imported.startsAtMinute,
        imported.endsAtMinute,
        existing.startsAtMinute,
        existing.endsAtMinute,
      ) &&
      _weeks(
        imported,
        totalWeeks,
      ).intersection(_existingWeeks(existing, totalWeeks)).isNotEmpty;

  bool _overlapsDrafts(
    CourseImportScheduleRuleDraft a,
    CourseImportScheduleRuleDraft b,
    int? totalWeeks,
  ) =>
      a.weekday == b.weekday &&
      _timeOverlaps(
        a.startsAtMinute,
        a.endsAtMinute,
        b.startsAtMinute,
        b.endsAtMinute,
      ) &&
      _weeks(a, totalWeeks).intersection(_weeks(b, totalWeeks)).isNotEmpty;

  bool _timeOverlaps(int? aStart, int? aEnd, int? bStart, int? bEnd) =>
      aStart != null &&
      aEnd != null &&
      bStart != null &&
      bEnd != null &&
      aStart < bEnd &&
      bStart < aEnd;

  Set<int> _weeks(CourseImportScheduleRuleDraft rule, int? totalWeeks) =>
      _weekSet(
        type: rule.weekRuleType,
        startWeek: rule.startWeek,
        endWeek: rule.endWeek,
        intervalWeeks: rule.intervalWeeks,
        customWeeks: rule.customWeeks,
        totalWeeks: totalWeeks,
      );

  Set<int> _existingWeeks(CourseScheduleRule rule, int? totalWeeks) => _weekSet(
    type: rule.weekRuleType,
    startWeek: rule.startWeek,
    endWeek: rule.endWeek,
    intervalWeeks: rule.intervalWeeks,
    customWeeks: rule.weekNumbers,
    totalWeeks: totalWeeks,
  );

  Set<int> _weekSet({
    required CourseWeekRuleType? type,
    required int? startWeek,
    required int? endWeek,
    required int? intervalWeeks,
    required Set<int> customWeeks,
    required int? totalWeeks,
  }) {
    if (type == CourseWeekRuleType.custom) return customWeeks;
    final start = startWeek ?? 1;
    final end = endWeek ?? totalWeeks ?? 60;
    final interval = intervalWeeks == null || intervalWeeks <= 0
        ? 1
        : intervalWeeks;
    return {
      for (var week = start; week <= end; week++)
        if (switch (type) {
          CourseWeekRuleType.oddWeeks => week.isOdd,
          CourseWeekRuleType.evenWeeks => week.isEven,
          CourseWeekRuleType.everyNWeeks => (week - start) % interval == 0,
          CourseWeekRuleType.everyWeek || null => true,
          CourseWeekRuleType.custom => false,
        })
          week,
    };
  }

  String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}
