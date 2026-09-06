import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_header.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../../plans/presentation/plans_page.dart';
import 'daily_detail_page.dart';
import 'calendar_workspace.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final today = dateOnly(DateTime.now());
    _focusedMonth = DateTime(today.year, today.month);
    _selectedDate = today;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: '日历',
              subtitle: '每天的安排、进度与时间记录',
              trailing: IconButton(
                tooltip: '计划',
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (context) => const PlansPage()),
                ),
                icon: const Icon(Icons.flag_outlined),
              ),
            ),
            const SizedBox(height: 20),
            const Expanded(child: CalendarWorkspace()),
          ],
        ),
      ),
    );
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + offset,
      );
      _selectedDate = _focusedMonth;
    });
  }

  void _goToToday() {
    final today = dateOnly(DateTime.now());
    setState(() {
      _focusedMonth = DateTime(today.year, today.month);
      _selectedDate = today;
    });
  }

  void _selectDate(DateTime date, bool desktop) {
    setState(() {
      _selectedDate = dateOnly(date);
      if (date.month != _focusedMonth.month ||
          date.year != _focusedMonth.year) {
        _focusedMonth = DateTime(date.year, date.month);
      }
    });
    if (!desktop) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (context) => DailyDetailPage(date: date)),
      );
    }
  }
}

class _CalendarPane extends StatelessWidget {
  const _CalendarPane({
    required this.monthData,
    required this.focusedMonth,
    required this.selectedDate,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onSelect,
  });

  final CalendarMonthData monthData;
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelect;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month);
    final gridStart = firstDay.subtract(Duration(days: firstDay.weekday - 1));
    final dates = List.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  DateFormat('yyyy年 M月', 'zh_CN').format(focusedMonth),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(onPressed: onToday, child: const Text('今天')),
                IconButton(
                  tooltip: '上个月',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: '下个月',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final weekday in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        weekday,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dates.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: constraints.maxWidth >= 650 ? 1.22 : 0.82,
                ),
                itemBuilder: (context, index) {
                  final date = dates[index];
                  final inMonth =
                      date.month == focusedMonth.month &&
                      date.year == focusedMonth.year;
                  final data = inMonth
                      ? monthData.day(date)
                      : CalendarDayData(date: date, tasks: const []);
                  return _CalendarDayCell(
                    date: date,
                    data: data,
                    inMonth: inMonth,
                    selected: localDateKey(date) == localDateKey(selectedDate),
                    today: localDateKey(date) == localDateKey(DateTime.now()),
                    onTap: () => onSelect(date),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.data,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime date;
  final CalendarDayData data;
  final bool inMonth;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final markers = data.tasks.take(4).toList();
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected
            ? AppColors.blush
            : inMonth
            ? AppColors.surface
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: today || selected
              ? const BorderSide(color: AppColors.primary, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: Column(
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    color: inMonth ? AppColors.ink : AppColors.muted,
                    fontSize: 13,
                    fontWeight: today || selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (markers.isNotEmpty)
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final task in markers) _TaskMarker(task: task),
                    ],
                  ),
                if (data.scheduledCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${data.completionPercent.round()}%',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskMarker extends StatelessWidget {
  const _TaskMarker({required this.task});

  final TaskDetails task;

  @override
  Widget build(BuildContext context) {
    final progress = task.kind == TaskKind.oneTime
        ? task.isCompleted
              ? 100.0
              : 0.0
        : task.todayProgressPercent.clamp(0, 100);
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: Color(task.colorValue).withValues(
          alpha: progress >= 100
              ? 1
              : progress > 0
              ? 0.55
              : 0.18,
        ),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.data});

  final CalendarMonthData data;

  @override
  Widget build(BuildContext context) {
    final scheduledDays = data.days.values
        .where((day) => day.scheduledCount > 0)
        .toList();
    final elapsedDays = scheduledDays
        .where((day) => !dateOnly(day.date).isAfter(dateOnly(DateTime.now())))
        .toList();
    final completedDays = elapsedDays
        .where((day) => day.completionPercent >= 100)
        .length;
    final average = elapsedDays.isEmpty
        ? 0.0
        : elapsedDays.fold<double>(
                0,
                (sum, day) => sum + day.completionPercent,
              ) /
              elapsedDays.length;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MonthMetric(
              label: '有安排',
              value: '${scheduledDays.length} 天',
            ),
          ),
          Expanded(
            child: _MonthMetric(label: '全部完成', value: '$completedDays 天'),
          ),
          Expanded(
            child: _MonthMetric(label: '平均完成度', value: '${average.round()}%'),
          ),
        ],
      ),
    );
  }
}

class _MonthMetric extends StatelessWidget {
  const _MonthMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
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
