import 'package:check_d/features/calendar/presentation/calendar_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile timetable uses the denser hour scale at supported widths', () {
    expect(timetableHourHeightForWidth(360), 50);
    expect(timetableHourHeightForWidth(390), 50);
    expect(timetableHourHeightForWidth(412), 50);
  });

  test('desktop timetable keeps the original hour scale', () {
    expect(timetableHourHeightForWidth(980), 64);
    expect(timetableHourHeightForWidth(1440), 64);
  });
}
