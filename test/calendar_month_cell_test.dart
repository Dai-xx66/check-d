import 'package:check_d/features/calendar/domain/calendar_models.dart';
import 'package:check_d/features/calendar/presentation/calendar_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarOccurrence item(String title, {int index = 0}) => CalendarOccurrence(
  id: 'item-$index',
  type: CalendarOccurrenceType.oneTime,
  title: title,
  date: DateTime(2026, 9, 7),
  colorValue: 0xFFEF8FA8,
);

Widget cell({
  required double width,
  required double height,
  List<CalendarOccurrence> items = const [],
  bool selected = false,
  bool desktop = false,
  TextScaler? textScaler,
}) {
  final child = MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: CalendarMonthDayCell(
          date: DateTime(2026, 9, 7),
          items: items,
          selected: selected,
          inMonth: true,
          desktop: desktop,
        ),
      ),
    ),
  );
  return textScaler == null
      ? child
      : MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: child,
        );
}

void main() {
  testWidgets('month cell stays bounded across adaptive density cases', (
    tester,
  ) async {
    final cases = <Widget>[
      cell(width: 56, height: 72),
      cell(width: 56, height: 72, items: [item('短事项')]),
      cell(width: 56, height: 72, items: [item('这是一个很长很长的事项名称')]),
      cell(width: 56, height: 72, items: [item('课程'), item('事项', index: 1)]),
      cell(width: 56, height: 72, selected: true),
      cell(width: 38, height: 48, items: [item('窄屏长事项')]),
      cell(width: 38, height: 30, items: [item('极小格')]),
      cell(
        width: 38,
        height: 30,
        items: [item('大字号事项')],
        textScaler: const TextScaler.linear(2),
      ),
    ];

    for (final testCell in cases) {
      await tester.pumpWidget(testCell);
      expect(tester.takeException(), isNull);
    }
  });
}
