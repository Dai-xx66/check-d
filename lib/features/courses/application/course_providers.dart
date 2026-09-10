import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/course_repository.dart';
import '../data/semester_repository.dart';
import 'course_schedule_import_service.dart';
import '../data/course_schedule_recognizer.dart';
import '../data/local_course_schedule_recognizer.dart';
import '../domain/course_models.dart';

final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  return CourseRepository(
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    userId: ref.watch(currentDataOwnerProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

final semesterRepositoryProvider = Provider<SemesterRepository>((ref) {
  return SemesterRepository(
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    userId: ref.watch(currentDataOwnerProvider),
  );
});

final courseScheduleImportServiceProvider =
    Provider<CourseScheduleImportService>((ref) {
      return CourseScheduleImportService(
        courses: ref.watch(courseRepositoryProvider),
        semesters: ref.watch(semesterRepositoryProvider),
      );
    });

final courseScheduleRecognizerProvider = Provider<CourseScheduleRecognizer>((
  ref,
) {
  // Local OCR is the only default. Cloud recognition remains an explicit
  // future option and is never used as a silent fallback.
  return LocalCourseScheduleRecognizer();
});

final semestersProvider = StreamProvider.autoDispose<List<SemesterDetails>>((
  ref,
) {
  return ref.watch(semesterRepositoryProvider).watchSemesters();
});

final currentSemesterProvider = StreamProvider.autoDispose<SemesterDetails?>((
  ref,
) {
  return ref.watch(semesterRepositoryProvider).watchCurrentSemester();
});

final coursesProvider = StreamProvider.autoDispose<List<CourseDetails>>((ref) {
  return ref.watch(courseRepositoryProvider).watchCourses();
});

final scheduleTemplatesProvider =
    StreamProvider.autoDispose<List<ScheduleTemplateDetails>>((ref) {
      return ref.watch(courseRepositoryProvider).watchScheduleTemplates();
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
