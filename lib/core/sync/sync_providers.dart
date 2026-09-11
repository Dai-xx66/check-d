import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import 'sync_apply_scope.dart';
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
