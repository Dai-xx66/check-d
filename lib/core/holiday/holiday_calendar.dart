import '../../features/tasks/domain/task_models.dart';

enum ChinaDayKind { workday, weekend, holiday, adjustedWorkday, unknown }

abstract interface class HolidayCalendar {
  Future<ChinaDayKind> kindFor(DateTime date);
}

Future<bool> isRecurringTaskDue({
  required TaskScheduleRule schedule,
  required bool holidayPause,
  required DateTime date,
  HolidayCalendar? holidayCalendar,
}) async {
  var dayKind = ChinaDayKind.unknown;
  if (holidayCalendar != null) {
    dayKind = await holidayCalendar.kindFor(date);
  }
  if (holidayPause && dayKind == ChinaDayKind.holiday) return false;
  if (dayKind == ChinaDayKind.adjustedWorkday &&
      schedule.preset == SchedulePreset.weekdays) {
    final day = dateOnly(date);
    return !day.isBefore(dateOnly(schedule.startsOn)) &&
        (schedule.endsOn == null || !day.isAfter(dateOnly(schedule.endsOn!)));
  }
  return schedule.isDueOn(date);
}
