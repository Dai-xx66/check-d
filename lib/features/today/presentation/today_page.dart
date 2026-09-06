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
import '../../statistics/application/statistics_providers.dart';
import '../../statistics/domain/statistics_models.dart';
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
    final statistics = ref.watch(statisticsSnapshotProvider);
    final todayCourses =
        courses is AsyncData<List<CourseDetails>> &&
            overrides is AsyncData<List<DailyItemOverride>>
        ? buildCourseItemsForDate(_selectedDate, courses.value, overrides.value)
        : const <TodayCourseItem>[];
    return SafeArea(
      child: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          debugPrint(
            '[Today] task stream failed: ${error.runtimeType}: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
          return Center(child: Text('今日任务加载失败：$error'));
        },
        data: (items) => _TodayContent(
          data: _TodayData(
            date: _selectedDate,
            now: now,
            tasks: items,
            courses: todayCourses,
            overrides: overrides.value ?? const <DailyItemOverride>[],
            adHocTimers: adHocTimers.value ?? const <AdHocTimerDetails>[],
            focusedSeconds:
                statistics.value
                    ?.report(StatisticsPeriod.day, _selectedDate, now)
                    .focusSeconds ??
                0,
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
    this.overrides = const [],
    this.adHocTimers = const [],
    required this.focusedSeconds,
  });

  final DateTime date;
  final DateTime now;
  final List<TaskDetails> tasks;
  final List<TodayCourseItem> courses;
  final List<DailyItemOverride> overrides;
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
      // AppShell has already reserved the desktop sidebar. Use the remaining
      // workspace width so a 1280px desktop window is not treated as tablet.
      if (constraints.maxWidth >= 850) {
        return _DesktopLayout(data: data, onDateSelected: onDateSelected);
      }
      if (constraints.maxWidth >= 600) return _TabletLayout(data: data);
      return _MobileLayout(data: data, onDateSelected: onDateSelected);
    },
  );
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.data, required this.onDateSelected});
  final _TodayData data;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) => _TodayScroll(
    horizontal: 28,
    child: _DesktopTodayWorkspace(data: data, onDateSelected: onDateSelected),
  );
}

enum _DesktopTaskFilter { all, courses, items }

class _DesktopTodayWorkspace extends ConsumerStatefulWidget {
  const _DesktopTodayWorkspace({
    required this.data,
    required this.onDateSelected,
  });

  final _TodayData data;
  final ValueChanged<DateTime> onDateSelected;

  @override
  ConsumerState<_DesktopTodayWorkspace> createState() =>
      _DesktopTodayWorkspaceState();
}

class _DesktopTodayWorkspaceState
    extends ConsumerState<_DesktopTodayWorkspace> {
  _DesktopTaskFilter _filter = _DesktopTaskFilter.all;

  _TodayData get data => widget.data;

  @override
  Widget build(BuildContext context) {
    final rightPanel = _DesktopContextPanel(
      data: data,
      onDateSelected: widget.onDateSelected,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidePanel = constraints.maxWidth >= 1020;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DesktopWorkspaceHeader(
                    data: data,
                    onPrevious: () => widget.onDateSelected(
                      data.date.subtract(const Duration(days: 1)),
                    ),
                    onNext: () => widget.onDateSelected(
                      data.date.add(const Duration(days: 1)),
                    ),
                    onToday: () => widget.onDateSelected(DateTime.now()),
                  ),
                  const SizedBox(height: 26),
                  _DesktopAgenda(
                    data: data,
                    filter: _filter,
                    onFilterChanged: (filter) =>
                        setState(() => _filter = filter),
                  ),
                  const SizedBox(height: 24),
                  _DesktopTodaySummary(data: data),
                  const SizedBox(height: 16),
                  _ReviewSummary(date: data.date),
                ],
              ),
            ),
            if (showSidePanel) ...[
              const SizedBox(width: 24),
              SizedBox(width: 310, child: rightPanel),
            ],
            if (!showSidePanel) ...[
              const SizedBox(width: 24),
              SizedBox(
                width: 62,
                child: _CollapsedContextButton(
                  data: data,
                  onDateSelected: widget.onDateSelected,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DesktopWorkspaceHeader extends StatelessWidget {
  const _DesktopWorkspaceHeader({
    required this.data,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final _TodayData data;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.isToday
                  ? '今天'
                  : DateFormat('M月d日', 'zh_CN').format(data.date),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            Text(data.dateText, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
      if (!data.isToday)
        TextButton.icon(
          onPressed: onToday,
          icon: const Icon(Icons.today_rounded, size: 17),
          label: const Text('回到今天'),
        ),
      IconButton(
        tooltip: '前一天',
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      IconButton(
        tooltip: '后一天',
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
      const SizedBox(width: 4),
      MascotWidget(state: data.mascotState, size: 56, compact: true),
    ],
  );
}

class _DesktopAgenda extends StatelessWidget {
  const _DesktopAgenda({
    required this.data,
    required this.filter,
    required this.onFilterChanged,
  });

  final _TodayData data;
  final _DesktopTaskFilter filter;
  final ValueChanged<_DesktopTaskFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final overrides = {
      for (final value in data.overrides)
        if (value.itemType != DayItemType.course) value.itemId: value,
    };
    final pending = data.tasks.where((task) {
      final override = overrides[task.id];
      return _taskMinute(task, override) == null;
    }).toList();
    final timeline = <_DesktopAgendaEntry>[
      if (filter != _DesktopTaskFilter.items)
        ...data.courses.map(_DesktopAgendaCourse.new),
      if (filter != _DesktopTaskFilter.courses)
        ...data.tasks
            .where((task) => _taskMinute(task, overrides[task.id]) != null)
            .map(
              (task) => _DesktopAgendaTask(
                task,
                _taskMinute(task, overrides[task.id])!,
              ),
            ),
    ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('今日任务', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            SegmentedButton<_DesktopTaskFilter>(
              segments: const [
                ButtonSegment(value: _DesktopTaskFilter.all, label: Text('全部')),
                ButtonSegment(
                  value: _DesktopTaskFilter.courses,
                  label: Text('课程'),
                ),
                ButtonSegment(
                  value: _DesktopTaskFilter.items,
                  label: Text('事项'),
                ),
              ],
              selected: {filter},
              showSelectedIcon: false,
              onSelectionChanged: (value) => onFilterChanged(value.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filter != _DesktopTaskFilter.courses)
          _DesktopPendingItems(
            tasks: pending,
            date: data.date,
            isToday: data.isToday,
          ),
        if (filter != _DesktopTaskFilter.courses) const SizedBox(height: 14),
        Text('今日完整安排', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: _DesktopTimeline(
              entries: timeline,
              data: data,
              showCurrentLine: data.isToday,
            ),
          ),
        ),
      ],
    );
  }
}

sealed class _DesktopAgendaEntry {
  const _DesktopAgendaEntry(this.startMinute);
  final int startMinute;
}

class _DesktopAgendaTask extends _DesktopAgendaEntry {
  const _DesktopAgendaTask(this.task, super.startMinute);
  final TaskDetails task;
}

class _DesktopAgendaCourse extends _DesktopAgendaEntry {
  _DesktopAgendaCourse(this.course) : super(course.startMinute);
  final TodayCourseItem course;
}

int? _taskMinute(TaskDetails task, DailyItemOverride? override) {
  if (override?.action == DayOverrideAction.skip) return null;
  if (override?.plannedStartMinute != null) return override!.plannedStartMinute;
  if (task.kind == TaskKind.recurring) return task.scheduledMinuteOfDay;
  final date = task.scheduledAt;
  return date == null ? null : date.hour * 60 + date.minute;
}

class _DesktopPendingItems extends StatelessWidget {
  const _DesktopPendingItems({
    required this.tasks,
    required this.date,
    required this.isToday,
  });

  final List<TaskDetails> tasks;
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inbox_outlined,
                color: AppColors.orange,
                size: 19,
              ),
              const SizedBox(width: 7),
              Text('待安排', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                '${tasks.length} 项',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final task in tasks)
                  _DesktopPendingChip(task: task, enabled: isToday),
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '没有需要安排的事项。',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
        ],
      ),
    ),
  );
}

class _DesktopPendingChip extends StatelessWidget {
  const _DesktopPendingChip({required this.task, required this.enabled});
  final TaskDetails task;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final content = Chip(
      avatar: Icon(
        taskIconData(task.iconName),
        size: 16,
        color: Color(task.colorValue),
      ),
      label: Text(task.name),
      side: const BorderSide(color: AppColors.border),
      backgroundColor: Colors.white,
    );
    if (!enabled) return content;
    return LongPressDraggable<TaskDetails>(
      data: task,
      feedback: Material(color: Colors.transparent, child: content),
      childWhenDragging: Opacity(opacity: .35, child: content),
      child: content,
    );
  }
}

class _DesktopTimeline extends ConsumerWidget {
  const _DesktopTimeline({
    required this.entries,
    required this.data,
    required this.showCurrentLine,
  });

  final List<_DesktopAgendaEntry> entries;
  final _TodayData data;
  final bool showCurrentLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DragTarget<TaskDetails>(
    onWillAcceptWithDetails: (_) => data.isToday,
    onAcceptWithDetails: (details) => _scheduleTask(context, ref, details.data),
    builder: (context, candidate, _) => Column(
      children: [
        if (showCurrentLine) ...[
          _CurrentTimeLine(now: data.now),
          const SizedBox(height: 8),
        ],
        if (entries.isEmpty)
          const MascotEmptyState(
            title: '今天还没有时间安排',
            message: '把上方待安排事项拖到这里，或先配置时间。',
          )
        else
          for (var index = 0; index < entries.length; index++)
            switch (entries[index]) {
              _DesktopAgendaCourse entry => _DesktopCourseAgendaRow(
                item: entry.course,
                status: _courseStatus(entry.course, data),
                last: index == entries.length - 1,
              ),
              _DesktopAgendaTask entry => _DesktopTaskAgendaRow(
                task: entry.task,
                minute: entry.startMinute,
                isToday: data.isToday,
                last: index == entries.length - 1,
              ),
            },
        if (candidate.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.blush,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary),
            ),
            child: const Row(
              children: [
                Icon(Icons.add_alarm_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text('松开以安排到今天'),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Future<void> _scheduleTask(
    BuildContext context,
    WidgetRef ref,
    TaskDetails task,
  ) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        data.now.add(const Duration(hours: 1)),
      ),
      helpText: '安排到今天',
    );
    if (selected == null || !context.mounted) return;
    final selectedMinute = selected.hour * 60 + selected.minute;
    final minute = selectedMinute > 1409 ? 1409 : selectedMinute;
    DailyItemOverride? existing;
    for (final override in data.overrides) {
      if (override.itemId == task.id &&
          override.itemType ==
              (task.kind == TaskKind.recurring
                  ? DayItemType.recurring
                  : DayItemType.oneTime)) {
        existing = override;
      }
    }
    try {
      await ref
          .read(dayScheduleRepositoryProvider)
          .saveDailyOverride(
            DailyItemOverrideDraft(
              itemType: task.kind == TaskKind.recurring
                  ? DayItemType.recurring
                  : DayItemType.oneTime,
              itemId: task.id,
              localDate: data.date,
              action: DayOverrideAction.reschedule,
              plannedStartMinute: minute,
              plannedEndMinute: minute + 30,
            ),
            overrideId: existing?.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将${task.name}安排到${_formatMinute(minute)}')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('安排失败：$error')));
      }
    }
  }
}

enum _DesktopCourseState { upcoming, active, finished }

_DesktopCourseState _courseStatus(TodayCourseItem item, _TodayData data) {
  if (!data.isToday) {
    return data.date.isBefore(dateOnly(data.now))
        ? _DesktopCourseState.finished
        : _DesktopCourseState.upcoming;
  }
  final minute = data.now.hour * 60 + data.now.minute;
  if (minute >= item.endMinute) return _DesktopCourseState.finished;
  if (minute >= item.startMinute) return _DesktopCourseState.active;
  return _DesktopCourseState.upcoming;
}

class _DesktopCourseAgendaRow extends StatelessWidget {
  const _DesktopCourseAgendaRow({
    required this.item,
    required this.status,
    required this.last,
  });

  final TodayCourseItem item;
  final _DesktopCourseState status;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = Color(item.course.colorValue);
    final statusText = switch (status) {
      _DesktopCourseState.active => '进行中',
      _DesktopCourseState.upcoming => '即将开始',
      _DesktopCourseState.finished => '已结束',
    };
    return _DesktopTimelineRow(
      minute: item.startMinute,
      color: color,
      last: last,
      leading: Icons.school_rounded,
      title: item.course.name,
      subtitle:
          '课程 · ${_formatMinute(item.startMinute)}–${_formatMinute(item.endMinute)}${item.classroom == null ? '' : ' · ${item.classroom}'}',
      trailing: _StatusPill(label: statusText, color: color),
    );
  }
}

class _DesktopTaskAgendaRow extends ConsumerWidget {
  const _DesktopTaskAgendaRow({
    required this.task,
    required this.minute,
    required this.isToday,
    required this.last,
  });

  final TaskDetails task;
  final int minute;
  final bool isToday;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = task.hasTimer
        ? ref.watch(taskTimerStateProvider(task.id)).value
        : null;
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final running = timer?.isRunning ?? false;
    final elapsed =
        timer?.elapsedSecondsAt(now) ?? task.todayActualDurationSeconds;
    final color = Color(task.colorValue);
    return _DesktopTimelineRow(
      minute: minute,
      color: color,
      last: last,
      leading: taskIconData(task.iconName),
      title: task.name,
      subtitle: task.hasTimer
          ? '${task.kind == TaskKind.recurring ? '周期事项' : '单次事项'} · ${formatDuration(elapsed)}'
          : '${task.kind == TaskKind.recurring ? '周期事项' : '单次事项'} · ${task.isCompleted ? '已完成' : '待完成'}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (task.hasTimer && isToday)
            _InlineTimerControls(taskId: task.id, timer: timer, color: color)
          else
            _CompletionButton(task: task, enabled: isToday),
          if (running) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _DesktopTimelineRow extends StatelessWidget {
  const _DesktopTimelineRow({
    required this.minute,
    required this.color,
    required this.last,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final int minute;
  final Color color;
  final bool last;
  final IconData leading;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 62,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              _formatMinute(minute),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 18),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            if (!last)
              Expanded(
                child: Container(width: 1, color: const Color(0xFFE6E8EA)),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                _TaskIcon(color: color, icon: leading),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                trailing,
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class _DesktopTodaySummary extends ConsumerWidget {
  const _DesktopTodaySummary({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statistics = ref.watch(statisticsSnapshotProvider);
    var streak = 0;
    statistics.when(
      data: (snapshot) {
        final report = snapshot.report(
          StatisticsPeriod.day,
          data.date,
          data.now,
        );
        for (final item in report.tasks) {
          if (item.currentStreak > streak) streak = item.currentStreak;
        }
      },
      loading: () {},
      error: (_, _) {},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('今日总结', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DesktopSummaryCard(
                label: '已完成',
                value: '${data.completed} / ${data.tasks.length}',
                icon: Icons.check_circle_rounded,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DesktopSummaryCard(
                label: '专注时长',
                value: formatDuration(data.focusedSeconds),
                icon: Icons.hourglass_bottom_rounded,
                color: AppColors.purple,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DesktopSummaryCard(
                label: '待办事项',
                value: '${data.remaining}',
                icon: Icons.inbox_outlined,
                color: AppColors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DesktopSummaryCard(
                label: '连续打卡',
                value: '$streak 天',
                icon: Icons.local_fire_department_rounded,
                color: AppColors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DesktopSummaryCard extends StatelessWidget {
  const _DesktopSummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _DesktopContextPanel extends StatelessWidget {
  const _DesktopContextPanel({
    required this.data,
    required this.onDateSelected,
  });
  final _TodayData data;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DesktopMiniCalendar(
        selectedDate: data.date,
        onDateSelected: onDateSelected,
      ),
      const SizedBox(height: 16),
      _DesktopUpcomingItems(data: data),
      const SizedBox(height: 16),
      _DesktopFocusCard(data: data),
    ],
  );
}

class _CollapsedContextButton extends StatelessWidget {
  const _CollapsedContextButton({
    required this.data,
    required this.onDateSelected,
  });
  final _TodayData data;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: IconButton(
      tooltip: '打开日期与专注面板',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: _DesktopContextPanel(
              data: data,
              onDateSelected: (date) {
                Navigator.of(context).pop();
                onDateSelected(date);
              },
            ),
          ),
        ),
      ),
      icon: const Icon(Icons.calendar_view_month_rounded),
    ),
  );
}

class _DesktopMiniCalendar extends StatefulWidget {
  const _DesktopMiniCalendar({
    required this.selectedDate,
    required this.onDateSelected,
  });
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  State<_DesktopMiniCalendar> createState() => _DesktopMiniCalendarState();
}

class _DesktopMiniCalendarState extends State<_DesktopMiniCalendar> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.selectedDate.year, widget.selectedDate.month);
  }

  @override
  void didUpdateWidget(covariant _DesktopMiniCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _month = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = _month.subtract(Duration(days: _month.weekday - 1));
    final today = dateOnly(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          children: [
            Row(
              children: [
                Text('迷你日历', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: '上个月',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: '下个月',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Text(DateFormat('yyyy年M月', 'zh_CN').format(_month)),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.05,
              ),
              itemBuilder: (context, index) {
                final day = dateOnly(start.add(Duration(days: index)));
                final selected = day == dateOnly(widget.selectedDate);
                final isToday = day == today;
                final isCurrentMonth = day.month == _month.month;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.onDateSelected(day),
                  child: Center(
                    child: Container(
                      width: 29,
                      height: 29,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : isToday
                            ? AppColors.blush
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected || isToday
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: selected
                              ? Colors.white
                              : isCurrentMonth
                              ? AppColors.ink
                              : AppColors.muted.withValues(alpha: .55),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => widget.onDateSelected(DateTime.now()),
              icon: const Icon(Icons.today_rounded, size: 16),
              label: const Text('回到今天'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopUpcomingItems extends StatelessWidget {
  const _DesktopUpcomingItems({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) {
    final entries = <_DesktopAgendaEntry>[
      ...data.courses.map(_DesktopAgendaCourse.new),
      ...data.tasks
          .where((task) => _taskMinute(task, null) != null)
          .map((task) => _DesktopAgendaTask(task, _taskMinute(task, null)!)),
    ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('近期事项', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text(
                '近期还没有已安排事项。',
                style: TextStyle(color: AppColors.muted),
              )
            else
              for (final entry in entries.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: switch (entry) {
                            _DesktopAgendaCourse value => Color(
                              value.course.course.colorValue,
                            ),
                            _DesktopAgendaTask value => Color(
                              value.task.colorValue,
                            ),
                          },
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          switch (entry) {
                            _DesktopAgendaCourse value =>
                              value.course.course.name,
                            _DesktopAgendaTask value => value.task.name,
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatMinute(entry.startMinute),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
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

class _DesktopFocusCard extends ConsumerStatefulWidget {
  const _DesktopFocusCard({required this.data});
  final _TodayData data;
  @override
  ConsumerState<_DesktopFocusCard> createState() => _DesktopFocusCardState();
}

class _DesktopFocusCardState extends ConsumerState<_DesktopFocusCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final taskTimers =
        ref.watch(unfinishedTaskTimersProvider).value ?? const [];
    final adHocTimers =
        ref.watch(unfinishedAdHocTimersProvider).value ?? const [];
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final total = taskTimers.length + adHocTimers.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: total == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '专注一会儿吧',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      MascotWidget(
                        state: MascotState.working,
                        size: 42,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '从现在开始，给自己 25 分钟的专注时光。',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: widget.data.isToday && !_busy
                        ? _startFocus
                        : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('开始计时'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正在进行 · $total',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final entry in taskTimers.take(2))
                    _CompactTaskTimerLine(
                      taskId: entry.taskId,
                      now: now,
                      enabled: widget.data.isToday,
                    ),
                  for (final timer in adHocTimers.take(
                    taskTimers.length >= 2 ? 0 : 2 - taskTimers.length,
                  ))
                    _CompactAdHocTimerLine(
                      timer: timer,
                      now: now,
                      enabled: widget.data.isToday,
                    ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _showMultiTimerSheet(context),
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: Text(total == 1 ? '查看计时' : '查看全部计时'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _startFocus() async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(dayScheduleRepositoryProvider);
      final id = await repository.createAdHocTimer(title: '专注时光');
      await repository.startAdHocTimer(id);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _CompactTaskTimerLine extends ConsumerWidget {
  const _CompactTaskTimerLine({
    required this.taskId,
    required this.now,
    required this.enabled,
  });

  final String taskId;
  final DateTime now;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskDetailsProvider(taskId)).value;
    final timer = ref.watch(taskTimerStateProvider(taskId)).value;
    if (task == null || timer == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              task.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatDuration(timer.elapsedSecondsAt(now)),
            style: TextStyle(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w800,
              color: Color(task.colorValue),
            ),
          ),
          const SizedBox(width: 8),
          _InlineTimerControls(
            taskId: taskId,
            timer: timer,
            color: Color(task.colorValue),
          ),
        ],
      ),
    );
  }
}

class _CompactAdHocTimerLine extends StatelessWidget {
  const _CompactAdHocTimerLine({
    required this.timer,
    required this.now,
    required this.enabled,
  });

  final AdHocTimerDetails timer;
  final DateTime now;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            timer.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          formatDuration(timer.durationSecondsForDate(dateOnly(now), now: now)),
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w800,
            color: Color(timer.colorValue),
          ),
        ),
        const SizedBox(width: 8),
        _AdHocCompactControls(timer: timer, enabled: enabled),
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
        _TodayArrangement(
          tasks: data.tasks,
          courses: data.courses,
          now: data.isToday ? data.now : null,
        ),
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
  Widget build(BuildContext context) {
    final overrides = {
      for (final value in data.overrides)
        if (value.itemType != DayItemType.course) value.itemId: value,
    };
    final pending = data.tasks.where((task) {
      final override = overrides[task.id];
      return !task.isCompleted &&
          override?.action != DayOverrideAction.skip &&
          _taskMinute(task, override) == null;
    }).toList();

    return Stack(
      children: [
        _TodayScroll(
          horizontal: 16,
          bottom: 124,
          child: Column(
            children: [
              _MobileHeader(data: data),
              if (!data.isToday) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => onDateSelected(DateTime.now()),
                    icon: const Icon(Icons.today_rounded, size: 17),
                    label: const Text('回到今天'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _PendingTasksSection(
                date: data.date,
                tasks: pending,
                isToday: data.isToday,
              ),
              const SizedBox(height: 18),
              _ThreeDaySchedule(
                selectedDate: data.date,
                now: data.now,
                onSelected: onDateSelected,
              ),
              const SizedBox(height: 18),
              _MobileSummary(data: data),
              const SizedBox(height: 18),
              _ReviewSummary(date: data.date),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: _MobileActiveTimerPanel(data: data),
        ),
      ],
    );
  }
}

class _PendingTasksSection extends StatelessWidget {
  const _PendingTasksSection({
    required this.date,
    required this.tasks,
    required this.isToday,
  });

  final DateTime date;
  final List<TaskDetails> tasks;
  final bool isToday;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            _pendingTitle(date),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(width: 8),
          Text(
            '${tasks.length}',
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Card(
        child: tasks.isEmpty
            ? MascotEmptyState(
                title: _pendingEmptyTitle(date),
                message: dateOnly(date).isBefore(dateOnly(DateTime.now()))
                    ? '没有遗留的未完成事项。'
                    : '完成得很棒，给自己一点休息时间～',
              )
            : Column(
                children: [
                  for (var index = 0; index < tasks.length; index++) ...[
                    _PendingTaskRow(task: tasks[index], enabled: isToday),
                    if (index != tasks.length - 1)
                      const Divider(height: 1, indent: 18, endIndent: 18),
                  ],
                ],
              ),
      ),
    ],
  );
}

String _pendingTitle(DateTime date) {
  final day = dateOnly(date);
  final today = dateOnly(DateTime.now());
  if (day == today) return '今日待完成';
  if (day == today.add(const Duration(days: 1))) return '明日待完成';
  if (day.isBefore(today)) return '${day.month}月${day.day}日未完成';
  return '${day.month}月${day.day}日待完成';
}

String _pendingEmptyTitle(DateTime date) {
  final day = dateOnly(date);
  final today = dateOnly(DateTime.now());
  if (day == today) return '今天已经没有待完成事项啦';
  if (day == today.add(const Duration(days: 1))) return '明天没有待完成事项';
  if (day.isBefore(today)) return '${day.month}月${day.day}日没有未完成事项';
  return '${day.month}月${day.day}日没有待完成事项';
}

class _PendingTaskRow extends ConsumerWidget {
  const _PendingTaskRow({required this.task, required this.enabled});

  final TaskDetails task;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(task.colorValue);
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final timer = task.hasTimer
        ? ref.watch(taskTimerStateProvider(task.id)).value
        : null;
    final elapsed =
        timer?.elapsedSecondsAt(now) ?? task.todayActualDurationSeconds;
    final target = task.targetDurationSeconds ?? 0;
    final progress = target > 0
        ? (elapsed / target).clamp(0, 1).toDouble()
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      child: Column(
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.hasTimer
                          ? _pendingTimerLabel(task, elapsed)
                          : '时间未定',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!task.hasTimer)
                _CompletionButton(task: task, enabled: enabled),
            ],
          ),
          if (task.hasTimer) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                if (target > 0)
                  Expanded(
                    child: _ProgressBar(value: progress, color: color),
                  ),
                if (target > 0) const SizedBox(width: 10),
                _InlineTimerControls(
                  taskId: task.id,
                  timer: timer,
                  color: color,
                ),
                if (task.todayTargetReached || task.isCompleted) ...[
                  const SizedBox(width: 2),
                  _CompletionButton(task: task, enabled: enabled),
                ],
              ],
            ),
            if (task.todayTargetReached && !task.isCompleted) ...[
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '目标时长已达到，请确认今日完成',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

String _pendingTimerLabel(TaskDetails task, int elapsed) {
  final target = task.targetDurationSeconds;
  if (target != null && target > 0) {
    return '${formatDuration(elapsed)} / ${formatDuration(target)}';
  }
  return elapsed > 0 ? '已专注 ${formatDuration(elapsed)}' : '时间未定';
}

class _ThreeDaySchedule extends ConsumerStatefulWidget {
  const _ThreeDaySchedule({
    required this.selectedDate,
    required this.now,
    required this.onSelected,
  });

  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelected;

  @override
  ConsumerState<_ThreeDaySchedule> createState() => _ThreeDayScheduleState();
}

class _ThreeDayScheduleState extends ConsumerState<_ThreeDaySchedule> {
  static const _originPage = 10000;
  late final PageController _controller;
  late DateTime _originDate;
  late DateTime _visibleDate;

  @override
  void initState() {
    super.initState();
    _originDate = dateOnly(widget.selectedDate);
    _visibleDate = _originDate;
    _controller = PageController(
      initialPage: _originPage,
      viewportFraction: .82,
    );
  }

  @override
  void didUpdateWidget(covariant _ThreeDaySchedule oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = dateOnly(widget.selectedDate);
    if (selected == _visibleDate) return;
    _originDate = selected;
    _visibleDate = selected;
    if (_controller.hasClients) _controller.jumpToPage(_originPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('三日日程', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      SizedBox(
        height: 326,
        child: PageView.builder(
          controller: _controller,
          onPageChanged: (page) {
            final date = dateOnly(
              _originDate.add(Duration(days: page - _originPage)),
            );
            _visibleDate = date;
            widget.onSelected(date);
          },
          itemBuilder: (context, page) {
            final date = dateOnly(
              _originDate.add(Duration(days: page - _originPage)),
            );
            return AnimatedBuilder(
              animation: _controller,
              child: _MobileScheduleCard(
                date: date,
                now: widget.now,
                onTap: () {
                  if (_controller.page?.round() != page) {
                    _controller.animateToPage(
                      page,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
              ),
              builder: (context, child) {
                final currentPage = _controller.hasClients
                    ? (_controller.page ?? _originPage.toDouble())
                    : _originPage.toDouble();
                final distance = (currentPage - page).abs().clamp(0.0, 1.0);
                return Opacity(
                  opacity: 1 - distance * .34,
                  child: Transform.scale(
                    scale: 1 - distance * .07,
                    child: child,
                  ),
                );
              },
            );
          },
        ),
      ),
      const SizedBox(height: 4),
      const Center(
        child: Text(
          '左右滑动切换日期',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ),
    ],
  );
}

class _MobileScheduleCard extends ConsumerWidget {
  const _MobileScheduleCard({
    required this.date,
    required this.now,
    required this.onTap,
  });

  final DateTime date;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekday = DateFormat('EEE', 'zh_CN').format(date);
    final tasks = ref.watch(tasksForDateProvider(date));
    final courses = ref.watch(coursesSnapshotProvider);
    final overrides = ref.watch(dailyOverridesSnapshotProvider(date));
    final isToday = dateOnly(date) == dateOnly(now);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _relativeDayLabel(date),
                    style: TextStyle(
                      color: isToday ? AppColors.primary : AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${date.month}月${date.day}日 · $weekday',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _MobileScheduleContents(
                  date: date,
                  now: now,
                  tasks: tasks,
                  courses: courses,
                  overrides: overrides,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeDayLabel(DateTime date) {
  final day = dateOnly(date);
  final today = dateOnly(DateTime.now());
  if (day == today) return '今天';
  if (day == today.subtract(const Duration(days: 1))) return '昨天';
  if (day == today.add(const Duration(days: 1))) return '明天';
  return '${day.month}/${day.day}';
}

class _MobileScheduleContents extends StatelessWidget {
  const _MobileScheduleContents({
    required this.date,
    required this.now,
    required this.tasks,
    required this.courses,
    required this.overrides,
  });

  final DateTime date;
  final DateTime now;
  final AsyncValue<List<TaskDetails>> tasks;
  final AsyncValue<List<CourseDetails>> courses;
  final AsyncValue<List<DailyItemOverride>> overrides;

  @override
  Widget build(BuildContext context) {
    if (tasks.isLoading || courses.isLoading || overrides.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (tasks.hasError || courses.hasError || overrides.hasError) {
      return const Center(child: Text('日程暂时不可用'));
    }

    final taskValues = tasks.value ?? const <TaskDetails>[];
    final overrideValues = overrides.value ?? const <DailyItemOverride>[];
    final taskOverrides = {
      for (final value in overrideValues)
        if (value.itemType != DayItemType.course) value.itemId: value,
    };
    final entries = <_DesktopAgendaEntry>[
      ...buildCourseItemsForDate(
        date,
        courses.value ?? const <CourseDetails>[],
        overrideValues,
      ).map(_DesktopAgendaCourse.new),
      ...taskValues
          .where((task) {
            final override = taskOverrides[task.id];
            return override?.action != DayOverrideAction.skip &&
                _taskMinute(task, override) != null;
          })
          .map(
            (task) => _DesktopAgendaTask(
              task,
              _taskMinute(task, taskOverrides[task.id])!,
            ),
          ),
    ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    if (entries.isEmpty) {
      return const Center(
        child: MascotEmptyState(
          title: '今天还没有安排～',
          message: '有明确时间的课程和事项会显示在这里。',
        ),
      );
    }

    final showNow = dateOnly(date) == dateOnly(now);
    final nowMinute = now.hour * 60 + now.minute;
    var lineInserted = false;
    final rows = <Widget>[];
    for (final entry in entries) {
      if (showNow && !lineInserted && entry.startMinute >= nowMinute) {
        rows.add(_MobileCurrentTimeLine(now: now));
        lineInserted = true;
      }
      rows.add(_MobileScheduleRow(entry: entry));
    }
    if (showNow && !lineInserted) rows.add(_MobileCurrentTimeLine(now: now));

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) => rows[index],
    );
  }
}

class _MobileScheduleRow extends StatelessWidget {
  const _MobileScheduleRow({required this.entry});

  final _DesktopAgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final isCourse = entry is _DesktopAgendaCourse;
    final course = isCourse ? (entry as _DesktopAgendaCourse).course : null;
    final task = !isCourse ? (entry as _DesktopAgendaTask).task : null;
    final color = course != null
        ? Color(course.course.colorValue)
        : Color(task!.colorValue);
    final title = course?.course.name ?? task!.name;
    final subtitle = course != null
        ? '课程${course.classroom == null ? '' : ' · ${course.classroom}'}'
        : (task!.tagId == null ? '事项 · 未分类' : '事项 · 已设置标签');

    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              _formatMinute(entry.startMinute),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(
            isCourse ? Icons.school_outlined : Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.muted,
          ),
        ],
      ),
    );

    if (task == null) return child;
    return InkWell(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.id)),
      ),
      child: child,
    );
  }
}

class _MobileCurrentTimeLine extends StatelessWidget {
  const _MobileCurrentTimeLine({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        const Expanded(
          child: Divider(color: Color(0xFFE34B62), thickness: 1.5),
        ),
        const SizedBox(width: 6),
        const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFE34B62),
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 8, height: 8),
        ),
        const SizedBox(width: 6),
        Text(
          '${_formatMinute(now.hour * 60 + now.minute)} 现在',
          style: const TextStyle(
            color: Color(0xFFE34B62),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: Divider(color: Color(0xFFE34B62), thickness: 1.5),
        ),
      ],
    ),
  );
}

class _MobileActiveTimerPanel extends ConsumerWidget {
  const _MobileActiveTimerPanel({required this.data});

  final _TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskTimers =
        ref.watch(unfinishedTaskTimersProvider).value ?? const [];
    final adHocTimers =
        ref.watch(unfinishedAdHocTimersProvider).value ?? const [];
    final total = taskTimers.length + adHocTimers.length;
    if (total == 0) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      elevation: 7,
      color: AppColors.glassStrong,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showMultiTimerSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              const _TaskIcon(
                color: AppColors.primary,
                icon: Icons.timer_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      total == 1 ? '正在计时' : '正在计时 · $total项',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    Text(
                      total == 1
                          ? _singleTimerTitle(ref, taskTimers, adHocTimers)
                          : '点击查看全部计时',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _singleTimerTitle(
  WidgetRef ref,
  List<TimerSessionEntry> taskTimers,
  List<AdHocTimerDetails> adHocTimers,
) {
  if (taskTimers.isNotEmpty) {
    return ref
            .watch(taskDetailsProvider(taskTimers.first.taskId))
            .value
            ?.name ??
        '任务计时';
  }
  return adHocTimers.first.title;
}

Future<void> _showMultiTimerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .72,
        child: _MultiTimerSheet(),
      ),
    );

class _MultiTimerSheet extends ConsumerWidget {
  const _MultiTimerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskTimers =
        ref.watch(unfinishedTaskTimersProvider).value ?? const [];
    final adHocTimers =
        ref.watch(unfinishedAdHocTimersProvider).value ?? const [];
    final runningTasks = taskTimers
        .where((timer) => timer.status == TimerSessionStatus.running)
        .toList();
    final runningAdHoc = adHocTimers
        .where((timer) => timer.timerStatus == AdHocTimerStatus.running)
        .toList();
    final now = DateTime.now();
    final hasLongRunningTimer =
        [
          ...runningTasks.map((timer) => timer.startedAt),
          ...runningAdHoc
              .map((timer) => timer.currentStartedAt)
              .whereType<DateTime>(),
        ].any(
          (startedAt) => now.difference(startedAt) >= const Duration(hours: 12),
        );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '正在计时',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (runningTasks.isNotEmpty || runningAdHoc.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      final taskRepository = ref.read(taskRepositoryProvider);
                      final scheduleRepository = ref.read(
                        dayScheduleRepositoryProvider,
                      );
                      await Future.wait([
                        for (final timer in runningTasks)
                          taskRepository.pauseTimer(timer.taskId),
                        for (final timer in runningAdHoc)
                          scheduleRepository.pauseAdHocTimer(timer.id),
                      ]);
                    },
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                    label: const Text('全部暂停'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (hasLongRunningTimer) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('有计时已持续超过 12 小时，请确认继续或结束。'),
              ),
            ],
            Expanded(
              child: ListView(
                children: [
                  for (final timer in taskTimers)
                    _MultiTaskTimerRow(taskId: timer.taskId),
                  for (final timer in adHocTimers)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: _AdHocRow(timer: timer, enabled: true),
                    ),
                  if (taskTimers.isEmpty && adHocTimers.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 44),
                        child: Text('当前没有未结束的计时'),
                      ),
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

class _MultiTaskTimerRow extends ConsumerWidget {
  const _MultiTaskTimerRow({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskDetailsProvider(taskId)).value;
    final timer = ref.watch(taskTimerStateProvider(taskId)).value;
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    if (task == null || timer == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            _TaskIcon(
              color: Color(task.colorValue),
              icon: taskIconData(task.iconName),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    timer.isPaused
                        ? '已暂停 · ${formatDuration(timer.elapsedSecondsAt(now))}'
                        : formatDuration(timer.elapsedSecondsAt(now)),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _InlineTimerControls(
              taskId: taskId,
              timer: timer,
              color: Color(task.colorValue),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdHocCompactControls extends ConsumerStatefulWidget {
  const _AdHocCompactControls({required this.timer, required this.enabled});

  final AdHocTimerDetails timer;
  final bool enabled;

  @override
  ConsumerState<_AdHocCompactControls> createState() =>
      _AdHocCompactControlsState();
}

class _AdHocCompactControlsState extends ConsumerState<_AdHocCompactControls> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final timer = widget.timer;
    final isRunning = timer.timerStatus == AdHocTimerStatus.running;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: isRunning ? '暂停' : '继续',
          visualDensity: VisualDensity.compact,
          onPressed: !widget.enabled || _busy ? null : _toggle,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
        ),
        IconButton(
          tooltip: '结束',
          visualDensity: VisualDensity.compact,
          onPressed: !widget.enabled || _busy ? null : _end,
          icon: const Icon(Icons.stop_rounded),
        ),
      ],
    );
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(dayScheduleRepositoryProvider);
      if (widget.timer.timerStatus == AdHocTimerStatus.running) {
        await repository.pauseAdHocTimer(widget.timer.id);
      } else {
        await repository.resumeAdHocTimer(widget.timer.id);
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
              _mobileHeaderTitle(data.date),
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

String _mobileHeaderTitle(DateTime date) {
  final day = dateOnly(date);
  final today = dateOnly(DateTime.now());
  if (day == today) return '今天';
  if (day == today.subtract(const Duration(days: 1))) return '昨天';
  if (day == today.add(const Duration(days: 1))) return '明天';
  return '${day.month}月${day.day}日';
}

class _DesktopSummary extends StatelessWidget {
  const _DesktopSummary({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF9FFFFFF), Color(0xDFFFF5F8)],
        ),
      ),
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
    ),
  );
}

class _MobileSummary extends ConsumerWidget {
  const _MobileSummary({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statistics = ref.watch(statisticsSnapshotProvider);
    var streak = 0;
    statistics.when(
      data: (snapshot) {
        final report = snapshot.report(
          StatisticsPeriod.day,
          data.date,
          data.now,
        );
        for (final item in report.tasks) {
          if (item.currentStreak > streak) streak = item.currentStreak;
        }
      },
      loading: () {},
      error: (_, _) {},
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data.isToday
                        ? '今日总结'
                        : '${data.date.month}月${data.date.day}日总结',
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    data.isToday ? '今日完成度' : '当日完成度',
                    style: const TextStyle(color: AppColors.muted),
                  ),
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
                  child: _MobileMetric(
                    label: '已完成',
                    value: '${data.completed}项',
                  ),
                ),
                const _MetricDivider(short: true),
                Expanded(
                  child: _MobileMetric(
                    label: '待完成',
                    value: '${data.remaining}项',
                  ),
                ),
                const _MetricDivider(short: true),
                Expanded(
                  child: _MobileMetric(
                    label: '累计专注',
                    value: formatDuration(data.focusedSeconds),
                  ),
                ),
                const _MetricDivider(short: true),
                Expanded(
                  child: _MobileMetric(label: '连续打卡', value: '$streak天'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
      final timer = task.hasTimer
          ? ref.read(taskTimerStateProvider(task.id)).value
          : null;
      final hasUnfinishedTimer = timer?.canStart == false;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(hasUnfinishedTimer ? '该事项正在计时' : '删除任务？'),
          content: Text(
            hasUnfinishedTimer
                ? '结束计时后再归档事项。历史打卡与计时记录将保留。'
                : '任务会归档，历史打卡与计时记录将保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(hasUnfinishedTimer ? '结束计时并删除' : '删除'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await ref
            .read(taskRepositoryProvider)
            .archiveTask(task.id, endUnfinishedTimer: hasUnfinishedTimer);
      }
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
  const _TodayArrangement({
    required this.tasks,
    this.courses = const [],
    this.now,
  });
  final List<TaskDetails> tasks;
  final List<TodayCourseItem> courses;
  final DateTime? now;
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
            if (now != null) ...[
              _CurrentTimeLine(now: now!),
              const SizedBox(height: 8),
            ],
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

class _CurrentTimeLine extends StatelessWidget {
  const _CurrentTimeLine({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final time = _formatMinute(now.hour * 60 + now.minute);
    return Row(
      children: [
        Text(
          time,
          style: const TextStyle(
            color: Color(0xFFE34B62),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Divider(color: Color(0xFFE34B62), thickness: 1.4),
        ),
        const SizedBox(width: 5),
        const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFE34B62),
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 8, height: 8),
        ),
      ],
    );
  }
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
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => const FractionallySizedBox(
                            heightFactor: 0.92,
                            child: ReviewsPage(),
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
