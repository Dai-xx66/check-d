import 'course_models.dart';
import 'local_ocr_models.dart';

enum CourseImportWarningKind {
  missingWeekday,
  missingSections,
  unmappedSections,
  unconfirmedWeekRule,
  possibleDuplicate,
  timeConflict,
  scheduleTemplateMissing,
  scheduleTemplateTimeConflict,
}

class CourseImportWarning {
  const CourseImportWarning(this.kind, this.message);

  final CourseImportWarningKind kind;
  final String message;
}

/// A recognition result is intentionally not a Course. It remains editable and
/// cannot write to persistence until the user confirms the import.
class RecognizedCourseDraft {
  RecognizedCourseDraft({
    required this.id,
    required this.name,
    this.teacher,
    this.classroom,
    this.selected = true,
    this.rules = const [],
    this.warnings = const [],
  });

  final String id;
  String name;
  String? teacher;
  String? classroom;
  bool selected;
  List<RecognizedScheduleRuleDraft> rules;
  List<CourseImportWarning> warnings;

  bool get isReady =>
      name.trim().isNotEmpty &&
      rules.isNotEmpty &&
      rules.every((rule) => rule.isReady);
}

class RecognizedScheduleRuleDraft {
  RecognizedScheduleRuleDraft({
    required this.weekday,
    required this.recognizedSectionNumbers,
    required this.weekRuleType,
    this.startWeek,
    this.endWeek,
    this.intervalWeeks,
    Set<int>? weekNumbers,
    List<String>? mappedSegmentIds,
    this.recognizedStartsAtMinute,
    this.recognizedEndsAtMinute,
    this.weekRuleConfirmed = true,
    this.warnings = const [],
  }) : weekNumbers = weekNumbers ?? {},
       mappedSegmentIds = mappedSegmentIds ?? [];

  int? weekday;
  List<int> recognizedSectionNumbers;
  List<String> mappedSegmentIds;
  CourseWeekRuleType? weekRuleType;
  int? startWeek;
  int? endWeek;
  int? intervalWeeks;
  Set<int> weekNumbers;
  int? recognizedStartsAtMinute;
  int? recognizedEndsAtMinute;
  bool weekRuleConfirmed;
  List<CourseImportWarning> warnings;

  bool get isReady =>
      weekday != null &&
      mappedSegmentIds.isNotEmpty &&
      weekRuleType != null &&
      weekRuleConfirmed;
}

class CourseScheduleRecognitionResult {
  const CourseScheduleRecognitionResult({
    required this.courses,
    this.detectedSegments = const [],
    this.warnings = const [],
    this.debug,
  });

  final List<RecognizedCourseDraft> courses;
  final List<RecognizedScheduleSegmentDraft> detectedSegments;
  final List<CourseImportWarning> warnings;
  final CourseScheduleParseDebug? debug;
}

/// Geometry retained only while diagnosing local OCR and schedule parsing.
/// It is never persisted and is ignored by the import path.
class CourseScheduleParseDebug {
  const CourseScheduleParseDebug({
    this.weekdayColumns = const [],
    this.sectionRows = const [],
    this.acceptedCells = const [],
    this.rejectedTokens = const [],
  });

  final List<OcrBoundingBox> weekdayColumns;
  final List<OcrBoundingBox> sectionRows;
  final List<OcrBoundingBox> acceptedCells;
  final List<OcrBoundingBox> rejectedTokens;
}

class RecognizedScheduleSegmentDraft {
  const RecognizedScheduleSegmentDraft({
    required this.number,
    required this.startsAtMinute,
    required this.endsAtMinute,
  });

  final int number;
  final int startsAtMinute;
  final int endsAtMinute;
}

class CourseImportPlan {
  const CourseImportPlan({
    required this.semester,
    required this.template,
    required this.courses,
    this.templateDraft,
    this.templateTimeConflict = false,
  });

  final SemesterDetails semester;
  final ScheduleTemplateDetails? template;
  final List<RecognizedCourseDraft> courses;
  final ScheduleTemplateDraft? templateDraft;
  final bool templateTimeConflict;

  bool get needsTemplate => template == null && templateDraft == null;
  bool get canImport =>
      !needsTemplate &&
      courses
          .where((course) => course.selected)
          .every((course) => course.isReady);
}

class CourseImportRequest {
  const CourseImportRequest({
    required this.semester,
    required this.template,
    required this.courses,
  });

  final SemesterDetails semester;
  final ScheduleTemplateDetails template;
  final List<RecognizedCourseDraft> courses;
}
