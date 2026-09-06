import 'package:check_d/features/statistics/domain/statistics_models.dart';
import 'package:check_d/features/statistics/presentation/tag_time_breakdown.dart';
import 'package:check_d/features/statistics/presentation/time_distribution_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final semester = StatisticsSemester(
    name: '2026秋季学期',
    start: DateTime(2026, 9, 1),
    end: DateTime(2027, 1, 4),
  );
  final data = StatisticsData(
    tags: const [TimeTag('study', '学习', 0xFF8FAFEA)],
    sessions: [
      TimeEntry(
        taskId: 'focus',
        tagId: 'study',
        start: DateTime(2026, 9, 3, 8),
        end: DateTime(2026, 9, 3, 10),
        durationSeconds: 7200,
        running: false,
      ),
    ],
    tasks: const [],
    reminderCompletions: const [],
    semesters: [semester],
  );

  for (final period in const [
    StatisticsPeriod.week,
    StatisticsPeriod.month,
    StatisticsPeriod.semester,
    StatisticsPeriod.year,
  ]) {
    testWidgets('$period trend and distribution render without overflow', (
      tester,
    ) async {
      final report = data.report(
        period,
        DateTime(2026, 9, 3),
        DateTime(2026, 9, 5),
        semester: period == StatisticsPeriod.semester ? semester : null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    width: 760,
                    child: StatisticsTrendChart(report: report, period: period),
                  ),
                  SizedBox(
                    width: 420,
                    child: TagTimeBreakdown(report: report, title: '专注时间分布'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
