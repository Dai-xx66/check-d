import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../tasks/application/task_providers.dart';
import '../application/statistics_providers.dart';
import '../domain/statistics_models.dart';
import 'time_distribution_chart.dart';

class DailyTagTime extends ConsumerWidget {
  const DailyTagTime({required this.date, super.key});
  final DateTime date;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    return ref
        .watch(statisticsDataProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(statisticsDataProvider),
            child: const Text('重新加载时间分布'),
          ),
          data: (data) => TagTimeBreakdown(
            report: data.report(StatisticsPeriod.day, date, now),
          ),
        );
  }
}

class TagTimeBreakdown extends StatelessWidget {
  const TagTimeBreakdown({required this.report, super.key});
  final StatisticsReport report;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (report.seconds == 0)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('本周期暂无计时记录', style: TextStyle(color: AppColors.muted)),
        ),
      for (final tag in report.tags.where(
        (t) => report.secondsForTag(t.id) > 0,
      ))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.label, color: Color(tag.colorValue), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tag.name, overflow: TextOverflow.ellipsis),
                  ),
                  Text(
                    '${timeLabel(report.secondsForTag(tag.id))} · ${(report.secondsForTag(tag.id) / report.seconds * 100).toStringAsFixed(0)}%',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: report.secondsForTag(tag.id) / report.seconds,
                color: Color(tag.colorValue),
                backgroundColor: AppColors.border,
                minHeight: 5,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        ),
    ],
  );
}
