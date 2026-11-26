import 'dart:developer' as developer;

import '../../../core/sync/sync_queue_service.dart';
import 'task_occurrence_remote.dart';
import 'task_occurrence_snapshot.dart';

/// Acceptance by the occurrence RPC is separate from server planning readiness.
class TaskOccurrencePublishService {
  TaskOccurrencePublishService({
    required SyncQueueService queue,
    required Future<TaskOccurrenceSnapshot> Function(SyncDeviceCheckpoint)
    buildSnapshot,
    required TaskOccurrenceRemotePublisher remote,
    required Object? Function(String userId) currentSyncEpoch,
    Future<int?> Function(SyncDeviceCheckpoint)? readCheckpointVersion,
    Future<void> Function(Duration)? delay,
  }) : _queue = queue,
       _buildSnapshot = buildSnapshot,
       _remote = remote,
       _currentSyncEpoch = currentSyncEpoch,
       _readCheckpointVersion = readCheckpointVersion,
       _delay = delay ?? Future<void>.delayed;

  static const _retryDelays = [
    Duration(milliseconds: 250),
    Duration(seconds: 1),
  ];

  final SyncQueueService _queue;
  final Future<TaskOccurrenceSnapshot> Function(SyncDeviceCheckpoint)
  _buildSnapshot;
  final TaskOccurrenceRemotePublisher _remote;
  final Object? Function(String userId) _currentSyncEpoch;
  final Future<int?> Function(SyncDeviceCheckpoint)? _readCheckpointVersion;
  final Future<void> Function(Duration) _delay;

  // A refresh of the same device ACK is not a new local generation or restore.
  // Do not relabel the same published input at a different server version.
  final _observed = <(String, String), (int, Object, bool)>{};
  final _rejections = <(String, String), (int, String, String, String)>{};

  Future<bool> publish(SyncDeviceCheckpoint checkpoint) async {
    final epoch = _currentSyncEpoch(checkpoint.userId);
    if (epoch == null || !await _isCurrent(checkpoint, epoch)) return false;
    final ownerDevice = (checkpoint.userId, checkpoint.deviceId);
    final observed = _observed[ownerDevice];
    if (observed != null &&
        observed.$1 == checkpoint.localGeneration &&
        observed.$2 == epoch) {
      return observed.$3;
    }
    final snapshot = await _buildSnapshot(checkpoint);
    if (snapshot.userId != checkpoint.userId ||
        snapshot.deviceId != checkpoint.deviceId ||
        snapshot.localGeneration != checkpoint.localGeneration ||
        !snapshot.hasRecurringTasks) {
      return false;
    }
    final inputVersion = (
      checkpoint.localGeneration,
      snapshot.taskDataVersion,
      snapshot.fromDate,
      snapshot.throughDate,
    );
    if (_rejections[ownerDevice] == inputVersion) return false;

    final missingTiming = snapshot.omissions.entries
        .where(
          (entry) => switch (entry.key) {
            TaskOccurrenceOmissionReason.missingPlannedStart ||
            TaskOccurrenceOmissionReason.missingPlannedEnd ||
            TaskOccurrenceOmissionReason.missingPlannedStartAndEnd => true,
            _ => false,
          },
        )
        .map((entry) => '${entry.key.name}=${entry.value}')
        .join(', ');
    if (missingTiming.isNotEmpty) {
      developer.log(missingTiming, name: 'checkd.task_occurrence');
    }

    final readVersion = _readCheckpointVersion;
    final expectedVersion = await readVersion?.call(checkpoint);
    if (readVersion != null && expectedVersion == null) return false;
    final payload = snapshot.toJson();

    for (var attempt = 0; ; attempt++) {
      if (attempt > 0 &&
          readVersion != null &&
          await readVersion(checkpoint) != expectedVersion) {
        return false;
      }
      if (!await _isCurrent(checkpoint, epoch)) return false;
      try {
        final receipt = await _remote.publish(
          userId: checkpoint.userId,
          deviceId: checkpoint.deviceId,
          snapshot: payload,
        );
        if (!await _isCurrent(checkpoint, epoch)) return false;
        final matchesVersion =
            expectedVersion == null ||
            receipt.serverDataVersion == expectedVersion;
        _observed[ownerDevice] = (
          checkpoint.localGeneration,
          epoch,
          matchesVersion,
        );
        if (!matchesVersion) return false;
        _rejections.remove(ownerDevice);
        developer.log(
          'server_data_version=${receipt.serverDataVersion} '
          'occurrence_digest=${receipt.occurrenceDigest}',
          name: 'checkd.task_occurrence',
        );
        return true;
      } on TaskOccurrencePublishFailure catch (error) {
        if (!await _isCurrent(checkpoint, epoch)) return false;
        if (!error.retryable) {
          _rejections[ownerDevice] = inputVersion;
          return false;
        }
        if (attempt == _retryDelays.length) return false;
        await _delay(_retryDelays[attempt]);
      }
    }
  }

  Future<bool> _isCurrent(SyncDeviceCheckpoint checkpoint, Object epoch) async {
    if (_currentSyncEpoch(checkpoint.userId) != epoch) return false;
    final latest = await _queue.settledCheckpoint(checkpoint.userId);
    return _currentSyncEpoch(checkpoint.userId) == epoch &&
        latest != null &&
        latest.deviceId == checkpoint.deviceId &&
        latest.localGeneration == checkpoint.localGeneration &&
        latest.acknowledgedGeneration == checkpoint.localGeneration;
  }
}
