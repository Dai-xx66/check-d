import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/mascot.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../reviews/application/review_providers.dart';
import '../../reviews/domain/review_models.dart';
import '../../reviews/presentation/reviews_page.dart';
import '../../statistics/presentation/tag_time_breakdown.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/task_detail_page.dart';
import '../../tasks/presentation/task_icon_picker.dart';
import '../../tasks/presentation/task_list_page.dart';
import '../../courses/application/course_providers.dart';
import '../../courses/domain/course_models.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../data/today_repository.dart';
import '../domain/today_models.dart';

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = dateOnly(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final tasks = ref.watch(tasksForDateProvider(_selectedDate));
    final courses = ref.watch(coursesSnapshotProvider);
    final overrides = ref.watch(dailyOverridesSnapshotProvider(_selectedDate));
    final adHocTimers = ref.watch(adHocTimersForDateProvider(_selectedDate));
    final todayCourses =
        courses is AsyncData<List<CourseDetails>> &&
            overrides is AsyncData<List<DailyItemOverride>>
        ? buildCourseItemsForDate(_selectedDate, courses.value, overrides.value)
        : const <TodayCourseItem>[];
    return SafeArea(
      child: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('今日任务加载失败')),
        data: (items) => _TodayContent(
          data: _TodayData(
            date: _selectedDate,
            now: now,
            tasks: items,
            courses: todayCourses,
            adHocTimers: adHocTimers.value ?? const <AdHocTimerDetails>[],
            focusedSeconds:
                (ref
                        .watch(dailyTimerStateProvider(_selectedDate))
                        .value
                        ?.elapsedSecondsAt(now) ??
                    0) +
                (adHocTimers.value ?? const <AdHocTimerDetails>[]).fold<int>(
                  0,
                  (sum, timer) =>
                      sum +
                      timer.durationSecondsForDate(_selectedDate, now: now),
                ),
          ),
          onDateSelected: (value) =>
              setState(() => _selectedDate = dateOnly(value)),
        ),
      ),
    );
  }
}

class _TodayData {
  const _TodayData({
    required this.date,
    required this.now,
    required this.tasks,
    this.courses = const [],
    this.adHocTimers = const [],
    required this.focusedSeconds,
  });

  final DateTime date;
  final DateTime now;
  final List<TaskDetails> tasks;
  final List<TodayCourseItem> courses;
  final List<AdHocTimerDetails> adHocTimers;
  final int focusedSeconds;

  List<TaskDetails> get recurring =>
      tasks.where((item) => item.kind == TaskKind.recurring).toList();
  List<TaskDetails> get oneTime =>
      tasks.where((item) => item.kind == TaskKind.oneTime).toList();
  int get completed => tasks.where((item) => item.isCompleted).length;
  int get remaining => tasks.length - completed;
  double get progress => tasks.isEmpty ? 0 : completed / tasks.length;
  bool get isToday => dateOnly(date) == dateOnly(now);
  String get dateText => DateFormat('M月d日 EEEE', 'zh_CN').format(date);
  String get encouragement => switch ((progress * 100).round()) {
    < 30 => '今天才刚刚开始～',
    < 60 => '慢慢来，已经在前进啦！',
    < 90 => '做得很好，继续保持～',
    < 100 => '马上就全部完成啦！',
    _ => '今天的任务全部完成啦！',
  };
  MascotState get mascotState => switch ((progress * 100).round()) {
    < 30 => MascotState.idle,
    < 60 => MascotState.encouraging,
    < 90 => MascotState.happy,
    < 100 => MascotState.encouraging,
    _ => MascotState.celebrating,
  };
}

class _TodayContent extends StatelessWidget {
  const _TodayContent({required this.data, required this.onDateSelected});

  final _TodayData data;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 1024) return _DesktopLayout(data: data);
      if (constraints.maxWidth >= 600) return _TabletLayout(data: data);
      return _MobileLayout(data: data, onDateSelected: onDateSelected);
    },
  );
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) => _TodayScroll(
    child: Column(
      children: [
        _DesktopHeader(data: data),
        const SizedBox(height: 18),
        _DesktopSummary(data: data),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 55, child: _TaskLists(data: data)),
            const SizedBox(width: 18),
            Expanded(
              flex: 45,
              child: _TodayArrangement(
                tasks: data.tasks,
                courses: data.courses,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 55,
              child: DailyTagTime(date: data.date, now: data.now),
            ),
            const SizedBox(width: 18),
            Expanded(flex: 45, child: _ReviewSummary(date: data.date)),
          ],
        ),
      ],
    ),
  );
}

class _TabletLayout extends StatelessWidget {
  const _TabletLayout({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) => _TodayScroll(
    child: Column(
      children: [
        _DesktopHeader(data: data),
        const SizedBox(height: 18),
        _DesktopSummary(data: data),
        const SizedBox(height: 18),
        _TaskLists(data: data),
        const SizedBox(height: 18),
        _TodayArrangement(tasks: data.tasks, courses: data.courses),
        const SizedBox(height: 18),
        DailyTagTime(date: data.date, now: data.now),
        const SizedBox(height: 18),
        _ReviewSummary(date: data.date),
      ],
    ),
  );
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.data, required this.onDateSelected});
  final _TodayData data;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) => _TodayScroll(
    horizontal: 16,
    bottom: 110,
    child: Column(
      children: [
        _MobileHeader(data: data),
        const SizedBox(height: 12),
        _WeekDateStrip(selectedDate: data.date, onSelected: onDateSelected),
        const SizedBox(height: 14),
        _MobileSummary(data: data),
        if (data.adHocTimers.isNotEmpty) ...[
          const SizedBox(height: 18),
          _AdHocSection(timers: data.adHocTimers, isToday: data.isToday),
        ],
        if (data.courses.isNotEmpty) ...[
          const SizedBox(height: 18),
          _MobileCourseSection(courses: data.courses),
        ],
        const SizedBox(height: 18),
        _TaskSection(
          title: '周期任务',
          icon: Icons.loop_rounded,
          tasks: data.recurring,
          isToday: data.isToday,
          emptyTitle: '今天没有周期任务',
          emptyMessage: '给自己安排一个温柔的小目标吧～',
        ),
        const SizedBox(height: 18),
        _TaskSection(
          title: '单次事项',
          icon: Icons.event_note_outlined,
          tasks: data.oneTime,
          isToday: data.isToday,
          emptyTitle: '今天没有其它安排～',
          emptyMessage: '临时事项会在这里出现。',
        ),
      ],
    ),
  );
}

class _MobileCourseSection extends StatelessWidget {
  const _MobileCourseSection({required this.courses});

  final List<TodayCourseItem> courses;

  @override
  Widget build(BuildContext context) {
    final sorted = [...courses]
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.school_outlined,
              size: 19,
              color: AppColors.primary,
            ),
            const SizedBox(width: 7),
            Text('今日课程', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 7),
            Text(
              '${sorted.length}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < sorted.length; index++) ...[
                _MobileCourseRow(item: sorted[index]),
                if (index != sorted.length - 1)
                  const Divider(height: 1, indent: 18, endIndent: 18),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileCourseRow extends StatelessWidget {
  const _MobileCourseRow({required this.item});

  final TodayCourseItem item;

  @override
  Widget build(BuildContext context) {
    final color = Color(item.course.colorValue);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              _timeRange(item),
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  item.classroom == null ? '课程' : '课程 · ${item.classroom}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: color, size: 20),
        ],
      ),
    );
  }

  String _timeRange(TodayCourseItem item) =>
      '${_minute(item.startMinute)}\n${_minute(item.endMinute)}';

  String _minute(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
}

class _AdHocSection extends StatelessWidget {
  const _AdHocSection({required this.timers, required this.isToday});

  final List<AdHocTimerDetails> timers;
  final bool isToday;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 19, color: AppColors.primary),
          const SizedBox(width: 7),
          Text('临时计时', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            for (var index = 0; index < timers.length; index++) ...[
              _AdHocRow(timer: timers[index], enabled: isToday),
              if (index != timers.length - 1)
                const Divider(height: 1, indent: 18, endIndent: 18),
            ],
          ],
        ),
      ),
    ],
  );
}

class _AdHocRow extends ConsumerStatefulWidget {
  const _AdHocRow({required this.timer, required this.enabled});

  final AdHocTimerDetails timer;
  final bool enabled;

  @override
  ConsumerState<_AdHocRow> createState() => _AdHocRowState();
}

class _AdHocRowState extends ConsumerState<_AdHocRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final timer = widget.timer;
    final color = Color(timer.colorValue);
    final action = switch (timer.timerStatus) {
      AdHocTimerStatus.idle => ('开始', Icons.play_arrow_rounded),
      AdHocTimerStatus.running => ('暂停', Icons.pause_rounded),
      AdHocTimerStatus.paused => ('继续', Icons.play_arrow_rounded),
      AdHocTimerStatus.ended => ('已结束', Icons.check_rounded),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      child: Row(
        children: [
          _TaskIcon(color: color, icon: Icons.bolt_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(timer.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  formatDuration(timer.accumulatedDurationSeconds),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (timer.timerStatus != AdHocTimerStatus.ended)
            FilledButton.icon(
              onPressed: widget.enabled && !_busy ? _runAction : null,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(action.$2, size: 16),
              label: Text(action.$1),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            const Icon(Icons.check_circle_rounded, color: AppColors.green),
          if (timer.timerStatus != AdHocTimerStatus.ended && widget.enabled)
            IconButton(
              tooltip: '结束',
              onPressed: _busy ? null : _end,
              icon: const Icon(Icons.stop_rounded),
            ),
        ],
      ),
    );
  }

  Future<void> _runAction() async {
    setState(() => _busy = true);
    final repository = ref.read(dayScheduleRepositoryProvider);
    try {
      switch (widget.timer.timerStatus) {
        case AdHocTimerStatus.idle:
          await repository.startAdHocTimer(widget.timer.id);
        case AdHocTimerStatus.running:
          await repository.pauseAdHocTimer(widget.timer.id);
        case AdHocTimerStatus.paused:
          await repository.resumeAdHocTimer(widget.timer.id);
        case AdHocTimerStatus.ended:
          break;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(dayScheduleRepositoryProvider)
          .endAdHocTimer(widget.timer.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _TodayScroll extends StatelessWidget {
  const _TodayScroll({
    required this.child,
    this.horizontal = 24,
    this.bottom = 36,
  });
  final Widget child;
  final double horizontal;
  final double bottom;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(horizontal, 22, horizontal, bottom),
        sliver: SliverToBoxAdapter(child: child),
      ),
    ],
  );
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(data.dateText, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
      const MascotWidget(state: MascotState.working, size: 76),
      const SizedBox(width: 8),
      IconButton(
        tooltip: '全部任务',
        onPressed: () => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => const TaskListPage())),
        icon: const Icon(Icons.checklist_rounded),
      ),
    ],
  );
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今天',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontSize: 31),
            ),
            const SizedBox(height: 2),
            Text(data.dateText, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
      MascotWidget(state: data.mascotState, size: 64, compact: true),
    ],
  );
}

class _DesktopSummary extends StatelessWidget {
  const _DesktopSummary({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          _ProgressRing(progress: data.progress, size: 82),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.encouragement,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '已完成 ${data.completed} 项，还有 ${data.remaining} 项待完成',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const _MetricDivider(),
          _Metric(
            icon: Icons.check_circle_outline_rounded,
            label: '已完成',
            value: '${data.completed} / ${data.tasks.length}',
          ),
          const _MetricDivider(),
          _Metric(
            icon: Icons.schedule_rounded,
            label: '待完成',
            value: '${data.remaining} 项',
          ),
          const _MetricDivider(),
          _Metric(
            icon: Icons.hourglass_bottom_rounded,
            label: '专注时长',
            value: formatDuration(data.focusedSeconds),
          ),
        ],
      ),
    ),
  );
}

class _MobileSummary extends StatelessWidget {
  const _MobileSummary({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '今日进度',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              MascotWidget(state: data.mascotState, size: 52, compact: true),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(data.progress * 100).round()}%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 34,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 7),
                child: Text('今日完成度', style: TextStyle(color: AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ProgressBar(value: data.progress, color: AppColors.primary),
          const SizedBox(height: 7),
          Text(
            '${data.completed}/${data.tasks.length} 项任务已完成',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MobileMetric(label: '已完成', value: '${data.completed}项'),
              ),
              const _MetricDivider(short: true),
              Expanded(
                child: _MobileMetric(label: '待完成', value: '${data.remaining}项'),
              ),
              const _MetricDivider(short: true),
              Expanded(
                child: _MobileMetric(
                  label: '累计专注',
                  value: formatDuration(data.focusedSeconds),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _TaskLists extends StatelessWidget {
  const _TaskLists({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _TaskSection(
        title: '周期任务',
        icon: Icons.loop_rounded,
        tasks: data.recurring,
        isToday: data.isToday,
        emptyTitle: '今天没有周期任务',
        emptyMessage: '创建一个想坚持的目标吧～',
      ),
      const SizedBox(height: 18),
      _TaskSection(
        title: '单次事项',
        icon: Icons.event_note_outlined,
        tasks: data.oneTime,
        isToday: data.isToday,
        emptyTitle: '今天没有单次事项',
        emptyMessage: '临时事项会安静地等在这里。',
      ),
    ],
  );
}

class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.title,
    required this.icon,
    required this.tasks,
    required this.isToday,
    required this.emptyTitle,
    required this.emptyMessage,
  });
  final String title;
  final IconData icon;
  final List<TaskDetails> tasks;
  final bool isToday;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 7),
          Text(
            '${tasks.length}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const TaskListPage()),
            ),
            child: const Text('管理 >'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Card(
        child: tasks.isEmpty
            ? MascotEmptyState(title: emptyTitle, message: emptyMessage)
            : Column(
                children: [
                  for (var index = 0; index < tasks.length; index++) ...[
                    _TaskRow(task: tasks[index], isToday: isToday),
                    if (index != tasks.length - 1)
                      const Divider(height: 1, indent: 18, endIndent: 18),
                  ],
                ],
              ),
      ),
    ],
  );
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task, required this.isToday});
  final TaskDetails task;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(task.colorValue);
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final timer = task.hasTimer
        ? ref.watch(taskTimerStateProvider(task.id)).value
        : null;
    final elapsed =
        timer?.elapsedSecondsAt(now) ?? task.todayActualDurationSeconds;
    final running = timer?.isRunning ?? false;
    final target = task.targetDurationSeconds ?? 0;
    final progress = task.hasDurationTarget && target > 0
        ? (elapsed / target).clamp(0, 1).toDouble()
        : 0.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      color: running ? color.withValues(alpha: .09) : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.id)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 430;
            return Column(
              children: [
                Row(
                  children: [
                    _TaskIcon(color: color, icon: taskIconData(task.iconName)),
                    const SizedBox(width: 10),
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
                          const SizedBox(height: 2),
                          Text(
                            _subtitle(task, elapsed),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!narrow && task.hasTimer)
                      _TimerText(
                        elapsed: elapsed,
                        running: running,
                        color: color,
                      ),
                    const SizedBox(width: 3),
                    _TaskMenu(task: task),
                    _CompletionButton(task: task, enabled: isToday),
                  ],
                ),
                if (task.hasTimer &&
                    (running ||
                        timer?.isPaused == true ||
                        task.hasDurationTarget)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (narrow) ...[
                        _TimerText(
                          elapsed: elapsed,
                          running: running,
                          color: color,
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (task.hasDurationTarget)
                        Expanded(
                          child: _ProgressBar(value: progress, color: color),
                        ),
                      if (task.hasDurationTarget) const SizedBox(width: 8),
                      if (task.hasDurationTarget)
                        Text(
                          '${formatDuration(elapsed)} / ${formatDuration(target)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      if (!task.hasDurationTarget) const Spacer(),
                      if (isToday)
                        _InlineTimerControls(
                          taskId: task.id,
                          timer: timer,
                          color: color,
                        ),
                    ],
                  ),
                ] else if (task.hasTimer && isToday) ...[
                  const SizedBox(height: 7),
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
            );
          },
        ),
      ),
    );
  }
}

String _subtitle(TaskDetails task, int elapsed) {
  if (task.kind == TaskKind.oneTime) {
    return task.scheduledAt == null
        ? '未设置日期'
        : DateFormat('今天 HH:mm').format(task.scheduledAt!);
  }
  if (task.hasDurationTarget) {
    return task.hasTimer
        ? '每天 · 目标 ${formatDuration(task.targetDurationSeconds ?? 0)}'
        : '每天';
  }
  return task.hasTimer ? '记录专注时长 · ${formatDuration(elapsed)}' : '点击打卡';
}

class _TaskIcon extends StatelessWidget {
  const _TaskIcon({required this.color, required this.icon});
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: color, size: 20),
  );
}

class _TimerText extends StatelessWidget {
  const _TimerText({
    required this.elapsed,
    required this.running,
    required this.color,
  });
  final int elapsed;
  final bool running;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    formatDuration(elapsed),
    style: TextStyle(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w800,
      color: running ? color : AppColors.ink,
    ),
  );
}

class _CompletionButton extends ConsumerWidget {
  const _CompletionButton({required this.task, required this.enabled});
  final TaskDetails task;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: task.isCompleted ? '撤销完成' : '标记完成',
    onPressed: !enabled
        ? null
        : () async {
            final repository = ref.read(taskRepositoryProvider);
            if (task.kind == TaskKind.recurring) {
              await repository.toggleRecurringCompletion(
                task.id,
                DateTime.now(),
              );
            } else {
              await repository.toggleOneTimeCompletion(task.id);
            }
          },
    icon: AnimatedScale(
      duration: const Duration(milliseconds: 280),
      scale: task.isCompleted ? 1.06 : 1,
      child: Icon(
        task.isCompleted
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: task.isCompleted ? Color(task.colorValue) : AppColors.muted,
      ),
    ),
  );
}

class _TaskMenu extends ConsumerWidget {
  const _TaskMenu({required this.task});
  final TaskDetails task;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: '更多操作',
    icon: const Icon(Icons.more_horiz_rounded, color: AppColors.muted),
    onSelected: (value) async {
      if (value == 'edit') {
        Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.id)),
        );
        return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除任务？'),
          content: const Text('任务会归档，历史打卡与计时记录将保留。'),
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
      if (accepted == true)
        await ref.read(taskRepositoryProvider).archiveTask(task.id);
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'edit', child: Text('查看 / 编辑')),
      PopupMenuItem(value: 'archive', child: Text('删除（归档）')),
    ],
  );
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
    if (_busy) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final timer = widget.timer;
    return Wrap(
      spacing: 6,
      children: [
        if (timer == null || timer.canStart)
          _control(
            Icons.play_arrow_rounded,
            '开始',
            () => ref.read(taskRepositoryProvider).startTimer(widget.taskId),
            filled: true,
          ),
        if (timer?.isRunning ?? false)
          _control(
            Icons.pause_rounded,
            '暂停',
            () => ref.read(taskRepositoryProvider).pauseTimer(widget.taskId),
          ),
        if (timer?.isPaused ?? false)
          _control(
            Icons.play_arrow_rounded,
            '继续',
            () => ref.read(taskRepositoryProvider).resumeTimer(widget.taskId),
            filled: true,
          ),
        if (timer != null && !timer.canStart)
          _control(
            Icons.stop_rounded,
            '结束',
            () => ref.read(taskRepositoryProvider).endTimer(widget.taskId),
          ),
      ],
    );
  }

  Widget _control(
    IconData icon,
    String label,
    Future<void> Function() action, {
    bool filled = false,
  }) => filled
      ? GlassButton(
          onPressed: () => _run(action),
          icon: icon,
          label: label,
          color: widget.color,
          filled: true,
        )
      : GlassButton(
          onPressed: () => _run(action),
          icon: icon,
          label: label,
          color: widget.color,
        );

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _TodayArrangement extends StatelessWidget {
  const _TodayArrangement({required this.tasks, this.courses = const []});
  final List<TaskDetails> tasks;
  final List<TodayCourseItem> courses;
  @override
  Widget build(BuildContext context) {
    final arranged = tasks.where(_isArranged).toList()
      ..sort((a, b) => _minuteOf(a).compareTo(_minuteOf(b)));
    final timeline = [...arranged.map(TodayTaskItem.new), ...courses]
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('今日安排', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                const Icon(Icons.today_outlined, color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 10),
            if (timeline.isEmpty)
              const MascotEmptyState(
                title: '今天还没有安排～',
                message: '配置日期与提醒后会显示在这里。',
              )
            else
              for (var i = 0; i < timeline.length; i++)
                switch (timeline[i]) {
                  TodayTaskItem item => _TimelineItem(
                    task: item.task,
                    last: i == timeline.length - 1,
                  ),
                  TodayCourseItem item => _CourseTimelineItem(
                    item: item,
                    last: i == timeline.length - 1,
                  ),
                },
          ],
        ),
      ),
    );
  }

  bool _isArranged(TaskDetails task) => task.kind == TaskKind.recurring
      ? task.scheduledMinuteOfDay != null && task.reminderMinuteOfDay != null
      : task.scheduledAt != null && task.remindBeforeMinutes != null;
  int _minuteOf(TaskDetails task) => task.kind == TaskKind.recurring
      ? task.scheduledMinuteOfDay!
      : task.scheduledAt!.hour * 60 + task.scheduledAt!.minute;
}

class _CourseTimelineItem extends StatelessWidget {
  const _CourseTimelineItem({required this.item, required this.last});

  final TodayCourseItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final start = _formatMinute(item.startMinute);
    final end = _formatMinute(item.endMinute);
    final color = Color(item.course.colorValue);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 11),
              child: Text(
                start,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 14),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!last)
                Expanded(child: Container(width: 1, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.course.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '课程 · $start–$end${item.classroom == null ? '' : ' · ${item.classroom}'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Icon(Icons.school_outlined, size: 18, color: AppColors.muted),
        ],
      ),
    );
  }
}

String _formatMinute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.task, required this.last});
  final TaskDetails task;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final minute = task.kind == TaskKind.recurring
        ? task.scheduledMinuteOfDay!
        : task.scheduledAt!.hour * 60 + task.scheduledAt!.minute;
    final label =
        '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
    final color = Color(task.colorValue);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 11),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 14),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!last)
                Expanded(child: Container(width: 1, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7, bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          task.tagId == null ? '未分类' : '已设置标签',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    task.isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: task.isCompleted ? color : AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSummary extends ConsumerWidget {
  const _ReviewSummary({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ReviewPeriod(
      type: ReviewType.day,
      startsOn: dateOnly(date),
      endsOn: dateOnly(date),
    );
    final review = ref.watch(reviewProvider(period));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: review.when(
          loading: () => const SizedBox(
            height: 104,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const Text('复盘加载失败'),
          data: (entry) {
            final content = entry?.learnedText ?? entry?.happenedText;
            final empty = content == null || content.trim().isEmpty;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今日复盘',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        empty ? '今天还没有留下记录' : content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: empty ? AppColors.muted : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 13),
                      TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ReviewsPage(),
                          ),
                        ),
                        child: Text(empty ? '去复盘 >' : '查看完整复盘 >'),
                      ),
                    ],
                  ),
                ),
                MascotWidget(
                  state: empty ? MascotState.writing : MascotState.happy,
                  size: 70,
                  compact: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WeekDateStrip extends StatelessWidget {
  const _WeekDateStrip({required this.selectedDate, required this.onSelected});
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;
  @override
  Widget build(BuildContext context) {
    final monday = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );
    final labels = const ['一', '二', '三', '四', '五', '六', '日'];
    final today = dateOnly(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: Row(
          children: List.generate(7, (index) {
            final day = dateOnly(monday.add(Duration(days: index)));
            final selected = day == selectedDate;
            final isToday = day == today;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelected(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.blush : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: 11,
                          color: selected ? AppColors.primary : AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 27,
                        height: 27,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : isToday
                              ? AppColors.lavender
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress, required this.size});
  final double progress;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 7,
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
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const Text(
              '完成度',
              style: TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: SizedBox(
      height: 7,
      child: LinearProgressIndicator(
        value: value,
        color: color,
        backgroundColor: color.withValues(alpha: .16),
      ),
    ),
  );
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider({this.short = false});
  final bool short;
  @override
  Widget build(BuildContext context) => Container(
    height: short ? 34 : 48,
    width: 1,
    color: AppColors.border,
    margin: EdgeInsets.symmetric(horizontal: short ? 7 : 20),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 105,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _MobileMetric extends StatelessWidget {
  const _MobileMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      const SizedBox(height: 3),
      FittedBox(
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    ],
  );
}
