import 'package:check_d/features/calendar/presentation/calendar_workspace.dart';
import 'package:check_d/features/courses/application/course_providers.dart';
import 'package:check_d/features/courses/domain/course_models.dart';
import 'package:check_d/features/schedule/application/day_schedule_providers.dart';
import 'package:check_d/features/tasks/application/task_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets('overlapping courses stay separate inside their phone day column',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final now = DateTime.now();
    final courses = List.generate(
      2,
      (index) => CourseDetails(
        id: 'course-$index',
        name: '重叠课程$index',
        colorValue: 0xFF8BA9F0,
        status: CourseStatus.active,
        createdAt: now,
        updatedAt: now,
        rules: [
          CourseScheduleRule(
            id: 'rule-$index',
            courseId: 'course-$index',
            weekday: DateTime.monday,
            weekRuleType: CourseWeekRuleType.everyWeek,
            startsAtMinute: 8 * 60,
            endsAtMinute: 10 * 60,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );

    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coursesProvider.overrideWith((ref) => Stream.value(courses)),
            scheduleTemplatesProvider.overrideWith((ref) => Stream.value([])),
            semestersProvider.overrideWith((ref) => Stream.value([])),
            tasksForDateProvider.overrideWith((ref, date) => Stream.value([])),
            dailyOverridesProvider.overrideWith((ref, date) => Stream.value([])),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const Scaffold(body: CalendarWorkspace()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('课表'));
      await tester.pumpAndSettle();

      final blocks = find.byType(CalendarWeekEventBlock);
      expect(blocks, findsNWidgets(2));
      final first = tester.getRect(blocks.at(0));
      final second = tester.getRect(blocks.at(1));
      final workspace = tester.getRect(find.byType(CalendarWorkspace));
      final dayLeft = workspace.left + 52;
      final dayRight = dayLeft + (workspace.width - 52) / 7;
      expect(first.left, greaterThanOrEqualTo(dayLeft));
      expect(first.right, lessThanOrEqualTo(second.left));
      expect(second.right, lessThanOrEqualTo(dayRight));
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('24:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
