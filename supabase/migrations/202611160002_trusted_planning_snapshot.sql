-- Server-owned planning source snapshot and automatic stale-proposal fencing.
-- Apply only to an isolated Supabase project until Production review.
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.agent_user_snapshot_versions
  add column if not exists revision bigint not null default 0 check (revision >= 0),
  add column if not exists snapshot_from date,
  add column if not exists snapshot_through date;

-- Server-side equivalent of the persisted CourseScheduleRule date/time
-- semantics. It uses the same semester week, odd/even/custom interval,
-- cancellation/reschedule, makeup, and teaching-segment inputs as Flutter.
create or replace function private.agent_course_occurrences(
  p_user_id uuid,p_from date,p_through date
) returns jsonb language sql security definer set search_path = '' as $$
  with dates as (
    select d::date as local_date
    from pg_catalog.generate_series(p_from::timestamp,p_through::timestamp,interval '1 day') d
  ), candidates as (
    select c.id as course_id,r.id as rule_id,d.local_date,r.week_rule_type,r.week_numbers,
      r.start_week,r.end_week,r.interval_weeks,r.time_mode,r.schedule_template_id,r.section_ids,
      r.starts_at_minute,r.ends_at_minute,o.id as override_id,o.action as override_action,
      o.planned_start_minute,o.planned_end_minute,
      case when s.id is not null then ((d.local_date-s.first_week_start_date::date)/7)+1
        when c.semester_starts_on is not null then ((d.local_date-c.semester_starts_on::date)/7)+1
        else extract(week from d.local_date)::integer end as week_no
    from dates d
    join public.courses c on c.user_id=p_user_id and c.status='active' and c.deleted_at is null
    join public.course_schedule_rules r on r.course_id=c.id and r.user_id=c.user_id and r.deleted_at is null
    left join public.semesters s on s.id=c.semester_id and s.user_id=c.user_id and s.deleted_at is null
    left join lateral (
      select x.* from public.daily_item_overrides x
      where x.user_id=p_user_id and x.item_type='course' and x.deleted_at is null
        and x.local_date=d.local_date and x.item_id in (r.id,c.id)
      order by case when x.item_id=r.id then 0 else 1 end,x.updated_at desc limit 1
    ) o on true
    where r.weekday=extract(isodow from d.local_date)::integer
      and (s.id is null or d.local_date between s.first_week_start_date::date
        and s.first_week_start_date::date+(s.total_weeks*7-1))
      and (c.semester_starts_on is null or s.id is not null or d.local_date>=c.semester_starts_on::date)
      and (c.semester_ends_on is null or s.id is not null or d.local_date<=c.semester_ends_on::date)
  ), active as (
    select c.* from candidates c
    where (c.start_week is null or c.week_no>=c.start_week)
      and (c.end_week is null or c.week_no<=c.end_week)
      and case c.week_rule_type
        when 'everyWeek' then true
        when 'oddWeeks' then mod(c.week_no,2)=1
        when 'evenWeeks' then mod(c.week_no,2)=0
        when 'everyNWeeks' then mod(c.week_no-coalesce(c.start_week,1),coalesce(c.interval_weeks,1))=0
        when 'custom' then c.week_numbers @> pg_catalog.jsonb_build_array(c.week_no)
        else false end
      and c.week_no>0 and c.override_action is distinct from 'skip'
      and not (c.override_id is not null and (c.planned_start_minute is not null or c.planned_end_minute is not null)
        and (c.planned_start_minute is null or c.planned_end_minute is null or c.planned_end_minute<=c.planned_start_minute))
  ), timed as (
    select a.*,
      coalesce(a.planned_start_minute,
        case when a.time_mode='periods' and a.schedule_template_id is not null and jsonb_array_length(a.section_ids)>0
          then seg.start_minute else null end,a.starts_at_minute) as start_minute,
      coalesce(a.planned_end_minute,
        case when a.time_mode='periods' and a.schedule_template_id is not null and jsonb_array_length(a.section_ids)>0
          then seg.end_minute else null end,a.ends_at_minute) as end_minute
    from active a
    left join lateral (
      select min(x.starts_at_minute) as start_minute,max(x.ends_at_minute) as end_minute
      from public.schedule_template_segments x
      where x.user_id=p_user_id and x.template_id=a.schedule_template_id and x.deleted_at is null
        and x.segment_type='classTime' and x.id::text in (select jsonb_array_elements_text(a.section_ids))
    ) seg on true
  ), regular as (
    select pg_catalog.jsonb_build_object(
      'source_id','course:'||t.rule_id::text||':'||t.local_date::text,'kind','course',
      'course_id',t.course_id,'rule_id',t.rule_id,'local_date',t.local_date,
      'starts_at',pg_catalog.timezone('Asia/Shanghai',t.local_date::timestamp+t.start_minute*interval '1 minute'),
      'ends_at',pg_catalog.timezone('Asia/Shanghai',t.local_date::timestamp+t.end_minute*interval '1 minute')
    ) as event
    from timed t where t.start_minute is not null and t.end_minute is not null and t.end_minute>t.start_minute
  ), extra as (
    select pg_catalog.jsonb_build_object(
      'source_id','course-extra:'||o.id::text,'kind','course','course_id',c.id,
      'local_date',o.local_date,
      'starts_at',pg_catalog.timezone('Asia/Shanghai',o.local_date::timestamp+o.planned_start_minute*interval '1 minute'),
      'ends_at',pg_catalog.timezone('Asia/Shanghai',o.local_date::timestamp+o.planned_end_minute*interval '1 minute')
    ) as event
    from public.daily_item_overrides o join public.courses c on c.id=o.item_id and c.user_id=o.user_id
    where o.user_id=p_user_id and o.item_type='course' and o.action='extraCourse'
      and o.deleted_at is null and c.deleted_at is null and c.status='active'
      and o.local_date between p_from and p_through and o.planned_start_minute is not null
      and o.planned_end_minute>o.planned_start_minute
  )
  select coalesce(pg_catalog.jsonb_agg(event order by event->>'starts_at'),'[]'::jsonb)
  from (select event from regular union all select event from extra) q
$$;
revoke all on function private.agent_course_occurrences(uuid,date,date) from public,anon,authenticated;

create or replace function private.agent_planning_source(
  p_user_id uuid, p_from date, p_through date
) returns jsonb
language sql security definer set search_path = '' as $$
  select pg_catalog.jsonb_build_object(
    'range', pg_catalog.jsonb_build_object('from',p_from,'through',p_through),
    'deadline_columns_available',(
      select count(*)=4 from pg_catalog.pg_attribute a
      where a.attrelid='public.one_time_reminders'::regclass and a.attnum>0 and not a.attisdropped
        and a.attname in ('available_from','planned_date','due_date','due_at')
    ),
    'tasks', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'task_id',t.id,'name',t.name,'kind',case t.type when 'one_time' then 'one_time' else 'recurring_template' end,
        'status',t.status,'updated_at',t.updated_at,'sync_version',t.sync_version,
        'scheduled_at',case when r.is_timed then r.scheduled_at else null end,
        -- Stage 14A is not present in every deployed baseline yet. Read its
        -- optional fields through the row JSON so this migration also runs on
        -- older schemas without inventing deadline values.
        'planned_date',case when r.has_scheduled_date and not r.is_timed
          then coalesce(to_jsonb(r)->>'planned_date',(r.scheduled_at at time zone 'Asia/Shanghai')::date::text)
          else to_jsonb(r)->>'planned_date' end,
        'available_from',to_jsonb(r)->>'available_from',
        'deadline_date',to_jsonb(r)->>'due_date','deadline_at',to_jsonb(r)->>'due_at',
        'completion_status',case when r.task_id is null then 'unknown'
          when r.completed_at is not null then 'completed' else 'pending' end,
        'remaining_seconds',e.remaining_seconds,
        'remaining_effort_state',case when e.remaining_seconds is null then 'unknown' else 'known' end,
        'deadline_state',case when to_jsonb(r)->>'due_date' is not null or to_jsonb(r)->>'due_at' is not null
          then 'known' else 'unknown_no_deadline_record' end
      ) order by t.id)
      from public.tasks t
      left join public.one_time_reminders r on r.user_id=t.user_id and r.task_id=t.id
      left join public.task_effort_estimates e on e.user_id=t.user_id and e.task_id=t.id and e.deleted_at is null
      where t.user_id=p_user_id and t.deleted_at is null and t.status='active'
    ),'[]'::jsonb),
    'recurring_task_details', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(l)-'user_id' order by l.task_id)
      from public.long_term_tasks l join public.tasks t on t.id=l.task_id and t.user_id=l.user_id
      where l.user_id=p_user_id and t.deleted_at is null and t.status='active'),'[]'::jsonb),
    'task_schedules', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s)-'user_id' order by s.task_id,s.id)
      from public.task_schedules s join public.tasks t on t.id=s.task_id and t.user_id=s.user_id
      where s.user_id=p_user_id and t.deleted_at is null and t.status='active'),'[]'::jsonb),
    'courses', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c)-'user_id' order by c.id)
      from public.courses c where c.user_id=p_user_id and c.deleted_at is null and c.status='active'),'[]'::jsonb),
    'course_schedule_rules', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r)-'user_id' order by r.id)
      from public.course_schedule_rules r join public.courses c on c.id=r.course_id and c.user_id=r.user_id
      where r.user_id=p_user_id and r.deleted_at is null and c.deleted_at is null and c.status='active'),'[]'::jsonb),
    'semesters', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s)-'user_id' order by s.id)
      from public.semesters s where s.user_id=p_user_id and s.deleted_at is null),'[]'::jsonb),
    'schedule_templates', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t)-'user_id' order by t.id)
      from public.schedule_templates t where t.user_id=p_user_id and t.deleted_at is null),'[]'::jsonb),
    'schedule_template_segments', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s)-'user_id' order by s.id)
      from public.schedule_template_segments s where s.user_id=p_user_id and s.deleted_at is null),'[]'::jsonb),
    'daily_item_overrides', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(o)-'user_id' order by o.local_date,o.id)
      from public.daily_item_overrides o where o.user_id=p_user_id and o.deleted_at is null
        and o.local_date between p_from and p_through),'[]'::jsonb),
    'course_occurrences',private.agent_course_occurrences(p_user_id,p_from,p_through),
    'effort_records', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(e)-'user_id' order by e.task_id)
      from public.task_effort_estimates e where e.user_id=p_user_id),'[]'::jsonb),
    'plan_versions', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(v)-'user_id' order by v.revision)
      from public.task_plan_versions v where v.user_id=p_user_id and v.status in ('confirmed','applied')),'[]'::jsonb),
    'time_blocks', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(b)-'user_id' order by b.starts_at,b.id)
      from public.task_time_blocks b join public.task_plan_versions v on v.user_id=b.user_id and v.id=b.plan_version_id
      where b.user_id=p_user_id and b.deleted_at is null and v.status in ('confirmed','applied')),'[]'::jsonb),
    'completion_facts', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'task_id',c.task_id,'local_date',c.local_date,'completed_at',c.completed_at,'is_success',c.is_success,
      'updated_at',c.updated_at,'sync_version',c.sync_version) order by c.local_date,c.task_id)
      from public.task_completions c where c.user_id=p_user_id and c.deleted_at is null
        and c.local_date between p_from and p_through),'[]'::jsonb),
    'limitations',(select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(item)) from (
      values ('device_latest_state_not_server_acknowledged'::text),
        (case when (select count(*)<4 from pg_catalog.pg_attribute a
          where a.attrelid='public.one_time_reminders'::regclass and a.attnum>0 and not a.attisdropped
            and a.attname in ('available_from','planned_date','due_date','due_at'))
          then 'cloud_deadline_fields_absent_or_history_unavailable' end),
        ('historical_deadlines_and_unsynced_device_rows_unknown'::text)
    ) limits(item) where item is not null)
  )
$$;
revoke all on function private.agent_planning_source(uuid,date,date) from public,anon,authenticated;



create or replace function private.invalidate_agent_planning_source()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid; v_version text;
begin
  if tg_op='DELETE' then v_user_id:=old.user_id; else v_user_id:=new.user_id; end if;
  update public.agent_user_snapshot_versions s
    set revision=s.revision+1,
        snapshot_version='dirty:'||(s.revision+1)::text||':'||pg_catalog.gen_random_uuid()::text,
        source_digest='dirty',computed_at=pg_catalog.clock_timestamp()
    where s.user_id=v_user_id
    returning snapshot_version into v_version;
  if found then
    update public.agent_plan_proposals p set status='superseded'
      where p.user_id=v_user_id and p.status in ('proposed','approved')
        and p.base_version<>v_version;
    update public.agent_plan_approvals a set status='expired',decided_at=pg_catalog.clock_timestamp()
      where a.user_id=v_user_id and a.status in ('pending','approved')
        and exists(select 1 from public.agent_plan_proposals p
          where p.user_id=a.user_id and p.id=a.proposal_id and p.status='superseded');
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.invalidate_agent_planning_source() from public,anon,authenticated;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'tasks','long_term_tasks','task_schedules','one_time_reminders','task_completions','courses','course_schedule_rules',
    'daily_item_overrides','semesters','schedule_templates','schedule_template_segments',
    'task_effort_estimates','task_plan_versions','task_time_blocks','planned_block_timer_links'
  ] loop
    execute pg_catalog.format('drop trigger if exists invalidate_agent_planning_source on public.%I',v_table);
    execute pg_catalog.format(
      'create trigger invalidate_agent_planning_source after insert or update or delete on public.%I for each row execute function private.invalidate_agent_planning_source()',
      v_table);
  end loop;
end $$;

create or replace function public.build_agent_planning_snapshot(p_from date,p_through date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid:=auth.uid();
  v_source jsonb;
  v_digest text;
  v_version text;
  v_revision bigint;
  v_previous_digest text;
  v_previous_from date;
  v_previous_through date;
  v_changed boolean;
  v_deadline_schema_available boolean;
begin
  if v_user_id is null then raise exception using errcode='28000',message='AUTH_REQUIRED'; end if;
  if p_from is null or p_through is null or p_through<p_from or p_through-p_from>90 then
    raise exception using errcode='22023',message='INVALID_SNAPSHOT_RANGE'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text,0));
  v_source:=private.agent_planning_source(v_user_id,p_from,p_through);
  v_deadline_schema_available:=coalesce((v_source->>'deadline_columns_available')::boolean,false);
  v_digest:=pg_catalog.encode(extensions.digest(v_source::text,'sha256'),'hex');
  select s.source_digest,s.snapshot_from,s.snapshot_through into v_previous_digest,v_previous_from,v_previous_through
    from public.agent_user_snapshot_versions s where s.user_id=v_user_id for update;
  v_changed:=not found or v_previous_digest is distinct from v_digest
    or v_previous_from is distinct from p_from or v_previous_through is distinct from p_through;
  insert into public.agent_user_snapshot_versions(user_id,snapshot_version,computed_at,source_digest,revision,snapshot_from,snapshot_through)
    values(v_user_id,'r1:'||v_digest,pg_catalog.clock_timestamp(),v_digest,1,p_from,p_through)
  on conflict(user_id) do update set
    revision=case when v_changed then public.agent_user_snapshot_versions.revision+1 else public.agent_user_snapshot_versions.revision end,
    snapshot_version=case when v_changed then 'r'||(public.agent_user_snapshot_versions.revision+1)::text||':'||excluded.source_digest else public.agent_user_snapshot_versions.snapshot_version end,
    source_digest=excluded.source_digest,computed_at=pg_catalog.clock_timestamp(),snapshot_from=excluded.snapshot_from,snapshot_through=excluded.snapshot_through;
  select snapshot_version,revision into v_version,v_revision from public.agent_user_snapshot_versions where user_id=v_user_id;
  update public.agent_plan_proposals p set status='superseded'
    where p.user_id=v_user_id and p.status in ('proposed','approved') and p.base_version<>v_version;
  update public.agent_plan_approvals a set status='expired',decided_at=pg_catalog.clock_timestamp()
    where a.user_id=v_user_id and a.status in ('pending','approved')
      and exists(select 1 from public.agent_plan_proposals p where p.user_id=a.user_id and p.id=a.proposal_id and p.status='superseded');
  return pg_catalog.jsonb_build_object(
    'ok',true,'snapshot_kind','server_source_snapshot','user_id',v_user_id,
    'snapshot_version',v_version,'snapshot_digest',v_digest,'revision',v_revision,
    'captured_at',pg_catalog.clock_timestamp(),'source',v_source,
    'planning_ready',false,'execution_eligible',false,
    'readiness_blockers',(select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(item)) from (
      values ('device_latest_state_not_server_acknowledged'::text),
        (case when not v_deadline_schema_available then 'cloud_deadline_fields_absent_or_history_unavailable' end),
        ('course_rules_need_contract_checked_occurrence_normalization'::text)
    ) blockers(item) where item is not null)
  );
end $$;
revoke all on function public.build_agent_planning_snapshot(date,date) from public,anon;
grant execute on function public.build_agent_planning_snapshot(date,date) to authenticated;

-- Conflict rows are private snapshots of both sides. Explicit resolution is
-- local-owner-only; remote replication of conflict decisions is a later step.
do $$
begin
  alter table public.planning_sync_conflicts drop constraint if exists planning_sync_conflicts_entity_type_check;
  alter table public.planning_sync_conflicts add constraint planning_sync_conflicts_entity_type_check
    check (entity_type in ('task_effort_estimates','task_plan_versions','task_time_blocks','planned_block_timer_links'));
end $$;

commit;
