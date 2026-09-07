import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../courses/application/course_providers.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/today_repository.dart';
import '../domain/today_models.dart';

final todayRepositoryProvider = Provider<TodayRepository>((ref) {
  return TodayRepository(
    tasks: ref.watch(taskRepositoryProvider),
    courses: ref.watch(courseRepositoryProvider),
    semesters: ref.watch(semesterRepositoryProvider),
    schedule: ref.watch(dayScheduleRepositoryProvider),
  );
});

final todaySnapshotProvider = StreamProvider.autoDispose
    .family<TodaySnapshot, DateTime>((ref, date) {
      ref.watch(miniWindowDataRevisionProvider);
      return ref.watch(todayRepositoryProvider).watch(date);
    });
