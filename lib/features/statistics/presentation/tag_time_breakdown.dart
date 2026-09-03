import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../tasks/application/task_providers.dart';
import '../application/statistics_providers.dart';
import '../domain/statistics_models.dart';
import 'time_distribution_chart.dart';

class DailyTagTime extends ConsumerWidget {
  const DailyTagTime({required this.date, required this.now, super.key});
  final DateTime date;
  final DateTime now;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(statisticsSnapshotProvider)
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
  Widget build(BuildContext context) {
    final entries = report.tags
        .where((tag) => report.secondsForTag(tag.id) > 0)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '标签时间分布',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '(今日)',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
                Text(
                  '总计 ${timeLabel(report.seconds)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '今日暂无计时记录',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      for (final tag in entries)
                        Expanded(
                          flex: report.secondsForTag(tag.id),
                          child: Container(
                            alignment: Alignment.center,
                            color: Color(tag.colorValue),
                            child: FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: Text(
                                  '${(report.secondsForTag(tag.id) / report.seconds * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  for (final tag in entries)
                    _TagLegend(
                      color: Color(tag.colorValue),
                      name: tag.name,
                      duration: timeLabel(report.secondsForTag(tag.id)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TagLegend extends StatelessWidget {
  const _TagLegend({
    required this.color,
    required this.name,
    required this.duration,
  });

  final Color color;
  final String name;
  final String duration;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        const SizedBox(height: 3),
        Text(duration, style: const TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}
