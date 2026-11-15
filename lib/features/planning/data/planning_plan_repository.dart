import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_queue_service.dart';

enum LocalPlanStatus { draft, confirmed, applied, superseded, failed }

class CandidatePlanBlock {
  const CandidatePlanBlock({
    required this.taskId,
    required this.startsAt,
    required this.endsAt,
    required this.plannedSeconds,
  });

  final String taskId;
  final DateTime startsAt;
  final DateTime endsAt;
  final int plannedSeconds;
}

class LocalPlanSnapshotChanged implements Exception {
  const LocalPlanSnapshotChanged();
}

class LocalPlanInputInvalid implements Exception {
  const LocalPlanInputInvalid(this.message);
  final String message;
}

class LocalPlanIdempotencyConflict implements Exception {
  const LocalPlanIdempotencyConflict();
}

class SavedLocalPlan {
  const SavedLocalPlan({
    required this.id,
    required this.revision,
    required this.status,
    required this.sourceSnapshotVersion,
    required this.createdAt,
    required this.blocks,
  });

  final String id;
  final int revision;
  final LocalPlanStatus status;
  final String sourceSnapshotVersion;
  final DateTime createdAt;
  final List<CandidatePlanBlock> blocks;
}

/// Persists confirmed plans in Drift first. When the existing sync queue is
/// supplied, matching outbox operations are committed in the same database
/// transaction; this is sync intent, not server approval or cloud execution.
/// The owner is injected from CheckD's current data-owner provider, not input.
class PlanningPlanRepository {
  PlanningPlanRepository({
    required AppDatabase database,
    required String userId,
    SyncQueueService? syncQueue,
  }) : _database = database,
       _userId = userId,
       _syncQueue = syncQueue;

  final AppDatabase _database;
  final String _userId;
  final SyncQueueService? _syncQueue;
  static const _uuid = Uuid();

  Future<SavedLocalPlan> confirmPlan({
    required String expectedSnapshotVersion,
    required Future<String> Function() readCurrentSnapshotVersion,
    required DateTime startsOn,
    required DateTime endsOn,
    required String rulesVersion,
    required List<CandidatePlanBlock> blocks,
    Map<String, int> confirmedRemainingSeconds = const {},
    DateTime? now,
  }) async {
    if (_userId.trim().isEmpty) {
      throw const LocalPlanInputInvalid('owner_required');
    }
    if (blocks.isEmpty || endsOn.isBefore(startsOn)) {
      throw const LocalPlanInputInvalid('plan_range_or_blocks_invalid');
    }
    final instant = (now ?? DateTime.now()).toUtc();
    for (final block in blocks) {
      if (block.taskId.isEmpty ||
          block.endsAt.isBefore(block.startsAt) ||
          block.endsAt.isAtSameMomentAs(block.startsAt) ||
          block.plannedSeconds <= 0 ||
          !block.startsAt.isAfter(instant)) {
        throw const LocalPlanInputInvalid('block_invalid_or_in_past');
      }
    }
    final digest = _digest(
      jsonEncode({
        'snapshot': expectedSnapshotVersion,
        'rules': rulesVersion,
        'starts_on': _date(startsOn),
        'ends_on': _date(endsOn),
        'blocks': blocks
            .map(
              (block) => {
                'task_id': block.taskId,
                'starts_at': block.startsAt.toUtc().toIso8601String(),
                'ends_at': block.endsAt.toUtc().toIso8601String(),
                'planned_seconds': block.plannedSeconds,
              },
            )
            .toList(),
        'remaining_seconds': confirmedRemainingSeconds,
      }),
    );
    final idempotencyKey = 'local-plan-$digest';

    return _database.transaction(() async {
      // Resolve a retry first: an earlier successful save may itself have
      // persisted explicitly confirmed effort, changing the next snapshot.
      final existing =
          await (_database.select(_database.taskPlanVersionRecords)..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.idempotencyKey.equals(idempotencyKey),
              ))
              .getSingleOrNull();
      if (existing != null) {
        if (existing.proposalDigest != digest) {
          throw const LocalPlanIdempotencyConflict();
        }
        return _readPlan(existing.id);
      }

      final currentVersion = await readCurrentSnapshotVersion();
      if (currentVersion != expectedSnapshotVersion) {
        throw const LocalPlanSnapshotChanged();
      }

      final sortedBlocks = [...blocks]
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      for (var index = 1; index < sortedBlocks.length; index++) {
        if (sortedBlocks[index].startsAt.isBefore(
          sortedBlocks[index - 1].endsAt,
        )) {
          throw const LocalPlanInputInvalid('candidate_blocks_overlap');
        }
      }

      // Validate ownership from the same local transaction as the write.
      final taskIds = blocks.map((block) => block.taskId).toSet();
      for (final taskId in taskIds) {
        final task =
            await (_database.select(_database.localTasks)..where(
                  (row) =>
                      row.id.equals(taskId) &
                      row.userId.equals(_userId) &
                      row.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (task == null) {
          throw const LocalPlanInputInvalid('task_not_found_for_owner');
        }
      }

      final previous = await (_database.select(
        _database.taskPlanVersionRecords,
      )..where((row) => row.userId.equals(_userId))).get();
      final revision = previous.isEmpty
          ? 1
          : previous
                    .map((row) => row.revision)
                    .reduce((a, b) => a > b ? a : b) +
                1;
      final id = _uuid.v4();
      final createdAt = instant;

      for (final entry in confirmedRemainingSeconds.entries) {
        if (!taskIds.contains(entry.key) || entry.value <= 0) {
          throw const LocalPlanInputInvalid('effort_value_invalid');
        }
        await _database
            .into(_database.taskEffortRecords)
            .insertOnConflictUpdate(
              TaskEffortRecordsCompanion.insert(
                taskId: entry.key,
                userId: _userId,
                estimatedSeconds: const Value.absent(),
                remainingSeconds: Value(entry.value),
                source: 'user_confirmed',
                updatedAt: createdAt,
                deletedAt: const Value(null),
              ),
            );
        await _syncQueue?.enqueue(
          entityType: 'task_effort_estimates',
          entityId: entry.key,
          operation: SyncOperationType.upsert,
          payload: {'task_id': entry.key},
          userId: _userId,
        );
      }

      // Supersede currently confirmed local plans that overlap this date range;
      // their history and blocks remain available for review.
      final overlappingConfirmed =
          await (_database.select(_database.taskPlanVersionRecords)..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.status.equals(LocalPlanStatus.confirmed.name) &
                    row.startsOn.isSmallerOrEqualValue(_date(endsOn)) &
                    row.endsOn.isBiggerOrEqualValue(_date(startsOn)),
              ))
              .get();
      await (_database.update(_database.taskPlanVersionRecords)..where(
            (row) =>
                row.userId.equals(_userId) &
                row.status.equals(LocalPlanStatus.confirmed.name) &
                row.startsOn.isSmallerOrEqualValue(_date(endsOn)) &
                row.endsOn.isBiggerOrEqualValue(_date(startsOn)),
          ))
          .write(
            TaskPlanVersionRecordsCompanion(
              status: Value(LocalPlanStatus.superseded.name),
            ),
          );
      for (final previous in overlappingConfirmed) {
        await _syncQueue?.enqueue(
          entityType: 'task_plan_versions',
          entityId: previous.id,
          operation: SyncOperationType.upsert,
          payload: {'id': previous.id},
          userId: _userId,
        );
      }

      await _database
          .into(_database.taskPlanVersionRecords)
          .insert(
            TaskPlanVersionRecordsCompanion.insert(
              id: id,
              userId: _userId,
              revision: revision,
              sourceSnapshotVersion: expectedSnapshotVersion,
              proposalDigest: digest,
              rulesVersion: rulesVersion,
              startsOn: _date(startsOn),
              endsOn: _date(endsOn),
              status: LocalPlanStatus.confirmed.name,
              idempotencyKey: idempotencyKey,
              createdAt: createdAt,
              confirmedAt: Value(createdAt),
              supersedesVersionIdsJson: Value(
                jsonEncode(overlappingConfirmed.map((row) => row.id).toList()),
              ),
            ),
          );
      await _syncQueue?.enqueue(
        entityType: 'task_plan_versions',
        entityId: id,
        operation: SyncOperationType.upsert,
        payload: {'id': id},
        userId: _userId,
      );
      for (final block in blocks) {
        final blockId = _uuid.v4();
        await _database
            .into(_database.plannedTimeBlockRecords)
            .insert(
              PlannedTimeBlockRecordsCompanion.insert(
                id: blockId,
                userId: _userId,
                planVersionId: id,
                taskId: block.taskId,
                startsAt: block.startsAt.toUtc(),
                endsAt: block.endsAt.toUtc(),
                plannedSeconds: block.plannedSeconds,
              ),
            );
        await _syncQueue?.enqueue(
          entityType: 'task_time_blocks',
          entityId: blockId,
          operation: SyncOperationType.upsert,
          payload: {'id': blockId},
          userId: _userId,
        );
      }
      return _readPlan(id);
    });
  }

  Future<List<SavedLocalPlan>> loadPlans({
    required DateTime startsOnOrBefore,
    required DateTime endsOnOrAfter,
  }) async {
    final rows =
        await (_database.select(_database.taskPlanVersionRecords)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.status.isNotValue(LocalPlanStatus.superseded.name) &
                    row.startsOn.isSmallerOrEqualValue(_date(endsOnOrAfter)) &
                    row.endsOn.isBiggerOrEqualValue(_date(startsOnOrBefore)),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.revision)]))
            .get();
    return [for (final row in rows) await _readPlan(row.id)];
  }

  Future<List<PlanningSyncConflict>> loadUnresolvedSyncConflicts() =>
      (_database.select(_database.planningSyncConflicts)
            ..where(
              (row) =>
                  row.userId.equals(_userId) & row.status.equals('unresolved'),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .get();

  /// Resolves one owner-scoped conflict without discarding either captured
  /// payload. Choosing local queues that value for upload; choosing remote
  /// applies the captured remote value and removes stale local outbox entries.
  Future<bool> resolveSyncConflict({
    required String conflictId,
    required String resolution,
    DateTime? now,
  }) async {
    if (resolution != 'keep_local' && resolution != 'keep_remote') {
      throw ArgumentError.value(resolution, 'resolution');
    }
    final resolvedAt = (now ?? DateTime.now()).toUtc();
    return _database.transaction(() async {
      final conflict =
          await (_database.select(_database.planningSyncConflicts)..where(
                (row) =>
                    row.id.equals(conflictId) &
                    row.userId.equals(_userId) &
                    row.status.equals('unresolved'),
              ))
              .getSingleOrNull();
      if (conflict == null) return false;

      if (resolution == 'keep_local') {
        final syncQueue = _syncQueue;
        if (syncQueue == null) return false;
        final exists = await _hasLocalConflictEntity(conflict);
        if (!exists) return false;
        await syncQueue.enqueue(
          entityType: conflict.entityType,
          entityId: conflict.entityId,
          operation: SyncOperationType.upsert,
          payload: conflict.entityType == 'planned_block_timer_links'
              ? _linkPayload(conflict.localPayloadJson)
              : {'id': conflict.entityId},
          userId: _userId,
        );
      } else {
        final remote =
            jsonDecode(conflict.remotePayloadJson) as Map<String, dynamic>;
        await _applyRemoteConflict(conflict, remote, resolvedAt);
        await (_database.delete(_database.syncOperations)..where(
              (op) =>
                  op.userId.equals(_userId) &
                  op.entityType.equals(conflict.entityType) &
                  op.entityId.equals(conflict.entityId) &
                  (op.status.equals('pending') | op.status.equals('failed')),
            ))
            .go();
      }

      await (_database.update(_database.planningSyncConflicts)..where(
            (row) => row.id.equals(conflictId) & row.userId.equals(_userId),
          ))
          .write(
            PlanningSyncConflictsCompanion(
              status: const Value('resolved'),
              resolution: Value(resolution),
              resolvedAt: Value(resolvedAt),
            ),
          );
      return true;
    });
  }

  Future<bool> _hasLocalConflictEntity(PlanningSyncConflict conflict) async {
    switch (conflict.entityType) {
      case 'task_effort_estimates':
        return await (_database.select(_database.taskEffortRecords)..where(
                  (row) =>
                      row.userId.equals(_userId) &
                      row.taskId.equals(conflict.entityId),
                ))
                .getSingleOrNull() !=
            null;
      case 'task_plan_versions':
        return await (_database.select(_database.taskPlanVersionRecords)..where(
                  (row) =>
                      row.userId.equals(_userId) &
                      row.id.equals(conflict.entityId),
                ))
                .getSingleOrNull() !=
            null;
      case 'task_time_blocks':
        return await (_database.select(_database.plannedTimeBlockRecords)
                  ..where(
                    (row) =>
                        row.userId.equals(_userId) &
                        row.id.equals(conflict.entityId),
                  ))
                .getSingleOrNull() !=
            null;
      case 'planned_block_timer_links':
        final ids = conflict.entityId.split(':');
        if (ids.length != 2) return false;
        return await (_database.select(_database.plannedBlockTimerLinks)..where(
                  (row) =>
                      row.userId.equals(_userId) &
                      row.plannedBlockId.equals(ids[0]) &
                      row.timerSessionId.equals(ids[1]),
                ))
                .getSingleOrNull() !=
            null;
      default:
        return false;
    }
  }

  Future<void> _applyRemoteConflict(
    PlanningSyncConflict conflict,
    Map<String, dynamic> row,
    DateTime resolvedAt,
  ) async {
    DateTime? date(String key) {
      final value = row[key] ?? row[_camel(key)];
      if (value is! String || value.isEmpty) return null;
      return DateTime.parse(value).toUtc();
    }

    int? integer(String key) {
      final value = row[key] ?? row[_camel(key)];
      return value is num ? value.toInt() : null;
    }

    String? string(String key) {
      final value = row[key] ?? row[_camel(key)];
      return value is String ? value : null;
    }

    switch (conflict.entityType) {
      case 'task_effort_estimates':
        final taskId = string('task_id') ?? conflict.entityId;
        final updatedAt = date('updated_at');
        if (updatedAt == null) {
          throw const FormatException('updated_at missing');
        }
        await _database
            .into(_database.taskEffortRecords)
            .insertOnConflictUpdate(
              TaskEffortRecordsCompanion.insert(
                userId: _userId,
                taskId: taskId,
                estimatedSeconds: Value(integer('estimated_seconds')),
                remainingSeconds: Value(integer('remaining_seconds')),
                source: string('source') ?? 'remote_conflict_resolution',
                updatedAt: updatedAt,
                deletedAt: Value(date('deleted_at')),
              ),
            );
      case 'task_plan_versions':
        final id = string('id') ?? conflict.entityId;
        final createdAt = date('created_at');
        if (createdAt == null) {
          throw const FormatException('created_at missing');
        }
        final supersedes =
            row['supersedes_version_ids'] ?? row['supersedesVersionIdsJson'];
        await _database
            .into(_database.taskPlanVersionRecords)
            .insertOnConflictUpdate(
              TaskPlanVersionRecordsCompanion.insert(
                id: id,
                userId: _userId,
                revision: integer('revision') ?? 1,
                sourceSnapshotVersion: string('source_snapshot_version') ?? '',
                proposalDigest: string('proposal_digest') ?? '',
                rulesVersion: string('rules_version') ?? '',
                startsOn: string('starts_on') ?? '',
                endsOn: string('ends_on') ?? '',
                status: string('status') ?? LocalPlanStatus.confirmed.name,
                idempotencyKey: string('idempotency_key') ?? '',
                createdAt: createdAt,
                confirmedAt: Value(date('confirmed_at')),
                appliedAt: Value(date('applied_at')),
                supersedesVersionIdsJson: Value(
                  supersedes is String
                      ? supersedes
                      : jsonEncode(supersedes ?? []),
                ),
              ),
            );
      case 'task_time_blocks':
        final id = string('id') ?? conflict.entityId;
        final startsAt = date('starts_at');
        final endsAt = date('ends_at');
        if (startsAt == null || endsAt == null) {
          throw const FormatException('block interval missing');
        }
        await _database
            .into(_database.plannedTimeBlockRecords)
            .insertOnConflictUpdate(
              PlannedTimeBlockRecordsCompanion.insert(
                id: id,
                userId: _userId,
                planVersionId: string('plan_version_id') ?? '',
                taskId: string('task_id') ?? '',
                startsAt: startsAt,
                endsAt: endsAt,
                plannedSeconds:
                    integer('planned_seconds') ??
                    endsAt.difference(startsAt).inSeconds,
                deletedAt: Value(date('deleted_at')),
              ),
            );
      case 'planned_block_timer_links':
        final blockId = string('planned_block_id');
        final timerId = string('timer_session_id');
        final linkedAt = date('linked_at') ?? resolvedAt;
        if (blockId == null || timerId == null) {
          throw const FormatException('timer link identifiers missing');
        }
        await _database
            .into(_database.plannedBlockTimerLinks)
            .insertOnConflictUpdate(
              PlannedBlockTimerLinksCompanion.insert(
                userId: _userId,
                plannedBlockId: blockId,
                timerSessionId: timerId,
                linkedAt: linkedAt,
              ),
            );
      default:
        throw StateError('unsupported planning conflict type');
    }
  }

  Map<String, Object?> _linkPayload(String json) {
    final row = jsonDecode(json) as Map<String, dynamic>;
    return {
      'planned_block_id': row['planned_block_id'] ?? row['plannedBlockId'],
      'timer_session_id': row['timer_session_id'] ?? row['timerSessionId'],
    };
  }

  String _camel(String key) {
    final parts = key.split('_');
    return parts.first +
        parts
            .skip(1)
            .map(
              (part) => part.isEmpty
                  ? ''
                  : '${part[0].toUpperCase()}${part.substring(1)}',
            )
            .join();
  }

  /// Tombstones a block instead of physically deleting it, so a later sync
  /// cannot resurrect it from another device's stale snapshot.
  Future<bool> tombstoneBlock(String blockId, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    return _database.transaction(() async {
      final row =
          await (_database.select(_database.plannedTimeBlockRecords)..where(
                (block) =>
                    block.id.equals(blockId) &
                    block.userId.equals(_userId) &
                    block.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (row == null) return false;
      await (_database.update(_database.plannedTimeBlockRecords)..where(
            (block) => block.id.equals(blockId) & block.userId.equals(_userId),
          ))
          .write(PlannedTimeBlockRecordsCompanion(deletedAt: Value(at)));
      await _syncQueue?.enqueue(
        entityType: 'task_time_blocks',
        entityId: blockId,
        operation: SyncOperationType.upsert,
        payload: {'id': blockId, 'deleted_at': at.toIso8601String()},
        userId: _userId,
      );
      return true;
    });
  }

  /// Links an immutable actual TimerSession to its planned block, if known.
  Future<void> linkTimerSession({
    required String plannedBlockId,
    required String timerSessionId,
    DateTime? linkedAt,
  }) async {
    await _database.transaction(() async {
      final block =
          await (_database.select(_database.plannedTimeBlockRecords)..where(
                (row) =>
                    row.id.equals(plannedBlockId) & row.userId.equals(_userId),
              ))
              .getSingleOrNull();
      final timer =
          await (_database.select(_database.timerSessionRecords)..where(
                (row) =>
                    row.id.equals(timerSessionId) & row.userId.equals(_userId),
              ))
              .getSingleOrNull();
      if (block == null || timer == null) {
        throw const LocalPlanInputInvalid('timer_or_block_not_found_for_owner');
      }
      await _database
          .into(_database.plannedBlockTimerLinks)
          .insertOnConflictUpdate(
            PlannedBlockTimerLinksCompanion.insert(
              userId: _userId,
              plannedBlockId: plannedBlockId,
              timerSessionId: timerSessionId,
              linkedAt: linkedAt ?? DateTime.now().toUtc(),
            ),
          );
      await _syncQueue?.enqueue(
        entityType: 'planned_block_timer_links',
        entityId: '$plannedBlockId:$timerSessionId',
        operation: SyncOperationType.upsert,
        payload: {
          'planned_block_id': plannedBlockId,
          'timer_session_id': timerSessionId,
        },
        userId: _userId,
      );
    });
  }

  Future<SavedLocalPlan> _readPlan(String id) async {
    final version =
        await (_database.select(_database.taskPlanVersionRecords)
              ..where((row) => row.id.equals(id) & row.userId.equals(_userId)))
            .getSingle();
    final blocks =
        await (_database.select(_database.plannedTimeBlockRecords)
              ..where(
                (row) =>
                    row.planVersionId.equals(id) &
                    row.userId.equals(_userId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.startsAt)]))
            .get();
    return SavedLocalPlan(
      id: version.id,
      revision: version.revision,
      status: LocalPlanStatus.values.byName(version.status),
      sourceSnapshotVersion: version.sourceSnapshotVersion,
      createdAt: version.createdAt,
      blocks: [
        for (final block in blocks)
          CandidatePlanBlock(
            taskId: block.taskId,
            startsAt: block.startsAt,
            endsAt: block.endsAt,
            plannedSeconds: block.plannedSeconds,
          ),
      ],
    );
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _digest(String value) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
