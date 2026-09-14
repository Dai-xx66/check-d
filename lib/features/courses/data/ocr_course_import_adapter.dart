import '../domain/course_import_models.dart';
import '../domain/course_models.dart';
import '../domain/course_schedule_import_models.dart';

class OcrCourseImportAdapter implements CourseImportAdapter {
  const OcrCourseImportAdapter();

  @override
  Set<CourseImportSourceType> get supportedSources => const {
    CourseImportSourceType.imageOcr,
  };

  @override
  bool supports(CourseImportSource source) =>
      supportedSources.contains(source.type);

  @override
  Future<CourseImportDraft> parse(CourseImportSource source) async {
    if (!supports(source) ||
        source.payload is! CourseScheduleRecognitionResult) {
      throw const CourseImportException(
        CourseImportErrorCategory.unsupportedFormat,
        'OCR 导入源格式不受支持。',
      );
    }
    final result = source.payload as CourseScheduleRecognitionResult;
    final detectedByNumber = {
      for (final segment in result.detectedSegments) segment.number: segment,
    };
    return CourseImportDraft(
      schemaVersion: CourseImportDraft.currentSchemaVersion,
      sourceType: CourseImportSourceType.imageOcr,
      issues: result.warnings.map(_issue).toList(),
      courses: [
        for (final course in result.courses)
          CourseImportCourseDraft(
            importKey: course.id,
            title: course.name,
            teacher: course.teacher,
            classroom: course.classroom,
            colorValue: _colorFor(course.name),
            selected: course.selected,
            issues: [
              if (course.name.trim().isEmpty)
                const CourseImportIssue(
                  state: CourseImportFieldState.missing,
                  path: 'course.title',
                  message: '缺少课程名称。',
                ),
              ...course.warnings.map(_issue),
            ],
            scheduleRules: [
              for (final rule in course.rules) _rule(rule, detectedByNumber),
            ],
          ),
      ],
    );
  }

  CourseImportScheduleRuleDraft _rule(
    RecognizedScheduleRuleDraft rule,
    Map<int, RecognizedScheduleSegmentDraft> detectedByNumber,
  ) {
    final segments = [
      for (final number in rule.recognizedSectionNumbers)
        CourseImportSegmentCandidate(
          label: '第$number节',
          order: number - 1,
          startsAtMinute: detectedByNumber[number]?.startsAtMinute,
          endsAtMinute: detectedByNumber[number]?.endsAtMinute,
        ),
    ];
    final detectedStarts = segments
        .map((segment) => segment.startsAtMinute)
        .whereType<int>()
        .toList();
    final detectedEnds = segments
        .map((segment) => segment.endsAtMinute)
        .whereType<int>()
        .toList();
    return CourseImportScheduleRuleDraft(
      weekday: rule.weekday,
      startsAtMinute: rule.recognizedStartsAtMinute ?? _minimum(detectedStarts),
      endsAtMinute: rule.recognizedEndsAtMinute ?? _maximum(detectedEnds),
      weekRuleType: rule.weekRuleType,
      startWeek: rule.startWeek,
      endWeek: rule.endWeek,
      intervalWeeks: rule.intervalWeeks,
      customWeeks: rule.weekNumbers,
      timeMode: segments.isEmpty
          ? CourseScheduleTimeMode.customTime
          : CourseScheduleTimeMode.periods,
      segments: segments,
      issues: [
        if (rule.weekday == null)
          const CourseImportIssue(
            state: CourseImportFieldState.missing,
            path: 'rule.weekday',
            message: '缺少星期。',
          ),
        if (rule.weekRuleType == null || !rule.weekRuleConfirmed)
          const CourseImportIssue(
            state: CourseImportFieldState.ambiguous,
            path: 'rule.weekRule',
            message: '周次规则需要确认。',
          ),
        ...rule.warnings.map(_issue),
      ],
    );
  }

  CourseImportIssue _issue(CourseImportWarning warning) => CourseImportIssue(
    state: switch (warning.kind) {
      CourseImportWarningKind.missingWeekday ||
      CourseImportWarningKind.missingSections ||
      CourseImportWarningKind.scheduleTemplateMissing =>
        CourseImportFieldState.missing,
      CourseImportWarningKind.unmappedSections ||
      CourseImportWarningKind.unconfirmedWeekRule ||
      CourseImportWarningKind.scheduleTemplateTimeConflict =>
        CourseImportFieldState.ambiguous,
      CourseImportWarningKind.possibleDuplicate ||
      CourseImportWarningKind.timeConflict => CourseImportFieldState.conflict,
    },
    path: 'ocr',
    message: warning.message,
  );

  int? _minimum(List<int> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a < b ? a : b);
  int? _maximum(List<int> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);

  int _colorFor(String name) {
    const colors = [0xFF8FA7F5, 0xFFD0A4F5, 0xFF7DCFB6, 0xFFFFB36B, 0xFFF28BA8];
    return colors[name.codeUnits.fold<int>(0, (sum, value) => sum + value) %
        colors.length];
  }
}
