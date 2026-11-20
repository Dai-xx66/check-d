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
  return MaterialApp(
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
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

  testWidgets('compact dates and counts share a column without clipping', (
    tester,
  ) async {
    final entries = List.generate(
      7,
      (index) => item('事项 $index', index: index),
    );
    for (final size in const [
      Size(38, 30),
      Size(44, 39),
      Size(38, 48),
      Size(56, 50),
      Size(48, 58),
    ]) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          cell(
            width: size.width,
            height: size.height,
            items: entries,
            selected: true,
            textScaler: TextScaler.linear(scale),
          ),
        );
        final bounds = tester.getRect(find.byType(CalendarMonthDayCell));
        final date = tester.getRect(find.text('7'));
        final count = tester.getRect(find.text('+7'));
        expect(date.center.dx, closeTo(bounds.center.dx, .01));
        expect(count.center.dx, closeTo(date.center.dx, .01));
        expect(date.bottom, lessThanOrEqualTo(count.top));
        for (final text in [date, count]) {
          expect(text.left, greaterThanOrEqualTo(bounds.left + 2));
          expect(text.right, lessThanOrEqualTo(bounds.right - 2));
          expect(text.top, greaterThanOrEqualTo(bounds.top + 2));
          expect(text.bottom, lessThanOrEqualTo(bounds.bottom - 2));
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('empty and selected compact dates keep the same baseline', (
    tester,
  ) async {
    await tester.pumpWidget(cell(width: 48, height: 58));
    final emptyDate = tester.getRect(find.text('7'));
    await tester.pumpWidget(
      cell(width: 48, height: 58, selected: true, items: [item('事项')]),
    );
    expect(tester.getRect(find.text('7')), emptyDate);
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('desktop summaries stay below the full date line', (
    tester,
  ) async {
    await tester.pumpWidget(
      cell(
        width: 80,
        height: 71,
        desktop: true,
        items: List.generate(5, (index) => item('事项 $index', index: index)),
      ),
    );
    final date = tester.getRect(find.text('7'));
    final summary = tester.getRect(find.text('事项 0'));
    expect(date.bottom, lessThan(summary.top));
    expect(tester.takeException(), isNull);
  });
}
