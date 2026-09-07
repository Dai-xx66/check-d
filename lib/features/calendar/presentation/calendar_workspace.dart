import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/app_time.dart';
import '../../courses/application/course_providers.dart';
import '../../courses/domain/course_models.dart';
import '../../courses/presentation/course_form_page.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../domain/calendar_models.dart';
import '../domain/calendar_occurrence_builder.dart';
import 'daily_detail_page.dart';

class CalendarWorkspace extends ConsumerStatefulWidget {
  const CalendarWorkspace({super.key});

  @override
  ConsumerState<CalendarWorkspace> createState() => _CalendarWorkspaceState();
}

class _CalendarWorkspaceState extends ConsumerState<CalendarWorkspace> {
  late DateTime _selectedDate;
  late DateTime _currentWeek;
  late DateTime _focusedMonth;
  CalendarViewMode _mode = CalendarViewMode.month;

  @override
  void initState() {
    super.initState();
    final now = calendarDateOnly(DateTime.now());
    _selectedDate = now;
    _currentWeek = mondayOfWeek(now);
    _focusedMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);
    final templatesAsync = ref.watch(scheduleTemplatesProvider);
    final semestersAsync = ref.watch(semestersProvider);
    final courses = coursesAsync.value ?? const <CourseDetails>[];
    final templates = templatesAsync.value ?? const <ScheduleTemplateDetails>[];
    final semesters = semestersAsync.value ?? const <SemesterDetails>[];
    final dates = _visibleDates();
    final data = <String, List<CalendarOccurrence>>{};
    var loading = false;
    for (final date in dates) {
      final tasksAsync = ref.watch(tasksForDateProvider(date));
      final overridesAsync = ref.watch(dailyOverridesProvider(date));
      if (tasksAsync.isLoading || overridesAsync.isLoading) loading = true;
      final tasks = tasksAsync.value ?? const <TaskDetails>[];
      final overrides = overridesAsync.value ?? const <DailyItemOverride>[];
      data[_key(date)] = buildCalendarOccurrencesForDate(
        date: date,
        tasks: tasks,
        courses: courses,
        overrides: overrides,
        templates: templates,
        semesters: semesters,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        final body = _buildView(data, desktop);
        if (desktop) {
          return Column(
            children: [
              _DesktopToolbar(
                mode: _mode,
                title: _periodTitle(),
                onModeChanged: _changeMode,
                onPrevious: () => _move(-1),
                onNext: () => _move(1),
                onToday: _goToday,
              ),
              const SizedBox(height: 14),
              if (loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: Row(
                  children: [
                    Expanded(flex: 8, child: body),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 280,
                      child: _mode == CalendarViewMode.month
                          ? DailyDetailPanel(date: _selectedDate)
                          : _DesktopContextPanel(
                              selectedDate: _selectedDate,
                              occurrences:
                                  data[_key(_selectedDate)] ?? const [],
                              semesterWeek: _semesterWeekLabel(courses),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _MobileToolbar(
              mode: _mode,
              title: _periodTitle(),
              onModeChanged: _changeMode,
              onPrevious: () => _move(-1),
              onNext: () => _move(1),
              onToday: _goToday,
            ),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  List<DateTime> _visibleDates() {
    if (_mode == CalendarViewMode.month) {
      final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
      final start = mondayOfWeek(first);
      return List.generate(42, (i) => start.add(Duration(days: i)));
    }
    return List.generate(7, (i) => _currentWeek.add(Duration(days: i)));
  }

  Widget _buildView(Map<String, List<CalendarOccurrence>> data, bool desktop) {
    return switch (_mode) {
      CalendarViewMode.month => _MonthView(
        focusedMonth: _focusedMonth,
        selectedDate: _selectedDate,
        data: data,
        desktop: desktop,
        onSelectDate: (date) => _selectMonthDate(date, desktop),
      ),
      CalendarViewMode.week => _WeekView(
        weekStart: _currentWeek,
        data: data,
        selectedDate: _selectedDate,
        onSelectDate: _selectDate,
      ),
      CalendarViewMode.timetable => _TimetableView(
        weekStart: _currentWeek,
        data: data,
        selectedDate: _selectedDate,
        onSelectDate: _selectDate,
      ),
      CalendarViewMode.agenda => _AgendaView(
        weekStart: _currentWeek,
        data: data,
        selectedDate: _selectedDate,
        onSelectDate: _selectDate,
      ),
    };
  }

  void _changeMode(CalendarViewMode mode) {
    setState(() {
      _mode = mode;
      _currentWeek = mondayOfWeek(_selectedDate);
      _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month);
    });
  }

  void _selectMonthDate(DateTime date, bool desktop) {
    _selectDate(date);
    if (!desktop) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => DailyDetailPage(date: date)),
      );
    }
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = calendarDateOnly(date);
      _currentWeek = mondayOfWeek(date);
      _focusedMonth = DateTime(date.year, date.month);
    });
  }

  void _move(int direction) {
    setState(() {
      if (_mode == CalendarViewMode.month) {
        _focusedMonth = DateTime(
          _focusedMonth.year,
          _focusedMonth.month + direction,
        );
        _selectedDate = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
        _currentWeek = mondayOfWeek(_selectedDate);
      } else {
        _currentWeek = _currentWeek.add(Duration(days: 7 * direction));
        _selectedDate = _selectedDate.add(Duration(days: 7 * direction));
        _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month);
      }
    });
  }

  void _goToday() {
    final now = calendarDateOnly(DateTime.now());
    setState(() {
      _selectedDate = now;
      _currentWeek = mondayOfWeek(now);
      _focusedMonth = DateTime(now.year, now.month);
    });
  }

  String _periodTitle() {
    if (_mode == CalendarViewMode.month) {
      return DateFormat('yyyy年 M月', 'zh_CN').format(_focusedMonth);
    }
    final end = _currentWeek.add(const Duration(days: 6));
    if (_currentWeek.year == end.year && _currentWeek.month == end.month) {
      return '${DateFormat('yyyy年 M月 d日', 'zh_CN').format(_currentWeek)} – ${end.day}日';
    }
    return '${DateFormat('M月d日', 'zh_CN').format(_currentWeek)} – ${DateFormat('M月d日', 'zh_CN').format(end)}';
  }

  String? _semesterWeekLabel(List<CourseDetails> courses) {
    final active = courses.where((course) {
      final start = course.semesterStartsOn;
      final end = course.semesterEndsOn;
      if (start == null) return false;
      if (_selectedDate.isBefore(calendarDateOnly(start))) return false;
      if (end != null && _selectedDate.isAfter(calendarDateOnly(end)))
        return false;
      return true;
    }).toList();
    if (active.isEmpty) return null;
    final first = active.first;
    final week = semesterWeekNumberFor(_selectedDate, first.semesterStartsOn!);
    return '${first.semester ?? '当前学期'} · 第$week周';
  }

  String _key(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _DesktopToolbar extends StatelessWidget {
  const _DesktopToolbar({
    required this.mode,
    required this.title,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });
  final CalendarViewMode mode;
  final String title;
  final ValueChanged<CalendarViewMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SegmentedButton<CalendarViewMode>(
          segments: const [
            ButtonSegment(value: CalendarViewMode.month, label: Text('月')),
            ButtonSegment(value: CalendarViewMode.week, label: Text('周')),
            ButtonSegment(value: CalendarViewMode.timetable, label: Text('课表')),
            ButtonSegment(value: CalendarViewMode.agenda, label: Text('日程')),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (value) => onModeChanged(value.first),
        ),
        const SizedBox(width: 24),
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        const Spacer(),
        TextButton(onPressed: onToday, child: const Text('今天')),
      ],
    );
  }
}

class _MobileToolbar extends StatelessWidget {
  const _MobileToolbar({
    required this.mode,
    required this.title,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });
  final CalendarViewMode mode;
  final String title;
  final ValueChanged<CalendarViewMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<CalendarViewMode>(
            segments: const [
              ButtonSegment(value: CalendarViewMode.month, label: Text('月')),
              ButtonSegment(value: CalendarViewMode.week, label: Text('周')),
              ButtonSegment(
                value: CalendarViewMode.timetable,
                label: Text('课表'),
              ),
              ButtonSegment(value: CalendarViewMode.agenda, label: Text('日程')),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (value) => onModeChanged(value.first),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(onPressed: onToday, child: const Text('今天')),
          ],
        ),
      ],
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.focusedMonth,
    required this.selectedDate,
    required this.data,
    required this.desktop,
    required this.onSelectDate,
  });
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final Map<String, List<CalendarOccurrence>> data;
  final bool desktop;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final start = mondayOfWeek(first);
    final dates = List.generate(42, (i) => start.add(Duration(days: i)));
    return Column(
      children: [
        Row(
          children: [
            for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GridView.builder(
            itemCount: dates.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final date = dates[index];
              final items = data[_dayKey(date)] ?? const <CalendarOccurrence>[];
              final selected = _sameDay(date, selectedDate);
              final inMonth =
                  date.month == focusedMonth.month &&
                  date.year == focusedMonth.year;
              return InkWell(
                onTap: () => onSelectDate(date),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.blush
                        : (inMonth ? AppColors.surface : Colors.transparent),
                    borderRadius: BorderRadius.circular(14),
                    border: selected || _sameDay(date, DateTime.now())
                        ? Border.all(color: AppColors.primary, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          color: inMonth ? AppColors.ink : AppColors.muted,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      for (final item in items.take(desktop ? 3 : 1))
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 1),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Color(
                              item.colorValue,
                            ).withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 8, height: 1),
                          ),
                        ),
                      if (items.length > (desktop ? 3 : 1))
                        Text(
                          '+${items.length - (desktop ? 3 : 1)}',
                          style: const TextStyle(
                            fontSize: 8,
                            height: 1,
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({
    required this.weekStart,
    required this.data,
    required this.selectedDate,
    required this.onSelectDate,
  });
  final DateTime weekStart;
  final Map<String, List<CalendarOccurrence>> data;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    return _TimeGrid(
      days: days,
      data: data,
      selectedDate: selectedDate,
      onSelectDate: onSelectDate,
      courseOnly: false,
      startHour: 6,
      endHour: 24,
    );
  }
}

class _TimetableView extends StatelessWidget {
  const _TimetableView({
    required this.weekStart,
    required this.data,
    required this.selectedDate,
    required this.onSelectDate,
  });
  final DateTime weekStart;
  final Map<String, List<CalendarOccurrence>> data;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    return _TimeGrid(
      days: days,
      data: data,
      selectedDate: selectedDate,
      onSelectDate: onSelectDate,
      courseOnly: true,
      startHour: 7,
      endHour: 23,
    );
  }
}

class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.days,
    required this.data,
    required this.selectedDate,
    required this.onSelectDate,
    required this.courseOnly,
    required this.startHour,
    required this.endHour,
  });
  final List<DateTime> days;
  final Map<String, List<CalendarOccurrence>> data;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final bool courseOnly;
  final int startHour;
  final int endHour;

  @override
  Widget build(BuildContext context) {
    const hourHeight = 64.0;
    final height = (endHour - startHour) * hourHeight;
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 52),
            for (final day in days)
              Expanded(
                child: InkWell(
                  onTap: () => onSelectDate(day),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: _sameDay(day, selectedDate) ? AppColors.blush : null,
                    child: Column(
                      children: [
                        Text(
                          DateFormat('E', 'zh_CN').format(day),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                        Text(
                          '${day.day}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Stack(
                      children: [
                        for (var hour = startHour; hour < endHour; hour++)
                          Positioned(
                            top: (hour - startHour) * hourHeight - 7,
                            right: 8,
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final colWidth = constraints.maxWidth / 7;
                        return Stack(
                          children: [
                            for (var h = 0; h <= endHour - startHour; h++)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: h * hourHeight,
                                child: const Divider(
                                  height: 1,
                                  color: AppColors.border,
                                ),
                              ),
                            for (var d = 0; d <= 7; d++)
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: d * colWidth,
                                child: const VerticalDivider(
                                  width: 1,
                                  color: AppColors.border,
                                ),
                              ),
                            for (
                              var dayIndex = 0;
                              dayIndex < days.length;
                              dayIndex++
                            )
                              ..._buildPositionedEvents(
                                dayIndex,
                                colWidth,
                                hourHeight,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPositionedEvents(
    int dayIndex,
    double colWidth,
    double hourHeight,
  ) {
    final date = days[dayIndex];
    var items = data[_dayKey(date)] ?? const <CalendarOccurrence>[];
    if (courseOnly) {
      items = items
          .where((item) => item.type == CalendarOccurrenceType.course)
          .toList();
    } else {
      items = items.where((item) => item.startMinute != null).toList();
    }
    final layouts = _layoutOverlaps(items);
    return [
      for (final layout in layouts)
        if (layout.item.startMinute! < endHour * 60 &&
            (layout.item.endMinute ?? layout.item.startMinute! + 45) >
                startHour * 60)
          Positioned(
            left:
                dayIndex * colWidth +
                3 +
                layout.lane * ((colWidth - 6) / layout.laneCount),
            width: math.max(24, (colWidth - 6) / layout.laneCount - 3),
            top: math.max(
              0,
              (layout.item.startMinute! - startHour * 60) / 60 * hourHeight,
            ),
            height: math.max(
              24,
              ((layout.item.endMinute ?? layout.item.startMinute! + 45) -
                      layout.item.startMinute!) /
                  60 *
                  hourHeight,
            ),
            child: CalendarWeekEventBlock(item: layout.item),
          ),
    ];
  }
}

/// Keeps a timed occurrence's real height while reducing detail for short
/// durations. Courses and timed task occurrences share this renderer.
class CalendarWeekEventBlock extends StatelessWidget {
  const CalendarWeekEventBlock({required this.item, super.key});

  final CalendarOccurrence item;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight;
      final showSubtitle = item.subtitle != null && height >= 52;
      final roomy = height >= 44;
      final compact = height < 32;
      return Container(
        padding: EdgeInsets.all(compact ? 2 : roomy ? 5 : 3),
        decoration: BoxDecoration(
          color: Color(item.colorValue).withValues(alpha: .20),
          borderRadius: BorderRadius.circular(7),
          border: Border(
            left: BorderSide(color: Color(item.colorValue), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.title,
              maxLines: roomy ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 8 : 10,
                height: 1.05,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showSubtitle)
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8,
                  height: 1.05,
                  color: AppColors.muted,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _AgendaView extends StatelessWidget {
  const _AgendaView({
    required this.weekStart,
    required this.data,
    required this.selectedDate,
    required this.onSelectDate,
  });
  final DateTime weekStart;
  final Map<String, List<CalendarOccurrence>> data;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 28),
      itemCount: days.length,
      separatorBuilder: (_, __) => const Divider(height: 24),
      itemBuilder: (context, index) {
        final day = days[index];
        final items = data[_dayKey(day)] ?? const <CalendarOccurrence>[];
        final timed = items.where((item) => item.hasTime).toList();
        final untimed = items.where((item) => !item.hasTime).toList();
        return InkWell(
          onTap: () => onSelectDate(day),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('M月d日 EEEE', 'zh_CN').format(day),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: _sameDay(day, selectedDate)
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (timed.isEmpty && untimed.isEmpty)
                  const Text('暂无安排', style: TextStyle(color: AppColors.muted)),
                for (final item in timed) _AgendaTile(item: item),
                if (untimed.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '待完成 / 时间未定',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final item in untimed) _AgendaTile(item: item),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AgendaTile extends ConsumerWidget {
  const _AgendaTile({required this.item});
  final CalendarOccurrence item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: item.type != CalendarOccurrenceType.course
          ? null
          : () => _showCourseOccurrenceActions(context, item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(
                item.startMinute == null
                    ? '—'
                    : _formatMinute(item.startMinute!),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: Color(item.colorValue),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      style: const TextStyle(
                        fontSize: 11,
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

void _showCourseOccurrenceActions(
  BuildContext context,
  CalendarOccurrence item,
) {
  final course = item.course;
  if (course == null) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('仅修改本次'),
              subtitle: const Text('调整本次时间、教室、备注或取消，不影响后续课程'),
              onTap: () {
                Navigator.pop(sheetContext);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _CourseOccurrenceOverrideSheet(item: item),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('修改课程安排'),
              subtitle: const Text('从本周起调整后续规则，历史安排保留'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => CourseFormPage(initialCourse: course),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _CourseOccurrenceOverrideSheet extends ConsumerStatefulWidget {
  const _CourseOccurrenceOverrideSheet({required this.item});
  final CalendarOccurrence item;
  @override
  ConsumerState<_CourseOccurrenceOverrideSheet> createState() =>
      _CourseOccurrenceOverrideSheetState();
}

class _CourseOccurrenceOverrideSheetState
    extends ConsumerState<_CourseOccurrenceOverrideSheet> {
  late int _start = widget.item.startMinute ?? 480;
  late int _end = widget.item.endMinute ?? _start + 45;
  late final TextEditingController _classroom = TextEditingController(
    text: widget.item.classroom ?? '',
  );
  final _notes = TextEditingController();
  bool _cancel = false;
  bool _reminderSettingsLoaded = false;
  late bool _advanceReminderEnabled =
      widget.item.courseRule?.remindBeforeMinutes != null;
  late int _advanceMinutes = widget.item.courseRule?.remindBeforeMinutes ?? 10;
  bool _atTimeReminderEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadReminderSettings();
  }

  Future<void> _loadReminderSettings() async {
    if (_reminderSettingsLoaded) return;
    final ownerId = widget.item.courseRule?.id;
    if (ownerId == null) return;
    final rules = await ref
        .read(dayScheduleRepositoryProvider)
        .loadReminderRules();
    if (!mounted) return;
    final date = calendarDateOnly(widget.item.date);
    final matching = rules
        .where(
          (rule) =>
              rule.ownerType == DayItemType.course &&
              rule.ownerId == ownerId &&
              calendarDateOnly(rule.localDate ?? DateTime(1)) == date,
        )
        .toList();
    final defaults = rules
        .where(
          (rule) =>
              rule.ownerType == DayItemType.course &&
              rule.ownerId == ownerId &&
              rule.localDate == null,
        )
        .toList();
    final selected = matching.isNotEmpty ? matching : defaults;
    if (selected.isNotEmpty) {
      setState(() {
        final advance = selected.where(
          (rule) => rule.reminderKind == ReminderKind.advance,
        );
        final due = selected.where(
          (rule) => rule.reminderKind == ReminderKind.due,
        );
        _advanceReminderEnabled = advance.firstOrNull?.enabled ?? false;
        _advanceMinutes = advance.firstOrNull?.remindBeforeMinutes ?? 10;
        _atTimeReminderEnabled = due.firstOrNull?.enabled ?? false;
        _reminderSettingsLoaded = true;
      });
    } else {
      _reminderSettingsLoaded = true;
    }
  }

  @override
  void dispose() {
    _classroom.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('仅修改本次课程', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _timeButton(
                    '开始',
                    _start,
                    (value) => setState(() => _start = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeButton(
                    '结束',
                    _end,
                    (value) => setState(() => _end = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _classroom,
              decoration: const InputDecoration(labelText: '临时教室（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: '备注（可选）'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Text('提醒', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('提前提醒'),
              value: _advanceReminderEnabled,
              onChanged: _cancel
                  ? null
                  : (value) => setState(() => _advanceReminderEnabled = value),
            ),
            if (_advanceReminderEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<int>(
                  value: _advanceMinutes,
                  decoration: const InputDecoration(labelText: '提前时间'),
                  items: const [5, 10, 15, 30, 60]
                      .map(
                        (minutes) => DropdownMenuItem(
                          value: minutes,
                          child: Text('提前 $minutes 分钟'),
                        ),
                      )
                      .toList(),
                  onChanged: _cancel
                      ? null
                      : (value) =>
                            setState(() => _advanceMinutes = value ?? 10),
                ),
              ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('到点提醒'),
              value: _atTimeReminderEnabled,
              onChanged: _cancel
                  ? null
                  : (value) => setState(() => _atTimeReminderEnabled = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('取消本次课程'),
              value: _cancel,
              onChanged: (value) => setState(() => _cancel = value),
            ),
            FilledButton(onPressed: _save, child: const Text('保存本次调整')),
          ],
        ),
      ),
    ),
  );
  Widget _timeButton(String label, int value, ValueChanged<int> onChanged) =>
      OutlinedButton(
        onPressed: () async {
          final result = await showAppTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
          );
          if (result != null) onChanged(result.hour * 60 + result.minute);
        },
        child: Text('$label ${_formatMinute(value)}'),
      );
  Future<void> _save() async {
    if (!_cancel && _end <= _start) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前课程安排暂不支持跨日时间')));
      return;
    }
    final rule = widget.item.courseRule;
    if (rule == null) return;
    final schedule = ref.read(dayScheduleRepositoryProvider);
    await schedule.saveDailyOverride(
      DailyItemOverrideDraft(
        itemType: DayItemType.course,
        itemId: rule.id,
        localDate: widget.item.date,
        action: _cancel
            ? DayOverrideAction.skip
            : DayOverrideAction.courseChange,
        plannedStartMinute: _cancel ? null : _start,
        plannedEndMinute: _cancel ? null : _end,
        temporaryClassroom: _classroom.text,
        notes: _notes.text,
      ),
    );
    if (!_cancel) {
      await schedule.replaceReminderConfiguration(
        ownerType: DayItemType.course,
        ownerId: rule.id,
        localDate: widget.item.date,
        advanceEnabled: _advanceReminderEnabled,
        advanceMinutes: _advanceReminderEnabled ? _advanceMinutes : null,
        atTimeEnabled: _atTimeReminderEnabled,
      );
    }
    if (mounted) Navigator.pop(context);
  }
}

class _DesktopContextPanel extends StatelessWidget {
  const _DesktopContextPanel({
    required this.selectedDate,
    required this.occurrences,
    required this.semesterWeek,
  });
  final DateTime selectedDate;
  final List<CalendarOccurrence> occurrences;
  final String? semesterWeek;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('M月d日 EEEE', 'zh_CN').format(selectedDate),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (semesterWeek != null) ...[
            const SizedBox(height: 4),
            Text(
              semesterWeek!,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            '${occurrences.length} 项安排',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final item in occurrences) _AgendaTile(item: item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlapLayout {
  const _OverlapLayout(this.item, this.lane, this.laneCount);
  final CalendarOccurrence item;
  final int lane;
  final int laneCount;
}

List<_OverlapLayout> _layoutOverlaps(List<CalendarOccurrence> input) {
  final items = [...input]
    ..sort((a, b) => a.startMinute!.compareTo(b.startMinute!));
  final laneEnds = <int>[];
  final temp = <(CalendarOccurrence, int)>[];
  for (final item in items) {
    final start = item.startMinute!;
    final end = item.endMinute ?? start + 45;
    var lane = laneEnds.indexWhere((laneEnd) => laneEnd <= start);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(end);
    } else {
      laneEnds[lane] = end;
    }
    temp.add((item, lane));
  }
  final count = math.max(1, laneEnds.length);
  return [for (final value in temp) _OverlapLayout(value.$1, value.$2, count)];
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _formatMinute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
