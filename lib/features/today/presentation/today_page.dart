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
import '../../statistics/presentation/tag_time_breakdown.dart';

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
              LayoutBuilder(
                builder: (context, constraints) {
                  final taskLists = _TaskLists(
                    recurringTasks: longTermTasks,
                    oneTimeTasks: oneTimeTasks,
                  );
                  final arrangement = _TodayArrangement(tasks: tasks);
                  if (constraints.maxWidth >= 960) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: taskLists),
                        const SizedBox(width: 18),
                        Expanded(flex: 4, child: arrangement),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      taskLists,
                      const SizedBox(height: 20),
                      arrangement,
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              DailyTagTime(date: dateOnly(now), now: now),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskLists extends StatelessWidget {
  const _TaskLists({required this.recurringTasks, required this.oneTimeTasks});

  final List<TaskDetails> recurringTasks;
  final List<TaskDetails> oneTimeTasks;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SectionTitle(
        title: '周期任务',
        count: recurringTasks.length,
        icon: Icons.loop_rounded,
      ),
      const SizedBox(height: 12),
      if (recurringTasks.isEmpty)
        const EmptyState(
          icon: Icons.loop_rounded,
          title: '今天没有周期任务',
          message: '从中央的“添加”入口创建第一个周期目标。',
        )
      else
        ...recurringTasks.map(
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
  );
}

class _TodayArrangement extends StatelessWidget {
  const _TodayArrangement({required this.tasks});

  final List<TaskDetails> tasks;

  @override
  Widget build(BuildContext context) {
    final arranged = tasks.where((task) {
      if (task.kind == TaskKind.recurring) {
        return task.scheduledMinuteOfDay != null &&
            task.reminderMinuteOfDay != null;
      }
      return task.scheduledAt != null && task.remindBeforeMinutes != null;
    }).toList()..sort((a, b) => _minuteOfDay(a).compareTo(_minuteOfDay(b)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '今日安排',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                const Icon(Icons.today_outlined, color: AppColors.muted),
              ],
            ),
            const SizedBox(height: 12),
            if (arranged.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  '还没有设置时间与提醒的事项',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            else
              ...arranged.map(
                (task) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(
                          _timeLabel(_minuteOfDay(task)),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Color(task.colorValue),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(task.name, overflow: TextOverflow.ellipsis),
                      ),
                      Icon(
                        taskIconData(task.iconName),
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _minuteOfDay(TaskDetails task) => task.kind == TaskKind.recurring
      ? task.scheduledMinuteOfDay!
      : task.scheduledAt!.hour * 60 + task.scheduledAt!.minute;

  String _timeLabel(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
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
    final remaining = totalCount - completedCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ring = _ProgressRing(progress: progress);
            final copy = Expanded(
              flex: constraints.maxWidth >= 700 ? 3 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress >= .7 ? '做得很棒，继续保持节奏！' : '慢慢来，今天也在前进。',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '已完成 $completedCount 项，还有 $remaining 项待完成',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            );
            final metrics = Wrap(
              spacing: 26,
              runSpacing: 12,
              children: [
                _Metric(label: '已完成', value: '$completedCount / $totalCount'),
                _Metric(label: '待完成', value: '$remaining 项'),
                _Metric(label: '专注时长', value: formatDuration(timedSeconds)),
              ],
            );
            if (constraints.maxWidth < 650) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [ring, copy]),
                  const SizedBox(height: 18),
                  metrics,
                ],
              );
            }
            return Row(children: [ring, copy, metrics]);
          },
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    height: 88,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 82,
          height: 82,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 8,
            strokeCap: StrokeCap.round,
            color: AppColors.primary,
            backgroundColor: AppColors.blush,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Text(
              '今日完成度',
              style: TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
      ],
    ),
  );
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
    final running = timer?.isRunning ?? false;
    final target = task.targetDurationSeconds ?? 0;
    final progress = task.hasDurationTarget && target > 0
        ? (elapsed / target * 100).clamp(0, 100).toDouble()
        : task.todayProgressPercent;
    return Card(
      color: running ? color.withValues(alpha: .12) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.id)),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(taskIconData(task.iconName), color: color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _subtitle(elapsed),
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (task.hasTimer)
                            Text(
                              formatDuration(elapsed),
                              style: TextStyle(
                                color: running ? color : AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          if (task.hasDurationTarget) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${progress.round()}%',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          IconButton(
                            tooltip: '删除任务',
                            onPressed: () => _delete(context, ref),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.muted,
                            ),
                          ),
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
                      if (task.hasTimer) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _InlineTimerControls(
                            taskId: task.id,
                            timer: timer,
                            color: color,
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

  String _subtitle(int elapsed) {
    if (task.kind == TaskKind.oneTime) {
      return task.scheduledAt == null
          ? '未设置日期'
          : DateFormat('HH:mm').format(task.scheduledAt!);
    }
    if (task.hasDurationTarget)
      return '目标 ${formatDuration(task.targetDurationSeconds ?? 0)}';
    return task.hasTimer ? '记录专注时长' : '点击打卡';
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
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
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

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务？'),
        content: const Text('任务会归档，历史打卡和计时数据将保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true)
      await ref.read(taskRepositoryProvider).archiveTask(task.id);
  }
}

class _InlineTimerControls extends ConsumerStatefulWidget {
  const _InlineTimerControls({
    required this.taskId,
    required this.timer,
    required this.color,
  });
  final String taskId;
  final TaskTimerState? timer;
  final Color color;
  @override
  ConsumerState<_InlineTimerControls> createState() =>
      _InlineTimerControlsState();
}

class _InlineTimerControlsState extends ConsumerState<_InlineTimerControls> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final timer = widget.timer;
    if (_busy)
      return const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    return Wrap(
      spacing: 8,
      children: [
        if (timer == null || timer.canStart)
          FilledButton.icon(
            onPressed: () => _run((repo) => repo.startTimer(widget.taskId)),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('开始'),
          ),
        if (timer?.isRunning ?? false)
          OutlinedButton.icon(
            onPressed: () => _run((repo) => repo.pauseTimer(widget.taskId)),
            icon: const Icon(Icons.pause_rounded, size: 18),
            label: const Text('暂停'),
          ),
        if (timer?.isPaused ?? false)
          FilledButton.icon(
            onPressed: () => _run((repo) => repo.resumeTimer(widget.taskId)),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('继续'),
          ),
        if (timer != null && !timer.canStart)
          OutlinedButton.icon(
            onPressed: () => _run((repo) => repo.endTimer(widget.taskId)),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('结束'),
          ),
      ],
    );
  }

  Future<void> _run(Future<void> Function(dynamic) action) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(taskRepositoryProvider));
    } on Object catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('计时操作失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
