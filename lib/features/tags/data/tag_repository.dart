import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_queue_service.dart';

class TagRepository {
  TagRepository(this.database, this.userId, this.syncQueue);

  final AppDatabase database;
  final String userId;
  final SyncQueueService syncQueue;

  Stream<List<TagRecord>> watchTags() async* {
    await ensureDefaults();
    yield* (database.select(database.tagRecords)
          ..where((row) => row.userId.equals(userId))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .watch();
  }

  Future<void> ensureDefaults() => database.transaction(() async {
    final key = 'default-tags:$userId';
    final existing = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    if (existing != null) return;
    const defaults = [
      ('学习', 0xFF3D73E8),
      ('健康', 0xFF45A77A),
      ('阅读', 0xFFE69545),
      ('工作', 0xFF8267D9),
      ('运动', 0xFF3BA3AC),
      ('习惯', 0xFFD96060),
      ('生活', 0xFF768B45),
    ];
    final names =
        (await (database.select(
              database.tagRecords,
            )..where((row) => row.userId.equals(userId))).get())
            .map((tag) => tag.name)
            .toSet();
    for (final item in defaults) {
      if (!names.contains(item.$1)) {
        await save(name: item.$1, colorValue: item.$2);
      }
    }
    await database
        .into(database.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: key,
            value: '1',
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  });

  Future<String> save({
    String? id,
    required String name,
    required int colorValue,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 30 || clean == '其它') {
      throw ArgumentError('标签名称需要 1–30 个字，且不能使用保留名称“其它”');
    }
    return database.transaction(() async {
      final all = await (database.select(
        database.tagRecords,
      )..where((row) => row.userId.equals(userId))).get();
      final matches = all.where((tag) => tag.id == id);
      if (id != null && matches.isEmpty) throw StateError('标签不存在');
      if (all.any(
        (tag) => tag.id != id && tag.name.toLowerCase() == clean.toLowerCase(),
      )) {
        throw ArgumentError('标签名称已存在（包含已归档标签）');
      }
      final now = DateTime.now().toUtc();
      final tagId = id ?? const Uuid().v4();
      await database
          .into(database.tagRecords)
          .insertOnConflictUpdate(
            TagRecordsCompanion.insert(
              id: tagId,
              userId: userId,
              name: clean,
              colorValue: colorValue,
              archived: Value(matches.isNotEmpty && matches.first.archived),
              createdAt: matches.isEmpty ? now : matches.first.createdAt,
              updatedAt: now,
            ),
          );
      await _record(tagId);
      return tagId;
    });
  }

  Future<void> setArchived(String id, bool archived) => database.transaction(
    () async {
      final count =
          await (database.update(database.tagRecords)
                ..where((row) => row.id.equals(id) & row.userId.equals(userId)))
              .write(
                TagRecordsCompanion(
                  archived: Value(archived),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
      if (count != 1) throw StateError('标签不存在');
      await _record(id);
    },
  );

  Future<void> _record(String id) async {
    final tag =
        await (database.select(database.tagRecords)
              ..where((row) => row.id.equals(id) & row.userId.equals(userId)))
            .getSingle();
    final payload = <String, Object?>{
      'id': id,
      'user_id': userId,
      'name': tag.name,
      'color': tag.colorValue,
      'archived': tag.archived,
      'updated_at': tag.updatedAt.toIso8601String(),
    };
    final revisionId = const Uuid().v4();
    await database
        .into(database.tagRevisionRecords)
        .insert(
          TagRevisionRecordsCompanion.insert(
            id: revisionId,
            tagId: id,
            userId: userId,
            snapshotJson: jsonEncode(payload),
            changedAt: tag.updatedAt,
          ),
        );
    await syncQueue.enqueue(
      entityType: 'tags',
      entityId: id,
      operation: SyncOperationType.upsert,
      payload: payload,
      userId: userId,
    );
    await syncQueue.enqueue(
      entityType: 'tag_revisions',
      entityId: revisionId,
      operation: SyncOperationType.upsert,
      userId: userId,
      payload: {
        'id': revisionId,
        'user_id': userId,
        'tag_id': id,
        'snapshot_json': payload,
        'changed_at': tag.updatedAt.toIso8601String(),
      },
    );
  }
}
