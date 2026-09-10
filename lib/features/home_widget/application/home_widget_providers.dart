import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../courses/application/course_providers.dart';
import '../../mini_window/data/mini_window_repository.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/home_widget_service.dart';

final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) {
  return HomeWidgetService(
    repository: MiniWindowRepository(
      database: ref.watch(appDatabaseProvider),
      userId: ref.watch(currentDataOwnerProvider),
      tasks: ref.watch(taskRepositoryProvider),
      courses: ref.watch(courseRepositoryProvider),
      semesters: ref.watch(semesterRepositoryProvider),
      schedule: ref.watch(dayScheduleRepositoryProvider),
    ),
  );
});
