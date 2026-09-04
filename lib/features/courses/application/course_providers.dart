import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/course_repository.dart';
import '../domain/course_models.dart';

final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  return CourseRepository(
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    userId: ref.watch(currentDataOwnerProvider),
  );
});

final coursesProvider = StreamProvider.autoDispose<List<CourseDetails>>((ref) {
  return ref.watch(courseRepositoryProvider).watchCourses();
});

final coursesSnapshotProvider = FutureProvider.autoDispose<List<CourseDetails>>(
  (ref) {
    return ref.watch(courseRepositoryProvider).loadCourses();
  },
);

final courseDetailsProvider = StreamProvider.autoDispose
    .family<CourseDetails?, String>((ref, courseId) {
      return ref.watch(courseRepositoryProvider).watchCourse(courseId);
    });
