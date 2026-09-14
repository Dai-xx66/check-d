import 'course_models.dart';

enum CourseImportSourceType {
  imageOcr,
  excel,
  csv,
  html,
  pdf,
  backup,
  shareCode,
  qrCode,
  aiNaturalLanguage,
  schoolProvider,
}

enum CourseImportErrorCategory {
  sourceReadFailed,
  parseFailed,
  unsupportedFormat,
  invalidDraft,
  conflict,
  userCancelled,
  providerUnavailable,
}

class CourseImportException implements Exception {
  const CourseImportException(this.category, this.message);

  final CourseImportErrorCategory category;
  final String message;

  @override
  String toString() => message;
}

enum CourseImportFieldState {
  parsed,
  missing,
  ambiguous,
  invalid,
  conflict,
  sourceWarning,
}

class CourseImportIssue {
  const CourseImportIssue({
    required this.state,
    required this.path,
    required this.message,
  });

  final CourseImportFieldState state;
  final String path;
  final String message;

  bool get blocksImport =>
      state == CourseImportFieldState.missing ||
      state == CourseImportFieldState.invalid ||
      state == CourseImportFieldState.ambiguous;
}

class CourseImportSource {
  const CourseImportSource({
    required this.type,
    required this.payload,
    this.filename,
    this.mimeType,
  });

  final CourseImportSourceType type;
  final Object payload;
  final String? filename;
  final String? mimeType;
}

abstract interface class CourseImportAdapter {
  Set<CourseImportSourceType> get supportedSources;

  bool supports(CourseImportSource source) =>
      supportedSources.contains(source.type);

  Future<CourseImportDraft> parse(CourseImportSource source);
}

class CourseImportSemesterCandidate {
  const CourseImportSemesterCandidate({
    required this.name,
    required this.firstWeekStartDate,
    required this.totalWeeks,
    this.matchedLocalSemesterId,
  });

  final String name;
  final DateTime firstWeekStartDate;
  final int totalWeeks;
  final String? matchedLocalSemesterId;

  CourseImportSemesterCandidate copyWith({String? matchedLocalSemesterId}) =>
      CourseImportSemesterCandidate(
        name: name,
        firstWeekStartDate: firstWeekStartDate,
        totalWeeks: totalWeeks,
        matchedLocalSemesterId:
            matchedLocalSemesterId ?? this.matchedLocalSemesterId,
      );
}

class CourseImportSegmentCandidate {
  const CourseImportSegmentCandidate({
    required this.label,
    required this.order,
    this.startsAtMinute,
    this.endsAtMinute,
    this.matchedLocalSegmentId,
  });

  final String label;
  final int order;
  final int? startsAtMinute;
  final int? endsAtMinute;
  final String? matchedLocalSegmentId;

  CourseImportSegmentCandidate copyWith({
    int? startsAtMinute,
    int? endsAtMinute,
    String? matchedLocalSegmentId,
  }) => CourseImportSegmentCandidate(
    label: label,
    order: order,
    startsAtMinute: startsAtMinute ?? this.startsAtMinute,
    endsAtMinute: endsAtMinute ?? this.endsAtMinute,
    matchedLocalSegmentId: matchedLocalSegmentId ?? this.matchedLocalSegmentId,
  );
}

class CourseImportReminderDraft {
  const CourseImportReminderDraft({
    this.advanceMinutes,
    this.atTime = false,
    this.explicitlyIncludedBySource = false,
  });

  final int? advanceMinutes;
  final bool atTime;
  final bool explicitlyIncludedBySource;
}

class CourseImportScheduleRuleDraft {
  const CourseImportScheduleRuleDraft({
    required this.weekRuleType,
    this.weekday,
    this.startsAtMinute,
    this.endsAtMinute,
    this.startWeek,
    this.endWeek,
    this.intervalWeeks,
    this.customWeeks = const {},
    this.timeMode = CourseScheduleTimeMode.customTime,
    this.segments = const [],
    this.classroomOverride,
    this.note,
    this.reminder,
    this.issues = const [],
  });

  final int? weekday;
  final int? startsAtMinute;
  final int? endsAtMinute;
  final CourseWeekRuleType? weekRuleType;
  final int? startWeek;
  final int? endWeek;
  final int? intervalWeeks;
  final Set<int> customWeeks;
  final CourseScheduleTimeMode timeMode;
  final List<CourseImportSegmentCandidate> segments;
  final String? classroomOverride;
  final String? note;
  final CourseImportReminderDraft? reminder;
  final List<CourseImportIssue> issues;

  CourseImportScheduleRuleDraft copyWith({
    int? startsAtMinute,
    int? endsAtMinute,
    CourseScheduleTimeMode? timeMode,
    List<CourseImportSegmentCandidate>? segments,
    List<CourseImportIssue>? issues,
  }) => CourseImportScheduleRuleDraft(
    weekday: weekday,
    startsAtMinute: startsAtMinute ?? this.startsAtMinute,
    endsAtMinute: endsAtMinute ?? this.endsAtMinute,
    weekRuleType: weekRuleType,
    startWeek: startWeek,
    endWeek: endWeek,
    intervalWeeks: intervalWeeks,
    customWeeks: customWeeks,
    timeMode: timeMode ?? this.timeMode,
    segments: segments ?? this.segments,
    classroomOverride: classroomOverride,
    note: note,
    reminder: reminder,
    issues: issues ?? this.issues,
  );
}

class CourseImportCourseDraft {
  const CourseImportCourseDraft({
    required this.importKey,
    required this.title,
    required this.colorValue,
    this.teacher,
    this.classroom,
    this.note,
    this.selected = true,
    this.scheduleRules = const [],
    this.issues = const [],
  });

  /// Ephemeral within a preview. It is never exported as a database identity.
  final String importKey;
  final String title;
  final String? teacher;
  final String? classroom;
  final int colorValue;
  final String? note;
  final bool selected;
  final List<CourseImportScheduleRuleDraft> scheduleRules;
  final List<CourseImportIssue> issues;

  CourseImportCourseDraft copyWith({
    String? title,
    String? teacher,
    String? classroom,
    int? colorValue,
    String? note,
    bool? selected,
    List<CourseImportScheduleRuleDraft>? scheduleRules,
    List<CourseImportIssue>? issues,
  }) => CourseImportCourseDraft(
    importKey: importKey,
    title: title ?? this.title,
    teacher: teacher ?? this.teacher,
    classroom: classroom ?? this.classroom,
    colorValue: colorValue ?? this.colorValue,
    note: note ?? this.note,
    selected: selected ?? this.selected,
    scheduleRules: scheduleRules ?? this.scheduleRules,
    issues: issues ?? this.issues,
  );
}

class CourseImportDraft {
  const CourseImportDraft({
    required this.schemaVersion,
    required this.sourceType,
    required this.courses,
    this.semester,
    this.issues = const [],
  });

  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final CourseImportSourceType sourceType;
  final CourseImportSemesterCandidate? semester;
  final List<CourseImportCourseDraft> courses;
  final List<CourseImportIssue> issues;

  bool get canConfirm {
    final selected = courses.where((course) => course.selected);
    return selected.isNotEmpty &&
        !issues.any((issue) => issue.blocksImport) &&
        selected.every(
          (course) =>
              !course.issues.any((issue) => issue.blocksImport) &&
              course.scheduleRules.isNotEmpty &&
              course.scheduleRules.every(
                (rule) => !rule.issues.any((issue) => issue.blocksImport),
              ),
        );
  }

  CourseImportDraft copyWith({
    CourseImportSemesterCandidate? semester,
    List<CourseImportCourseDraft>? courses,
    List<CourseImportIssue>? issues,
  }) => CourseImportDraft(
    schemaVersion: schemaVersion,
    sourceType: sourceType,
    semester: semester ?? this.semester,
    courses: courses ?? this.courses,
    issues: issues ?? this.issues,
  );
}

enum CourseImportConflictType {
  existingCourseTime,
  importedCourseTime,
  duplicateCandidate,
}

class CourseImportConflict {
  const CourseImportConflict({
    required this.type,
    required this.courseImportKey,
    required this.message,
    this.otherCourseImportKey,
    this.existingCourseId,
  });

  final CourseImportConflictType type;
  final String courseImportKey;
  final String? otherCourseImportKey;
  final String? existingCourseId;
  final String message;
}

class CourseImportPipelineResult {
  const CourseImportPipelineResult({
    required this.draft,
    this.conflicts = const [],
  });

  final CourseImportDraft draft;
  final List<CourseImportConflict> conflicts;
}
