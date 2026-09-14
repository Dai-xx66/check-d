enum CourseStatus { active, paused, archived }

enum CourseWeekRuleType { everyWeek, oddWeeks, evenWeeks, everyNWeeks, custom }

/// Period rules keep only stable template segment IDs. Custom rules retain
/// their own clock times so legacy courses keep working without a template.
enum CourseScheduleTimeMode { periods, customTime }

enum ScheduleSegmentType { classTime, breakTime, custom }

class CourseDraft {
  const CourseDraft({
    required this.name,
    required this.colorValue,
    this.teacher,
    this.classroom,
    this.semester,
    this.semesterId,
    this.semesterStartsOn,
    this.semesterEndsOn,
    this.notes,
  });

  final String name;
  final int colorValue;
  final String? teacher;
  final String? classroom;
  final String? semester;
  final String? semesterId;
  final DateTime? semesterStartsOn;
  final DateTime? semesterEndsOn;
  final String? notes;
}

class CourseDetails {
  const CourseDetails({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.teacher,
    this.classroom,
    this.semester,
    this.semesterId,
    this.semesterStartsOn,
    this.semesterEndsOn,
    this.notes,
    this.rules = const [],
  });

  final String id;
  final String name;
  final int colorValue;
  final CourseStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? teacher;
  final String? classroom;
  final String? semester;
  final String? semesterId;
  final DateTime? semesterStartsOn;
  final DateTime? semesterEndsOn;
  final String? notes;
  final List<CourseScheduleRule> rules;
}

class CourseScheduleRuleDraft {
  const CourseScheduleRuleDraft({
    required this.courseId,
    required this.weekday,
    required this.weekRuleType,
    required this.startsAtMinute,
    required this.endsAtMinute,
    this.startWeek,
    this.endWeek,
    this.intervalWeeks,
    this.weekNumbers = const {},
    this.scheduleTemplateId,
    this.sectionIds = const [],
    this.timeMode = CourseScheduleTimeMode.customTime,
    this.classroomOverride,
    this.notes,
    this.remindBeforeMinutes,
  });

  final String courseId;
  final int weekday;
  final CourseWeekRuleType weekRuleType;
  final int startsAtMinute;
  final int endsAtMinute;
  final int? startWeek;
  final int? endWeek;
  final int? intervalWeeks;
  final Set<int> weekNumbers;
  final String? scheduleTemplateId;
  final List<String> sectionIds;
  final CourseScheduleTimeMode timeMode;
  final String? classroomOverride;
  final String? notes;
  final int? remindBeforeMinutes;
}

class CourseScheduleRule {
  const CourseScheduleRule({
    required this.id,
    required this.courseId,
    required this.weekday,
    required this.weekRuleType,
    required this.startsAtMinute,
    required this.endsAtMinute,
    required this.createdAt,
    required this.updatedAt,
    this.startWeek,
    this.endWeek,
    this.intervalWeeks,
    this.weekNumbers = const {},
    this.scheduleTemplateId,
    this.sectionIds = const [],
    this.timeMode = CourseScheduleTimeMode.customTime,
    this.classroomOverride,
    this.notes,
    this.remindBeforeMinutes,
  });

  final String id;
  final String courseId;
  final int weekday;
  final CourseWeekRuleType weekRuleType;
  final int startsAtMinute;
  final int endsAtMinute;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? startWeek;
  final int? endWeek;
  final int? intervalWeeks;
  final Set<int> weekNumbers;
  final String? scheduleTemplateId;
  final List<String> sectionIds;
  final CourseScheduleTimeMode timeMode;
  final String? classroomOverride;
  final String? notes;
  final int? remindBeforeMinutes;

  bool isDueInWeek(int weekNumber) {
    if (weekNumber <= 0) return false;
    if (startWeek != null && weekNumber < startWeek!) return false;
    if (endWeek != null && weekNumber > endWeek!) return false;
    return switch (weekRuleType) {
      CourseWeekRuleType.everyWeek => true,
      CourseWeekRuleType.oddWeeks => weekNumber.isOdd,
      CourseWeekRuleType.evenWeeks => weekNumber.isEven,
      CourseWeekRuleType.everyNWeeks => _matchesInterval(weekNumber),
      CourseWeekRuleType.custom => weekNumbers.contains(weekNumber),
    };
  }

  bool _matchesInterval(int weekNumber) {
    final start = startWeek ?? 1;
    final interval = intervalWeeks ?? 1;
    return (weekNumber - start) % interval == 0;
  }
}

class ScheduleTemplateDraft {
  const ScheduleTemplateDraft({
    required this.name,
    this.timezone = 'Asia/Shanghai',
    this.isDefault = false,
    this.segments = const [],
  });

  final String name;
  final String timezone;
  final bool isDefault;
  final List<ScheduleTemplateSegmentDraft> segments;
}

class ScheduleTemplateDetails {
  const ScheduleTemplateDetails({
    required this.id,
    required this.name,
    required this.timezone,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    this.segments = const [],
  });

  final String id;
  final String name;
  final String timezone;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ScheduleTemplateSegment> segments;
}

class ScheduleTemplateSegmentDraft {
  const ScheduleTemplateSegmentDraft({
    required this.name,
    required this.startsAtMinute,
    required this.endsAtMinute,
    this.id,
    this.segmentType = ScheduleSegmentType.classTime,
    this.sortOrder = 0,
  });

  final String? id;
  final String name;
  final int startsAtMinute;
  final int endsAtMinute;
  final ScheduleSegmentType segmentType;
  final int sortOrder;
}

class ScheduleTemplateSegment {
  const ScheduleTemplateSegment({
    required this.id,
    required this.templateId,
    required this.name,
    required this.startsAtMinute,
    required this.endsAtMinute,
    required this.segmentType,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String templateId;
  final String name;
  final int startsAtMinute;
  final int endsAtMinute;
  final ScheduleSegmentType segmentType;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class SemesterDraft {
  const SemesterDraft({
    required this.name,
    required this.firstWeekStartDate,
    required this.totalWeeks,
    this.scheduleTemplateId,
    this.isCurrent = false,
  });

  final String name;
  final DateTime firstWeekStartDate;
  final int totalWeeks;
  final String? scheduleTemplateId;
  final bool isCurrent;
}

class SemesterDetails {
  const SemesterDetails({
    required this.id,
    required this.name,
    required this.firstWeekStartDate,
    required this.totalWeeks,
    required this.isCurrent,
    required this.createdAt,
    required this.updatedAt,
    this.scheduleTemplateId,
  });

  final String id;
  final String name;
  final DateTime firstWeekStartDate;
  final int totalWeeks;
  final String? scheduleTemplateId;
  final bool isCurrent;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get endsOn => firstWeekStartDate.add(
    Duration(days: totalWeeks * DateTime.daysPerWeek - 1),
  );

  int weekNumberFor(DateTime date) {
    final start = DateTime(
      firstWeekStartDate.year,
      firstWeekStartDate.month,
      firstWeekStartDate.day,
    );
    final day = DateTime(date.year, date.month, date.day);
    return day.difference(start).inDays ~/ DateTime.daysPerWeek + 1;
  }

  bool contains(DateTime date) {
    final week = weekNumberFor(date);
    return week >= 1 && week <= totalWeeks;
  }
}

/// Shared validation used by interactive editing and every import source.
void validateCourseScheduleRuleDraft(CourseScheduleRuleDraft draft) {
  if (draft.weekday < DateTime.monday || draft.weekday > DateTime.sunday) {
    throw ArgumentError.value(draft.weekday, 'weekday', '星期必须在 1 到 7 之间');
  }
  if (draft.startsAtMinute < 0 || draft.startsAtMinute > 1439) {
    throw ArgumentError.value(draft.startsAtMinute, 'startsAtMinute', '开始时间无效');
  }
  if (draft.endsAtMinute < 1 ||
      draft.endsAtMinute > 1440 ||
      draft.endsAtMinute <= draft.startsAtMinute) {
    throw ArgumentError.value(draft.endsAtMinute, 'endsAtMinute', '结束时间无效');
  }
  if (draft.timeMode == CourseScheduleTimeMode.periods &&
      (draft.scheduleTemplateId == null || draft.sectionIds.isEmpty)) {
    throw ArgumentError('节次排课需要选择作息模板和至少一个节次');
  }
  if (draft.weekRuleType == CourseWeekRuleType.everyNWeeks &&
      (draft.intervalWeeks == null || draft.intervalWeeks! <= 0)) {
    throw ArgumentError.value(
      draft.intervalWeeks,
      'intervalWeeks',
      '每 N 周规则需要有效间隔',
    );
  }
  if (draft.weekRuleType == CourseWeekRuleType.custom &&
      draft.weekNumbers.isEmpty) {
    throw ArgumentError.value(draft.weekNumbers, 'weekNumbers', '请选择周次');
  }
}
