import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/platform/desktop_mini_window.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../calendar/presentation/calendar_page.dart';
import '../../courses/presentation/course_form_page.dart';
import '../../courses/presentation/course_list_page.dart';
import '../../profile/presentation/my_page.dart';
import '../../schedule/presentation/ad_hoc_timer_form_page.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../statistics/presentation/statistics_page.dart';
import '../../tasks/presentation/long_term_task_form_page.dart';
import '../../tasks/presentation/one_time_reminder_form_page.dart';
import '../../tasks/application/task_providers.dart';
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
    _Destination('统计', Icons.bar_chart_outlined, Icons.bar_chart_rounded),
    _Destination('我的', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  static const _pages = [
    TodayPage(),
    CalendarPage(),
    StatisticsPage(),
    MyPage(),
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
            onCreateCourse: _createCourse,
            onCreateRecurring: _createRecurring,
            onCreateOneTime: _createOneTime,
            onStartFocus: _startQuickFocus,
            onOpenMiniWindow: _openMiniWindow,
            onSignOut: _signOut,
          );
        }
        return _MobileShell(
          selectedIndex: _selectedIndex,
          page: _pages[_selectedIndex],
          onDestinationSelected: _selectDestination,
          onAdd: _showCreateSheet,
        );
      },
    );
  }

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _openMiniWindow() => DesktopMiniWindowLauncher.open(
    ownerId: ref.read(currentDataOwnerProvider),
  );

  Future<void> _showCreateSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .82,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
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

  void _createCourse() {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const CourseFormPage()));
  }

  void _createRecurring() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RecurringTaskFormPage()),
    );
  }

  void _createOneTime() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const OneTimeReminderFormPage()),
    );
  }

  Future<void> _startQuickFocus() async {
    try {
      final repository = ref.read(dayScheduleRepositoryProvider);
      final id = await repository.createAdHocTimer(title: '专注时光');
      await repository.startAdHocTimer(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已开始一段临时专注计时。')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
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
    final navigationIndex = switch (selectedIndex) {
      0 => 0,
      1 => 1,
      2 => 3,
      3 => 4,
      _ => 0,
    };

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
              3 => 2,
              _ => 3,
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
                label: '统计',
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart_rounded,
                selected: selectedIndex == 3,
                onTap: () => onSelected(3),
              ),
              _MobileNavItem(
                label: '我的',
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
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
    required this.onCreateCourse,
    required this.onCreateRecurring,
    required this.onCreateOneTime,
    required this.onStartFocus,
    required this.onOpenMiniWindow,
    required this.onSignOut,
  });

  final int selectedIndex;
  final List<_Destination> destinations;
  final Widget page;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onCreateCourse;
  final VoidCallback onCreateRecurring;
  final VoidCallback onCreateOneTime;
  final VoidCallback onStartFocus;
  final VoidCallback onOpenMiniWindow;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFC),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _DesktopSidebar(
              selectedIndex: selectedIndex,
              destinations: destinations,
              onDestinationSelected: onDestinationSelected,
              onCreateCourse: onCreateCourse,
              onCreateRecurring: onCreateRecurring,
              onCreateOneTime: onCreateOneTime,
              onStartFocus: onStartFocus,
              onOpenMiniWindow: onOpenMiniWindow,
              onSignOut: onSignOut,
            ),
            const SizedBox(width: 24),
            Expanded(child: page),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.onCreateCourse,
    required this.onCreateRecurring,
    required this.onCreateOneTime,
    required this.onStartFocus,
    required this.onOpenMiniWindow,
    required this.onSignOut,
  });

  final int selectedIndex;
  final List<_Destination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onCreateCourse;
  final VoidCallback onCreateRecurring;
  final VoidCallback onCreateOneTime;
  final VoidCallback onStartFocus;
  final VoidCallback onOpenMiniWindow;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    width: 224,
    padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAF8),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE8ECEA)),
      boxShadow: const [AppShadows.soft],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 2, 10, 18),
          child: Row(
            children: [
              Icon(Icons.task_alt_rounded, color: AppColors.primary, size: 28),
              SizedBox(width: 9),
              Text(
                '小羊日常',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        for (var index = 0; index < destinations.length; index++)
          _DesktopNavItem(
            destination: destinations[index],
            selected: index == selectedIndex,
            onTap: () => onDestinationSelected(index),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onCreateRecurring,
          icon: const Icon(Icons.add_rounded),
          label: const Text('新建'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '快速创建',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 5),
        _DesktopCreateLink(
          icon: Icons.school_outlined,
          label: '添加课程',
          onTap: onCreateCourse,
        ),
        _DesktopCreateLink(
          icon: Icons.loop_rounded,
          label: '周期事项',
          onTap: onCreateRecurring,
        ),
        _DesktopCreateLink(
          icon: Icons.event_note_outlined,
          label: '单次事项',
          onTap: onCreateOneTime,
        ),
        _DesktopCreateLink(
          icon: Icons.bolt_rounded,
          label: '立即开始计时',
          onTap: onStartFocus,
        ),
        _DesktopCreateLink(
          icon: Icons.open_in_new_rounded,
          label: '打开桌面组件',
          onTap: onOpenMiniWindow,
        ),
        const Spacer(),
        const Divider(color: Color(0xFFE6EAE8)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('退出当前模式'),
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
          ),
        ),
      ],
    ),
  );
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });
  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: selected ? AppColors.blush : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: selected ? AppColors.primary : AppColors.ink,
                size: 20,
              ),
              const SizedBox(width: 11),
              Text(
                destination.label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DesktopCreateLink extends StatelessWidget {
  const _DesktopCreateLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
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
