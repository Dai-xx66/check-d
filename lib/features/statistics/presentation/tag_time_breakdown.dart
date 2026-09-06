import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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
            title: '今日专注时间分布',
          ),
        );
  }
}

class TagTimeBreakdown extends StatelessWidget {
  const TagTimeBreakdown({
    required this.report,
    this.title = '专注时间分布',
    super.key,
  });
  final StatisticsReport report;
  final String title;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  timeLabel(report.seconds),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '当前周期暂无专注记录',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            else ...[
              Center(
                child: SizedBox(
                  width: 168,
                  height: 168,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      values: [
                        for (final tag in entries) report.secondsForTag(tag.id),
                      ],
                      colors: [
                        for (final tag in entries) Color(tag.colorValue),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '标签投入',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            timeLabel(report.seconds),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
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
                      percent:
                          '${(report.secondsForTag(tag.id) / report.seconds * 100).round()}%',
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
    required this.percent,
  });

  final Color color;
  final String name;
  final String duration;
  final String percent;

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
        Text(
          '$duration · $percent',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.values, required this.colors});

  final List<int> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) return;
    final rect = Offset.zero & size;
    var start = -1.5707963267948966;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * 6.283185307179586;
      canvas.drawArc(
        rect.deflate(17),
        start,
        sweep,
        false,
        Paint()
          ..color = colors[index]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 25
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}
