import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'sync_apply_scope.dart';

enum SyncOperationType { upsert, archive }

class SyncQueueService {
  SyncQueueService(this._database, {SyncApplyScope? applyScope})
    : _applyScope = applyScope;

  final AppDatabase _database;
  final SyncApplyScope? _applyScope;
  final Uuid _uuid = const Uuid();

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperationType operation,
    required Map<String, Object?> payload,
    String? userId,
  }) async {
    if (_applyScope?.isApplying ?? false) return;
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      int? generation;
      if (userId != null && userId.trim().isNotEmpty) {
        final current = await (_database.select(
          _database.syncDeviceStates,
        )..where((row) => row.userId.equals(userId))).getSingleOrNull();
        final next = (current?.localGeneration ?? 0) + 1;
        final deviceId = current?.deviceId ?? _uuid.v4();
        await _database
            .into(_database.syncDeviceStates)
            .insertOnConflictUpdate(
              SyncDeviceStatesCompanion.insert(
                userId: userId,
                deviceId: deviceId,
                localGeneration: Value(next),
                acknowledgedGeneration: Value(
                  current?.acknowledgedGeneration ?? 0,
                ),
                serverAcknowledgedGeneration: Value(
                  current?.serverAcknowledgedGeneration ?? 0,
                ),
                updatedAt: now,
              ),
            );
        generation = next;
      }
      await _database
          .into(_database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(userId),
              entityType: entityType,
              entityId: entityId,
              operation: operation.name,
              payloadJson: jsonEncode(payload),
              localGeneration: Value(generation),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  Future<DeviceSyncWatermark?> nextServerAcknowledgement(String userId) async {
    final state = await (_database.select(
      _database.syncDeviceStates,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    if (state == null) return null;
    final unsettled =
        await (_database.select(_database.syncOperations)
              ..where(
                (row) =>
                    row.userId.equals(userId) &
                    (row.status.equals('pending') |
                        row.status.equals('failed')),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.localGeneration)]))
            .get();
    if (unsettled.any((operation) => operation.localGeneration == null)) {
      return null;
    }
    final candidate = unsettled.isEmpty
        ? state.localGeneration
        : (unsettled.first.localGeneration! - 1)
              .clamp(state.serverAcknowledgedGeneration, state.localGeneration)
              .toInt();
    if (candidate <= state.serverAcknowledgedGeneration) return null;
    return DeviceSyncWatermark(
      userId: userId,
      deviceId: state.deviceId,
      generation: candidate,
    );
  }

  Future<void> markServerAcknowledged(DeviceSyncWatermark watermark) async {
    await (_database.update(
      _database.syncDeviceStates,
    )..where((row) => row.userId.equals(watermark.userId))).write(
      SyncDeviceStatesCompanion(
        serverAcknowledgedGeneration: Value(watermark.generation),
        acknowledgedGeneration: Value(watermark.generation),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Stream<List<SyncOperation>> watchPending() {
    final query = _database.select(_database.syncOperations)
      ..where((row) => row.status.equals('pending'))
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query.watch();
  }

  Future<List<SyncOperation>> loadRetryableForUser(
    String userId, {
    int limit = 100,
  }) {
    final query = _database.select(_database.syncOperations)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (row.status.equals('pending') | row.status.equals('failed')),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Stream<List<SyncOperation>> watchRetryableForUser(String userId) {
    final query = _database.select(_database.syncOperations)
      ..where(
        (row) =>
            row.userId.equals(userId) &
            (row.status.equals('pending') | row.status.equals('failed')),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query.watch();
  }

  Future<void> markCompleted(String operationId) {
    final now = DateTime.now().toUtc();
    return (_database.update(
      _database.syncOperations,
    )..where((row) => row.id.equals(operationId))).write(
      SyncOperationsCompanion(
        status: const Value('completed'),
        lastError: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> markFailed(String operationId, Object error) {
    final now = DateTime.now().toUtc();
    final message = error.toString();
    return (_database.update(
      _database.syncOperations,
    )..where((row) => row.id.equals(operationId))).write(
      SyncOperationsCompanion.custom(
        status: const Constant('failed'),
        retryCount: const CustomExpression<int>('retry_count + 1'),
        lastError: Variable<String>(
          message.length > 500 ? message.substring(0, 500) : message,
        ),
        updatedAt: Variable<DateTime>(now),
      ),
    );
  }
}

class DeviceSyncWatermark {
  const DeviceSyncWatermark({
    required this.userId,
    required this.deviceId,
    required this.generation,
  });

  final String userId;
  final String deviceId;
  final int generation;
}
