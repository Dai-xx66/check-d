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
            createdAt: now,
            updatedAt: now,
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
