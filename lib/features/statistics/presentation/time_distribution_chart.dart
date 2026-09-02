import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/statistics_models.dart';

String timeLabel(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  return minutes < 60 ? '$minutes 分钟' : '${minutes ~/ 60}小时${minutes % 60}分';
}

class TimeDistributionChart extends StatelessWidget {
  const TimeDistributionChart({required this.report, super.key});
  final StatisticsReport report;

  @override
  Widget build(BuildContext context) {
    final maxSeconds = report.buckets.fold<int>(
      0,
      (m, b) => math.max(m, b.seconds),
    );
    final maxHours = math.max(1, (maxSeconds / 3600).ceil());
    final scale = maxHours * 3600;
    const plotHeight = 170.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '小时',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              height: plotHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$maxHours'),
                  Text('${maxHours / 2}'),
                  const Text('0'),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final width = math.max(
                    constraints.maxWidth,
                    report.buckets.length * 32.0,
                  );
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          SizedBox(
                            height: plotHeight,
                            child: Stack(
                              children: [
                                const Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: Divider(height: 1),
                                ),
                                const Positioned(
                                  top: plotHeight / 2,
                                  left: 0,
                                  right: 0,
                                  child: Divider(height: 1),
                                ),
                                const Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Divider(height: 1),
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    for (final bucket in report.buckets)
                                      Expanded(
                                        child: Tooltip(
                                          message: _tooltip(bucket),
                                          child: Semantics(
                                            label: _tooltip(bucket),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                  ),
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        maxWidth: 46,
                                                      ),
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      for (final tag
                                                          in report.tags.where(
                                                            (t) =>
                                                                (bucket.secondsByTag[t
                                                                        .id] ??
                                                                    0) >
                                                                0,
                                                          ))
                                                        Container(
                                                          width:
                                                              double.infinity,
                                                          height:
                                                              (bucket.secondsByTag[tag
                                                                      .id] ??
                                                                  0) /
                                                              scale *
                                                              plotHeight,
                                                          color: Color(
                                                            tag.colorValue,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final bucket in report.buckets)
                                Expanded(
                                  child: Text(
                                    bucket.label,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final tag in report.tags.where(
              (t) => report.secondsForTag(t.id) > 0,
            ))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 9, color: Color(tag.colorValue)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(tag.name, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String _tooltip(TimeBucket bucket) =>
      '${DateFormat('M/d').format(bucket.start)} · ${timeLabel(bucket.seconds)}\n${report.tags.where((t) => (bucket.secondsByTag[t.id] ?? 0) > 0).map((t) => '${t.name} ${timeLabel(bucket.secondsByTag[t.id]!)}').join('\n')}';
}
