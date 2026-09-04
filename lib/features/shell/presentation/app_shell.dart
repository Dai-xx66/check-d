import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../calendar/presentation/calendar_page.dart';
import '../../courses/presentation/course_form_page.dart';
import '../../courses/presentation/course_list_page.dart';
import '../../schedule/presentation/ad_hoc_timer_form_page.dart';
import '../../plans/presentation/plans_page.dart';
import '../../reviews/presentation/reviews_page.dart';
import '../../statistics/presentation/statistics_page.dart';
import '../../tasks/presentation/long_term_task_form_page.dart';
import '../../tasks/presentation/one_time_reminder_form_page.dart';
import '../../today/presentation/today_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    _Destination('今日', Icons.today_outlined, Icons.today_rounded),
    _Destination('日历', Icons.calendar_month_outlined, Icons.calendar_month),
    _Destination('计划', Icons.flag_outlined, Icons.flag_rounded),
    _Destination('复盘', Icons.edit_note_outlined, Icons.edit_note_rounded),
    _Destination('统计', Icons.bar_chart_outlined, Icons.bar_chart_rounded),
  ];

  static const _pages = [
    TodayPage(),
    CalendarPage(),
    PlansPage(),
    ReviewsPage(),
    StatisticsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1024) {
          return _DesktopShell(
            selectedIndex: _selectedIndex,
            destinations: _destinations,
            page: _pages[_selectedIndex],
            onDestinationSelected: _selectDestination,
            onAdd: _showCreateSheet,
            onSignOut: _signOut,
          );
        }
        return _MobileShell(
          selectedIndex: _mobileIndexFor(_selectedIndex),
          page: _pages[_mobilePageFor(_selectedIndex)],
          onDestinationSelected: _selectDestination,
          onAdd: _showCreateSheet,
        );
      },
    );
  }

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }

  int _mobilePageFor(int desktopIndex) => switch (desktopIndex) {
    0 || 1 || 3 || 4 => desktopIndex,
    _ => 0,
  };

  int _mobileIndexFor(int desktopIndex) => switch (desktopIndex) {
    0 => 0,
    1 => 1,
    3 => 2,
    4 => 3,
    _ => 0,
  };

  Future<void> _showCreateSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '创建什么？',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _CreateOption(
                icon: Icons.school_outlined,
                color: AppColors.blueMist,
                title: '添加课程',
                subtitle: '课程会出现在今日时间轴，不参与打卡和专注统计',
                onTap: () => _openCourseForm(context),
              ),
              const SizedBox(height: 10),
              _CreateOption(
                icon: Icons.view_list_rounded,
                color: AppColors.lavender,
                title: '课程管理',
                subtitle: '编辑课程安排或归档旧课程',
                onTap: () => _openCourseList(context),
              ),
              const SizedBox(height: 10),
              _CreateOption(
                icon: Icons.loop_rounded,
                color: AppColors.primary,
                title: '周期任务',
                subtitle: '计时记录与完成状态独立',
                onTap: () => _openLongTermForm(context),
              ),
              const SizedBox(height: 10),
              _CreateOption(
                icon: Icons.bolt_rounded,
                color: AppColors.orange,
                title: '临时计时',
                subtitle: '记录一段不属于任务的专注时间',
                onTap: () => _openAdHocTimer(context),
              ),
              const SizedBox(height: 10),
              _CreateOption(
                icon: Icons.event_note_rounded,
                color: AppColors.orange,
                title: '单次事项',
                subtitle: '会议、截止日期或临时事项',
                onTap: () => _openOneTimeForm(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLongTermForm(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => const RecurringTaskFormPage()),
    );
  }

  void _openCourseForm(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => const CourseFormPage()),
    );
  }

  void _openCourseList(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => const CourseListPage()),
    );
  }

  void _openOneTimeForm(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => const OneTimeReminderFormPage()),
    );
  }

  void _openAdHocTimer(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => const AdHocTimerFormPage()),
    );
  }

  Future<void> _signOut() {
    return ref.read(authControllerProvider.notifier).signOut();
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.selectedIndex,
    required this.page,
    required this.onDestinationSelected,
    required this.onAdd,
  });

  final int selectedIndex;
  final Widget page;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final navigationIndex = selectedIndex < 2
        ? selectedIndex
        : selectedIndex + 1;

    return Scaffold(
      body: _SweetBackdrop(child: page),
      bottomNavigationBar: _MobileBottomBar(
        selectedIndex: navigationIndex,
        onSelected: (index) {
          if (index == 2) {
            onAdd();
          } else {
            onDestinationSelected(switch (index) {
              0 => 0,
              1 => 1,
              3 => 3,
              _ => 4,
            });
          }
        },
      ),
    );
  }
}

class _MobileBottomBar extends StatelessWidget {
  const _MobileBottomBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 76,
          decoration: const BoxDecoration(
            color: AppColors.glassStrong,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              _MobileNavItem(
                label: '今日',
                icon: Icons.today_outlined,
                activeIcon: Icons.today_rounded,
                selected: selectedIndex == 0,
                onTap: () => onSelected(0),
              ),
              _MobileNavItem(
                label: '日历',
                icon: Icons.calendar_month_outlined,
                activeIcon: Icons.calendar_month,
                selected: selectedIndex == 1,
                onTap: () => onSelected(1),
              ),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -14),
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: '添加',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(38),
                        onTap: () => onSelected(2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [AppShadows.soft],
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 1),
                            const Text(
                              '添加',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                height: 1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _MobileNavItem(
                label: '复盘',
                icon: Icons.edit_note_outlined,
                activeIcon: Icons.edit_note_rounded,
                selected: selectedIndex == 3,
                onTap: () => onSelected(3),
              ),
              _MobileNavItem(
                label: '统计',
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart_rounded,
                selected: selectedIndex == 4,
                onTap: () => onSelected(4),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            selected ? activeIcon : icon,
            color: selected ? AppColors.primary : AppColors.muted,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.muted,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.selectedIndex,
    required this.destinations,
    required this.page,
    required this.onDestinationSelected,
    required this.onAdd,
    required this.onSignOut,
  });

  final int selectedIndex;
  final List<_Destination> destinations;
  final Widget page;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onAdd;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _SweetBackdrop(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xCFFFFFFF),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F0010),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: NavigationRail(
                  selectedIndex: selectedIndex,
                  extended: MediaQuery.sizeOf(context).width >= 1180,
                  leading: const Padding(
                    padding: EdgeInsets.only(top: 18, bottom: 18),
                    child: Icon(
                      Icons.task_alt_rounded,
                      size: 32,
                      color: AppColors.primary,
                    ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlassButton(
                            onPressed: onAdd,
                            icon: Icons.add_rounded,
                            label: '添加',
                            filled: true,
                          ),
                          const SizedBox(height: 16),
                          IconButton(
                            tooltip: '退出当前模式',
                            onPressed: onSignOut,
                            icon: const Icon(Icons.logout_rounded),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                  ],
                  onDestinationSelected: onDestinationSelected,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x8AFFFFFF),
                        border: Border.all(color: Colors.white),
                      ),
                      child: page,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SweetBackdrop extends StatelessWidget {
  const _SweetBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8FA), Color(0xFFF8F1FF), Color(0xFFFFF4F0)],
        ),
      ),
      child: child,
    );
  }
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minTileHeight: 76,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
