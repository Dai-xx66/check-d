-- Rollback for 202611230005_task_occurrence_snapshots.sql.
-- Idempotent. Drops only objects created by that migration; it does NOT touch
-- agent_course_occurrence_snapshots, the approval chain, or any business data.
-- After running this, set CHECKD_TASK_OCCURRENCE_EVIDENCE_ENABLED=0 (default)
-- so the read path stops querying the missing table and the original
-- fail-closed blocker recurring_occurrences_not_resolved returns.

drop policy if exists agent_task_occurrence_snapshots_owner on public.agent_task_occurrence_snapshots;

drop function if exists public.publish_agent_task_occurrence_snapshot(uuid, jsonb);

drop table if exists public.agent_task_occurrence_snapshots;

notify pgrst, 'reload schema';
