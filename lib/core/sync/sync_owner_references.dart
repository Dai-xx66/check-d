import 'dart:convert';

/// Typed parent references shared by restore and offline-account adoption.
/// Foreign keys alone do not establish account ownership.
class SyncOwnerReference {
  const SyncOwnerReference(
    this.remoteTable,
    this.localTable,
    this.parentColumn,
    this.parentTable, {
    this.optional = false,
  });

  final String remoteTable;
  final String localTable;
  final String parentColumn;
  final String parentTable;
  final bool optional;
}

const syncOwnerReferences = <SyncOwnerReference>[
  SyncOwnerReference(
    'schedule_template_segments',
    'schedule_template_segment_records',
    'template_id',
    'schedule_template_records',
  ),
  SyncOwnerReference(
    'semesters',
    'semester_records',
    'schedule_template_id',
    'schedule_template_records',
    optional: true,
  ),
  SyncOwnerReference(
    'courses',
    'course_records',
    'semester_id',
    'semester_records',
    optional: true,
  ),
  SyncOwnerReference(
    'course_schedule_rules',
    'course_schedule_rule_records',
    'course_id',
    'course_records',
  ),
  SyncOwnerReference(
    'course_schedule_rules',
    'course_schedule_rule_records',
    'schedule_template_id',
    'schedule_template_records',
    optional: true,
  ),
  SyncOwnerReference(
    'tasks',
    'local_tasks',
    'tag_id',
    'tag_records',
    optional: true,
  ),
  SyncOwnerReference(
    'long_term_tasks',
    'long_term_task_records',
    'task_id',
    'local_tasks',
  ),
  SyncOwnerReference(
    'task_schedules',
    'task_schedule_records',
    'task_id',
    'local_tasks',
  ),
  SyncOwnerReference(
    'one_time_reminders',
    'one_time_reminder_records',
    'task_id',
    'local_tasks',
  ),
  SyncOwnerReference(
    'task_completions',
    'task_completion_records',
    'task_id',
    'local_tasks',
  ),
  SyncOwnerReference(
    'timer_sessions',
    'timer_session_records',
    'task_id',
    'local_tasks',
  ),
  SyncOwnerReference(
    'timer_sessions',
    'timer_session_records',
    'tag_id',
    'tag_records',
    optional: true,
  ),
  SyncOwnerReference(
    'ad_hoc_timers',
    'ad_hoc_timer_records',
    'tag_id',
    'tag_records',
    optional: true,
  ),
  SyncOwnerReference(
    'ad_hoc_timer_intervals',
    'ad_hoc_timer_interval_records',
    'timer_id',
    'ad_hoc_timer_records',
  ),
  SyncOwnerReference(
    'plan_tasks',
    'plan_task_records',
    'plan_id',
    'plan_records',
  ),
  SyncOwnerReference(
    'plan_tasks',
    'plan_task_records',
    'task_id',
    'local_tasks',
  ),
  SyncOwnerReference(
    'tag_revisions',
    'tag_revision_records',
    'tag_id',
    'tag_records',
  ),
];

/// The additional local columns needed by references that a single SQL join
/// cannot describe. Task revisions belong to the local merge graph only.
const localExpandedSyncReferenceColumns = <String, String>{
  'daily_item_override_records': 'item_type, item_id, action, deleted_at',
  'reminder_rule_records': 'owner_type, owner_id, deleted_at',
  'alarm_rule_records': 'owner_type, owner_id, deleted_at',
  'course_schedule_rule_records':
      'section_ids_json, schedule_template_id, deleted_at',
  'task_revision_records': 'task_id',
};

const _remoteParentTables = {
  'local_tasks': 'tasks',
  'course_records': 'courses',
  'course_schedule_rule_records': 'course_schedule_rules',
  'schedule_template_records': 'schedule_templates',
  'schedule_template_segment_records': 'schedule_template_segments',
  'semester_records': 'semesters',
  'tag_records': 'tags',
  'ad_hoc_timer_records': 'ad_hoc_timers',
  'plan_records': 'plans',
};

class ResolvedSyncOwnerReference {
  const ResolvedSyncOwnerReference(
    this.column,
    this.id,
    this.localParentTables, {
    this.sectionTemplateId,
  });

  final String column;
  final String id;
  final List<String> localParentTables;
  final String? sectionTemplateId;

  List<String> get remoteParentTables => [
    for (final table in localParentTables) _remoteParentTables[table]!,
  ];
}

Iterable<ResolvedSyncOwnerReference> resolveSyncOwnerReferences(
  String table,
  Map<String, Object?> row, {
  required bool local,
}) sync* {
  for (final reference in syncOwnerReferences) {
    if ((local ? reference.localTable : reference.remoteTable) != table) {
      continue;
    }
    final value = row[reference.parentColumn];
    if (value == null && reference.optional) continue;
    yield ResolvedSyncOwnerReference(
      reference.parentColumn,
      _referenceId(value, reference.parentColumn),
      [reference.parentTable],
    );
  }
  yield* resolveExpandedSyncOwnerReferences(table, row, local: local);
}

Iterable<ResolvedSyncOwnerReference> resolveExpandedSyncOwnerReferences(
  String table,
  Map<String, Object?> row, {
  required bool local,
}) sync* {
  if (table ==
      (local ? 'daily_item_override_records' : 'daily_item_overrides')) {
    yield _scheduleReference(
      row,
      'item_type',
      'item_id',
      extraCourse: row['action'] == 'extraCourse',
    );
  } else if (table == (local ? 'reminder_rule_records' : 'reminder_rules') ||
      table == (local ? 'alarm_rule_records' : 'alarm_rules')) {
    yield _scheduleReference(row, 'owner_type', 'owner_id');
  } else if (table ==
      (local ? 'course_schedule_rule_records' : 'course_schedule_rules')) {
    final column = local ? 'section_ids_json' : 'section_ids';
    final rawIds = row[column];
    final ids = rawIds is String ? jsonDecode(rawIds) : rawIds;
    if (ids == null && rawIds == null) return;
    if (ids is! List) {
      throw FormatException(
        'Invalid course section reference list in $column.',
      );
    }
    if (ids.isEmpty) return;
    final templateId = _referenceId(
      row['schedule_template_id'],
      'schedule_template_id',
    );
    for (final id in ids) {
      yield ResolvedSyncOwnerReference(column, _referenceId(id, column), const [
        'schedule_template_segment_records',
      ], sectionTemplateId: templateId);
    }
  } else if (local && table == 'task_revision_records') {
    yield ResolvedSyncOwnerReference(
      'task_id',
      _referenceId(row['task_id'], 'task_id'),
      const ['local_tasks'],
    );
  }
}

ResolvedSyncOwnerReference _scheduleReference(
  Map<String, Object?> row,
  String typeColumn,
  String idColumn, {
  bool extraCourse = false,
}) {
  final parentTables = switch (row[typeColumn]) {
    'recurring' || 'oneTime' => const ['local_tasks'],
    'course' when extraCourse => const ['course_records'],
    // Existing schedules can target a whole course or a single lesson rule.
    'course' => const ['course_records', 'course_schedule_rule_records'],
    _ => throw FormatException(
      'Invalid schedule reference type in $typeColumn.',
    ),
  };
  return ResolvedSyncOwnerReference(
    idColumn,
    _referenceId(row[idColumn], idColumn),
    parentTables,
  );
}

String _referenceId(Object? value, String column) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid parent reference in $column.');
  }
  return value;
}
