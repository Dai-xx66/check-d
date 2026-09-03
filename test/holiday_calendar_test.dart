import 'package:check_d/core/holiday/holiday_calendar.dart';
import 'package:check_d/features/tasks/domain/task_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final workdays = TaskScheduleRule(
    preset: SchedulePreset.weekdays,
    weekdaysMask: WeekdayMask.weekdays,
    startsOn: DateTime(2026, 1, 1),
  );

  test('holiday pause excludes an otherwise due recurring task', () async {
    final due = await isRecurringTaskDue(
      schedule: workdays,
      holidayPause: true,
      date: DateTime(2026, 5, 1),
      holidayCalendar: _FixedHolidayCalendar(ChinaDayKind.holiday),
    );

    expect(due, isFalse);
  });

  test('adjusted workday makes a weekend workday preset due', () async {
    final due = await isRecurringTaskDue(
      schedule: workdays,
      holidayPause: true,
      date: DateTime(2026, 5, 9),
      holidayCalendar: _FixedHolidayCalendar(ChinaDayKind.adjustedWorkday),
    );

    expect(due, isTrue);
  });
}

class _FixedHolidayCalendar implements HolidayCalendar {
  const _FixedHolidayCalendar(this.kind);

  final ChinaDayKind kind;

  @override
  Future<ChinaDayKind> kindFor(DateTime date) async => kind;
}
