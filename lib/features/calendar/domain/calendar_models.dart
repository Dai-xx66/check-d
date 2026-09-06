import '../../courses/domain/course_models.dart';
import '../../tasks/domain/task_models.dart';

enum CalendarViewMode { month, week, timetable, agenda }

enum CalendarOccurrenceType { course, recurring, oneTime }

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
