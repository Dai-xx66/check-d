import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_header.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/task_detail_page.dart';
import '../../tasks/presentation/task_icon_picker.dart';
import '../../tasks/presentation/task_list_page.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final dateText = DateFormat('M月d日 EEEE', 'zh_CN').format(now);
    final tasksValue = ref.watch(tasksForDateProvider(dateOnly(now)));

    return SafeArea(
      child: tasksValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Text('今日任务加载失败')),
        data: (tasks) => _TodayContent(dateText: dateText, tasks: tasks),
      ),
    );
  }
}

class _TodayContent extends ConsumerWidget {
  const _TodayContent({required this.dateText, required this.tasks});

  final String dateText;
  final List<TaskDetails> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final longTermTasks = tasks
        .where((task) => task.kind == TaskKind.recurring)
        .toList();
    final oneTimeTasks = tasks
        .where((task) => task.kind == TaskKind.oneTime)
        .toList();
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final completedCount = tasks.where((task) => task.isCompleted).length;
    final timedSeconds =
        ref
            .watch(dailyTimerStateProvider(dateOnly(now)))
            .value
            ?.elapsedSecondsAt(now) ??
        0;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          sliver: SliverList.list(
            children: [
              PageHeader(
                title: '今日',
                subtitle: dateText,
                trailing: IconButton(
                  tooltip: '全部任务',
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (context) => const TaskListPage(),
                    ),
                  ),
                  icon: const Icon(Icons.checklist_rounded),
                ),
              ),
              const SizedBox(height: 22),
              _TodaySummary(
                totalCount: tasks.length,
                completedCount: completedCount,
                timedSeconds: timedSeconds,
              ),
              const SizedBox(height: 28),
              _SectionTitle(
                title: '周期任务',
                count: longTermTasks.length,
                icon: Icons.loop_rounded,
              ),
              const SizedBox(height: 12),
              if (longTermTasks.isEmpty)
                const EmptyState(
                  icon: Icons.loop_rounded,
                  title: '今天没有周期任务',
                  message: '从中央的“添加”入口创建第一个周期目标。',
                )
              else
                ...longTermTasks.map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TaskCard(task: task),
                  ),
                ),
              const SizedBox(height: 16),
              _SectionTitle(
                title: '单次事项',
                count: oneTimeTasks.length,
                icon: Icons.event_note_outlined,
              ),
              const SizedBox(height: 12),
              if (oneTimeTasks.isEmpty)
                const EmptyState(
                  icon: Icons.event_note_outlined,
                  title: '今天没有单次事项',
                  message: '临时事项和重要日期会单独显示在这里。',
                )
              else
                ...oneTimeTasks.map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TaskCard(task: task),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({
    required this.totalCount,
    required this.completedCount,
    required this.timedSeconds,
  });

  final int totalCount;
  final int completedCount;
  final int timedSeconds;

  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Positioned(
              right: -6,
              top: -24,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.9,
                  child: Image.asset(
                    'assets/images/pink_lamb_piano.png',
                    width: 150,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('今日进度', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 82),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          label: '今日完成度',
                          value: '${(progress * 100).round()}%',
                        ),
                      ),
                      Expanded(
                        child: _Metric(
                          label: '已完成',
                          value: '$completedCount/$totalCount',
                        ),
                      ),
                      Expanded(
                        child: _Metric(
                          label: '计时时长',
                          value: formatDuration(timedSeconds),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    color: AppColors.primary,
                    backgroundColor: AppColors.blush,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task});

  final TaskDetails task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(task.colorValue);
    final now = task.hasTimer
        ? ref.watch(timerNowProvider).value ?? DateTime.now()
        : DateTime.now();
    final timer = task.hasTimer
        ? ref.watch(taskTimerStateProvider(task.id)).value
        : null;
    final elapsed =
        timer?.elapsedSecondsAt(now) ?? task.todayActualDurationSeconds;
    final target = task.targetDurationSeconds ?? 0;
    final progress = task.hasDurationTarget && target > 0
        ? (elapsed / target * 100).clamp(0, 100).toDouble()
        : task.todayProgressPercent;
    final completed = task.isCompleted;
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
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                  child: Row(
                    children: [
                      Icon(taskIconData(task.iconName), color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _subtitle(task, elapsed),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (task.hasDurationTarget) ...[
                        Text(
                          '${progress.round()}%',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        tooltip: task.isCompleted ? '撤销完成' : '标记完成',
                        onPressed: () => _toggle(context, ref),
                        icon: Icon(
                          task.isCompleted
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: task.isCompleted ? color : AppColors.muted,
                        ),
                      ),
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

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    if (task.isCompleted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('撤销完成状态？'),
          content: const Text('状态会改回未完成，但历史记录不会被删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认撤销'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final repository = ref.read(taskRepositoryProvider);
    if (task.kind == TaskKind.recurring) {
      await repository.toggleRecurringCompletion(task.id, DateTime.now());
    } else {
      await repository.toggleOneTimeCompletion(task.id);
    }
  }

  String _subtitle(TaskDetails task, int elapsedSeconds) {
    if (task.kind == TaskKind.oneTime) {
      final time = DateFormat('HH:mm').format(task.scheduledAt!);
      return task.hasTimer
          ? '$time · 已计时 ${formatDuration(elapsedSeconds)}'
          : time;
    }
    if (task.hasDurationTarget) {
      return '${formatDuration(elapsedSeconds)} / '
          '${formatDuration(task.targetDurationSeconds ?? 0)}';
    }
    if (task.hasTimer) return '今日计时 ${formatDuration(elapsedSeconds)}';
    return '点击打卡';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.count,
    required this.icon,
  });

  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.muted),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Text('$count', style: const TextStyle(color: AppColors.muted)),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
