import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../calendar/presentation/calendar_page.dart';
import '../../reviews/presentation/reviews_page.dart';
import '../../statistics/presentation/statistics_page.dart';
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
    _Destination('复盘', Icons.edit_note_outlined, Icons.edit_note_rounded),
    _Destination('统计', Icons.bar_chart_outlined, Icons.bar_chart_rounded),
  ];

  static const _pages = [
    TodayPage(),
    CalendarPage(),
    ReviewsPage(),
    StatisticsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
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
                icon: Icons.loop_rounded,
                color: AppColors.primary,
                title: '长期任务',
                subtitle: '计时型或点击型打卡',
                onTap: () => _showPhaseNotice(context),
              ),
              const SizedBox(height: 10),
              _CreateOption(
                icon: Icons.event_note_rounded,
                color: AppColors.orange,
                title: '单次事项提醒',
                subtitle: '会议、截止日期或临时事项',
                onTap: () => _showPhaseNotice(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhaseNotice(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('任务创建将在 Phase 2 开放')));
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
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationIndex,
        onDestinationSelected: (index) {
          if (index == 2) {
            onAdd();
          } else {
            onDestinationSelected(index < 2 ? index : index - 1);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today_rounded),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '日历',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: '添加',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note_rounded),
            label: '复盘',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: '统计',
          ),
        ],
      ),
    );
  }
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
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            extended: MediaQuery.sizeOf(context).width >= 1180,
            leading: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 18),
              child: Column(
                children: [
                  const Icon(
                    Icons.task_alt_rounded,
                    size: 32,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加'),
                  ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    tooltip: '退出当前模式',
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                  ),
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
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: page),
        ],
      ),
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
