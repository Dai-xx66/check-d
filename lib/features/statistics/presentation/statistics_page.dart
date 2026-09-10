import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/check_d_design.dart';
import '../../../shared/widgets/mascot.dart';
import '../../tags/presentation/tags_page.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/task_detail_page.dart';
import '../../tasks/presentation/task_icon_picker.dart';
import '../application/statistics_providers.dart';
import '../domain/statistics_models.dart';
import 'tag_time_breakdown.dart';
import 'time_distribution_chart.dart';

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  StatisticsPeriod _period = StatisticsPeriod.week;
  DateTime _anchor = dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(timerNowProvider).value ?? DateTime.now();
    final data = ref.watch(statisticsDataProvider);
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              children: [
                _PageHeader(
                  period: _period,
                  onPeriodChanged: (period) => setState(() {
                    _period = period;
                    _anchor = dateOnly(now);
                  }),
                ),
                const SizedBox(height: 18),
                data.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(60),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => Center(
                    child: TextButton.icon(
                      onPressed: () => ref.invalidate(statisticsDataProvider),
                      icon: const CheckDIcon(CheckDIconType.refresh),
                      label: const Text('统计加载失败，重试'),
                    ),
                  ),
                  data: (value) {
                    final semester = _period == StatisticsPeriod.semester
                        ? value.semesterFor(_anchor)
                        : null;
                    final report = value.report(
                      _period,
                      _anchor,
                      now,
                      semester: semester,
                    );
                    final isCurrent = report.range.contains(now);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _RangeNavigator(
                          label: _rangeLabel(report.range, semester),
                          currentLabel: _period.currentAction,
                          isCurrent: isCurrent,
                          onPrevious: () => _move(-1, value),
                          onNext: isCurrent || report.range.start.isAfter(now)
                              ? null
                              : () => _move(1, value),
                          onCurrent: isCurrent
                              ? null
                              : () => setState(() => _anchor = dateOnly(now)),
                        ),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: AppMotion.duration(
                            context,
                            AppMotion.emphasis,
                          ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, .018),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _ReportContent(
                            key: ValueKey(
                              '${_period.name}-${report.range.start}',
                            ),
                            report: report,
                            period: _period,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _rangeLabel(
    StatisticsRange range,
    StatisticsSemester? semester,
  ) => switch (_period) {
    StatisticsPeriod.day => DateFormat('yyyy年M月d日').format(range.start),
    StatisticsPeriod.week =>
      '${DateFormat('M月d日').format(range.start)}–${DateFormat('M月d日').format(range.end.subtract(const Duration(days: 1)))}',
    StatisticsPeriod.month => DateFormat('yyyy年M月').format(range.start),
    StatisticsPeriod.semester => semester?.name ?? '当前学期',
    StatisticsPeriod.year => '${range.start.year}年',
  };

  void _move(int delta, StatisticsData data) => setState(() {
    final semester = _period == StatisticsPeriod.semester
        ? data.semesterFor(_anchor)
        : null;
    final start = StatisticsRange(_period, _anchor, semester: semester).start;
    _anchor = switch (_period) {
      StatisticsPeriod.day => DateTime(
        start.year,
        start.month,
        start.day + delta,
      ),
      StatisticsPeriod.week => DateTime(
        start.year,
        start.month,
        start.day + delta * 7,
      ),
      StatisticsPeriod.month => DateTime(start.year, start.month + delta),
      StatisticsPeriod.semester => DateTime(
        start.year,
        start.month + delta * 6,
        start.day,
      ),
      StatisticsPeriod.year => DateTime(start.year + delta),
    };
  });
}

extension on StatisticsPeriod {
  String get tabLabel => switch (this) {
    StatisticsPeriod.week => '周',
    StatisticsPeriod.month => '月',
    StatisticsPeriod.semester => '学期',
    StatisticsPeriod.year => '年',
    StatisticsPeriod.day => '日',
  };

  String get currentAction => switch (this) {
    StatisticsPeriod.week => '回到本周',
    StatisticsPeriod.month => '回到本月',
    StatisticsPeriod.semester => '回到本学期',
    StatisticsPeriod.year => '回到今年',
    StatisticsPeriod.day => '回到今天',
  };

  String get focusLabel => switch (this) {
    StatisticsPeriod.week => '本周主动专注',
    StatisticsPeriod.month => '本月主动专注',
    StatisticsPeriod.semester => '本学期主动专注',
    StatisticsPeriod.year => '年度主动专注',
    StatisticsPeriod.day => '今日主动专注',
  };

  String get trendTitle => switch (this) {
    StatisticsPeriod.week => '每日专注时长',
    StatisticsPeriod.month => '每日专注时长',
    StatisticsPeriod.semester => '每周专注时长趋势',
    StatisticsPeriod.year => '每月专注时长',
    StatisticsPeriod.day => '当日专注时长',
  };

  String get distributionTitle => switch (this) {
    StatisticsPeriod.week => '本周专注时间分布',
    StatisticsPeriod.month => '本月专注时间分布',
    StatisticsPeriod.semester => '本学期专注时间分布',
    StatisticsPeriod.year => '年度专注时间分布',
    StatisticsPeriod.day => '今日专注时间分布',
  };

  String get emptyPeriod => switch (this) {
    StatisticsPeriod.week => '这周',
    StatisticsPeriod.month => '这个月',
    StatisticsPeriod.semester => '本学期',
    StatisticsPeriod.year => '今年',
    StatisticsPeriod.day => '今天',
  };
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.period, required this.onPeriodChanged});

  final StatisticsPeriod period;
  final ValueChanged<StatisticsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final switcher = _PeriodSwitcher(
        period: period,
        onChanged: onPeriodChanged,
      );
      if (constraints.maxWidth < 680) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_titleRow(context), const SizedBox(height: 16), switcher],
        );
      }
      return Row(
        children: [
          Expanded(child: _titleRow(context)),
          switcher,
        ],
      );
    },
  );

  Widget _titleRow(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('统计', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 3),
            const Text(
              '记录每一份努力，看见更好的自己',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      IconButton(
        tooltip: '标签管理',
        icon: const CheckDIcon(CheckDIconType.tag),
        onPressed: () => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => const TagsPage())),
      ),
    ],
  );
}

class _RangeNavigator extends StatelessWidget {
  const _RangeNavigator({
    required this.label,
    required this.currentLabel,
    required this.isCurrent,
    required this.onPrevious,
    required this.onNext,
    required this.onCurrent,
  });

  final String label;
  final String currentLabel;
  final bool isCurrent;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCurrent;

  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.plain,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    radius: BorderRadius.circular(18),
    child: Row(
      children: [
        IconButton(
          tooltip: '上一周期',
          onPressed: onPrevious,
          icon: const CheckDIcon(CheckDIconType.back),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        IconButton(
          tooltip: '下一周期',
          onPressed: onNext,
          icon: const CheckDIcon(CheckDIconType.forward),
        ),
        TextButton.icon(
          onPressed: onCurrent,
          icon: const CheckDIcon(CheckDIconType.today, size: 17),
          label: Text(currentLabel),
        ),
      ],
    ),
  );
}

class _PeriodSwitcher extends StatelessWidget {
  const _PeriodSwitcher({required this.period, required this.onChanged});

  final StatisticsPeriod period;
  final ValueChanged<StatisticsPeriod> onChanged;

  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.plain,
    padding: const EdgeInsets.all(4),
    radius: BorderRadius.circular(18),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final value in const [
          StatisticsPeriod.week,
          StatisticsPeriod.month,
          StatisticsPeriod.semester,
          StatisticsPeriod.year,
        ])
          _PeriodButton(
            label: value.tabLabel,
            selected: value == period,
            onTap: () => onChanged(value),
          ),
      ],
    ),
  );
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CheckDPressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.standard),
      curve: AppMotion.curve,
      width: 62,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: selected ? AppColors.blush : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? AppColors.primaryStrong : AppColors.muted,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({required this.report, required this.period, super.key});

  final StatisticsReport report;
  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SummaryCards(report: report, period: period),
      const SizedBox(height: 18),
      if (report.focusSeconds == 0)
        _StatisticsEmptyState(period: period)
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final trend = _Panel(
              title: period.trendTitle,
              subtitle: _trendSubtitle(period),
              child: StatisticsTrendChart(report: report, period: period),
            );
            final distribution = TagTimeBreakdown(
              report: report,
              title: period.distributionTitle,
            );
            if (constraints.maxWidth < 820) {
              return Column(
                children: [trend, const SizedBox(height: 16), distribution],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: trend),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: distribution),
              ],
            );
          },
        ),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, constraints) {
          final insight = _SmartSummaryCard(summary: report.smartSummary);
          final tasks = _TaskPerformance(report: report);
          if (constraints.maxWidth < 820) {
            return Column(
              children: [insight, const SizedBox(height: 16), tasks],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: insight),
              const SizedBox(width: 16),
              Expanded(child: tasks),
            ],
          );
        },
      ),
    ],
  );

  String _trendSubtitle(StatisticsPeriod period) => switch (period) {
    StatisticsPeriod.week => '按周一至周日统计，仅包含主动计时',
    StatisticsPeriod.month => '颜色越深，当天主动专注时间越长',
    StatisticsPeriod.semester => '按学期周汇总主动专注时长',
    StatisticsPeriod.year => '按月份汇总主动专注时长',
    StatisticsPeriod.day => '仅包含主动计时',
  };
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.report, required this.period});

  final StatisticsReport report;
  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final focus = CheckDSurface(
        level: CheckDSurfaceLevel.glassSoft,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.blush,
                shape: BoxShape.circle,
              ),
              child: const CheckDIcon(
                CheckDIconType.focus,
                color: AppColors.primaryStrong,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    period.focusLabel,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    timeLabel(report.focusSeconds),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            if (report.focusSeconds > 0)
              const CheckDIcon(
                CheckDIconType.insight,
                color: AppColors.creamYellow,
                size: 22,
              ),
          ],
        ),
      );
      final compact = Row(
        children: [
          Expanded(
            child: _CompactMetric(
              label: '完成事项',
              value: '${report.completedItems}/${report.expectedItems}',
              icon: CheckDIconType.completion,
              color: AppColors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _CompactMetric(
              label: '打卡天数',
              value: '${report.checkInDays}天',
              icon: CheckDIconType.checkIn,
              color: AppColors.orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _CompactMetric(
              label: period == StatisticsPeriod.year ? '最长坚持' : '连续坚持',
              value:
                  '${period == StatisticsPeriod.year ? report.longestStreak : report.currentStreak}天',
              icon: CheckDIconType.streak,
              color: AppColors.purple,
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 520) {
        return Column(children: [focus, const SizedBox(height: 10), compact]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: focus),
          const SizedBox(width: 12),
          Expanded(flex: 7, child: compact),
        ],
      );
    },
  );
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final CheckDIconType icon;
  final Color color;

  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.raised,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    radius: BorderRadius.circular(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckDIcon(icon, size: 19, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _StatisticsEmptyState extends StatelessWidget {
  const _StatisticsEmptyState({required this.period});

  final StatisticsPeriod period;

  @override
  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
      child: Column(
        children: [
          const CheckDSheep(
            state: SheepState.idle,
            size: MascotSize.md,
            framed: false,
            compact: true,
          ),
          const SizedBox(height: 10),
          Text(
            '${period.emptyPeriod}还没有专注记录',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 7),
          const Text(
            '完成一次专注后，\n这里会慢慢记录下你的节奏。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({this.title, this.subtitle, required this.child});

  final String? title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.raised,
    padding: const EdgeInsets.all(18),
    radius: BorderRadius.circular(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 22),
        ],
        child,
      ],
    ),
  );
}

class _SmartSummaryCard extends StatelessWidget {
  const _SmartSummaryCard({required this.summary});
  final SmartSummary summary;

  @override
  Widget build(BuildContext context) {
    final color = switch (summary.tone) {
      SmartSummaryTone.positive => AppColors.green,
      SmartSummaryTone.attention => AppColors.accentLavender,
      SmartSummaryTone.neutral => AppColors.accentPink,
    };
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckDIcon(CheckDIconType.insight, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  summary.message,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPerformance extends StatelessWidget {
  const _TaskPerformance({required this.report});
  final StatisticsReport report;

  @override
  Widget build(BuildContext context) => _Panel(
    title: '周期事项表现',
    subtitle: '目标计时时长不会自动计为完成，以真实打卡记录为准',
    child: report.tasks.isEmpty
        ? const Text('当前周期暂无周期事项', style: TextStyle(color: AppColors.muted))
        : Column(
            children: [
              for (var index = 0; index < report.tasks.length; index++) ...[
                _TaskRow(task: report.tasks[index]),
                if (index != report.tasks.length - 1) const Divider(height: 24),
              ],
            ],
          ),
  );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final TaskStatistics task;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: task.task.id)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Color(task.task.colorValue).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              taskIconData(task.task.iconName),
              color: Color(task.task.colorValue),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.task.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '打卡 ${task.completed}/${task.expected} · 专注 ${timeLabel(task.seconds)} · 连续 ${task.currentStreak} 天',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            task.expected == 0 ? '--' : '${(task.rate * 100).round()}%',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          const CheckDIcon(CheckDIconType.forward, color: AppColors.muted),
        ],
      ),
    ),
  );
}
