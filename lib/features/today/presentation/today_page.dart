import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/app_time.dart';
import '../../../shared/widgets/check_d_design.dart';
import '../../../shared/widgets/mascot.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../calendar/domain/calendar_models.dart';
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
      // workspace width, while keeping a narrow desktop shell on the desktop
      // composition so its context rail can collapse instead of reverting to
      // the unrelated tablet dashboard.
      final inDesktopShell = MediaQuery.sizeOf(context).width >= 1024;
      if (inDesktopShell || constraints.maxWidth >= 850) {
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
    horizontal: 0,
    bottom: 18,
    child: _DesktopTodayWorkspace(data: data, onDateSelected: onDateSelected),
  );
}

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
  _TodayData get data => widget.data;

  @override
  Widget build(BuildContext context) {
    final rightPanel = _DesktopContextPanel(
      data: data,
      onDateSelected: widget.onDateSelected,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidePanel = constraints.maxWidth >= 980;
        final railWidth = constraints.maxWidth >= 1240 ? 350.0 : 320.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DesktopWorkspaceHeader(
                    data: data,
                    onToday: () => widget.onDateSelected(DateTime.now()),
                  ),
                  const SizedBox(height: 12),
                  _DesktopAgenda(
                    data: data,
                    onDateSelected: widget.onDateSelected,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 96,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 6,
                          child: _DesktopTodaySummary(data: data),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: _ReviewSummary(date: data.date),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showSidePanel) ...[
              const SizedBox(width: 16),
              SizedBox(width: railWidth, child: rightPanel),
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

class _DesktopWorkspaceHeader extends ConsumerWidget {
  const _DesktopWorkspaceHeader({required this.data, required this.onToday});

  final _TodayData data;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskTimers =
        ref.watch(unfinishedTaskTimersProvider).value ?? const [];
    final adHocTimers =
        ref.watch(unfinishedAdHocTimersProvider).value ?? const [];
    final sheepState = _mobileSheepState(data, taskTimers, adHocTimers);
    return Container(
      height: 142,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x96FFF3E8), Color(0x52FFFAF6), Color(0x24FFE8EE)],
          stops: [0, .58, 1],
        ),
        borderRadius: BorderRadius.all(AppRadius.feature),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 14,
            bottom: -2,
            child: CheckDSheep(
              state: sheepState,
              size: MascotSize.heroLarge,
              framed: false,
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 178, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.wb_sunny_rounded,
                        color: AppColors.creamYellow,
                        size: 28,
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          data.isToday
                              ? _greetingFor(data.now)
                              : _mobileHeaderTitle(data.date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(fontSize: 25),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    data.dateText,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.isToday ? '专注让每一天更靠近理想的自己 ♡' : data.encouragement,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!data.isToday)
            Positioned(
              right: 12,
              top: 10,
              child: TextButton.icon(
                onPressed: onToday,
                icon: const Icon(Icons.today_rounded, size: 16),
                label: const Text('回到今天'),
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopAgenda extends StatelessWidget {
  const _DesktopAgenda({required this.data, required this.onDateSelected});

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
      return !task.isCompleted && override?.action != DayOverrideAction.skip;
    }).toList();
    final timeline = <_DesktopAgendaEntry>[
      ...data.courses.map(_DesktopAgendaCourse.new),
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
        CheckDSectionTitle(
          title: data.isToday ? '今日待完成' : '${data.date.day}日待完成',
          count: pending.length,
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const TaskListPage()),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              visualDensity: VisualDensity.compact,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('全部'),
                Icon(Icons.chevron_right_rounded, size: 17),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        _DesktopPendingItems(
          tasks: pending,
          date: data.date,
          overrides: overrides,
          isToday: data.isToday,
        ),
        const SizedBox(height: 12),
        _DesktopThreeDaySchedule(
          selectedDate: data.date,
          onDateSelected: onDateSelected,
        ),
        const SizedBox(height: 12),
        CheckDSectionTitle(
          title: data.isToday
              ? '今日时间轴'
              : '${data.date.month}月${data.date.day}日时间轴',
          trailing: Text(
            data.dateText,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 7),
        CheckDSurface(
          level: CheckDSurfaceLevel.plain,
          color: const Color(0x8CFFFFFF),
          padding: const EdgeInsets.fromLTRB(15, 8, 15, 10),
          child: _DesktopTimeline(
            entries: timeline,
            data: data,
            showCurrentLine: data.isToday,
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

class _DesktopThreeDaySchedule extends StatelessWidget {
  const _DesktopThreeDaySchedule({
    required this.selectedDate,
    required this.onDateSelected,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final selected = dateOnly(selectedDate);
    final dates = [
      selected.subtract(const Duration(days: 1)),
      selected,
      selected.add(const Duration(days: 1)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckDSectionTitle(
          title: '三日日程',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '前一天',
                visualDensity: VisualDensity.compact,
                onPressed: () => onDateSelected(dates.first),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: '后一天',
                visualDensity: VisualDensity.compact,
                onPressed: () => onDateSelected(dates.last),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        AnimatedSwitcher(
          duration: AppMotion.duration(context, AppMotion.emphasis),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(.035, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: SizedBox(
            key: ValueKey(selected),
            height: 130,
            child: Row(
              children: [
                Expanded(
                  flex: 10,
                  child: _DesktopDayCard(
                    date: dates[0],
                    selected: false,
                    onTap: () => onDateSelected(dates[0]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 11,
                  child: _DesktopDayCard(
                    date: dates[1],
                    selected: true,
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 10,
                  child: _DesktopDayCard(
                    date: dates[2],
                    selected: false,
                    onTap: () => onDateSelected(dates[2]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopDayCard extends ConsumerWidget {
  const _DesktopDayCard({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksForDateProvider(date)).value ?? const [];
    final completed = tasks.where((task) => task.isCompleted).length;
    final running = tasks.where((task) => !task.isCompleted).length;
    return CheckDHoverLift(
      radius: const BorderRadius.all(AppRadius.importantCard),
      child: AnimatedScale(
        scale: selected ? 1 : .94,
        duration: AppMotion.duration(context, AppMotion.standard),
        curve: AppMotion.curve,
        child: Opacity(
          opacity: selected ? 1 : .7,
          child: CheckDSurface(
            level: selected
                ? CheckDSurfaceLevel.glassSoft
                : CheckDSurfaceLevel.raised,
            color: selected ? const Color(0xA6FFF2F5) : const Color(0xA8FFFFFF),
            borderColor: selected
                ? const Color(0x30FFFFFF)
                : const Color(0x48FFFFFF),
            child: CheckDPressable(
              onTap: onTap,
              pressedScale: .985,
              borderRadius: const BorderRadius.all(AppRadius.importantCard),
              child: Stack(
                children: [
                  if (selected)
                    Positioned(
                      right: 12,
                      bottom: -12,
                      child: CheckDSheep(
                        state: running > 0 ? SheepState.focus : SheepState.idle,
                        size: MascotSize.lg,
                        compact: true,
                        framed: false,
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      12,
                      selected ? 72 : 14,
                      10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _relativeDayLabel(date),
                          style: TextStyle(
                            color: selected
                                ? AppColors.primaryStrong
                                : AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${date.month}月${date.day}日',
                          style: TextStyle(
                            fontSize: selected ? 20 : 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          running > 0 ? '进行中 $running 项' : '完成 $completed 项',
                          style: TextStyle(
                            color: running > 0
                                ? AppColors.primaryStrong
                                : AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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

class _DesktopPendingItems extends ConsumerWidget {
  const _DesktopPendingItems({
    required this.tasks,
    required this.date,
    required this.overrides,
    required this.isToday,
  });

  final List<TaskDetails> tasks;
  final DateTime date;
  final Map<String, DailyItemOverride> overrides;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerEntries =
        ref.watch(unfinishedTaskTimersProvider).value ?? const [];
    final statusByTask = {
      for (final value in timerEntries) value.taskId: value,
    };
    final sorted = [...tasks]
      ..sort((a, b) {
        int rank(TaskDetails task) => switch (statusByTask[task.id]?.status) {
          TimerSessionStatus.running => 0,
          TimerSessionStatus.paused => 1,
          _ => 2,
        };
        return rank(a).compareTo(rank(b));
      });
    return CheckDSurface(
      level: CheckDSurfaceLevel.raised,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sorted.isEmpty)
            const SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  '今天的待完成事项已经处理好了',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 228),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: sorted.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final task = sorted[index];
                  return _DesktopPendingChip(
                    task: task,
                    enabled: isToday,
                    plannedMinute: _taskMinute(task, overrides[task.id]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopPendingChip extends ConsumerWidget {
  const _DesktopPendingChip({
    required this.task,
    required this.enabled,
    required this.plannedMinute,
  });
  final TaskDetails task;
  final bool enabled;
  final int? plannedMinute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(task.colorValue);
    final timer = task.hasTimer
        ? ref.watch(taskTimerStateProvider(task.id)).value
        : null;
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final elapsed =
        timer?.elapsedSecondsAt(now) ?? task.todayActualDurationSeconds;
    final running = timer?.isRunning ?? false;
    final paused = timer?.isPaused ?? false;
    final content = CheckDSurface(
      level: running
          ? CheckDSurfaceLevel.glassActive
          : paused
          ? CheckDSurfaceLevel.raised
          : CheckDSurfaceLevel.plain,
      radius: const BorderRadius.all(AppRadius.control),
      color: paused ? const Color(0x8CF3EEFF) : null,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.standard),
        curve: AppMotion.curve,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(taskIconData(task.iconName), size: 19, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    running || paused
                        ? '${running ? '进行中' : '已暂停'} · ${formatDuration(elapsed)}'
                        : plannedMinute == null
                        ? _desktopPendingTimerLabel(task, timer)
                        : _formatMinute(plannedMinute!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: running
                          ? AppColors.primaryStrong
                          : paused
                          ? AppColors.purple
                          : AppColors.muted,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: running || paused
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            if (running || paused)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CheckDSheep(
                  state: running ? SheepState.focus : SheepState.paused,
                  size: MascotSize.sm,
                  compact: true,
                  framed: false,
                ),
              ),
            if (enabled)
              task.hasTimer
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _InlineTimerControls(
                          taskId: task.id,
                          timer: timer,
                          color: AppColors.primaryStrong,
                        ),
                        const SizedBox(width: 2),
                        _CompletionButton(
                          task: task,
                          enabled: true,
                          dimension: 34,
                        ),
                      ],
                    )
                  : _CompletionButton(task: task, enabled: true),
          ],
        ),
      ),
    );
    if (!enabled) return content;
    final hoverContent = CheckDHoverLift(
      radius: const BorderRadius.all(AppRadius.control),
      child: content,
    );
    return LongPressDraggable<TaskDetails>(
      data: task,
      feedback: Material(color: Colors.transparent, child: content),
      childWhenDragging: Opacity(opacity: .35, child: content),
      child: hoverContent,
    );
  }
}

String _desktopPendingTimerLabel(TaskDetails task, TaskTimerState? timer) {
  if (timer?.isRunning ?? false) return '进行中';
  if (timer?.isPaused ?? false) return '已暂停';
  final target = task.targetDurationSeconds;
  return target != null && target > 0
      ? '目标 ${formatDuration(target)}'
      : '记录专注时长';
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
    builder: (context, candidate, _) {
      final timeline = <Widget>[];
      var currentInserted = !showCurrentLine;
      final nowMinute = data.now.hour * 60 + data.now.minute;

      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        if (!currentInserted && nowMinute <= entry.startMinute) {
          timeline.add(_CurrentTimeLine(now: data.now));
          currentInserted = true;
        }
        timeline.add(switch (entry) {
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
        });
      }
      if (!currentInserted) {
        timeline.add(_CurrentTimeLine(now: data.now));
      }
      return Column(
        children: [
          if (entries.isEmpty)
            const SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  '今天还没有明确时间的安排',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            )
          else
            ...timeline,
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
      );
    },
  );

  Future<void> _scheduleTask(
    BuildContext context,
    WidgetRef ref,
    TaskDetails task,
  ) async {
    final selected = await showAppTimePicker(
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
      highlighted: status == _DesktopCourseState.active,
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
    final paused = timer?.isPaused ?? false;
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _InlineTimerControls(
                  taskId: task.id,
                  timer: timer,
                  color: color,
                ),
                const SizedBox(width: 2),
                _CompletionButton(task: task, enabled: true, dimension: 34),
              ],
            )
          else
            _CompletionButton(task: task, enabled: isToday),
          if (running) const SizedBox(width: 4),
        ],
      ),
      highlighted: running || paused,
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
    this.highlighted = false,
  });

  final int minute;
  final Color color;
  final bool last;
  final IconData leading;
  final String title;
  final String subtitle;
  final Widget trailing;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: AppMotion.duration(context, AppMotion.standard),
    curve: AppMotion.curve,
    decoration: BoxDecoration(
      color: highlighted ? const Color(0x66FFE8EF) : Colors.transparent,
      borderRadius: const BorderRadius.all(AppRadius.control),
    ),
    child: IntrinsicHeight(
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
              padding: const EdgeInsets.symmetric(vertical: 7),
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
    return CheckDSurface(
      level: CheckDSurfaceLevel.raised,
      child: SizedBox(
        height: 96,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.isToday ? '今日总结' : '${data.date.day}日总结',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: _DesktopSummaryMetric(
                      label: '已完成',
                      value: '${data.completed}',
                      icon: Icons.check_rounded,
                      color: AppColors.green,
                    ),
                  ),
                  Expanded(
                    child: _DesktopSummaryMetric(
                      label: '专注时长',
                      value: formatDuration(data.focusedSeconds),
                      icon: Icons.hourglass_bottom_rounded,
                      color: AppColors.purple,
                    ),
                  ),
                  Expanded(
                    child: _DesktopSummaryMetric(
                      label: '待完成',
                      value: '${data.remaining}',
                      icon: Icons.folder_outlined,
                      color: AppColors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSummaryMetric extends StatelessWidget {
  const _DesktopSummaryMetric({
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
  Widget build(BuildContext context) => Row(
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 28,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
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
      SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: CheckDPressable(
                pressedScale: .985,
                borderRadius: const BorderRadius.all(AppRadius.chip),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const TaskListPage()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: const BoxDecoration(
                    color: Color(0xAAFFFFFF),
                    borderRadius: BorderRadius.all(AppRadius.chip),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 17,
                        color: AppColors.muted,
                      ),
                      SizedBox(width: 7),
                      Text(
                        '查看课程、事项...',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _DesktopMiniCalendar(
        selectedDate: data.date,
        onDateSelected: onDateSelected,
      ),
      const SizedBox(height: 12),
      _DesktopFocusCard(data: data),
      const SizedBox(height: 12),
      _DesktopUpcomingItems(data: data),
      const SizedBox(height: 12),
      const _DesktopMotivationCard(),
    ],
  );
}

class _DesktopMotivationCard extends StatelessWidget {
  const _DesktopMotivationCard();

  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.glassSoft,
    color: const Color(0xCFFFF5EF),
    child: SizedBox(
      height: 132,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 17, 16, 14),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            '每一个专注的日子\n都在靠近更好的自己 ♡',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF855B63),
              height: 1.55,
            ),
          ),
        ),
      ),
    ),
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
    return CheckDSurface(
      level: CheckDSurfaceLevel.raised,
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
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
          const SizedBox(height: 6),
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
          const SizedBox(height: 3),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.15,
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
          const SizedBox(height: 3),
          TextButton.icon(
            onPressed: () => widget.onDateSelected(DateTime.now()),
            icon: const Icon(Icons.today_rounded, size: 16),
            label: const Text('回到今天'),
          ),
        ],
      ),
    );
  }
}

class _DesktopUpcomingItems extends ConsumerWidget {
  const _DesktopUpcomingItems({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courseValues = ref.watch(coursesSnapshotProvider).value ?? const [];
    final upcoming =
        <({DateTime date, int minute, String title, Color color})>[];
    for (var offset = 1; offset <= 5; offset++) {
      final day = dateOnly(data.date.add(Duration(days: offset)));
      final tasks = ref.watch(tasksForDateProvider(day)).value ?? const [];
      final overrides =
          ref.watch(dailyOverridesSnapshotProvider(day)).value ?? const [];
      final overrideMap = {
        for (final value in overrides)
          if (value.itemType != DayItemType.course) value.itemId: value,
      };
      for (final course in buildCourseItemsForDate(
        day,
        courseValues,
        overrides,
      )) {
        upcoming.add((
          date: day,
          minute: course.startMinute,
          title: course.course.name,
          color: Color(course.course.colorValue),
        ));
      }
      for (final task in tasks) {
        if (task.isCompleted ||
            overrideMap[task.id]?.action == DayOverrideAction.skip) {
          continue;
        }
        final minute = _taskMinute(task, overrideMap[task.id]);
        if (minute == null) continue;
        upcoming.add((
          date: day,
          minute: minute,
          title: task.name,
          color: Color(task.colorValue),
        ));
      }
    }
    upcoming.sort((a, b) {
      final day = a.date.compareTo(b.date);
      return day != 0 ? day : a.minute.compareTo(b.minute);
    });
    return CheckDSurface(
      level: CheckDSurfaceLevel.raised,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '近期事项',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Text(
                '更多',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 17,
              ),
            ],
          ),
          const SizedBox(height: 5),
          if (upcoming.isEmpty)
            const SizedBox(
              height: 34,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '近期还没有已安排事项。',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
            )
          else
            for (final entry in upcoming.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: entry.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 58,
                      child: Text(
                        '${entry.date.month}月${entry.date.day}日',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
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
    final minute = now.hour * 60 + now.minute;
    final currentCourses = widget.data.isToday
        ? widget.data.courses
              .where(
                (course) =>
                    minute >= course.startMinute && minute < course.endMinute,
              )
              .toList()
        : const <TodayCourseItem>[];
    final total =
        currentCourses.length + taskTimers.length + adHocTimers.length;
    return CheckDSurface(
      level: total > 0
          ? CheckDSurfaceLevel.glassActive
          : CheckDSurfaceLevel.raised,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '正在进行${total > 1 ? ' · $total' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (total > 0)
                CheckDSheep(
                  state: currentCourses.isNotEmpty
                      ? (currentCourses.first.courseTiming
                                    ?.phaseAt(minute)
                                    .kind ==
                                CourseOccurrencePhaseKind.breakTime
                            ? SheepState.breakTime
                            : SheepState.course)
                      : SheepState.focus,
                  size: MascotSize.sm,
                  compact: true,
                  framed: false,
                ),
            ],
          ),
          if (total == 0) ...[
            const SizedBox(height: 4),
            const Text(
              '当前没有进行中的课程或计时事项',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.data.isToday && !_busy ? _startFocus : null,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.primaryStrong,
              ),
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('开始计时'),
            ),
          ] else ...[
            for (final course in currentCourses)
              _DesktopCurrentCourseLine(course: course, now: now),
            for (final entry in taskTimers)
              _CompactTaskTimerLine(
                taskId: entry.taskId,
                now: now,
                enabled: widget.data.isToday,
              ),
            for (final timer in adHocTimers)
              _CompactAdHocTimerLine(
                timer: timer,
                now: now,
                enabled: widget.data.isToday,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showMultiTimerSheet(context),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.timer_outlined, size: 16),
                label: Text(
                  taskTimers.length + adHocTimers.length <= 1
                      ? '查看计时'
                      : '查看全部计时',
                ),
              ),
            ),
          ],
        ],
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

class _DesktopCurrentCourseLine extends StatelessWidget {
  const _DesktopCurrentCourseLine({required this.course, required this.now});

  final TodayCourseItem course;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final minute = now.hour * 60 + now.minute;
    final phase = course.courseTiming?.phaseAt(minute);
    final inBreak = phase?.kind == CourseOccurrencePhaseKind.breakTime;
    final span = (course.endMinute - course.startMinute).clamp(1, 1440);
    final progress = ((minute - course.startMinute) / span).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                inBreak ? Icons.coffee_rounded : Icons.menu_book_rounded,
                size: 18,
                color: inBreak ? AppColors.orange : AppColors.accentBlue,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  course.course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                inBreak ? '课间休息' : '上课中',
                style: TextStyle(
                  color: inBreak ? AppColors.orange : AppColors.primaryStrong,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 25,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const sheepSize = 25.0;
                final left = (constraints.maxWidth - sheepSize) * progress;
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: progress,
                        backgroundColor: AppColors.blush,
                        valueColor: AlwaysStoppedAnimation(
                          inBreak ? AppColors.orange : AppColors.primary,
                        ),
                      ),
                    ),
                    Positioned(
                      left: left,
                      child: CheckDSheep(
                        state: inBreak
                            ? SheepState.breakTime
                            : SheepState.course,
                        size: sheepSize,
                        compact: true,
                        framed: false,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${_formatMinute(course.startMinute)}–${_formatMinute(course.endMinute)}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
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
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final floatingLayerGap = CheckDLayout.mobileFloatingLayerGap;
    final bottomNavigationExtent = CheckDLayout.mobileBottomNavigationExtent(
      context,
    );
    final overrides = {
      for (final value in data.overrides)
        if (value.itemType != DayItemType.course) value.itemId: value,
    };
    final pending = data.tasks.where((task) {
      final override = overrides[task.id];
      return _isMobilePendingTask(task, override);
    }).toList();

    return Stack(
      children: [
        _TodayScroll(
          horizontal: 16,
          bottom: bottomNavigationExtent + floatingLayerGap,
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
              const SizedBox(height: 18),
              _PendingTasksSection(
                date: data.date,
                tasks: pending,
                isToday: data.isToday,
              ),
              const SizedBox(height: 20),
              _ThreeDaySchedule(
                selectedDate: data.date,
                now: data.now,
                onSelected: onDateSelected,
              ),
              const SizedBox(height: 20),
              _MobileSummary(data: data),
              const SizedBox(height: 14),
              _ReviewSummary(date: data.date),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: safeBottom + floatingLayerGap,
          child: _MobileActiveTimerPanel(data: data),
        ),
      ],
    );
  }
}

bool _isMobilePendingTask(TaskDetails task, DailyItemOverride? override) {
  if (task.isCompleted || override?.action == DayOverrideAction.skip) {
    return false;
  }

  // One-off items are projected by their exact planned time, never by their
  // execution mode. A timer can be running or paused while the item remains
  // a pending, untimed item in Today.
  if (task.kind == TaskKind.oneTime) {
    return task.scheduledAt == null && override?.plannedStartMinute == null;
  }
  return _taskMinute(task, override) == null;
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
      CheckDSectionTitle(
        title: _pendingTitle(date),
        count: tasks.length,
        trailing: TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push<void>(MaterialPageRoute(builder: (_) => const TaskListPage())),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.muted,
            visualDensity: VisualDensity.compact,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('全部', style: TextStyle(fontSize: 12)),
              Icon(Icons.chevron_right_rounded, size: 17),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      CheckDSurface(
        level: CheckDSurfaceLevel.raised,
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
    final status = timer?.latest?.status;
    final active = status == TimerSessionStatus.running;
    final paused = status == TimerSessionStatus.paused;
    final stateKey = active
        ? 'running'
        : paused
        ? 'paused'
        : 'idle';
    return CheckDSurface(
      level: active
          ? CheckDSurfaceLevel.glassActive
          : paused
          ? CheckDSurfaceLevel.raised
          : CheckDSurfaceLevel.plain,
      radius: const BorderRadius.all(AppRadius.control),
      color: paused ? const Color(0x78F3EEFF) : null,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.standard),
        curve: AppMotion.curve,
        padding: EdgeInsets.fromLTRB(14, active || paused ? 13 : 10, 10, 10),
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
                      AnimatedSwitcher(
                        duration: AppMotion.duration(
                          context,
                          AppMotion.standard,
                        ),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            alignment: Alignment.topCenter,
                            child: child,
                          ),
                        ),
                        child: Row(
                          key: ValueKey(stateKey),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (active || paused) ...[
                              CheckDStatusDot(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.purple,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                task.hasTimer
                                    ? _pendingTimerLabel(task, elapsed, status)
                                    : '时间未定',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: active
                                      ? AppColors.primaryStrong
                                      : paused
                                      ? AppColors.purple
                                      : AppColors.muted,
                                  fontWeight: active || paused
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: AppMotion.duration(context, AppMotion.emphasis),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: active || paused
                      ? CheckDSheep(
                          key: ValueKey('pending-sheep-$stateKey'),
                          state: active ? SheepState.focus : SheepState.paused,
                          size: MascotSize.md,
                          compact: true,
                          framed: false,
                        )
                      : const SizedBox.shrink(key: ValueKey('no-sheep')),
                ),
                if (!task.hasTimer)
                  _CompletionButton(
                    task: task,
                    enabled: enabled,
                    dimension: 34,
                  ),
              ],
            ),
            if (task.hasTimer) ...[
              SizedBox(height: active || paused ? 8 : 6),
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
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 2),
                  _CompletionButton(
                    task: task,
                    enabled: enabled,
                    dimension: 34,
                  ),
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
      ),
    );
  }
}

String _pendingTimerLabel(
  TaskDetails task,
  int elapsed,
  TimerSessionStatus? status,
) {
  final target = task.targetDurationSeconds;
  final prefix = switch (status) {
    TimerSessionStatus.running => '进行中 · ',
    TimerSessionStatus.paused => '已暂停 · ',
    _ => '',
  };
  if (target != null && target > 0) {
    return '$prefix${formatDuration(elapsed)} / ${formatDuration(target)}';
  }
  if (status == TimerSessionStatus.running ||
      status == TimerSessionStatus.paused) {
    return '$prefix${formatDuration(elapsed)}';
  }
  return elapsed > 0 ? '$prefix已专注 ${formatDuration(elapsed)}' : '时间未定';
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

  @override
  void initState() {
    super.initState();
    _originDate = dateOnly(widget.selectedDate);
    _controller = PageController(
      initialPage: _originPage,
      viewportFraction: .34,
    );
  }

  @override
  void didUpdateWidget(covariant _ThreeDaySchedule oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = dateOnly(widget.selectedDate);
    final expectedPage = _originPage + selected.difference(_originDate).inDays;
    if (_controller.hasClients && _controller.page?.round() != expectedPage) {
      _originDate = selected;
      _controller.jumpToPage(_originPage);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = dateOnly(widget.selectedDate);
    final tasks = ref.watch(tasksForDateProvider(selected)).value ?? const [];
    final courses = ref.watch(coursesSnapshotProvider).value ?? const [];
    final overrides =
        ref.watch(dailyOverridesSnapshotProvider(selected)).value ?? const [];
    final taskOverrides = {
      for (final value in overrides)
        if (value.itemType != DayItemType.course) value.itemId: value,
    };
    final scheduledTaskCount = tasks.where((task) {
      final override = taskOverrides[task.id];
      return override?.action != DayOverrideAction.skip &&
          _taskMinute(task, override) != null;
    }).length;
    final courseCount = buildCourseItemsForDate(
      selected,
      courses,
      overrides,
    ).length;
    final entryCount = scheduledTaskCount + courseCount;
    final timelineHeight = entryCount == 0
        ? 112.0
        : (70.0 + entryCount.clamp(1, 5) * 48).clamp(118.0, 310.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CheckDSectionTitle(title: '三日日程'),
        const SizedBox(height: 9),
        SizedBox(
          height: 150,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => PageView.builder(
              controller: _controller,
              padEnds: true,
              onPageChanged: (page) {
                final date = _originDate.add(
                  Duration(days: page - _originPage),
                );
                widget.onSelected(dateOnly(date));
              },
              itemBuilder: (context, page) {
                final currentPage = _controller.hasClients
                    ? (_controller.page ?? _originPage.toDouble())
                    : _originPage.toDouble();
                final emphasis = (1 - (currentPage - page).abs()).clamp(
                  0.0,
                  1.0,
                );
                final date = _originDate.add(
                  Duration(days: page - _originPage),
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _ThreeDayCard(
                    date: date,
                    emphasis: emphasis,
                    onTap: () => _controller.animateToPage(
                      page,
                      duration: AppMotion.duration(context, AppMotion.emphasis),
                      curve: Curves.easeInOutCubic,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedContainer(
          height: timelineHeight,
          duration: AppMotion.duration(context, AppMotion.standard),
          curve: AppMotion.curve,
          child: _MobileScheduleCard(
            date: selected,
            now: widget.now,
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _ThreeDayCard extends ConsumerWidget {
  const _ThreeDayCard({
    required this.date,
    required this.emphasis,
    required this.onTap,
  });

  final DateTime date;
  final double emphasis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksForDateProvider(date));
    final values = tasks.value ?? const <TaskDetails>[];
    final completed = values.where((task) => task.isCompleted).length;
    final remaining = values.length - completed;
    final selected = emphasis > .72;
    final scale = .9 + emphasis * .1;
    final opacity = .58 + emphasis * .42;
    return Semantics(
      button: true,
      selected: selected,
      label: '${date.month}月${date.day}日',
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: CheckDSurface(
            level: selected
                ? CheckDSurfaceLevel.glassSoft
                : CheckDSurfaceLevel.raised,
            color: selected ? const Color(0xA6FFF2F5) : const Color(0xA8FFFFFF),
            borderColor: selected
                ? const Color(0x30FFFFFF)
                : const Color(0x48FFFFFF),
            radius: const BorderRadius.all(AppRadius.importantCard),
            child: CheckDPressable(
              borderRadius: const BorderRadius.all(AppRadius.importantCard),
              onTap: onTap,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(7, 13, 7, 10),
                    child: Column(
                      children: [
                        Text(
                          _relativeDayLabel(date),
                          style: TextStyle(
                            color: selected
                                ? AppColors.primaryStrong
                                : AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${date.month}月${date.day}日',
                          style: TextStyle(
                            color: selected ? AppColors.ink : AppColors.muted,
                            fontSize: selected ? 18 : 16,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          values.isEmpty
                              ? '暂无事项'
                              : selected && remaining > 0
                              ? '进行中 $remaining 项'
                              : '完成 $completed 项',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? AppColors.primaryStrong
                                : AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: selected ? 12 : 8,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: selected ? .68 : .18,
                        child: CheckDSheep(
                          state: SheepState.idle,
                          size: selected
                              ? MascotSize.lg
                              : MascotSize.compactLarge,
                          compact: true,
                          framed: false,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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

    return CheckDSurface(
      level: CheckDSurfaceLevel.plain,
      radius: const BorderRadius.all(AppRadius.importantCard),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 13, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  isToday ? '今日时间轴' : '${date.month}月${date.day}日时间轴',
                  style: TextStyle(
                    color: isToday ? AppColors.primary : AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${date.month}月${date.day}日 · $weekday',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
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
        child: Text(
          '今天还没有明确时间的安排',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
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
      rows.add(_MobileScheduleRow(entry: entry, date: date, now: now));
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

class _MobileScheduleRow extends ConsumerWidget {
  const _MobileScheduleRow({
    required this.entry,
    required this.date,
    required this.now,
  });

  final _DesktopAgendaEntry entry;
  final DateTime date;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCourse = entry is _DesktopAgendaCourse;
    final course = isCourse ? (entry as _DesktopAgendaCourse).course : null;
    final task = !isCourse ? (entry as _DesktopAgendaTask).task : null;
    final color = course != null
        ? Color(course.course.colorValue)
        : Color(task!.colorValue);
    final title = course?.course.name ?? task!.name;
    final currentMinute = now.hour * 60 + now.minute;
    final isCurrentCourse =
        course != null &&
        dateOnly(date) == dateOnly(now) &&
        currentMinute >= entry.startMinute &&
        currentMinute < course.endMinute;
    final coursePhase = isCurrentCourse
        ? course.courseTiming?.phaseAt(currentMinute).kind
        : null;
    final courseStatus = coursePhase == CourseOccurrencePhaseKind.breakTime
        ? '课间休息'
        : isCurrentCourse
        ? '上课中'
        : '课程';
    final subtitle = course != null
        ? '$courseStatus${course.classroom == null ? '' : ' · ${course.classroom}'}'
        : (task!.tagId == null ? '事项 · 未分类' : '事项 · 已设置标签');
    final timer = task?.hasTimer == true
        ? ref.watch(taskTimerStateProvider(task!.id)).value
        : null;
    final taskRunning = timer?.isRunning ?? false;
    final taskPaused = timer?.isPaused ?? false;
    final taskElapsed = task == null
        ? 0
        : timer?.elapsedSecondsAt(now) ?? task.todayActualDurationSeconds;
    final highlighted = isCurrentCourse || taskRunning || taskPaused;
    final courseProgress =
        course == null || course.endMinute <= entry.startMinute
        ? 0.0
        : ((currentMinute - entry.startMinute) /
                  (course.endMinute - entry.startMinute))
              .clamp(0.0, 1.0);

    final content = AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.standard),
      curve: AppMotion.curve,
      padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
      decoration: BoxDecoration(
        gradient: highlighted
            ? const LinearGradient(
                colors: [Color(0x64FFF0F4), Color(0x30FFFFFF)],
              )
            : null,
        borderRadius: const BorderRadius.all(AppRadius.control),
        boxShadow: highlighted
            ? const [
                BoxShadow(
                  color: Color(0x0C754A55),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCourse
                      ? Icons.menu_book_outlined
                      : taskIconData(task!.iconName),
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (task != null)
                _CompletionButton(
                  task: task,
                  enabled: dateOnly(date) == dateOnly(now),
                  dimension: 34,
                ),
              AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.standard),
                child: Text(
                  key: ValueKey(
                    isCurrentCourse
                        ? courseStatus
                        : taskRunning
                        ? 'running'
                        : taskPaused
                        ? 'paused'
                        : subtitle,
                  ),
                  isCurrentCourse
                      ? courseStatus
                      : taskRunning
                      ? '进行中 ${formatDuration(taskElapsed)}'
                      : taskPaused
                      ? '已暂停 ${formatDuration(taskElapsed)}'
                      : subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: highlighted
                        ? AppColors.primaryStrong
                        : AppColors.muted,
                    fontSize: 10,
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          if (isCurrentCourse) ...[
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(left: 37, right: 2),
              child: _ProgressBar(
                value: courseProgress,
                color: coursePhase == CourseOccurrencePhaseKind.breakTime
                    ? AppColors.orange
                    : AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );

    final row = SizedBox(
      height: isCurrentCourse
          ? 56
          : task != null
          ? 50
          : 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 47,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _formatMinute(entry.startMinute),
                style: TextStyle(
                  color: highlighted ? AppColors.current : AppColors.muted,
                  fontSize: 12,
                  fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 18,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: AppColors.border),
                ),
                Positioned(
                  top: 14,
                  child: Container(
                    width: highlighted ? 10 : 8,
                    height: highlighted ? 10 : 8,
                    decoration: BoxDecoration(
                      color: highlighted ? AppColors.primary : color,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Expanded(child: content),
        ],
      ),
    );

    if (task == null) return row;
    return CheckDPressable(
      borderRadius: const BorderRadius.all(AppRadius.control),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.id)),
      ),
      child: row,
    );
  }
}

class _MobileCurrentTimeLine extends StatelessWidget {
  const _MobileCurrentTimeLine({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 47,
          child: Text(
            _formatMinute(now.hour * 60 + now.minute),
            style: const TextStyle(
              color: AppColors.current,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFE34B62),
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 8, height: 8),
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
    if (total == 0) {
      return const AnimatedSwitcher(
        duration: AppMotion.standard,
        child: SizedBox.shrink(key: ValueKey('no-mobile-timer')),
      );
    }
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final runningCount =
        taskTimers
            .where((timer) => timer.status == TimerSessionStatus.running)
            .length +
        adHocTimers
            .where((timer) => timer.timerStatus == AdHocTimerStatus.running)
            .length;
    final paused = runningCount == 0;
    final elapsed = taskTimers.isNotEmpty
        ? taskTimers.first.elapsedSecondsAt(now)
        : adHocTimers.first.durationSecondsForDate(now, now: now);
    final panel = CheckDSurface(
      key: ValueKey('mobile-timer-$total-$paused'),
      level: CheckDSurfaceLevel.glassFloating,
      radius: const BorderRadius.all(AppRadius.feature),
      child: CheckDPressable(
        borderRadius: const BorderRadius.all(AppRadius.feature),
        onTap: () => _showMultiTimerSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              CheckDSheep(
                state: paused ? SheepState.paused : SheepState.focus,
                size: MascotSize.sm,
                compact: true,
                framed: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paused
                          ? '计时已暂停'
                          : total == 1
                          ? '专注进行中'
                          : '$runningCount 项进行中 · $total 项计时',
                      style: TextStyle(
                        fontSize: 12,
                        color: paused
                            ? AppColors.purple
                            : AppColors.primaryStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            total == 1
                                ? _singleTimerTitle(
                                    ref,
                                    taskTimers,
                                    adHocTimers,
                                  )
                                : '点击查看全部计时',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (total == 1)
                          Text(
                            formatDuration(elapsed),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
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
    return AnimatedSwitcher(
      duration: AppMotion.duration(context, AppMotion.emphasis),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, .24),
          end: Offset.zero,
        ).animate(animation);
        final scale = Tween<double>(begin: .96, end: 1).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
      child: panel,
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

class _MobileHeader extends ConsumerWidget {
  const _MobileHeader({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskTimers =
        ref.watch(unfinishedTaskTimersProvider).value ?? const [];
    final adHocTimers =
        ref.watch(unfinishedAdHocTimersProvider).value ?? const [];
    final state = _mobileSheepState(data, taskTimers, adHocTimers);
    return Container(
      height: 132,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x96FFF3E8), Color(0x4CFFFAF6), Color(0x20FFE8EE)],
          stops: [0, .58, 1],
        ),
        borderRadius: BorderRadius.all(AppRadius.feature),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -4,
            bottom: -4,
            child: CheckDSheep(
              state: state,
              size: MascotSize.hero,
              framed: false,
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 15, 112, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.wb_sunny_rounded,
                        color: AppColors.creamYellow,
                        size: 25,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          data.isToday
                              ? _greetingFor(data.now)
                              : _mobileHeaderTitle(data.date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    data.dateText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.encouragement,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
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

String _greetingFor(DateTime now) => switch (now.hour) {
  < 6 => '夜深了',
  < 11 => 'Good Morning !',
  < 14 => '中午好！',
  < 18 => 'Good Afternoon !',
  _ => 'Good Evening !',
};

SheepState _mobileSheepState(
  _TodayData data,
  List<TimerSessionEntry> taskTimers,
  List<AdHocTimerDetails> adHocTimers,
) {
  var hasCurrentCourse = false;
  var isCourseBreak = false;
  if (data.isToday) {
    final minute = data.now.hour * 60 + data.now.minute;
    for (final course in data.courses) {
      if (minute < course.startMinute || minute >= course.endMinute) continue;
      final phase = course.courseTiming?.phaseAt(minute).kind;
      hasCurrentCourse = true;
      isCourseBreak = phase == CourseOccurrencePhaseKind.breakTime;
      break;
    }
  }
  final running =
      taskTimers.any((timer) => timer.status == TimerSessionStatus.running) ||
      adHocTimers.any((timer) => timer.timerStatus == AdHocTimerStatus.running);
  return resolveCheckDSheepState(
    hasCurrentCourse: hasCurrentCourse,
    isCourseBreak: isCourseBreak,
    hasRunningTimer: running,
    hasPausedTimer: taskTimers.isNotEmpty || adHocTimers.isNotEmpty,
    allTasksComplete: data.tasks.isNotEmpty && data.remaining == 0,
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

class _MobileSummary extends StatelessWidget {
  const _MobileSummary({required this.data});
  final _TodayData data;

  @override
  Widget build(BuildContext context) {
    return CheckDSurface(
      level: CheckDSurfaceLevel.raised,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 12, 13),
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
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MobileMetric(
                    icon: Icons.check_circle_rounded,
                    color: AppColors.green,
                    label: '已完成',
                    value: '${data.completed}',
                  ),
                ),
                const _MetricDivider(short: true),
                Expanded(
                  child: _MobileMetric(
                    icon: Icons.hourglass_bottom_rounded,
                    color: AppColors.purple,
                    label: '专注时长',
                    value: formatDuration(data.focusedSeconds),
                  ),
                ),
                const _MetricDivider(short: true),
                Expanded(
                  child: _MobileMetric(
                    icon: Icons.folder_outlined,
                    color: AppColors.orange,
                    label: '待完成',
                    value: '${data.remaining}',
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

class _CompletionButton extends ConsumerStatefulWidget {
  const _CompletionButton({
    required this.task,
    required this.enabled,
    this.dimension = 42,
  });
  final TaskDetails task;
  final bool enabled;
  final double dimension;

  @override
  ConsumerState<_CompletionButton> createState() => _CompletionButtonState();
}

class _CompletionButtonState extends ConsumerState<_CompletionButton> {
  bool _celebrating = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Tooltip(
      message: task.isCompleted ? '撤销完成' : '标记完成',
      child: SizedBox.square(
        dimension: widget.dimension,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            CheckDPressable(
              onTap: widget.enabled ? _toggle : null,
              pressedScale: .9,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: EdgeInsets.all(widget.dimension * .19),
                child: AnimatedSwitcher(
                  duration: AppMotion.duration(
                    context,
                    const Duration(milliseconds: 420),
                  ),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    task.isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    key: ValueKey(task.isCompleted),
                    color: task.isCompleted
                        ? Color(task.colorValue)
                        : AppColors.muted,
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _celebrating ? 1 : 0,
                duration: AppMotion.duration(
                  context,
                  const Duration(milliseconds: 180),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 38,
                  color: AppColors.creamYellow,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    final completing = !widget.task.isCompleted;
    if (completing) setState(() => _celebrating = true);
    try {
      final repository = ref.read(taskRepositoryProvider);
      if (widget.task.kind == TaskKind.recurring) {
        await repository.toggleRecurringCompletion(
          widget.task.id,
          DateTime.now(),
        );
      } else {
        await repository.toggleOneTimeCompletion(widget.task.id);
      }
      if (completing) {
        await Future<void>.delayed(const Duration(milliseconds: 560));
      }
    } finally {
      if (mounted && _celebrating) setState(() => _celebrating = false);
    }
  }
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
    final timer = widget.timer;
    final stateKey = _busy
        ? 'busy'
        : timer?.isRunning == true
        ? 'running'
        : timer?.isPaused == true
        ? 'paused'
        : 'idle';
    if (_busy) {
      return AnimatedSwitcher(
        duration: AppMotion.duration(context, AppMotion.standard),
        child: const SizedBox(
          key: ValueKey('busy'),
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.duration(context, AppMotion.standard),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Wrap(
        key: ValueKey(stateKey),
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
      ),
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
    return CheckDSurface(
      level: CheckDSurfaceLevel.raised,
      color: const Color(0xC8FFF3EC),
      borderColor: const Color(0x48FFFFFF),
      child: review.when(
        loading: () => const SizedBox(
          height: 88,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const Text('复盘加载失败'),
        data: (entry) {
          final content = entry?.learnedText ?? entry?.happenedText;
          final empty = content == null || content.trim().isEmpty;
          return CheckDPressable(
            borderRadius: const BorderRadius.all(AppRadius.card),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => const FractionallySizedBox(
                heightFactor: 0.92,
                child: ReviewsPage(),
              ),
            ),
            child: SizedBox(
              height: 96,
              child: Stack(
                children: [
                  Positioned(
                    right: 34,
                    bottom: -10,
                    child: CheckDSheep(
                      state: empty ? SheepState.idle : SheepState.complete,
                      size: MascotSize.card,
                      compact: true,
                      framed: false,
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(17, 14, 112, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '今日复盘',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            empty ? '记录今天的成长，遇见更好的自己' : content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: empty ? AppColors.muted : AppColors.ink,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 12,
                    top: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
  const _MobileMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 17),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}
