import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/app_providers.dart';
import 'sync_apply_scope.dart';
import 'sync_account_service.dart';
import 'sync_bootstrap_service.dart';
import 'sync_download_service.dart';
import 'sync_queue_service.dart';
import 'sync_upload_service.dart';
import '../../features/courses/data/course_repository.dart';
import '../../features/courses/data/semester_repository.dart';
import '../../features/schedule/data/day_schedule_repository.dart';
import '../../features/planning/data/course_occurrence_snapshot.dart';
import '../../features/planning/data/task_occurrence_publish_service.dart';
import '../../features/planning/data/task_occurrence_remote.dart';
import '../../features/planning/data/task_occurrence_snapshot.dart';
import '../holiday/holiday_providers.dart';

final syncApplyScopeProvider = Provider<SyncApplyScope>((ref) {
  return SyncApplyScope();
});

final syncQueueServiceProvider = Provider<SyncQueueService>(
  (ref) => SyncQueueService(
    ref.watch(appDatabaseProvider),
    applyScope: ref.watch(syncApplyScopeProvider),
  ),
);

final syncBootstrapServiceProvider = Provider<SyncBootstrapService>(
  (ref) => SyncBootstrapService(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueServiceProvider),
  ),
);

final offlineDataMergeServiceProvider = Provider<OfflineDataMergeService>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return OfflineDataMergeService(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueServiceProvider),
    remoteReader: client == null ? null : SupabaseSyncRemoteReader(client),
  );
});

final offlineDataSummaryProvider = FutureProvider<OfflineDataSummary>((ref) {
  return ref.watch(offlineDataMergeServiceProvider).summary();
});

final syncOperationHealthProvider = StreamProvider<SyncOperationHealth>((ref) {
  final userId = ref.watch(supabaseClientProvider)?.auth.currentUser?.id;
  if (userId == null) {
    return Stream.value(const SyncOperationHealth(pending: 0, failed: 0));
  }
  return ref.watch(syncQueueServiceProvider).watchHealthForUser(userId);
});

final syncFailureDiagnosticsProvider =
    StreamProvider<List<SyncFailureDiagnostic>>((ref) {
      final userId = ref.watch(supabaseClientProvider)?.auth.currentUser?.id;
      if (userId == null) return Stream.value(const []);
      return ref
          .watch(syncQueueServiceProvider)
          .watchFailureDiagnosticsForUser(userId);
    });

final syncUploadCoordinatorProvider = Provider<SyncUploadCoordinator?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  final database = ref.watch(appDatabaseProvider);
  final queue = ref.watch(syncQueueServiceProvider);
  final applyScope = ref.watch(syncApplyScopeProvider);
  final occurrenceRepository = DriftTaskOccurrenceSnapshotRepository(
    database: database,
    syncQueue: queue,
    holidayCalendar: ref.watch(holidayCalendarProvider),
  );
  final occurrencePublisher = TaskOccurrencePublishService(
    queue: queue,
    buildSnapshot: occurrenceRepository.build,
    remote: SupabaseTaskOccurrenceRemotePublisher(client),
    currentSyncEpoch: (userId) {
      if (!ref.mounted ||
          client.auth.currentSession?.user.id != userId ||
          applyScope.isApplying) {
        return null;
      }
      final status = ref.read(syncAccountStatusProvider);
      if (status.userId != userId ||
          !status.initialRestoreComplete ||
          (status.phase != SyncAccountPhase.synced &&
              (status.phase != SyncAccountPhase.syncing ||
                  status.stage != SyncAccountStage.upload))) {
        return null;
      }
      return status.restoreStartedAt;
    },
  );
  final remote = SupabaseSyncRemoteStore(client);
  final executor = SyncUploadExecutor(
    database: database,
    queue: queue,
    remote: remote,
    currentUserId: () => client.auth.currentUser?.id,
    publishTaskOccurrenceSnapshot: occurrencePublisher.publish,
    publishCourseOccurrenceSnapshot: (checkpoint) async {
      tzdata.initializeTimeZones();
      final now = tz.TZDateTime.now(tz.getLocation('Asia/Shanghai'));
      final from = DateTime(now.year, now.month, now.day);
      final through = from.add(
        Duration(days: DriftCourseOccurrenceSnapshotRepository.maximumDays - 1),
      );
      final snapshot = await DriftCourseOccurrenceSnapshotRepository(
        userId: checkpoint.userId,
        courses: CourseRepository(
          database: database,
          syncQueue: queue,
          userId: checkpoint.userId,
        ),
        semesters: SemesterRepository(
          database: database,
          syncQueue: queue,
          userId: checkpoint.userId,
        ),
        schedule: DayScheduleRepository(
          database: database,
          syncQueue: queue,
          userId: checkpoint.userId,
        ),
        syncQueue: queue,
      ).build(from: from, through: through);
      await remote.publishCourseOccurrenceSnapshot(
        userId: checkpoint.userId,
        deviceId: checkpoint.deviceId,
        snapshot: snapshot.toJson(),
      );
    },
  );
  final coordinator = SyncUploadCoordinator(executor, queue);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final syncDownloadCoordinatorProvider = Provider<SyncDownloadCoordinator?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return SyncDownloadCoordinator(
    SyncDownloadExecutor(
      database: ref.watch(appDatabaseProvider),
      remote: SupabaseSyncRemoteReader(client),
      applyScope: ref.watch(syncApplyScopeProvider),
      currentUserId: () => client.auth.currentUser?.id,
    ),
  );
});

final syncAccountCoordinatorProvider = Provider<SyncAccountCoordinator?>((ref) {
  final download = ref.watch(syncDownloadCoordinatorProvider);
  final upload = ref.watch(syncUploadCoordinatorProvider);
  if (download == null || upload == null) return null;
  return SyncAccountCoordinator(
    database: ref.watch(appDatabaseProvider),
    download: download,
    upload: upload,
    bootstrap: ref.watch(syncBootstrapServiceProvider),
    status: ref.read(syncAccountStatusProvider.notifier),
  );
});
