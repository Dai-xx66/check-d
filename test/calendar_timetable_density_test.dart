import 'package:check_d/features/calendar/presentation/calendar_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mobile full-day timetable derives its hour scale from available height',
    () {
      expect(timetableHourHeightForAvailableHeight(600), 25);
      expect(timetableHourHeightForAvailableHeight(720), 30);
    },
  );

  test('24 hours always fit the available mobile timetable height', () {
    for (final height in [560.0, 620.0, 700.0]) {
      expect(timetableHourHeightForAvailableHeight(height) * 24, height);
    }
  });

  test('full-day labels keep both 00:00 and 24:00 inside the grid', () {
    const availableHeight = 600.0;
    const hourHeight = 25.0;
    expect(
      timetableHourLabelTop(
        hour: 0,
        startHour: 0,
        hourHeight: hourHeight,
        availableHeight: availableHeight,
      ),
      0,
    );
    expect(
      timetableHourLabelTop(
        hour: 24,
        startHour: 0,
        hourHeight: hourHeight,
        availableHeight: availableHeight,
      ),
      586,
    );
  });
}
