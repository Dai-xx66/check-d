import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'sync_download_service.dart';
import 'sync_owner_references.dart';
import 'sync_queue_service.dart';

const offlineDataOwner = 'offline-user';

class SyncBootstrapResult {
  const SyncBootstrapResult({
    required this.operationsCreated,
    required this.alreadyCompleted,
  });

  final int operationsCreated;
  final bool alreadyCompleted;
}

class OfflineDataSummary {
  const OfflineDataSummary({
    required this.courses,
    required this.tasks,
    required this.timerSessions,
    required this.completions,
    required this.otherRecords,
  });

  final int courses;
  final int tasks;
  final int timerSessions;
  final int completions;
  final int otherRecords;

  int get total => courses + tasks + timerSessions + completions + otherRecords;
  bool get isEmpty => total == 0;
}

class OfflineDataConflict implements Exception {
  const OfflineDataConflict(this.message);

  final String message;

  @override
  String toString() => message;
}

class SyncBootstrapService {
  SyncBootstrapService(this._database, this._queue);

  static const version = 1;

  final AppDatabase _database;
  final SyncQueueService _queue;

  String _markerKey(String userId) => 'sync-bootstrap:$version:$userId';

  Future<SyncBootstrapResult> bootstrap(String userId) async {
    if (userId.isEmpty || userId == offlineDataOwner) {
      return const SyncBootstrapResult(
        operationsCreated: 0,
        alreadyCompleted: false,
      );
    }
    final marker = await (_database.select(
      _database.appSettings,
    )..where((row) => row.key.equals(_markerKey(userId)))).getSingleOrNull();
    if (marker != null) {
      return const SyncBootstrapResult(
        operationsCreated: 0,
        alreadyCompleted: true,
      );
    }

    return _database.transaction(() async {
      final created = await _enqueueCoverage(userId);
      final now = DateTime.now().toUtc();
      await _database
          .into(_database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: _markerKey(userId),
              value: jsonEncode({
                'version': version,
                'completedAt': now.toIso8601String(),
              }),
              updatedAt: now,
            ),
          );
      return SyncBootstrapResult(
        operationsCreated: created,
        alreadyCompleted: false,
      );
    });
  }

  Future<int> _enqueueCoverage(String userId) async {
    var created = 0;
    for (final spec in _coverage) {
      final rows = await _database
          .customSelect(
            'SELECT DISTINCT ${spec.idColumn} AS entity_id FROM ${spec.table} '
            'WHERE user_id = ?',
            variables: [Variable<String>(userId)],
          )
          .get();
      for (final row in rows) {
        final id = row.read<String>('entity_id');
        if (await _hasOperation(userId, spec.entityType, id)) continue;
        await _queue.enqueue(
          entityType: spec.entityType,
          entityId: id,
          operation: SyncOperationType.upsert,
          payload: spec.entityType == 'plan_tasks'
              ? {'plan_id': id}
              : {'id': id},
          userId: userId,
        );
        created++;
      }
    }

    final preferenceKey = 'reminder-defaults:$userId';
    final preference = await (_database.select(
      _database.appSettings,
    )..where((row) => row.key.equals(preferenceKey))).getSingleOrNull();
    if (preference != null &&
        !await _hasOperation(userId, 'user_preferences', userId)) {
      final decoded = jsonDecode(preference.value);
      await _queue.enqueue(
        entityType: 'user_preferences',
        entityId: userId,
        operation: SyncOperationType.upsert,
        payload: {
          'id': userId,
          'preference_key': 'reminder_defaults',
          'value': decoded,
          'updated_at': preference.updatedAt.toUtc().toIso8601String(),
        },
        userId: userId,
      );
      created++;
    }
    return created;
  }

  Future<bool> _hasOperation(
    String userId,
    String entityType,
    String entityId,
  ) async {
    final row =
        await (_database.select(_database.syncOperations)
              ..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.entityType.equals(entityType) &
                    item.entityId.equals(entityId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  static const _coverage = <_CoverageSpec>[
    _CoverageSpec('semester_records', 'id', 'semesters'),
    _CoverageSpec('schedule_template_records', 'id', 'schedule_templates'),
    _CoverageSpec(
      'schedule_template_segment_records',
      'id',
      'schedule_template_segments',
    ),
    _CoverageSpec('course_records', 'id', 'courses'),
    _CoverageSpec(
      'course_schedule_rule_records',
      'id',
      'course_schedule_rules',
    ),
    _CoverageSpec('daily_item_override_records', 'id', 'daily_item_overrides'),
    _CoverageSpec('local_tasks', 'id', 'tasks'),
    _CoverageSpec('task_completion_records', 'id', 'task_completions'),
    _CoverageSpec('timer_session_records', 'id', 'timer_sessions'),
    _CoverageSpec('ad_hoc_timer_records', 'id', 'ad_hoc_timers'),
    _CoverageSpec(
      'ad_hoc_timer_interval_records',
      'id',
      'ad_hoc_timer_intervals',
    ),
    _CoverageSpec('tag_records', 'id', 'tags'),
    _CoverageSpec('tag_revision_records', 'id', 'tag_revisions'),
    _CoverageSpec('reminder_rule_records', 'id', 'reminder_rules'),
    _CoverageSpec('alarm_rule_records', 'id', 'alarm_rules'),
    _CoverageSpec('plan_records', 'id', 'plans'),
    _CoverageSpec('plan_task_records', 'plan_id', 'plan_tasks'),
    _CoverageSpec('review_records', 'id', 'reviews'),
  ];
}

class OfflineDataMergeService {
  OfflineDataMergeService(
    this._database,
    this._queue, {
    SyncRemoteReader? remoteReader,
  }) : _remoteReader = remoteReader;

  final AppDatabase _database;
  final SyncQueueService _queue;
  final SyncRemoteReader? _remoteReader;

  Future<OfflineDataSummary> summary() async {
    final courses = await _count('course_records');
    final tasks = await _count('local_tasks');
    final timers =
        await _count('timer_session_records') +
        await _count('ad_hoc_timer_records');
    final completions = await _count('task_completion_records');
    var all = 0;
    for (final table in _ownedTables) {
      all += await _count(table);
    }
    return OfflineDataSummary(
      courses: courses,
      tasks: tasks,
      timerSessions: timers,
      completions: completions,
      otherRecords: all - courses - tasks - timers - completions,
    );
  }

  Future<int> _count(String table) async {
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS amount FROM $table WHERE user_id = ?',
          variables: const [Variable<String>(offlineDataOwner)],
        )
        .getSingle();
    return row.read<int>('amount');
  }

  Future<SyncBootstrapResult> mergeInto(String userId) async {
    if (userId.isEmpty || userId == offlineDataOwner) {
      throw ArgumentError.value(userId, 'userId');
    }
    await _validateRemoteConflicts(userId);
    return _database.transaction(() async {
      await _validateOwnershipGraph(userId);
      for (final table in _ownedTables) {
        await _database.customUpdate(
          'UPDATE $table SET user_id = ? WHERE user_id = ?',
          variables: [
            Variable<String>(userId),
            const Variable<String>(offlineDataOwner),
          ],
          updates: const {},
        );
      }
      final created = await SyncBootstrapService(
        _database,
        _queue,
      )._enqueueCoverage(userId);
      return SyncBootstrapResult(
        operationsCreated: created,
        alreadyCompleted: false,
      );
    });
  }

  Future<void> _validateRemoteConflicts(String userId) async {
    final remote = _remoteReader;
    if (remote == null) return;
    for (final spec in _mergeIdentityCoverage) {
      final localRows = await _database
          .customSelect(
            'SELECT ${spec.localIdColumn} AS entity_id FROM ${spec.localTable} '
            'WHERE user_id = ?',
            variables: const [Variable<String>(offlineDataOwner)],
          )
          .get();
      if (localRows.isEmpty) continue;
      final offlineIds = {
        for (final row in localRows) row.read<String>('entity_id'),
      };
      final remoteRows = await remote.readTable(
        spec.remoteTable,
        userId: userId,
      );
      final conflict = remoteRows.any((row) {
        final value = row[spec.remoteIdColumn];
        return value != null && offlineIds.contains(value.toString());
      });
      if (conflict) {
        throw const OfflineDataConflict('本机数据与当前账号的云端实体存在 ID 冲突，未执行合并。');
      }
    }
  }

  Future<void> _validateOwnershipGraph(String userId) async {
    for (final relation in syncOwnerReferences) {
      final rows = await _database
          .customSelect(
            'SELECT 1 FROM ${relation.localTable} child '
            'JOIN ${relation.parentTable} parent '
            'ON child.${relation.parentColumn} = parent.id '
            'WHERE (child.user_id = ? AND parent.user_id IS NOT ?) '
            'OR (child.user_id = ? AND parent.user_id = ?) LIMIT 1',
            variables: [
              const Variable<String>(offlineDataOwner),
              const Variable<String>(offlineDataOwner),
              Variable<String>(userId),
              const Variable<String>(offlineDataOwner),
            ],
          )
          .get();
      if (rows.isNotEmpty) {
        throw const OfflineDataConflict('本机数据与当前账号存在 ID 归属冲突，未执行合并。');
      }
    }
  }

  static const _ownedTables = <String>[
    'tag_records',
    'tag_revision_records',
    'schedule_template_records',
    'schedule_template_segment_records',
    'semester_records',
    'course_records',
    'course_schedule_rule_records',
    'daily_item_override_records',
    'local_tasks',
    'long_term_task_records',
    'task_schedule_records',
    'one_time_reminder_records',
    'task_completion_records',
    'timer_session_records',
    'task_revision_records',
    'ad_hoc_timer_records',
    'ad_hoc_timer_interval_records',
    'reminder_rule_records',
    'alarm_rule_records',
    'plan_records',
    'plan_task_records',
    'review_records',
  ];

  static const _mergeIdentityCoverage = <_MergeIdentitySpec>[
    _MergeIdentitySpec('tag_records', 'id', 'tags', 'id'),
    _MergeIdentitySpec('tag_revision_records', 'id', 'tag_revisions', 'id'),
    _MergeIdentitySpec(
      'schedule_template_records',
      'id',
      'schedule_templates',
      'id',
    ),
    _MergeIdentitySpec(
      'schedule_template_segment_records',
      'id',
      'schedule_template_segments',
      'id',
    ),
    _MergeIdentitySpec('semester_records', 'id', 'semesters', 'id'),
    _MergeIdentitySpec('course_records', 'id', 'courses', 'id'),
    _MergeIdentitySpec(
      'course_schedule_rule_records',
      'id',
      'course_schedule_rules',
      'id',
    ),
    _MergeIdentitySpec(
      'daily_item_override_records',
      'id',
      'daily_item_overrides',
      'id',
    ),
    _MergeIdentitySpec('local_tasks', 'id', 'tasks', 'id'),
    _MergeIdentitySpec(
      'long_term_task_records',
      'task_id',
      'long_term_tasks',
      'task_id',
    ),
    _MergeIdentitySpec(
      'task_schedule_records',
      'task_id',
      'task_schedules',
      'task_id',
    ),
    _MergeIdentitySpec(
      'one_time_reminder_records',
      'task_id',
      'one_time_reminders',
      'task_id',
    ),
    _MergeIdentitySpec(
      'task_completion_records',
      'id',
      'task_completions',
      'id',
    ),
    _MergeIdentitySpec('timer_session_records', 'id', 'timer_sessions', 'id'),
    _MergeIdentitySpec('ad_hoc_timer_records', 'id', 'ad_hoc_timers', 'id'),
    _MergeIdentitySpec(
      'ad_hoc_timer_interval_records',
      'id',
      'ad_hoc_timer_intervals',
      'id',
    ),
    _MergeIdentitySpec('reminder_rule_records', 'id', 'reminder_rules', 'id'),
    _MergeIdentitySpec('alarm_rule_records', 'id', 'alarm_rules', 'id'),
    _MergeIdentitySpec('plan_records', 'id', 'plans', 'id'),
    _MergeIdentitySpec('plan_task_records', 'plan_id', 'plan_tasks', 'plan_id'),
    _MergeIdentitySpec('review_records', 'id', 'reviews', 'id'),
  ];
}

class _CoverageSpec {
  const _CoverageSpec(this.table, this.idColumn, this.entityType);

  final String table;
  final String idColumn;
  final String entityType;
}

class _MergeIdentitySpec {
  const _MergeIdentitySpec(
    this.localTable,
    this.localIdColumn,
    this.remoteTable,
    this.remoteIdColumn,
  );

  final String localTable;
  final String localIdColumn;
  final String remoteTable;
  final String remoteIdColumn;
}
