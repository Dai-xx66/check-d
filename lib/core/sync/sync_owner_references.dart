/// Typed parent references shared by restore and offline-account adoption.
/// Foreign keys alone do not establish account ownership.
class SyncOwnerReference {
  const SyncOwnerReference(
    this.remoteTable,
    this.localTable,
    this.parentColumn,
    this.parentTable,
  );

  final String remoteTable;
  final String localTable;
  final String parentColumn;
  final String parentTable;
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
  ),
  SyncOwnerReference(
    'courses',
    'course_records',
    'semester_id',
    'semester_records',
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
  ),
  SyncOwnerReference('tasks', 'local_tasks', 'tag_id', 'tag_records'),
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
  ),
  SyncOwnerReference(
    'ad_hoc_timers',
    'ad_hoc_timer_records',
    'tag_id',
    'tag_records',
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
