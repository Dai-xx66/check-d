import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import 'sync_queue_service.dart';

final syncQueueServiceProvider = Provider<SyncQueueService>(
  (ref) => SyncQueueService(ref.watch(appDatabaseProvider)),
);
