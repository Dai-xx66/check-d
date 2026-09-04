enum CourseStatus { active, paused, archived }

enum CourseWeekRuleType { everyWeek, oddWeeks, evenWeeks, everyNWeeks, custom }

enum ScheduleSegmentType { classTime, breakTime, custom }

class CourseDraft {
  const CourseDraft({
    required this.name,
    required this.colorValue,
    this.teacher,
    this.classroom,
    this.semester,
    this.notes,
  });

  final String name;
  final int colorValue;
  final String? teacher;
  final String? classroom;
  final String? semester;
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
    this.segmentType = ScheduleSegmentType.classTime,
    this.sortOrder = 0,
  });

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
