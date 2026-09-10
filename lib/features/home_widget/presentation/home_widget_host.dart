import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../courses/application/course_providers.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../application/home_widget_providers.dart';

class HomeWidgetHost extends ConsumerStatefulWidget {
  const HomeWidgetHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HomeWidgetHost> createState() => _HomeWidgetHostState();
}

class _HomeWidgetHostState extends ConsumerState<HomeWidgetHost>
    with WidgetsBindingObserver {
  Timer? _periodic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _periodic = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() => ref.read(homeWidgetServiceProvider).refresh();

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    ref.listen(unfinishedTaskTimersProvider, (_, _) => _refresh());
    ref.listen(unfinishedAdHocTimersProvider, (_, _) => _refresh());
    ref.listen(tasksForDateProvider(today), (_, _) => _refresh());
    ref.listen(coursesProvider, (_, _) => _refresh());
    ref.listen(semestersProvider, (_, _) => _refresh());
    ref.listen(scheduleTemplatesProvider, (_, _) => _refresh());
    ref.listen(dailyOverridesProvider(today), (_, _) => _refresh());
    ref.listen(miniWindowDataRevisionProvider, (_, _) => _refresh());
    return widget.child;
  }

  @override
  void dispose() {
    _periodic?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
