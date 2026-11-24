import 'dart:convert';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/sync/sync_queue_service.dart';
import 'package:check_d/features/planning/data/task_occurrence_publish_service.dart';
import 'package:check_d/features/planning/data/task_occurrence_remote.dart';
import 'package:check_d/features/planning/data/task_occurrence_snapshot.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = 'd1d151a5-8612-4a04-ab5f-7a367ea4bd59';
  late AppDatabase database;
  late SyncQueueService queue;
  late SyncDeviceCheckpoint checkpoint;
  late _RecordingPublisher remote;
  late List<Duration> delays;
  late Object? syncEpoch;
  late String version;
  late TaskOccurrencePublishService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueueService(database);
    await queue.ensureDeviceState(owner);
    checkpoint = (await queue.settledCheckpoint(owner))!;
    await queue.markCheckpointAcknowledged(checkpoint);
    remote = _RecordingPublisher();
    delays = [];
    syncEpoch = 1;
    version = 'fixture-v1';
    service = TaskOccurrencePublishService(
      queue: queue,
      buildSnapshot: (checkpoint) async => TaskOccurrenceSnapshot(
        userId: checkpoint.userId,
        deviceId: checkpoint.deviceId,
        localGeneration: checkpoint.localGeneration,
        fromDate: '2026-11-24',
        throughDate: '2026-12-24',
        generatedAt: DateTime.utc(2026, 11, 24, 3),
        taskDataVersion: version,
        occurrences: const [],
      ),
      remote: remote,
      currentSyncEpoch: (userId) => userId == owner ? syncEpoch : null,
      delay: (duration) async => delays.add(duration),
    );
  });

  tearDown(() => database.close());

  test('retries only transient failures with identical RPC payload', () async {
    remote.failures.addAll(const [
      TaskOccurrencePublishFailure('network', retryable: true),
      TaskOccurrencePublishFailure('server', retryable: true),
    ]);

    expect(await service.publish(checkpoint), isTrue);
    expect(remote.requests, hasLength(3));
    expect(remote.requests.toSet(), hasLength(1));
    expect(delays, [
      const Duration(milliseconds: 250),
      const Duration(seconds: 1),
    ]);
  });

  test(
    'permanent rejection is retried only for a changed publication',
    () async {
      remote.failures.add(const TaskOccurrencePublishFailure('22023'));

      expect(await service.publish(checkpoint), isFalse);
      expect(await service.publish(checkpoint), isFalse);
      expect(remote.requests, hasLength(1));
      expect(delays, isEmpty);

      version = 'fixture-v2';
      expect(await service.publish(checkpoint), isTrue);
      expect(remote.requests, hasLength(2));
    },
  );

  test(
    'an unsettled generation cannot be retried after an in-flight edit',
    () async {
      remote.onRequest = () => queue.enqueue(
        entityType: 'tasks',
        entityId: 'local-edit',
        operation: SyncOperationType.upsert,
        payload: const {'id': 'local-edit'},
        userId: owner,
      );
      remote.failures.add(
        const TaskOccurrencePublishFailure('server', retryable: true),
      );

      expect(await service.publish(checkpoint), isFalse);
      expect(remote.requests, hasLength(1));
    },
  );

  test(
    'account change or a new restore invalidates an in-flight result',
    () async {
      remote.onRequest = () async {
        syncEpoch = 2;
      };

      expect(await service.publish(checkpoint), isFalse);
      expect(remote.requests, hasLength(1));

      syncEpoch = null;
      expect(await service.publish(checkpoint), isFalse);
      expect(remote.requests, hasLength(1));
    },
  );
}

class _RecordingPublisher implements TaskOccurrenceRemotePublisher {
  final failures = <TaskOccurrencePublishFailure>[];
  final requests = <String>[];
  Future<void> Function()? onRequest;

  @override
  Future<TaskOccurrencePublishReceipt> publish({
    required String userId,
    required String deviceId,
    required Map<String, Object?> snapshot,
  }) async {
    requests.add(
      jsonEncode({'user': userId, 'device': deviceId, 'snapshot': snapshot}),
    );
    await onRequest?.call();
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return const TaskOccurrencePublishReceipt(
      serverDataVersion: 12,
      occurrenceDigest:
          '1111111111111111111111111111111111111111111111111111111111111111',
    );
  }
}
