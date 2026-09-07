import 'package:check_d/features/calendar/domain/calendar_models.dart';
import 'package:check_d/features/calendar/presentation/calendar_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('short timed event reduces detail without a layout overflow', (
    tester,
  ) async {
    final item = CalendarOccurrence(
      id: 'short-course',
      type: CalendarOccurrenceType.course,
      title: '英语',
      subtitle: 'A301 · 第1节',
      date: DateTime(2026, 9, 8),
      colorValue: 0xFF8BA9F0,
      startMinute: 13 * 60 + 20,
      endMinute: 13 * 60 + 45,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 42,
            height: 27,
            child: CalendarWeekEventBlock(item: item),
          ),
        ),
      ),
    );

    expect(find.text('英语'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
