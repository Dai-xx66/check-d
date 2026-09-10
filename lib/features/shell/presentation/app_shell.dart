import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/platform/desktop_mini_window.dart';
import '../../../shared/widgets/check_d_design.dart';
import '../../../shared/widgets/mascot.dart';
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
    _Destination('今日', CheckDIconType.today),
    _Destination('日历', CheckDIconType.calendar),
    _Destination('统计', CheckDIconType.statistics),
    _Destination('我的', CheckDIconType.profile),
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
            onOpenSettings: () => _selectDestination(3),
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
                  icon: CheckDIconType.course,
                  color: AppColors.blueMist,
                  title: '添加课程',
                  subtitle: '课程会出现在今日时间轴，不参与打卡和专注统计',
                  onTap: () => _openCourseForm(context),
                ),
                const SizedBox(height: 10),
                _CreateOption(
                  icon: CheckDIconType.course,
                  color: AppColors.lavender,
                  title: '课程管理',
                  subtitle: '编辑课程安排或归档旧课程',
                  onTap: () => _openCourseList(context),
                ),
                const SizedBox(height: 10),
                _CreateOption(
                  icon: CheckDIconType.recurring,
                  color: AppColors.primary,
                  title: '周期任务',
                  subtitle: '计时记录与完成状态独立',
                  onTap: () => _openLongTermForm(context),
                ),
                const SizedBox(height: 10),
                _CreateOption(
                  icon: CheckDIconType.timer,
                  color: AppColors.orange,
                  title: '临时计时',
                  subtitle: '记录一段不属于任务的专注时间',
                  onTap: () => _openAdHocTimer(context),
                ),
                const SizedBox(height: 10),
                _CreateOption(
                  icon: CheckDIconType.oneOff,
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
      checkDPageRoute(builder: (context) => const RecurringTaskFormPage()),
    );
  }

  void _openCourseForm(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(
      context,
    ).push<void>(checkDPageRoute(builder: (context) => const CourseFormPage()));
  }

  void _openCourseList(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(
      context,
    ).push<void>(checkDPageRoute(builder: (context) => const CourseListPage()));
  }

  void _openOneTimeForm(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push<void>(
      checkDPageRoute(builder: (context) => const OneTimeReminderFormPage()),
    );
  }

  void _openAdHocTimer(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push<void>(
      checkDPageRoute(builder: (context) => const AdHocTimerFormPage()),
    );
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
    child: SizedBox(
      height: CheckDLayout.mobileBottomBarHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalInset = 8.0;
          const topInset = 6.0;
          final contentWidth = constraints.maxWidth - horizontalInset * 2;
          final slotWidth = contentWidth / 5;
          final motionReduced =
              MediaQuery.maybeOf(context)?.disableAnimations == true;
          final duration = motionReduced
              ? Duration.zero
              : const Duration(milliseconds: 280);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The filter is deliberately inside this local clipped surface.
              // Keeping it out of the full Scaffold prevents Web compositor
              // backdrops from blurring the page above the navigation bar.
              Positioned(
                left: horizontalInset,
                right: horizontalInset,
                top: topInset,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  clipBehavior: Clip.antiAlias,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0xD4FFFEFC),
                        border: Border.fromBorderSide(
                          BorderSide(color: Color(0x70FFFFFF)),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x0E754A55),
                            blurRadius: 24,
                            offset: Offset(0, -7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: horizontalInset + selectedIndex * slotWidth + 10,
                top: topInset - 2,
                width: slotWidth - 20,
                height: 60,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: AppColors.blush.withValues(alpha: .64),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .78),
                      ),
                      boxShadow: const [AppShadows.soft],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: horizontalInset,
                right: horizontalInset,
                top: topInset,
                bottom: 0,
                child: Row(
                  children: [
                    _MobileNavItem(
                      label: '今天',
                      icon: CheckDIconType.today,
                      selected: selectedIndex == 0,
                      reducedMotion: motionReduced,
                      onTap: () => onSelected(0),
                    ),
                    _MobileNavItem(
                      label: '日历',
                      icon: CheckDIconType.calendar,
                      selected: selectedIndex == 1,
                      reducedMotion: motionReduced,
                      onTap: () => onSelected(1),
                    ),
                    Expanded(
                      child: Transform.translate(
                        offset: const Offset(0, -14),
                        child: Center(
                          child: Semantics(
                            button: true,
                            label: '添加',
                            child: CheckDPressable(
                              borderRadius: BorderRadius.circular(38),
                              pressedScale: .96,
                              onTap: () => onSelected(2),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFFF993AE),
                                          AppColors.primaryStrong,
                                        ],
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [AppShadows.soft],
                                    ),
                                    child: const CheckDIcon(
                                      CheckDIconType.add,
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
                      icon: CheckDIconType.statistics,
                      selected: selectedIndex == 3,
                      reducedMotion: motionReduced,
                      onTap: () => onSelected(3),
                    ),
                    _MobileNavItem(
                      label: '我的',
                      icon: CheckDIconType.profile,
                      selected: selectedIndex == 4,
                      reducedMotion: motionReduced,
                      onTap: () => onSelected(4),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.reducedMotion,
    required this.onTap,
  });
  final String label;
  final CheckDIconType icon;
  final bool selected;
  final bool reducedMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: label,
      child: CheckDPressable(
        pressedScale: .97,
        onTap: onTap,
        child: AnimatedSlide(
          duration: reducedMotion ? Duration.zero : AppMotion.standard,
          curve: Curves.easeOutCubic,
          offset: selected ? const Offset(0, -.10) : Offset.zero,
          child: AnimatedScale(
            duration: reducedMotion ? Duration.zero : AppMotion.standard,
            curve: Curves.easeOutBack,
            scale: selected ? 1.14 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CheckDIcon(
                  icon,
                  active: selected,
                  color: selected ? AppColors.primaryStrong : AppColors.muted,
                  size: selected ? 24 : 21,
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: reducedMotion ? Duration.zero : AppMotion.quick,
                  style: TextStyle(
                    color: selected ? AppColors.primaryStrong : AppColors.muted,
                    fontSize: 11,
                    height: 1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
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
    required this.onOpenSettings,
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
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _SweetBackdrop(
        child: Padding(
          padding: const EdgeInsets.all(18),
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
                onOpenSettings: onOpenSettings,
              ),
              const SizedBox(width: 16),
              Expanded(child: page),
            ],
          ),
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
    required this.onOpenSettings,
  });

  final int selectedIndex;
  final List<_Destination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onCreateCourse;
  final VoidCallback onCreateRecurring;
  final VoidCallback onCreateOneTime;
  final VoidCallback onStartFocus;
  final VoidCallback onOpenMiniWindow;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Container(
    width: 244,
    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xDBFFFEFC), Color(0xC8FFF9F6)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0x78FFFFFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0C5E3B43),
          blurRadius: 24,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 2, 8, 20),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 38,
                  child: CheckDIcon(
                    CheckDIconType.today,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check D',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'A kinder way to keep going ♡',
                      maxLines: 1,
                      style: TextStyle(fontSize: 9, color: AppColors.muted),
                    ),
                  ],
                ),
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
          icon: const CheckDIcon(CheckDIconType.add, color: Colors.white),
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
          icon: CheckDIconType.course,
          label: '添加课程',
          onTap: onCreateCourse,
        ),
        _DesktopCreateLink(
          icon: CheckDIconType.recurring,
          label: '周期事项',
          onTap: onCreateRecurring,
        ),
        _DesktopCreateLink(
          icon: CheckDIconType.oneOff,
          label: '单次事项',
          onTap: onCreateOneTime,
        ),
        _DesktopCreateLink(
          icon: CheckDIconType.timer,
          label: '立即开始计时',
          onTap: onStartFocus,
        ),
        _DesktopCreateLink(
          icon: CheckDIconType.widget,
          label: '打开桌面组件',
          onTap: onOpenMiniWindow,
        ),
        const Spacer(),
        const SizedBox(
          height: 126,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 4,
                bottom: 2,
                child: Opacity(
                  opacity: .66,
                  child: CheckDSheep(
                    state: SheepState.idle,
                    size: MascotSize.compactLarge,
                    compact: true,
                    framed: false,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 34,
                child: Text(
                  'Small Steps\nBright Days ♡',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.primaryStrong,
                    fontSize: 10,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: AppColors.border),
        _DesktopCreateLink(
          icon: CheckDIconType.settings,
          label: '设置',
          onTap: onOpenSettings,
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
      color: selected ? const Color(0x9CFFE6EC) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              CheckDIcon(
                destination.icon,
                active: selected,
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
  final CheckDIconType icon;
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
          CheckDIcon(icon, size: 18, color: AppColors.muted),
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
          colors: [Color(0xFFFFF7F1), Color(0xFFFFFCF9), Color(0xFFFFF8FA)],
          stops: [0, .54, 1],
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

  final CheckDIconType icon;
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
          child: CheckDIcon(icon, size: 20, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const CheckDIcon(CheckDIconType.forward),
        onTap: onTap,
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final CheckDIconType icon;
}
