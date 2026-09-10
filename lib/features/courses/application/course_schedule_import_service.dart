import '../data/course_repository.dart';
import '../data/semester_repository.dart';
import '../domain/course_models.dart';
import '../domain/course_schedule_import_models.dart';

/// Maps recognition output onto the user's actual semester/template and only
/// persists it after the preview has explicitly been confirmed.
class CourseScheduleImportService {
  CourseScheduleImportService({
    required CourseRepository courses,
    required SemesterRepository semesters,
  }) : _courses = courses,
       _semesters = semesters;

  final CourseRepository _courses;
  final SemesterRepository _semesters;

  Future<CourseImportPlan> prepare({
    required SemesterDetails semester,
    required ScheduleTemplateDetails? template,
    required CourseScheduleRecognitionResult result,
  }) async {
    final templateDraft = result.detectedSegments.isNotEmpty
        ? _templateDraft(semester, result.detectedSegments)
        : null;
    final target = template;
    final timeConflict =
        target != null && _templateConflicts(target, result.detectedSegments);
    for (final course in result.courses) {
      final updated = <RecognizedScheduleRuleDraft>[];
      for (final rule in course.rules) {
        final warnings = [...rule.warnings];
        final mapped = target == null
            ? <String>[]
            : _mapSections(target, rule.recognizedSectionNumbers);
        if (rule.weekday == null) {
          warnings.add(
            const CourseImportWarning(
              CourseImportWarningKind.missingWeekday,
              '缺少星期，请确认',
            ),
          );
        }
        if (rule.recognizedSectionNumbers.isEmpty) {
          warnings.add(
            const CourseImportWarning(
              CourseImportWarningKind.missingSections,
              '缺少节次，请确认',
            ),
          );
        } else if (target != null &&
            mapped.length != rule.recognizedSectionNumbers.length) {
          warnings.add(
            const CourseImportWarning(
              CourseImportWarningKind.unmappedSections,
              '部分节次无法映射到当前作息模板',
            ),
          );
        }
        updated.add(
          RecognizedScheduleRuleDraft(
            weekday: rule.weekday,
            recognizedSectionNumbers: rule.recognizedSectionNumbers,
            mappedSegmentIds: mapped,
            weekRuleType: rule.weekRuleType,
            startWeek: rule.startWeek,
            endWeek: rule.endWeek,
            intervalWeeks: rule.intervalWeeks,
            weekNumbers: rule.weekNumbers,
            recognizedStartsAtMinute: rule.recognizedStartsAtMinute,
            recognizedEndsAtMinute: rule.recognizedEndsAtMinute,
            weekRuleConfirmed: rule.weekRuleConfirmed,
            warnings: warnings,
          ),
        );
      }
      course.rules = updated;
      course.warnings = course.rules.expand((rule) => rule.warnings).toList();
    }
    final plan = CourseImportPlan(
      semester: semester,
      template: template,
      courses: result.courses,
      templateDraft: templateDraft,
      templateTimeConflict: timeConflict,
    );
    await _applyExistingWarnings(plan);
    return plan;
  }

  /// Creates a template only after the preview user chooses it, then binds the
  /// same semester to the new stable template before importing courses.
  Future<int> confirm({
    required CourseImportPlan plan,
    required bool createRecognizedTemplate,
  }) async {
    if (!plan.canImport &&
        !(createRecognizedTemplate && plan.templateDraft != null)) {
      throw StateError('请先补全课程信息和作息模板后再导入。');
    }
    ScheduleTemplateDetails? template = plan.template;
    if (createRecognizedTemplate) {
      final draft = plan.templateDraft;
      if (draft == null) throw StateError('没有可创建的识别作息模板。');
      final templateId = await _courses.saveScheduleTemplate(draft);
      template = await _courses.loadScheduleTemplate(templateId);
      if (template == null) throw StateError('创建作息模板失败。');
      await _semesters.saveSemester(
        SemesterDraft(
          name: plan.semester.name,
          firstWeekStartDate: plan.semester.firstWeekStartDate,
          totalWeeks: plan.semester.totalWeeks,
          scheduleTemplateId: template.id,
          isCurrent: plan.semester.isCurrent,
        ),
        semesterId: plan.semester.id,
      );
      _mapAll(plan.courses, template);
    }
    if (template == null) throw StateError('请先为该学期设置作息模板。');
    final selected = plan.courses.where((course) => course.selected).toList();
    if (selected.any((course) => !course.isReady)) {
      throw StateError('仍有课程信息需要确认。');
    }

    final savedIds = <String>[];
    try {
      for (final course in selected) {
        final id = await _courses.saveCourse(
          CourseDraft(
            name: course.name,
            colorValue: _colorFor(course.name),
            teacher: course.teacher,
            classroom: course.classroom,
            semesterId: plan.semester.id,
            semester: plan.semester.name,
            semesterStartsOn: plan.semester.firstWeekStartDate,
            semesterEndsOn: plan.semester.endsOn,
          ),
        );
        savedIds.add(id);
        for (final rule in course.rules) {
          await _courses.saveScheduleRule(
            CourseScheduleRuleDraft(
              courseId: id,
              weekday: rule.weekday!,
              weekRuleType: rule.weekRuleType!,
              startsAtMinute: _startMinute(template, rule),
              endsAtMinute: _endMinute(template, rule),
              startWeek: rule.startWeek,
              endWeek: rule.endWeek,
              intervalWeeks: rule.intervalWeeks,
              weekNumbers: rule.weekNumbers,
              scheduleTemplateId: template.id,
              sectionIds: rule.mappedSegmentIds,
              timeMode: CourseScheduleTimeMode.periods,
            ),
          );
        }
      }
    } catch (_) {
      for (final id in savedIds) {
        await _courses.archiveCourse(id);
      }
      rethrow;
    }
    return savedIds.length;
  }

  Future<void> _applyExistingWarnings(CourseImportPlan plan) async {
    final existing = await _courses.loadCourses();
    for (final draft in plan.courses) {
      for (final rule in draft.rules) {
        for (final course in existing) {
          for (final existingRule in course.rules) {
            final sameDay = existingRule.weekday == rule.weekday;
            final sameSegments = _sameSet(
              existingRule.sectionIds,
              rule.mappedSegmentIds,
            );
            if (sameDay &&
                sameSegments &&
                _normalise(course.name) == _normalise(draft.name)) {
              draft.warnings = [
                ...draft.warnings,
                const CourseImportWarning(
                  CourseImportWarningKind.possibleDuplicate,
                  '可能与已有课程重复',
                ),
              ];
            } else if (sameDay && sameSegments) {
              draft.warnings = [
                ...draft.warnings,
                const CourseImportWarning(
                  CourseImportWarningKind.timeConflict,
                  '与已有课程时间冲突',
                ),
              ];
            }
          }
        }
      }
    }
  }

  ScheduleTemplateDraft _templateDraft(
    SemesterDetails semester,
    List<RecognizedScheduleSegmentDraft> segments,
  ) {
    final ordered = [...segments]..sort((a, b) => a.number.compareTo(b.number));
    return ScheduleTemplateDraft(
      name: '${semester.name}识别作息模板',
      segments: [
        for (var index = 0; index < ordered.length; index++)
          ScheduleTemplateSegmentDraft(
            name: '第${ordered[index].number}节',
            startsAtMinute: ordered[index].startsAtMinute,
            endsAtMinute: ordered[index].endsAtMinute,
            sortOrder: index,
          ),
      ],
    );
  }

  bool _templateConflicts(
    ScheduleTemplateDetails template,
    List<RecognizedScheduleSegmentDraft> detected,
  ) {
    for (final item in detected) {
      final index = item.number - 1;
      if (index < 0 || index >= template.segments.length) continue;
      final current = template.segments[index];
      if (current.startsAtMinute != item.startsAtMinute ||
          current.endsAtMinute != item.endsAtMinute)
        return true;
    }
    return false;
  }

  List<String> _mapSections(
    ScheduleTemplateDetails template,
    List<int> numbers,
  ) {
    final ordered =
        template.segments
            .where(
              (segment) => segment.segmentType == ScheduleSegmentType.classTime,
            )
            .toList()
          ..sort((a, b) => a.startsAtMinute.compareTo(b.startsAtMinute));
    return [
      for (final number in numbers)
        if (number > 0 && number <= ordered.length) ordered[number - 1].id,
    ];
  }

  void _mapAll(
    List<RecognizedCourseDraft> courses,
    ScheduleTemplateDetails template,
  ) {
    for (final course in courses) {
      for (final rule in course.rules) {
        rule.mappedSegmentIds = _mapSections(
          template,
          rule.recognizedSectionNumbers,
        );
      }
    }
  }

  int _startMinute(
    ScheduleTemplateDetails template,
    RecognizedScheduleRuleDraft rule,
  ) => template.segments
      .where((item) => rule.mappedSegmentIds.contains(item.id))
      .map((item) => item.startsAtMinute)
      .reduce((a, b) => a < b ? a : b);
  int _endMinute(
    ScheduleTemplateDetails template,
    RecognizedScheduleRuleDraft rule,
  ) => template.segments
      .where((item) => rule.mappedSegmentIds.contains(item.id))
      .map((item) => item.endsAtMinute)
      .reduce((a, b) => a > b ? a : b);
  bool _sameSet(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);
  String _normalise(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  int _colorFor(String name) {
    const colors = [0xFF8FA7F5, 0xFFD0A4F5, 0xFF7DCFB6, 0xFFFFB36B, 0xFFF28BA8];
    return colors[name.codeUnits.fold<int>(0, (sum, value) => sum + value) %
        colors.length];
  }
}
