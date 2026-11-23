import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../features/auth/presentation/auth_controller.dart';
import 'sync_apply_scope.dart';
import 'sync_account_service.dart';
import 'sync_bootstrap_service.dart';
import 'sync_download_service.dart';
import 'sync_queue_service.dart';
import 'sync_upload_service.dart';

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
  final userId = ref.watch(authenticatedUserIdProvider);
  if (userId == null) {
    return Stream.value(const SyncOperationHealth(pending: 0, failed: 0));
  }
  return ref.watch(syncQueueServiceProvider).watchHealthForUser(userId);
});

final syncFailureDiagnosticsProvider =
    StreamProvider<List<SyncFailureDiagnostic>>((ref) {
      final userId = ref.watch(authenticatedUserIdProvider);
      if (userId == null) return Stream.value(const []);
      return ref
          .watch(syncQueueServiceProvider)
          .watchFailureDiagnosticsForUser(userId);
    });

final syncUploadCoordinatorProvider = Provider<SyncUploadCoordinator?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  final executor = SyncUploadExecutor(
    database: ref.watch(appDatabaseProvider),
    queue: ref.watch(syncQueueServiceProvider),
    remote: SupabaseSyncRemoteStore(client),
    currentUserId: () => client.auth.currentUser?.id,
  );
  final coordinator = SyncUploadCoordinator(
    executor,
    ref.watch(syncQueueServiceProvider),
  );
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
