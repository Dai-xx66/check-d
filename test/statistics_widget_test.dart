import 'package:check_d/core/theme/app_theme.dart';
import 'package:check_d/features/statistics/application/statistics_providers.dart';
import 'package:check_d/features/statistics/domain/statistics_models.dart';
import 'package:check_d/features/statistics/presentation/statistics_page.dart';
import 'package:check_d/features/tasks/application/task_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final data = StatisticsData(
    tags: const [
      TimeTag('study', '学习', 0xFF3D73E8),
      TimeTag('health', '健康', 0xFF45A77A),
    ],
    sessions: [
      TimeEntry(
        taskId: 'a',
        tagId: 'study',
        start: start,
        end: start.add(const Duration(hours: 1)),
        durationSeconds: 3600,
        running: false,
      ),
      TimeEntry(
        taskId: 'b',
        tagId: 'health',
        start: start.add(const Duration(hours: 1)),
        end: start.add(const Duration(hours: 2)),
        durationSeconds: 3600,
        running: false,
      ),
    ],
    tasks: [
      StatisticsTask(
        id: 'a',
        name: '英语听力与阅读练习',
        iconName: 'headphones',
        colorValue: 0xFF3D73E8,
        days: [
          ExecutionDay(
            date: start,
            success: false,
            targetSeconds: 1800,
            storedTargetReached: true,
          ),
        ],
      ),
    ],
    reminderCompletions: [],
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('statistics periods and layout at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statisticsDataProvider.overrideWith((ref) => Stream.value(data)),
            timerNowProvider.overrideWith(
              (ref) => Stream.value(start.add(const Duration(hours: 12))),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: StatisticsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('投入时间'), findsOneWidget);
      expect(find.text('0 / 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('年', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(find.text('12月'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('月', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('日', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
