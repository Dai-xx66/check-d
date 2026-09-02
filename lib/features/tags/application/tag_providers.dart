import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/tag_repository.dart';

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(currentDataOwnerProvider),
    ref.watch(syncQueueServiceProvider),
  ),
);

final tagsProvider = StreamProvider.autoDispose<List<TagRecord>>(
  (ref) => ref.watch(tagRepositoryProvider).watchTags(),
);
