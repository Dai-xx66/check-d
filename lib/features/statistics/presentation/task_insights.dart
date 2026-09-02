import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../application/statistics_providers.dart';
import '../domain/statistics_models.dart';

class TaskInsights extends ConsumerWidget {
  const TaskInsights({required this.task, super.key});
  final TaskDetails task;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    return ref
        .watch(statisticsDataProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(statisticsDataProvider),
            child: const Text('重新加载坚持数据'),
          ),
          data: (data) {
            final tags = data.tags.where((tag) => tag.id == task.tagId);
            final tag = tags.isEmpty ? TimeTag.other : tags.first;
            final periods = [
              StatisticsPeriod.week,
              StatisticsPeriod.month,
              StatisticsPeriod.year,
            ];
            final results = [
              for (final period in periods)
                ...data
                    .report(period, now, now)
                    .tasks
                    .where((item) => item.task.id == task.id),
            ];
            final stats = results.isEmpty ? null : results.first;
            if (!task.hasTimer && stats == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (task.hasTimer)
                    Row(
                      children: [
                        Icon(
                          Icons.label,
                          color: Color(tag.colorValue),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tag.name)),
                      ],
                    ),
                  if (stats != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '已坚持 ${stats.totalSuccess} 天',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (task.targetDays != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '目标 ${task.targetDays} 天 · 剩余 ${(task.targetDays! - stats.totalSuccess).clamp(0, task.targetDays!)} 天',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        Text('当前连续 ${stats.currentStreak} 天'),
                        Text('历史最长 ${stats.longestStreak} 天'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        for (var i = 0; i < results.length; i++)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                const ['本周完成率', '本月完成率', '本年完成率'][i],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                results[i].expected == 0
                                    ? '--'
                                    : '${(results[i].rate * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(task.colorValue),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
  }
}
