import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

enum SyncOperationType { upsert, archive }

class SyncQueueService {
  SyncQueueService(this._database);

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperationType operation,
    required Map<String, Object?> payload,
    String? userId,
  }) async {
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
}
