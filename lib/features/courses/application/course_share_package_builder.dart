import '../domain/course_import_models.dart';
import '../domain/course_models.dart';
import '../domain/course_share_schema.dart';

abstract final class CourseSharePackageBuilder {
  static SharePackage build({
    required List<CourseDetails> courses,
    SemesterDetails? semester,
    ScheduleTemplateDetails? template,
    bool includeNotes = false,
    DateTime? exportedAt,
  }) {
    final selected = semester == null
        ? courses
        : courses.where((course) => course.semesterId == semester.id).toList();
    if (selected.isEmpty) throw StateError('没有可分享的课程。');
    final draft = CourseImportDraft(
      schemaVersion: CourseImportDraft.currentSchemaVersion,
      sourceType: CourseImportSourceType.shareCode,
      semester: semester == null
          ? null
          : CourseImportSemesterCandidate(
              name: semester.name,
              firstWeekStartDate: semester.firstWeekStartDate,
              totalWeeks: semester.totalWeeks,
            ),
      courses: [
        for (final course in selected)
          CourseImportCourseDraft(
            importKey: 'export-${course.id}',
            title: course.name,
            teacher: course.teacher,
            classroom: course.classroom,
            colorValue: course.colorValue,
            note: includeNotes ? course.notes : null,
            scheduleRules: [
              for (final rule in course.rules)
                CourseImportScheduleRuleDraft(
                  weekday: rule.weekday,
                  startsAtMinute: rule.startsAtMinute,
                  endsAtMinute: rule.endsAtMinute,
                  weekRuleType: rule.weekRuleType,
                  startWeek: rule.startWeek,
                  endWeek: rule.endWeek,
                  intervalWeeks: rule.intervalWeeks,
                  customWeeks: rule.weekNumbers,
                  timeMode: rule.timeMode,
                  classroomOverride: rule.classroomOverride,
                  note: includeNotes ? rule.notes : null,
                  segments: _portableSegments(rule, template),
                ),
            ],
          ),
      ],
    );
    return SharePackage.fromDraft(
      draft,
      includeNotes: includeNotes,
      exportedAt: exportedAt,
    );
  }

  static List<CourseImportSegmentCandidate> _portableSegments(
    CourseScheduleRule rule,
    ScheduleTemplateDetails? template,
  ) {
    if (rule.timeMode != CourseScheduleTimeMode.periods || template == null) {
      return const [];
    }
    final byId = {for (final segment in template.segments) segment.id: segment};
    return [
      for (final sectionId in rule.sectionIds)
        if (byId[sectionId] case final segment?)
          CourseImportSegmentCandidate(
            label: segment.name,
            order: segment.sortOrder,
            startsAtMinute: segment.startsAtMinute,
            endsAtMinute: segment.endsAtMinute,
          ),
    ];
  }
}
