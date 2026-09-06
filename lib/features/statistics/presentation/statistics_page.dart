import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/mascot.dart';
import '../../schedule/application/day_schedule_providers.dart';
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
      color: const Color(0xFFFAFBFC),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
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
                      icon: const Icon(Icons.refresh_rounded),
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
                        _ReportContent(report: report, period: _period),
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
      final switcher = SegmentedButton<StatisticsPeriod>(
        showSelectedIcon: false,
        segments: [
          for (final value in const [
            StatisticsPeriod.week,
            StatisticsPeriod.month,
            StatisticsPeriod.semester,
            StatisticsPeriod.year,
          ])
            ButtonSegment(value: value, label: Text(value.tabLabel)),
        ],
        selected: {period},
        onSelectionChanged: (value) => onPeriodChanged(value.first),
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
      Text('统计', style: Theme.of(context).textTheme.headlineSmall),
      const Spacer(),
      IconButton(
        tooltip: '标签管理',
        icon: const Icon(Icons.label_outline_rounded),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8EAED)),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: '上一周期',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: '下一周期',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        TextButton.icon(
          onPressed: onCurrent,
          icon: const Icon(Icons.today_outlined, size: 17),
          label: Text(currentLabel),
        ),
      ],
    ),
  );
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({required this.report, required this.period});

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
      _SmartSummaryCard(summary: report.smartSummary),
      const SizedBox(height: 18),
      _TaskPerformance(report: report),
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
      final columns = constraints.maxWidth >= 800 ? 4 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Metric(
            width: width,
            label: period.focusLabel,
            value: timeLabel(report.focusSeconds),
            color: AppColors.accentBlue,
            icon: Icons.hourglass_bottom_rounded,
          ),
          _Metric(
            width: width,
            label: '完成事项',
            value: '${report.completedItems} / ${report.expectedItems}',
            color: AppColors.accentMint,
            icon: Icons.task_alt_rounded,
          ),
          _Metric(
            width: width,
            label: '打卡天数',
            value: '${report.checkInDays} 天',
            color: AppColors.orange,
            icon: Icons.calendar_month_rounded,
          ),
          _Metric(
            width: width,
            label: period == StatisticsPeriod.year ? '最长连续坚持' : '连续坚持',
            value:
                '${period == StatisticsPeriod.year ? report.longestStreak : report.currentStreak} 天',
            color: AppColors.accentLavender,
            icon: Icons.local_fire_department_outlined,
          ),
        ],
      );
    },
  );
}

class _StatisticsEmptyState extends ConsumerStatefulWidget {
  const _StatisticsEmptyState({required this.period});

  final StatisticsPeriod period;

  @override
  ConsumerState<_StatisticsEmptyState> createState() =>
      _StatisticsEmptyStateState();
}

class _StatisticsEmptyStateState extends ConsumerState<_StatisticsEmptyState> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const MascotWidget(state: MascotState.working, size: 84),
          const SizedBox(height: 14),
          Text(
            '${widget.period.emptyPeriod}还没有专注记录',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 7),
          const Text(
            '开始一次计时后，这里会记录你的专注轨迹。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _starting ? null : _startFocus,
            icon: _starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_starting ? '正在开始' : '开始计时'),
          ),
        ],
      ),
    ),
  );

  Future<void> _startFocus() async {
    setState(() => _starting = true);
    try {
      final repository = ref.read(dayScheduleRepositoryProvider);
      final timerId = await repository.createAdHocTimer(title: '专注时光');
      await repository.startAdHocTimer(timerId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}

class _Panel extends StatelessWidget {
  const _Panel({this.title, this.subtitle, required this.child});

  final String? title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE8EAED)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A1A1D23),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
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
          Icon(Icons.auto_awesome_outlined, color: color),
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
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}
