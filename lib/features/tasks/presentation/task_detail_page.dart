import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../statistics/presentation/task_insights.dart';
import '../application/task_providers.dart';
import '../domain/task_models.dart';
import 'long_term_task_form_page.dart';
import 'one_time_reminder_form_page.dart';
import 'task_icon_picker.dart';

class TaskDetailPage extends ConsumerWidget {
  const TaskDetailPage({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskValue = ref.watch(taskDetailsProvider(taskId));
    return taskValue.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('任务加载失败')),
      ),
      data: (task) {
        if (task == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('任务不存在或已归档')),
          );
        }
        return _TaskDetailContent(task: task);
      },
    );
  }
}

class _TaskDetailContent extends ConsumerWidget {
  const _TaskDetailContent({required this.task});

  final TaskDetails task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(task.colorValue);
    return Scaffold(
      appBar: AppBar(
        title: Text(task.kind == TaskKind.longTerm ? '长期任务详情' : '单次事项详情'),
        backgroundColor: AppColors.background,
        actions: [
          if (task.status != TaskLifecycle.archived) ...[
            IconButton(
              tooltip: '编辑',
              onPressed: () => _edit(context),
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                if (value == 'archive') _archive(context, ref);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined),
                      SizedBox(width: 10),
                      Text('归档任务'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                taskIconData(task.iconName),
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    task.kind == TaskKind.longTerm
                                        ? _longTermSubtitle(task)
                                        : _oneTimeSubtitle(task),
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (task.status == TaskLifecycle.archived)
                              const Chip(label: Text('已归档')),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (task.kind == TaskKind.longTerm)
                      _LongTermStatusCard(task: task, color: color)
                    else
                      _OneTimeStatusCard(task: task, color: color),
                    TaskInsights(task: task),
                    if (task.notes != null) ...[
                      const SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '备注',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              Text(task.notes!),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (task.kind == TaskKind.longTerm) ...[
                      const SizedBox(height: 22),
                      Text(
                        '打卡历史',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _CompletionHistory(taskId: task.id, color: color),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => task.kind == TaskKind.longTerm
            ? LongTermTaskFormPage(initialTask: task)
            : OneTimeReminderFormPage(initialTask: task),
      ),
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档任务？'),
        content: const Text('任务会从今日列表移除，但历史打卡和统计数据会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(taskRepositoryProvider).archiveTask(task.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  String _longTermSubtitle(TaskDetails task) {
    final mode = switch (task.checkMode) {
      LongTermCheckMode.freeTimer => '自由计时',
      LongTermCheckMode.targetTimer => '目标时长计时',
      _ => '点击直接完成',
    };
    return '$mode · ${_scheduleDescription(task.schedule!)}';
  }

  String _oneTimeSubtitle(TaskDetails task) {
    return DateFormat('yyyy年M月d日 HH:mm').format(task.scheduledAt!);
  }
}

class _LongTermStatusCard extends ConsumerWidget {
  const _LongTermStatusCard({required this.task, required this.color});

  final TaskDetails task;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (task.hasTimer) ...[
              _TimerControl(task: task, color: color),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 12),
              _DetailValue(
                label: '今日任务状态',
                value: task.todayCompleted ? '已完成' : '未完成',
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: () => _toggle(context, ref),
                icon: Icon(
                  task.todayCompleted
                      ? Icons.undo_rounded
                      : Icons.check_rounded,
                ),
                label: Text(task.todayCompleted ? '撤销今日完成' : '完成今日任务'),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _DetailValue(
                      label: '今日状态',
                      value: task.todayCompleted ? '已完成' : '未完成',
                    ),
                  ),
                  Expanded(
                    child: _DetailValue(
                      label: '长期目标',
                      value: task.targetDays == null
                          ? '未设置'
                          : '${task.targetDays} 天',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: (task.todayProgressPercent / 100).clamp(0, 1),
                minHeight: 8,
                color: color,
                backgroundColor: const Color(0xFFE9EBEF),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: () => _toggle(context, ref),
                icon: Icon(
                  task.todayCompleted
                      ? Icons.undo_rounded
                      : Icons.check_rounded,
                ),
                label: Text(task.todayCompleted ? '撤销今日打卡' : '完成今日打卡'),
              ),
            ],
            const SizedBox(height: 16),
            _InfoRow(
              label: '执行周期',
              value: _scheduleDescription(task.schedule!),
            ),
            const SizedBox(height: 10),
            _InfoRow(label: '节假日暂停', value: task.holidayPause ? '已开启' : '未开启'),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    if (task.todayCompleted) {
      final confirmed = await _confirmUndo(context);
      if (!confirmed) return;
    }
    await ref
        .read(taskRepositoryProvider)
        .toggleLongTermCompletion(task.id, DateTime.now());
  }
}

class _TimerControl extends ConsumerStatefulWidget {
  const _TimerControl({required this.task, required this.color});

  final TaskDetails task;
  final Color color;

  @override
  ConsumerState<_TimerControl> createState() => _TimerControlState();
}

class _TimerControlState extends ConsumerState<_TimerControl> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final timerValue = ref.watch(taskTimerStateProvider(widget.task.id));
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    return timerValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const Text('计时状态加载失败'),
      data: (timer) {
        final target = widget.task.targetDurationSeconds ?? 0;
        final isOneTime = widget.task.kind == TaskKind.oneTime;
        final elapsed = isOneTime
            ? timer.totalElapsedSecondsAt(now)
            : timer.elapsedSecondsAt(now);
        final progress = widget.task.hasDurationTarget
            ? timer.progressAt(now, target)
            : 0.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _DetailValue(
                    label: timer.isRunning
                        ? '正在计时'
                        : timer.isPaused
                        ? '已暂停'
                        : isOneTime
                        ? '累计计时'
                        : '今日累计',
                    value: formatDuration(elapsed),
                  ),
                ),
                if (widget.task.hasDurationTarget)
                  Expanded(
                    child: _DetailValue(
                      label: '每日目标',
                      value: '${target ~/ 60} 分钟',
                    ),
                  )
                else
                  const Expanded(
                    child: _DetailValue(label: '计时方式', value: '自由计时'),
                  ),
              ],
            ),
            if (widget.task.hasDurationTarget) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    progress >= 100 ? '今日目标时长已达到' : '时长进度 ${progress.round()}%',
                    style: TextStyle(
                      color: progress >= 100 ? widget.color : AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${formatDuration(elapsed)} / ${formatDuration(target)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress / 100,
                minHeight: 8,
                color: widget.color,
                backgroundColor: const Color(0xFFE9EBEF),
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            const SizedBox(height: 18),
            if (timer.canStart)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: widget.color),
                onPressed: _isSubmitting
                    ? null
                    : () => _run(
                        () => ref
                            .read(taskRepositoryProvider)
                            .startTimer(widget.task.id),
                      ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开始计时'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _run(
                              () => timer.isRunning
                                  ? ref
                                        .read(taskRepositoryProvider)
                                        .pauseTimer(widget.task.id)
                                  : ref
                                        .read(taskRepositoryProvider)
                                        .resumeTimer(widget.task.id),
                            ),
                      icon: Icon(
                        timer.isRunning
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(timer.isRunning ? '暂停' : '继续'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.color,
                      ),
                      onPressed: _isSubmitting
                          ? null
                          : () => _run(
                              () => ref
                                  .read(taskRepositoryProvider)
                                  .endTimer(widget.task.id),
                            ),
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('结束'),
                    ),
                  ),
                ],
              ),
            if (timer.sessions.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              Text(
                isOneTime ? '计时片段' : '今日计时片段',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...timer.sessions
                  .where((session) {
                    if (isOneTime) return true;
                    final end = session.endedAt ?? now;
                    final startDay = dateOnly(session.startedAt);
                    final endDay = dateOnly(end);
                    return !timer.localDate.isBefore(startDay) &&
                        !timer.localDate.isAfter(endDay);
                  })
                  .take(6)
                  .map(
                    (session) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Icon(
                            session.status == TimerSessionStatus.running
                                ? Icons.timelapse_rounded
                                : Icons.schedule_rounded,
                            size: 18,
                            color: widget.color,
                          ),
                          const SizedBox(width: 9),
                          Text(DateFormat('HH:mm').format(session.startedAt)),
                          const Text(' - '),
                          Text(
                            session.endedAt == null
                                ? '进行中'
                                : DateFormat('HH:mm').format(session.endedAt!),
                          ),
                          const Spacer(),
                          Text(
                            formatDuration(session.elapsedSecondsAt(now)),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _isSubmitting = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('计时状态已变化，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _OneTimeStatusCard extends ConsumerWidget {
  const _OneTimeStatusCard({required this.task, required this.color});

  final TaskDetails task;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = dateOnly(
      task.scheduledAt!,
    ).difference(dateOnly(DateTime.now())).inDays;
    final countdown = days > 0
        ? '还有 $days 天'
        : days == 0
        ? '就是今天'
        : '已过去 ${-days} 天';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (task.hasTimer) ...[
              _TimerControl(task: task, color: color),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _DetailValue(label: '倒计时', value: countdown),
                ),
                Expanded(
                  child: _DetailValue(
                    label: '状态',
                    value: task.isCompleted ? '已完成' : '未完成',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: () async {
                if (task.isCompleted && !await _confirmUndo(context)) return;
                await ref
                    .read(taskRepositoryProvider)
                    .toggleOneTimeCompletion(task.id);
              },
              icon: Icon(
                task.isCompleted ? Icons.undo_rounded : Icons.check_rounded,
              ),
              label: Text(task.isCompleted ? '撤销完成' : '完成事项'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionHistory extends ConsumerWidget {
  const _CompletionHistory({required this.taskId, required this.color});

  final String taskId;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(taskCompletionHistoryProvider(taskId));
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const Text('历史记录加载失败'),
      data: (entries) {
        if (entries.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('还没有打卡记录', style: TextStyle(color: AppColors.muted)),
            ),
          );
        }
        return Card(
          child: Column(
            children: [
              for (var index = 0; index < entries.length; index++) ...[
                ListTile(
                  leading: Icon(
                    entries[index].isSuccess
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: entries[index].isSuccess ? color : AppColors.muted,
                  ),
                  title: Text(entries[index].localDate),
                  subtitle: Text(
                    '计时 ${formatDuration(entries[index].actualDurationSeconds)}'
                    '${entries[index].targetReached ? ' · 时长目标已达到' : ''}',
                  ),
                  trailing: Text(
                    entries[index].isSuccess ? '已完成' : '未完成',
                    style: TextStyle(
                      color: entries[index].isSuccess ? color : AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (index != entries.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});

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
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted)),
        const Spacer(),
        Flexible(child: Text(value, textAlign: TextAlign.right)),
      ],
    );
  }
}

Future<bool> _confirmUndo(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('撤销完成状态？'),
          content: const Text('这会把今天的状态改回未完成，历史记录仍会保留。'),
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
      ) ??
      false;
}

String _scheduleDescription(TaskScheduleRule schedule) {
  return switch (schedule.preset) {
    SchedulePreset.daily => '每天',
    SchedulePreset.weekdays => '工作日',
    SchedulePreset.weekends => '周末',
    SchedulePreset.custom =>
      WeekdayMask.toDays(schedule.weekdaysMask)
          .map(
            (day) => '周${const ['一', '二', '三', '四', '五', '六', '日'][day - 1]}',
          )
          .join('、'),
  };
}
