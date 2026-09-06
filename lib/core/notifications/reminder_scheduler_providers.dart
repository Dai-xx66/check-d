import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/courses/application/course_providers.dart';
import '../../features/schedule/application/day_schedule_providers.dart';
import '../../features/tasks/application/task_providers.dart';
import '../../features/tasks/domain/task_models.dart';
import 'notification_providers.dart';
import 'reminder_scheduler.dart';

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return ReminderScheduler(
    notifications: ref.watch(notificationServiceProvider),
    tasks: ref.watch(taskRepositoryProvider),
    courses: ref.watch(courseRepositoryProvider),
    semesters: ref.watch(semesterRepositoryProvider),
    schedule: ref.watch(dayScheduleRepositoryProvider),
  );
});

class ReminderSchedulerHost extends ConsumerStatefulWidget {
  const ReminderSchedulerHost({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<ReminderSchedulerHost> createState() =>
      _ReminderSchedulerHostState();
}

class _ReminderSchedulerHostState extends ConsumerState<ReminderSchedulerHost>
    with WidgetsBindingObserver {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(
      tasksByStatusProvider(TaskLifecycle.active),
      (_, _) => _queue(),
    );
    ref.listenManual(coursesProvider, (_, _) => _queue());
    ref.listenManual(semestersProvider, (_, _) => _queue());
    ref.listenManual(scheduleTemplatesProvider, (_, _) => _queue());
    ref.listenManual(reminderScheduleTriggerProvider, (_, _) => _queue());
    _queue();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _queue();
  }

  void _queue() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(reminderSchedulerProvider).refreshFuture().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
