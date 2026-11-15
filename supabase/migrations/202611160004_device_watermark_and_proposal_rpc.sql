-- Isolated integration support for device outbox acknowledgments and
-- server-owned Proposal/Approval creation. Do not apply to Production yet.
begin;

create table if not exists public.agent_device_sync_watermarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  acknowledged_generation bigint not null default 0 check (acknowledged_generation >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);
alter table public.agent_device_sync_watermarks enable row level security;
create policy agent_device_watermarks_owner_all on public.agent_device_sync_watermarks
  for all to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
grant select,insert,update on public.agent_device_sync_watermarks to authenticated;

alter table public.agent_plan_proposals
  add column if not exists request_digest text;

create or replace function public.create_agent_plan_proposal(
  p_from date,
  p_through date,
  p_expected_snapshot_version text,
  p_device_id uuid,
  p_local_generation bigint,
  p_rules_version text,
  p_idempotency_key text,
  p_changes jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_snapshot jsonb;
  v_current_version text;
  v_ack bigint;
  v_request_digest text;
  v_change_digest text;
  v_changes jsonb := '[]'::jsonb;
  v_item jsonb;
  v_task record;
  v_start timestamptz;
  v_end timestamptz;
  v_local_start date;
  v_local_end date;
  v_due_date date;
  v_due_at timestamptz;
  v_available_from date;
  v_id uuid;
  v_proposal public.agent_plan_proposals%rowtype;
begin
  if v_user is null then raise exception using errcode='28000',message='AUTH_REQUIRED'; end if;
  if p_from is null or p_through is null or p_through<p_from or p_through-p_from>90
     or p_local_generation is null or p_local_generation<0
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128
     or p_rules_version is distinct from 'planning_rules_v1'
     or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes)=0
     or jsonb_array_length(p_changes)>100 then
    raise exception using errcode='22023',message='INVALID_PROPOSAL_INPUT';
  end if;

  v_request_digest:=pg_catalog.encode(extensions.digest(
    pg_catalog.jsonb_build_object('from',p_from,'through',p_through,
      'rules_version',p_rules_version,'changes',p_changes)::text,'sha256'),'hex');
  select * into v_proposal from public.agent_plan_proposals
    where user_id=v_user and idempotency_key=p_idempotency_key for update;
  if found then
    if v_proposal.request_digest is distinct from v_request_digest then
      raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';
    end if;
    return pg_catalog.jsonb_build_object('ok',true,'proposal_id',v_proposal.id,
      'status',v_proposal.status,'base_version',v_proposal.base_version,
      'change_digest',v_proposal.change_digest,'expires_at',v_proposal.expires_at,
      'replayed',true,'execution_eligible',false);
  end if;

  select acknowledged_generation into v_ack from public.agent_device_sync_watermarks
    where user_id=v_user and device_id=p_device_id for update;
  if not found or v_ack<p_local_generation then
    raise exception using errcode='P0001',message='DEVICE_SYNC_PENDING';
  end if;
  v_snapshot:=public.build_agent_planning_snapshot(p_from,p_through);
  v_current_version:=v_snapshot->>'snapshot_version';
  if v_current_version is distinct from p_expected_snapshot_version then
    raise exception using errcode='40001',message='SNAPSHOT_CONFLICT';
  end if;
  if coalesce((v_snapshot#>>'{source,deadline_columns_available}')::boolean,false)=false then
    raise exception using errcode='P0001',message='PLANNING_SOURCE_INCOMPLETE';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_changes) loop
    begin
      v_id:=pg_catalog.gen_random_uuid();
      if jsonb_typeof(v_item)<>'object' or
         (select count(*) from pg_catalog.jsonb_object_keys(v_item))<>4 or
         not (v_item ?& array['task_id','starts_at','ends_at','planned_seconds']) then
        raise exception using errcode='22023',message='CHANGE_SHAPE_INVALID';
      end if;
      v_start:=(v_item->>'starts_at')::timestamptz;
      v_end:=(v_item->>'ends_at')::timestamptz;
      if v_start is null or v_end is null or v_end<=v_start or v_start<=pg_catalog.clock_timestamp()
         or round(extract(epoch from (v_end-v_start)))::integer<>(v_item->>'planned_seconds')::integer then
        raise exception using errcode='22023',message='CHANGE_TIME_INVALID';
      end if;
      v_local_start:=(v_start at time zone 'Asia/Shanghai')::date;
      v_local_end:=((v_end-interval '1 microsecond') at time zone 'Asia/Shanghai')::date;
      if v_local_start<>v_local_end or v_local_start<p_from or v_local_start>p_through then
        raise exception using errcode='22023',message='CHANGE_RANGE_INVALID';
      end if;
      select t.id,r.available_from,r.due_date,r.due_at,r.completed_at
        into v_task from public.tasks t
        join public.one_time_reminders r on r.user_id=t.user_id and r.task_id=t.id
        where t.id=(v_item->>'task_id')::uuid and t.user_id=v_user
          and t.type='one_time' and t.status='active' and t.deleted_at is null
        for share of t,r;
      if not found then raise exception using errcode='P0002',message='NOT_FOUND'; end if;
      if v_task.completed_at is not null then raise exception using errcode='P0001',message='TASK_COMPLETED'; end if;
      if v_task.available_from is not null and v_local_start<v_task.available_from then
        raise exception using errcode='P0001',message='BEFORE_AVAILABLE_FROM';
      end if;
      if v_task.due_date is not null and v_local_end>v_task.due_date then
        raise exception using errcode='P0001',message='AFTER_DATE_DEADLINE';
      end if;
      if v_task.due_at is not null and v_end>v_task.due_at then
        raise exception using errcode='P0001',message='AFTER_EXACT_DEADLINE';
      end if;
      if exists (
        select 1 from pg_catalog.jsonb_array_elements(v_changes) prior(value)
        where (prior.value->>'starts_at')::timestamptz < v_end
          and v_start < (prior.value->>'ends_at')::timestamptz
      ) then raise exception using errcode='P0001',message='PROPOSAL_BLOCK_CONFLICT'; end if;
      if exists (
        select 1 from pg_catalog.jsonb_array_elements(v_snapshot#>'{source,course_occurrences}') c(value)
        where (c.value->>'starts_at')::timestamptz < v_end
          and v_start < (c.value->>'ends_at')::timestamptz
      ) then raise exception using errcode='P0001',message='FIXED_EVENT_CONFLICT'; end if;
      if exists (
        select 1 from pg_catalog.jsonb_array_elements(v_snapshot#>'{source,time_blocks}') b(value)
        where (b.value->>'starts_at')::timestamptz < v_end
          and v_start < (b.value->>'ends_at')::timestamptz
      ) then raise exception using errcode='P0001',message='EXISTING_PLAN_CONFLICT'; end if;
      v_changes:=v_changes||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'id',v_id,'task_id',(v_item->>'task_id')::uuid,'starts_at',v_start,
        'ends_at',v_end,'planned_seconds',(v_item->>'planned_seconds')::integer));
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception using errcode='22023',message='CHANGE_FIELD_INVALID';
    end;
  end loop;
  v_change_digest:=pg_catalog.encode(extensions.digest(v_changes::text,'sha256'),'hex');
  insert into public.agent_plan_proposals(user_id,base_version,changes,change_digest,rules_version,
    starts_on,ends_on,status,expires_at,idempotency_key,request_digest)
  values(v_user,v_current_version,v_changes,v_change_digest,p_rules_version,p_from,p_through,
    'proposed',pg_catalog.clock_timestamp()+interval '30 minutes',p_idempotency_key,v_request_digest)
  returning * into v_proposal;
  return pg_catalog.jsonb_build_object('ok',true,'proposal_id',v_proposal.id,
    'status',v_proposal.status,'base_version',v_proposal.base_version,
    'change_digest',v_proposal.change_digest,'expires_at',v_proposal.expires_at,
    'replayed',false,'execution_eligible',false,
    'data_completeness','active_device_acknowledged_only');
end $$;
revoke all on function public.create_agent_plan_proposal(date,date,text,uuid,bigint,text,text,jsonb) from public,anon;
grant execute on function public.create_agent_plan_proposal(date,date,text,uuid,bigint,text,text,jsonb) to authenticated;

create or replace function public.approve_agent_plan_proposal(p_proposal_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid:=auth.uid();
  v_proposal public.agent_plan_proposals%rowtype;
  v_snapshot jsonb;
  v_approval public.agent_plan_approvals%rowtype;
begin
  if v_user is null then raise exception using errcode='28000',message='AUTH_REQUIRED'; end if;
  select * into v_proposal from public.agent_plan_proposals
    where id=p_proposal_id and user_id=v_user for update;
  if not found then raise exception using errcode='P0002',message='NOT_FOUND'; end if;
  if v_proposal.status<>'proposed' then raise exception using errcode='P0001',message='PROPOSAL_NOT_APPROVABLE'; end if;
  if pg_catalog.clock_timestamp()>=v_proposal.expires_at then
    update public.agent_plan_proposals set status='expired' where id=v_proposal.id;
    raise exception using errcode='P0001',message='PROPOSAL_EXPIRED';
  end if;
  v_snapshot:=public.build_agent_planning_snapshot(v_proposal.starts_on,v_proposal.ends_on);
  if v_snapshot->>'snapshot_version' is distinct from v_proposal.base_version then
    update public.agent_plan_proposals set status='superseded' where id=v_proposal.id;
    raise exception using errcode='40001',message='SNAPSHOT_CONFLICT';
  end if;
  insert into public.agent_plan_approvals(user_id,proposal_id,base_version,change_digest,status,expires_at,decided_at)
  values(v_user,v_proposal.id,v_proposal.base_version,v_proposal.change_digest,'approved',
    least(v_proposal.expires_at,pg_catalog.clock_timestamp()+interval '5 minutes'),pg_catalog.clock_timestamp())
  returning * into v_approval;
  update public.agent_plan_proposals set status='approved' where id=v_proposal.id;
  return pg_catalog.jsonb_build_object('ok',true,'proposal_id',v_proposal.id,
    'approval_id',v_approval.id,'status','approved','expires_at',v_approval.expires_at,
    'simulated_approval',true);
end $$;
revoke all on function public.approve_agent_plan_proposal(uuid) from public,anon;
grant execute on function public.approve_agent_plan_proposal(uuid) to authenticated;

commit;
