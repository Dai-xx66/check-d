import '../../courses/domain/course_models.dart';
import '../../tasks/domain/task_models.dart';

enum CalendarViewMode { month, week, timetable, agenda }

enum CalendarOccurrenceType { course, recurring, oneTime }

/// A stable teaching segment selected by a course rule. Breaks are never
/// persisted: they are derived from gaps between adjacent teaching segments.
class CourseTeachingSegment {
  const CourseTeachingSegment({
    required this.id,
    required this.label,
    required this.startMinute,
    required this.endMinute,
    required this.index,
    required this.total,
  });

  final String id;
  final String label;
  final int startMinute;
  final int endMinute;
  final int index;
  final int total;
}

enum CourseOccurrencePhaseKind { before, teaching, breakTime, finished }

/// A runtime-only phase inside one effective course occurrence.
class CourseOccurrencePhase {
  const CourseOccurrencePhase({
    required this.kind,
    required this.startMinute,
    required this.endMinute,
    this.currentTeachingSegment,
    this.previousTeachingSegment,
    this.nextTeachingSegment,
  });

  final CourseOccurrencePhaseKind kind;
  final int startMinute;
  final int endMinute;
  final CourseTeachingSegment? currentTeachingSegment;
  final CourseTeachingSegment? previousTeachingSegment;
  final CourseTeachingSegment? nextTeachingSegment;

  double progressAt(int minute) {
    if (endMinute <= startMinute) {
      return kind == CourseOccurrencePhaseKind.finished ? 1 : 0;
    }
    return ((minute - startMinute) / (endMinute - startMinute)).clamp(0.0, 1.0);
  }
}

/// Shared timing projection for an effective course occurrence. Every UI
/// consumes this object instead of independently inferring teaching/break
/// status from a course rule or a template.
class CourseOccurrenceTiming {
  CourseOccurrenceTiming._({
    required this.startMinute,
    required this.endMinute,
    required this.teachingSegments,
    required this.phases,
  });

  factory CourseOccurrenceTiming.fromTeachingSegments(
    Iterable<CourseTeachingSegment> source,
  ) {
    final sorted = source.toList()
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    if (sorted.isEmpty) throw ArgumentError('课程至少需要一个教学节次');
    final teaching = [
      for (var index = 0; index < sorted.length; index++)
        CourseTeachingSegment(
          id: sorted[index].id,
          label: sorted[index].label,
          startMinute: sorted[index].startMinute,
          endMinute: sorted[index].endMinute,
          index: index,
          total: sorted.length,
        ),
    ];
    final phases = <CourseOccurrencePhase>[];
    for (var index = 0; index < teaching.length; index++) {
      final segment = teaching[index];
      phases.add(
        CourseOccurrencePhase(
          kind: CourseOccurrencePhaseKind.teaching,
          startMinute: segment.startMinute,
          endMinute: segment.endMinute,
          currentTeachingSegment: segment,
        ),
      );
      if (index == teaching.length - 1) continue;
      final next = teaching[index + 1];
      if (segment.endMinute < next.startMinute) {
        phases.add(
          CourseOccurrencePhase(
            kind: CourseOccurrencePhaseKind.breakTime,
            startMinute: segment.endMinute,
            endMinute: next.startMinute,
            previousTeachingSegment: segment,
            nextTeachingSegment: next,
          ),
        );
      }
    }
    return CourseOccurrenceTiming._(
      startMinute: teaching.first.startMinute,
      endMinute: teaching.last.endMinute,
      teachingSegments: teaching,
      phases: phases,
    );
  }

  factory CourseOccurrenceTiming.single({
    required int startMinute,
    required int endMinute,
    String id = 'custom-time',
    String label = '课程',
  }) => CourseOccurrenceTiming.fromTeachingSegments([
    CourseTeachingSegment(
      id: id,
      label: label,
      startMinute: startMinute,
      endMinute: endMinute,
      index: 0,
      total: 1,
    ),
  ]);

  final int startMinute;
  final int endMinute;
  final List<CourseTeachingSegment> teachingSegments;
  final List<CourseOccurrencePhase> phases;

  CourseOccurrencePhase phaseAt(int minute) {
    if (minute < startMinute) {
      return CourseOccurrencePhase(
        kind: CourseOccurrencePhaseKind.before,
        startMinute: startMinute,
        endMinute: startMinute,
      );
    }
    for (final phase in phases) {
      if (minute >= phase.startMinute && minute < phase.endMinute) return phase;
    }
    return CourseOccurrencePhase(
      kind: CourseOccurrencePhaseKind.finished,
      startMinute: endMinute,
      endMinute: endMinute,
    );
  }

  double overallProgressAt(int minute) {
    if (endMinute <= startMinute) return minute >= endMinute ? 1 : 0;
    return ((minute - startMinute) / (endMinute - startMinute)).clamp(0.0, 1.0);
  }
}

class CalendarOccurrence {
  const CalendarOccurrence({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    required this.colorValue,
    this.startMinute,
    this.endMinute,
    this.subtitle,
    this.course,
    this.courseRule,
    this.courseTiming,
    this.classroom,
    this.task,
  });

  final String id;
  final CalendarOccurrenceType type;
  final String title;
  final DateTime date;
  final int colorValue;
  final int? startMinute;
  final int? endMinute;
  final String? subtitle;
  final CourseDetails? course;
  final CourseScheduleRule? courseRule;
  final CourseOccurrenceTiming? courseTiming;
  final String? classroom;
  final TaskDetails? task;

  bool get hasTime => startMinute != null;
}

class CalendarSemesterContext {
  const CalendarSemesterContext({required this.start, this.end, this.label});

  final DateTime start;
  final DateTime? end;
  final String? label;

  int weekNumberFor(DateTime date) {
    final startDay = DateTime(start.year, start.month, start.day);
    final day = DateTime(date.year, date.month, date.day);
    final firstWeekStart = startDay.subtract(
      Duration(days: startDay.weekday - 1),
    );
    final weekStart = day.subtract(Duration(days: day.weekday - 1));
    return weekStart.difference(firstWeekStart).inDays ~/ 7 + 1;
  }
}
