import 'package:check_d/features/calendar/domain/calendar_occurrence_builder.dart';
import 'package:check_d/features/calendar/domain/calendar_models.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/domain/day_schedule_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 9, 8); // Tuesday
  final template = _template(day);

  test('two selected segments create one occurrence with a derived break', () {
    final occurrences = buildCourseOccurrencesForDate(
      date: day,
      courses: [
        _course(sectionIds: const ['period-2', 'period-1']),
      ],
      overrides: const [],
      templates: [template],
    );

    expect(occurrences, hasLength(1));
    final timing = occurrences.single.courseTiming!;
    expect(timing.startMinute, 8 * 60);
    expect(timing.endMinute, 9 * 60 + 40);
    expect(timing.teachingSegments.map((item) => item.id), [
      'period-1',
      'period-2',
    ]);
    expect(timing.phases.map((item) => item.kind), [
      CourseOccurrencePhaseKind.teaching,
      CourseOccurrencePhaseKind.breakTime,
      CourseOccurrencePhaseKind.teaching,
    ]);
    final breakPhase = timing.phases[1];
    expect(breakPhase.startMinute, 8 * 60 + 45);
    expect(breakPhase.endMinute, 8 * 60 + 55);
  });

  test('course phase and progress are derived from current time', () {
    final timing = _singleOccurrence(template).courseTiming!;

    final first = timing.phaseAt(8 * 60 + 30);
    expect(first.kind, CourseOccurrencePhaseKind.teaching);
    expect(first.currentTeachingSegment!.id, 'period-1');
    expect(first.currentTeachingSegment!.index, 0);
    expect(first.currentTeachingSegment!.total, 2);

    final between = timing.phaseAt(8 * 60 + 50);
    expect(between.kind, CourseOccurrencePhaseKind.breakTime);
    expect(between.previousTeachingSegment!.id, 'period-1');
    expect(between.nextTeachingSegment!.id, 'period-2');
    expect(between.progressAt(8 * 60 + 50), closeTo(.5, .001));

    final second = timing.phaseAt(9 * 60 + 10);
    expect(second.kind, CourseOccurrencePhaseKind.teaching);
    expect(second.currentTeachingSegment!.id, 'period-2');
    expect(
      timing.phaseAt(9 * 60 + 45).kind,
      CourseOccurrencePhaseKind.finished,
    );
    expect(timing.overallProgressAt(8 * 60 + 50), closeTo(.5, .001));
  });

  test(
    'three selected segments preserve their teaching and break sequence',
    () {
      final occurrence = buildCourseOccurrencesForDate(
        date: day,
        courses: [
          _course(sectionIds: const ['period-3', 'period-1', 'period-2']),
        ],
        overrides: const [],
        templates: [template],
      ).single;
      final timing = occurrence.courseTiming!;

      expect(timing.teachingSegments, hasLength(3));
      expect(timing.phases.map((phase) => phase.kind), [
        CourseOccurrencePhaseKind.teaching,
        CourseOccurrencePhaseKind.breakTime,
        CourseOccurrencePhaseKind.teaching,
        CourseOccurrencePhaseKind.breakTime,
        CourseOccurrencePhaseKind.teaching,
      ]);
    },
  );

  test('old single-segment rules remain one teaching phase', () {
    final occurrence = buildCourseOccurrencesForDate(
      date: day,
      courses: [
        _course(sectionIds: const ['period-1']),
      ],
      overrides: const [],
      templates: [template],
    ).single;

    expect(occurrence.courseTiming!.teachingSegments, hasLength(1));
    expect(occurrence.courseTiming!.phases, hasLength(1));
    expect(
      occurrence.courseTiming!.phaseAt(8 * 60 + 30).kind,
      CourseOccurrencePhaseKind.teaching,
    );
  });

  test(
    'custom time, reschedule, cancellation and extra course stay effective',
    () {
      final custom = _course(
        rule: _rule(
          timeMode: CourseScheduleTimeMode.customTime,
          startsAtMinute: 13 * 60,
          endsAtMinute: 14 * 60 + 30,
        ),
      );
      final customOccurrence = buildCourseOccurrencesForDate(
        date: day,
        courses: [custom],
        overrides: const [],
      ).single;
      expect(customOccurrence.courseTiming!.teachingSegments, hasLength(1));
      expect(customOccurrence.courseTiming!.phases, hasLength(1));

      final original = _course(sectionIds: const ['period-1', 'period-2']);
      final moved = buildCourseOccurrencesForDate(
        date: day,
        courses: [original],
        overrides: [
          _override('rule-1', DayOverrideAction.reschedule, 14 * 60, 15 * 60),
        ],
        templates: [template],
      ).single;
      expect(moved.startMinute, 14 * 60);
      expect(moved.courseTiming!.teachingSegments, hasLength(1));
      expect(
        moved.courseTiming!.phaseAt(14 * 60 + 30).kind,
        CourseOccurrencePhaseKind.teaching,
      );

      final cancelled = buildCourseOccurrencesForDate(
        date: day,
        courses: [original],
        overrides: [_override('rule-1', DayOverrideAction.skip)],
        templates: [template],
      );
      expect(cancelled, isEmpty);

      final extra = buildCourseOccurrencesForDate(
        date: day,
        courses: [original],
        overrides: [
          _override(
            'course-1',
            DayOverrideAction.extraCourse,
            16 * 60,
            17 * 60,
          ),
        ],
        templates: [template],
      );
      expect(
        extra.where((item) => item.id.startsWith('course-extra:')),
        hasLength(1),
      );
    },
  );

  test('a gap between different courses never becomes a course break', () {
    final first = _course(sectionIds: const ['period-1', 'period-2']);
    final second = CourseDetails(
      id: 'course-2',
      name: '英语',
      colorValue: 0xff8ba9f0,
      status: CourseStatus.active,
      createdAt: day,
      updatedAt: day,
      rules: [
        _rule(id: 'rule-2', startsAtMinute: 10 * 60, endsAtMinute: 11 * 60),
      ],
    );
    final occurrences = buildCourseOccurrencesForDate(
      date: day,
      courses: [first, second],
      overrides: const [],
      templates: [template],
    );

    expect(occurrences, hasLength(2));
    expect(
      occurrences.first.courseTiming!.phaseAt(9 * 60 + 50).kind,
      CourseOccurrencePhaseKind.finished,
    );
    expect(
      occurrences.last.courseTiming!.phaseAt(9 * 60 + 50).kind,
      CourseOccurrencePhaseKind.before,
    );
  });

  test('overlapping course occurrences are all preserved', () {
    final first = _course(sectionIds: const ['period-1', 'period-2']);
    final second = CourseDetails(
      id: 'course-2',
      name: '英语',
      colorValue: 0xff8ba9f0,
      status: CourseStatus.active,
      createdAt: day,
      updatedAt: day,
      rules: [
        _rule(
          id: 'rule-2',
          timeMode: CourseScheduleTimeMode.customTime,
          startsAtMinute: 9 * 60,
          endsAtMinute: 10 * 60 + 30,
        ),
      ],
    );

    final occurrences = buildCourseOccurrencesForDate(
      date: day,
      courses: [first, second],
      overrides: const [],
      templates: [template],
    );

    expect(occurrences, hasLength(2));
    expect(
      occurrences.where(
        (item) =>
            9 * 60 + 10 >= item.startMinute! && 9 * 60 + 10 < item.endMinute!,
      ),
      hasLength(2),
    );
  });
}

CalendarOccurrence _singleOccurrence(ScheduleTemplateDetails template) =>
    buildCourseOccurrencesForDate(
      date: DateTime(2026, 9, 8),
      courses: [
        _course(sectionIds: const ['period-1', 'period-2']),
      ],
      overrides: const [],
      templates: [template],
    ).single;

CourseDetails _course({
  List<String> sectionIds = const [],
  CourseScheduleRule? rule,
}) => CourseDetails(
  id: 'course-1',
  name: '高等数学',
  colorValue: 0xfff47ba2,
  status: CourseStatus.active,
  createdAt: DateTime(2026, 9, 8),
  updatedAt: DateTime(2026, 9, 8),
  rules: [rule ?? _rule(sectionIds: sectionIds)],
);

CourseScheduleRule _rule({
  String id = 'rule-1',
  List<String> sectionIds = const [],
  CourseScheduleTimeMode timeMode = CourseScheduleTimeMode.periods,
  int startsAtMinute = 8 * 60,
  int endsAtMinute = 9 * 60 + 40,
}) => CourseScheduleRule(
  id: id,
  courseId: id == 'rule-2' ? 'course-2' : 'course-1',
  weekday: DateTime.tuesday,
  weekRuleType: CourseWeekRuleType.everyWeek,
  startsAtMinute: startsAtMinute,
  endsAtMinute: endsAtMinute,
  createdAt: DateTime(2026, 9, 8),
  updatedAt: DateTime(2026, 9, 8),
  scheduleTemplateId: timeMode == CourseScheduleTimeMode.periods
      ? 'template-1'
      : null,
  sectionIds: sectionIds,
  timeMode: timeMode,
);

DailyItemOverride _override(
  String itemId,
  DayOverrideAction action, [
  int? start,
  int? end,
]) => DailyItemOverride(
  id: '$itemId-$action',
  itemType: DayItemType.course,
  itemId: itemId,
  localDate: DateTime(2026, 9, 8),
  action: action,
  plannedStartMinute: start,
  plannedEndMinute: end,
  createdAt: DateTime(2026, 9, 8),
  updatedAt: DateTime(2026, 9, 8),
);

ScheduleTemplateDetails _template(DateTime day) => ScheduleTemplateDetails(
  id: 'template-1',
  name: '测试作息',
  timezone: 'Asia/Shanghai',
  isDefault: true,
  createdAt: day,
  updatedAt: day,
  segments: [
    _segment('period-1', '第1节', 8 * 60, 8 * 60 + 45, day),
    _segment(
      'break-1',
      '课间',
      8 * 60 + 45,
      8 * 60 + 55,
      day,
      ScheduleSegmentType.breakTime,
    ),
    _segment('period-2', '第2节', 8 * 60 + 55, 9 * 60 + 40, day),
    _segment(
      'break-2',
      '课间',
      9 * 60 + 40,
      9 * 60 + 50,
      day,
      ScheduleSegmentType.breakTime,
    ),
    _segment('period-3', '第3节', 9 * 60 + 50, 10 * 60 + 35, day),
  ],
);

ScheduleTemplateSegment _segment(
  String id,
  String label,
  int start,
  int end,
  DateTime day, [
  ScheduleSegmentType type = ScheduleSegmentType.classTime,
]) => ScheduleTemplateSegment(
  id: id,
  templateId: 'template-1',
  name: label,
  startsAtMinute: start,
  endsAtMinute: end,
  segmentType: type,
  sortOrder: start,
  createdAt: day,
  updatedAt: day,
);
