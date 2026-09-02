import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/task_detail_page.dart';
import '../../tasks/presentation/task_icon_picker.dart';

class DailyDetailPage extends StatelessWidget {
  const DailyDetailPage({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('当天详情'),
        backgroundColor: AppColors.background,
      ),
      body: SafeArea(child: DailyDetailPanel(date: date, showTitle: false)),
    );
  }
}

class DailyDetailPanel extends ConsumerWidget {
  const DailyDetailPanel({
    required this.date,
    this.showTitle = true,
    super.key,
  });

  final DateTime date;
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = DateTime(date.year, date.month);
    final monthValue = ref.watch(calendarMonthProvider(month));
    return monthValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const Center(child: Text('当天记录加载失败')),
      data: (monthData) => _DailyContent(
        date: date,
        data: monthData.day(date),
        showTitle: showTitle,
      ),
    );
  }
}

class _DailyContent extends ConsumerWidget {
  const _DailyContent({
    required this.date,
    required this.data,
    required this.showTitle,
  });

  final DateTime date;
  final CalendarDayData data;
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday = localDateKey(date) == localDateKey(DateTime.now());
    final now = isToday
        ? ref.watch(timerNowProvider).value ?? DateTime.now()
        : DateTime.now();
    int elapsedFor(TaskDetails task) {
      if (!isToday || !task.hasTimer) return task.todayActualDurationSeconds;
      return ref
              .watch(taskTimerStateProvider(task.id))
              .value
              ?.elapsedSecondsAt(now) ??
          task.todayActualDurationSeconds;
    }

    double progressFor(TaskDetails task) {
      if (!task.hasDurationTarget) return task.isCompleted ? 100 : 0;
      final target = task.targetDurationSeconds ?? 0;
      if (target <= 0) return 0;
      return (elapsedFor(task) / target * 100).clamp(0, 100).toDouble();
    }

    final completionPercent = data.tasks.isEmpty
        ? 0.0
        : data.completedCount / data.tasks.length * 100;
    final completedCount = data.completedCount;
    final timedSeconds = isToday
        ? ref
                  .watch(dailyTimerStateProvider(dateOnly(date)))
                  .value
                  ?.elapsedSecondsAt(now) ??
              data.timedSeconds
        : data.timedSeconds;
    final longTermTasks = data.tasks
        .where((task) => task.kind == TaskKind.longTerm)
        .toList();
    final reminders = data.tasks
        .where((task) => task.kind == TaskKind.oneTime)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        if (showTitle) ...[
          Text(
            DateFormat('M月d日 EEEE', 'zh_CN').format(date),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
        ],
        _DailySummary(
          completionPercent: completionPercent,
          completedCount: completedCount,
          totalCount: data.scheduledCount,
          timedSeconds: timedSeconds,
        ),
        const SizedBox(height: 22),
        if (data.tasks.isEmpty)
          const EmptyState(
            icon: Icons.event_available_outlined,
            title: '当天没有安排',
            message: '这一天没有长期任务或单次事项。',
          )
        else ...[
          _SectionTitle(title: '长期任务', count: longTermTasks.length),
          const SizedBox(height: 10),
          if (longTermTasks.isEmpty)
            const Text('无', style: TextStyle(color: AppColors.muted))
          else
            ...longTermTasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DailyTaskCard(
                  task: task,
                  progress: progressFor(task),
                  actualDurationSeconds: elapsedFor(task),
                ),
              ),
            ),
          const SizedBox(height: 14),
          _SectionTitle(title: '单次事项提醒', count: reminders.length),
          const SizedBox(height: 10),
          if (reminders.isEmpty)
            const Text('无', style: TextStyle(color: AppColors.muted))
          else
            ...reminders.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DailyTaskCard(
                  task: task,
                  progress: progressFor(task),
                  actualDurationSeconds: elapsedFor(task),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _DailySummary extends StatelessWidget {
  const _DailySummary({
    required this.completionPercent,
    required this.completedCount,
    required this.totalCount,
    required this.timedSeconds,
  });

  final double completionPercent;
  final int completedCount;
  final int totalCount;
  final int timedSeconds;

  @override
  Widget build(BuildContext context) {
    final progress = completionPercent / 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 86,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: 76,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      color: AppColors.primary,
                      backgroundColor: const Color(0xFFE9EBEF),
                    ),
                  ),
                  Text(
                    '${completionPercent.round()}%',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当天完成度',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '完成 $completedCount/$totalCount',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '计时 ${formatDuration(timedSeconds)}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTaskCard extends StatelessWidget {
  const _DailyTaskCard({
    required this.task,
    required this.progress,
    required this.actualDurationSeconds,
  });

  final TaskDetails task;
  final double progress;
  final int actualDurationSeconds;

  @override
  Widget build(BuildContext context) {
    final color = Color(task.colorValue);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => TaskDetailPage(taskId: task.id),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            taskIconData(task.iconName),
                            size: 20,
                            color: color,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              task.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${progress.round()}%',
                            style: TextStyle(
                              color: progress >= 100 ? color : AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 6,
                        color: color,
                        backgroundColor: const Color(0xFFE9EBEF),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      if (task.hasDurationTarget) ...[
                        const SizedBox(height: 7),
                        Text(
                          '${formatDuration(actualDurationSeconds)} / '
                          '${formatDuration(task.targetDurationSeconds ?? 0)}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ] else if (task.hasTimer) ...[
                        const SizedBox(height: 7),
                        Text(
                          '计时 ${formatDuration(actualDurationSeconds)}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ] else if (task.kind == TaskKind.oneTime) ...[
                        const SizedBox(height: 7),
                        Text(
                          DateFormat('HH:mm').format(task.scheduledAt!),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Text('$count', style: const TextStyle(color: AppColors.muted)),
      ],
    );
  }
}
