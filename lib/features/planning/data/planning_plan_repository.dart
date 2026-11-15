import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

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

/// Persists local confirmed plans only. It never queues a Supabase operation.
/// The owner is injected from CheckD's current data-owner provider, not input.
class PlanningPlanRepository {
  PlanningPlanRepository({
    required AppDatabase database,
    required String userId,
  }) : _database = database,
       _userId = userId;

  final AppDatabase _database;
  final String _userId;
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
              ),
            );
      }

      // Supersede currently confirmed local plans that overlap this date range;
      // their history and blocks remain available for review.
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
            ),
          );
      for (final block in blocks) {
        await _database
            .into(_database.plannedTimeBlockRecords)
            .insert(
              PlannedTimeBlockRecordsCompanion.insert(
                id: _uuid.v4(),
                userId: _userId,
                planVersionId: id,
                taskId: block.taskId,
                startsAt: block.startsAt.toUtc(),
                endsAt: block.endsAt.toUtc(),
                plannedSeconds: block.plannedSeconds,
              ),
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
                    row.planVersionId.equals(id) & row.userId.equals(_userId),
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
