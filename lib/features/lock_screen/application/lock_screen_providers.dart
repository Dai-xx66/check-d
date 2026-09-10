import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../courses/application/course_providers.dart';
import '../../mini_window/data/mini_window_repository.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/lock_screen_status_service.dart';

final lockScreenStatusServiceProvider = Provider<LockScreenStatusService>((
  ref,
) {
  return LockScreenStatusService(
    repository: MiniWindowRepository(
      database: ref.watch(appDatabaseProvider),
      userId: ref.watch(currentDataOwnerProvider),
      tasks: ref.watch(taskRepositoryProvider),
      courses: ref.watch(courseRepositoryProvider),
      semesters: ref.watch(semesterRepositoryProvider),
      schedule: ref.watch(dayScheduleRepositoryProvider),
    ),
    notifications: ref.watch(notificationServiceProvider),
  );
});
