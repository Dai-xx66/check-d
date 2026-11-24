import '../../../core/sync/sync_queue_service.dart';
import 'task_occurrence_remote.dart';
import 'task_occurrence_snapshot.dart';

/// Publishes a snapshot only while the same owner's settled checkpoint remains
/// current. Acceptance by one RPC is separate from server planning readiness.
class TaskOccurrencePublishService {
  TaskOccurrencePublishService({
    required SyncQueueService queue,
    required Future<TaskOccurrenceSnapshot> Function(SyncDeviceCheckpoint)
    buildSnapshot,
    required TaskOccurrenceRemotePublisher remote,
    required Object? Function(String userId) currentSyncEpoch,
    Future<void> Function(Duration)? delay,
  }) : _queue = queue,
       _buildSnapshot = buildSnapshot,
       _remote = remote,
       _currentSyncEpoch = currentSyncEpoch,
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
  final Future<void> Function(Duration) _delay;

  // Rejecting a payload permanently shouldn't resend it every watermark tick.
  // Another generation or data/window version creates a new publication.
  final _rejections = <(String, String), (int, String, String, String)>{};
  final _published = <(String, String), (int, DateTime, Object)>{};

  Future<bool> publish(SyncDeviceCheckpoint checkpoint) async {
    final epoch = _currentSyncEpoch(checkpoint.userId);
    if (epoch == null) return false;
    if (!await _isCurrent(checkpoint, epoch)) return false;
    final ownerDevice = (checkpoint.userId, checkpoint.deviceId);
    final watermark = (checkpoint.localGeneration, checkpoint.updatedAt, epoch);
    if (_published[ownerDevice] == watermark) return true;
    final snapshot = await _buildSnapshot(checkpoint);
    if (snapshot.userId != checkpoint.userId ||
        snapshot.deviceId != checkpoint.deviceId ||
        snapshot.localGeneration != checkpoint.localGeneration) {
      return false;
    }
    final version = (
      checkpoint.localGeneration,
      snapshot.taskDataVersion,
      snapshot.fromDate,
      snapshot.throughDate,
    );
    if (_rejections[ownerDevice] == version) return false;

    final payload = snapshot.toJson();
    for (var attempt = 0; ; attempt++) {
      if (!await _isCurrent(checkpoint, epoch)) return false;
      try {
        await _remote.publish(
          userId: checkpoint.userId,
          deviceId: checkpoint.deviceId,
          snapshot: payload,
        );
        if (!await _isCurrent(checkpoint, epoch)) return false;
        _rejections.remove(ownerDevice);
        _published[ownerDevice] = watermark;
        return true;
      } on TaskOccurrencePublishFailure catch (error) {
        if (!await _isCurrent(checkpoint, epoch)) return false;
        if (!error.retryable) {
          _rejections[ownerDevice] = version;
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
