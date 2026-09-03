import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import 'china_holiday_service.dart';
import 'holiday_calendar.dart';

final holidayCalendarProvider = Provider<HolidayCalendar>((ref) {
  return ChinaHolidayService(ref.watch(appDatabaseProvider));
});
