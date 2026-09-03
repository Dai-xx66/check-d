import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../tags/presentation/tags_page.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/task_detail_page.dart';
import '../../tasks/presentation/task_icon_picker.dart';
import '../application/statistics_providers.dart';
import '../domain/statistics_models.dart';
import 'time_distribution_chart.dart';
import 'tag_time_breakdown.dart';

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
    final range = StatisticsRange(_period, _anchor);
    final isCurrent = range.contains(now);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
            children: [
              Row(
                children: [
                  Text(
                    '统计',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '标签管理',
                    icon: const Icon(Icons.label_outline),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const TagsPage()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SegmentedButton<StatisticsPeriod>(
                segments: const [
                  ButtonSegment(value: StatisticsPeriod.day, label: Text('日')),
                  ButtonSegment(value: StatisticsPeriod.week, label: Text('周')),
                  ButtonSegment(
                    value: StatisticsPeriod.month,
                    label: Text('月'),
                  ),
                  ButtonSegment(value: StatisticsPeriod.year, label: Text('年')),
                ],
                selected: {_period},
                onSelectionChanged: (v) => setState(() => _period = v.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    tooltip: '上一周期',
                    onPressed: () => _move(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      _rangeLabel(range),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: '下一周期',
                    onPressed: isCurrent || range.start.isAfter(now)
                        ? null
                        : () => _move(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: '回到当前周期',
                    onPressed: isCurrent
                        ? null
                        : () => setState(() => _anchor = dateOnly(now)),
                    icon: const Icon(Icons.today_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              data.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(50),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => Center(
                  child: TextButton.icon(
                    onPressed: () => ref.invalidate(statisticsDataProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('统计加载失败，重试'),
                  ),
                ),
                data: (value) =>
                    _ReportContent(report: value.report(_period, _anchor, now)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _rangeLabel(StatisticsRange range) => switch (_period) {
    StatisticsPeriod.day => DateFormat('yyyy年M月d日').format(range.start),
    StatisticsPeriod.week =>
      '${DateFormat('yyyy/M/d').format(range.start)} - ${DateFormat('M/d').format(range.end.subtract(const Duration(days: 1)))}',
    StatisticsPeriod.month => DateFormat('yyyy年M月').format(range.start),
    StatisticsPeriod.year => '${range.start.year}年',
  };

  void _move(int delta) => setState(() {
    final start = StatisticsRange(_period, _anchor).start;
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
      StatisticsPeriod.year => DateTime(start.year + delta),
    };
  });
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({required this.report});
  final StatisticsReport report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (_, constraints) {
          final columns = constraints.maxWidth >= 700 ? 4 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(
                width: width,
                label: '投入时间',
                value: timeLabel(report.seconds),
                color: AppColors.primary,
                icon: Icons.timer_outlined,
              ),
              _Metric(
                width: width,
                label: '周期任务完成率',
                value: report.expected == 0
                    ? '--'
                    : '${(report.rate * 100).toStringAsFixed(0)}%',
                color: AppColors.green,
                icon: Icons.task_alt,
              ),
              _Metric(
                width: width,
                label: '周期任务打卡',
                value: '${report.completed} / ${report.expected}',
                color: AppColors.orange,
                icon: Icons.check_circle_outline,
              ),
              _Metric(
                width: width,
                label: '时长目标达成',
                value: '${report.targetReached} 次',
                color: AppColors.purple,
                icon: Icons.track_changes,
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      Text(
        '单次事项已完成：${report.remindersCompleted}',
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      _SmartSummaryCard(summary: report.smartSummary),
      const SizedBox(height: 30),
      const _Heading('时间分布'),
      const SizedBox(height: 16),
      TimeDistributionChart(report: report),
      const SizedBox(height: 24),
      const _Heading('标签时间'),
      const SizedBox(height: 10),
      TagTimeBreakdown(report: report),
      const SizedBox(height: 28),
      const _Heading('周期任务'),
      const SizedBox(height: 12),
      if (report.tasks.isEmpty)
        const Text('暂无周期任务', style: TextStyle(color: AppColors.muted)),
      for (final task in report.tasks)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => TaskDetailPage(taskId: task.task.id),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          taskIconData(task.task.iconName),
                          color: Color(task.task.colorValue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            task.task.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          task.expected == 0
                              ? '--'
                              : '${(task.rate * 100).toStringAsFixed(0)}%',
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: task.rate,
                      color: Color(task.task.colorValue),
                      backgroundColor: AppColors.border,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        Text('本期打卡 ${task.completed}/${task.expected}'),
                        Text('计时 ${timeLabel(task.seconds)}'),
                        Text('时长达标 ${task.targetReached} 次'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '累计 ${task.totalSuccess} 天 · 当前连续 ${task.currentStreak} 天 · 最长 ${task.longestStreak} 天',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _SmartSummaryCard extends StatelessWidget {
  const _SmartSummaryCard({required this.summary});
  final SmartSummary summary;

  @override
  Widget build(BuildContext context) {
    final color = switch (summary.tone) {
      SmartSummaryTone.positive => AppColors.green,
      SmartSummaryTone.attention => AppColors.orange,
      SmartSummaryTone.neutral => AppColors.primary,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
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
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 12),
            SizedBox(
              height: 28,
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}
