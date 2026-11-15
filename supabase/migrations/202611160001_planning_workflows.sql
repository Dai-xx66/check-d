-- Planning tombstones, server proposals/approvals, and durable risk queues.
-- Validate only in isolated Supabase. No Production rollout is authorized.
begin;

alter table public.task_effort_estimates add column if not exists deleted_at timestamptz;
alter table public.task_plan_versions add column if not exists supersedes_version_ids uuid[] not null default '{}';
alter table public.task_time_blocks add column if not exists deleted_at timestamptz;

create table if not exists public.planning_sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('task_effort_estimates','task_plan_versions','task_time_blocks')),
  entity_id text not null,
  local_version text not null,
  remote_version text not null,
  local_payload jsonb not null,
  remote_payload jsonb not null,
  status text not null default 'unresolved' check (status in ('unresolved','resolved')),
  resolution text check (resolution is null or resolution in ('keep_local','keep_remote')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (user_id, entity_type, entity_id, local_version, remote_version)
);

-- The trusted server snapshot builder alone advances this version.
create table if not exists public.agent_user_snapshot_versions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  snapshot_version text not null,
  computed_at timestamptz not null,
  source_digest text not null
);

create table if not exists public.agent_plan_proposals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  base_version text not null,
  changes jsonb not null check (jsonb_typeof(changes) = 'array' and jsonb_array_length(changes) > 0),
  change_digest text not null,
  rules_version text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null default 'proposed' check (status in ('proposed','approved','applying','applied','rejected','expired','failed','superseded')),
  expires_at timestamptz not null,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  unique (user_id, id), unique (user_id, idempotency_key), check (starts_on <= ends_on)
);

create table if not exists public.agent_plan_approvals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  proposal_id uuid not null,
  base_version text not null,
  change_digest text not null,
  status text not null check (status in ('pending','approved','rejected','consumed','expired')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  unique (user_id,id),
  foreign key (user_id,proposal_id) references public.agent_plan_proposals(user_id,id) on delete cascade
);

create table if not exists public.agent_plan_apply_idempotency (
  user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null,
  proposal_id uuid not null,
  change_digest text not null,
  status text not null check (status in ('applying','applied')),
  result jsonb,
  created_at timestamptz not null default now(),
  primary key(user_id,idempotency_key),
  foreign key(user_id,proposal_id) references public.agent_plan_proposals(user_id,id) on delete cascade
);

create table if not exists public.agent_risk_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  dedupe_key text not null,
  event_type text not null,
  payload jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending','processing','retry','done','dead')),
  attempts integer not null default 0 check (attempts >= 0),
  next_retry_at timestamptz not null default now(),
  lease_until timestamptz,
  lease_token uuid,
  last_error_code text,
  result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id,dedupe_key)
);

create table if not exists public.agent_risk_states (
  user_id uuid not null references auth.users(id) on delete cascade,
  risk_key text not null,
  snapshot_version text not null,
  fingerprint text not null,
  risk_type text not null,
  severity text not null check (severity in ('low','medium','high','critical')),
  status text not null check (status in ('active','resolved','dismissed')),
  payload jsonb not null,
  evaluated_at timestamptz not null,
  last_notified_at timestamptz,
  cooldown_until timestamptz,
  primary key(user_id,risk_key)
);

create table if not exists public.agent_risk_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  dedupe_key text not null,
  risk_key text not null,
  status text not null check (status in ('pending','sent','suppressed','failed')),
  available_at timestamptz not null default now(),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  unique(user_id,dedupe_key)
);

create index if not exists agent_risk_events_ready_idx on public.agent_risk_events(status,next_retry_at,lease_until);
create index if not exists agent_risk_states_owner_status_idx on public.agent_risk_states(user_id,status,evaluated_at desc);
create index if not exists agent_risk_notifications_owner_ready_idx on public.agent_risk_notifications(user_id,status,available_at);

alter table public.planning_sync_conflicts enable row level security;
alter table public.agent_user_snapshot_versions enable row level security;
alter table public.agent_plan_proposals enable row level security;
alter table public.agent_plan_approvals enable row level security;
alter table public.agent_plan_apply_idempotency enable row level security;
alter table public.agent_risk_events enable row level security;
alter table public.agent_risk_states enable row level security;
alter table public.agent_risk_notifications enable row level security;

create policy planning_sync_conflicts_owner_read on public.planning_sync_conflicts for select to authenticated using (auth.uid() = user_id);
create policy agent_snapshot_owner_read on public.agent_user_snapshot_versions for select to authenticated using (auth.uid() = user_id);
create policy agent_proposals_owner_read on public.agent_plan_proposals for select to authenticated using (auth.uid() = user_id);
create policy agent_approvals_owner_read on public.agent_plan_approvals for select to authenticated using (auth.uid() = user_id);
create policy agent_apply_idempotency_owner_read on public.agent_plan_apply_idempotency for select to authenticated using (auth.uid() = user_id);
create policy agent_risk_events_owner_read on public.agent_risk_events for select to authenticated using (auth.uid() = user_id);
create policy agent_risk_states_owner_read on public.agent_risk_states for select to authenticated using (auth.uid() = user_id);
create policy agent_risk_notifications_owner_read on public.agent_risk_notifications for select to authenticated using (auth.uid() = user_id);

grant select on public.planning_sync_conflicts,public.agent_user_snapshot_versions,public.agent_plan_proposals,public.agent_plan_approvals,public.agent_plan_apply_idempotency,public.agent_risk_events,public.agent_risk_states,public.agent_risk_notifications to authenticated;
revoke insert,update,delete on public.planning_sync_conflicts,public.agent_user_snapshot_versions,public.agent_plan_proposals,public.agent_plan_approvals,public.agent_plan_apply_idempotency,public.agent_risk_events,public.agent_risk_states,public.agent_risk_notifications from anon,authenticated;

-- User JWT binds writes to auth.uid(); proposal/approval rows are server-created.
create or replace function public.apply_approved_plan(p_proposal_id uuid,p_approval_id uuid,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_proposal public.agent_plan_proposals%rowtype;
  v_approval public.agent_plan_approvals%rowtype;
  v_snapshot public.agent_user_snapshot_versions%rowtype;
  v_existing public.agent_plan_apply_idempotency%rowtype;
  v_plan_id uuid;
  v_revision bigint;
  v_inserted integer := 0;
  v_expected integer;
  v_result jsonb;
  v_next_snapshot_version text;
begin
  if v_user is null then raise exception using errcode='28000',message='AUTH_REQUIRED'; end if;
  select * into v_proposal from public.agent_plan_proposals where id=p_proposal_id and user_id=v_user for update;
  if not found then raise exception using errcode='P0002',message='NOT_FOUND'; end if;
  if v_proposal.status='applied' then
    select * into v_existing from public.agent_plan_apply_idempotency where user_id=v_user and idempotency_key=p_idempotency_key;
    if found and v_existing.proposal_id=v_proposal.id and v_existing.change_digest=v_proposal.change_digest and v_existing.status='applied' then return v_existing.result; end if;
    raise exception using errcode='P0001',message='ALREADY_APPLIED';
  end if;
  if v_proposal.status<>'approved' then raise exception using errcode='P0001',message='PROPOSAL_NOT_APPROVED'; end if;
  if pg_catalog.clock_timestamp()>=v_proposal.expires_at then raise exception using errcode='P0001',message='PROPOSAL_EXPIRED'; end if;
  select * into v_approval from public.agent_plan_approvals where id=p_approval_id and proposal_id=v_proposal.id and user_id=v_user for update;
  if not found then raise exception using errcode='P0002',message='NOT_FOUND'; end if;
  if v_approval.status='consumed' then raise exception using errcode='P0001',message='APPROVAL_CONSUMED'; end if;
  if v_approval.status<>'approved' then raise exception using errcode='P0001',message='APPROVAL_REQUIRED'; end if;
  if pg_catalog.clock_timestamp()>=v_approval.expires_at then raise exception using errcode='P0001',message='APPROVAL_EXPIRED'; end if;
  if v_approval.base_version<>v_proposal.base_version or v_approval.change_digest<>v_proposal.change_digest then raise exception using errcode='P0001',message='APPROVAL_UNTRUSTED'; end if;
  select * into v_snapshot from public.agent_user_snapshot_versions where user_id=v_user for update;
  if not found or v_snapshot.snapshot_version<>v_proposal.base_version then raise exception using errcode='40001',message='SNAPSHOT_CONFLICT'; end if;
  if pg_catalog.encode(extensions.digest(v_proposal.changes::text,'sha256'),'hex')<>v_proposal.change_digest then raise exception using errcode='P0001',message='CHANGE_DIGEST_MISMATCH'; end if;
  select * into v_existing from public.agent_plan_apply_idempotency where user_id=v_user and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.proposal_id<>v_proposal.id or v_existing.change_digest<>v_proposal.change_digest then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if;
    if v_existing.status='applied' then return v_existing.result; end if;
  end if;
  insert into public.agent_plan_apply_idempotency(user_id,idempotency_key,proposal_id,change_digest,status) values(v_user,p_idempotency_key,v_proposal.id,v_proposal.change_digest,'applying');
  update public.agent_plan_approvals set status='consumed',decided_at=pg_catalog.clock_timestamp() where id=v_approval.id and user_id=v_user;
  update public.agent_plan_proposals set status='applying' where id=v_proposal.id and user_id=v_user;
  select coalesce(max(revision),0)+1 into v_revision from public.task_plan_versions where user_id=v_user;
  v_plan_id:=pg_catalog.gen_random_uuid();
  insert into public.task_plan_versions(id,user_id,revision,source_snapshot_version,proposal_digest,rules_version,starts_on,ends_on,status,idempotency_key,created_at,confirmed_at,applied_at,supersedes_version_ids)
  values(v_plan_id,v_user,v_revision,v_proposal.base_version,v_proposal.change_digest,v_proposal.rules_version,v_proposal.starts_on,v_proposal.ends_on,'applied','server-'||p_idempotency_key,pg_catalog.clock_timestamp(),pg_catalog.clock_timestamp(),pg_catalog.clock_timestamp(),'{}');
  v_expected:=pg_catalog.jsonb_array_length(v_proposal.changes);
  insert into public.task_time_blocks(id,user_id,plan_version_id,task_id,starts_at,ends_at,planned_seconds)
  select (item->>'id')::uuid,v_user,v_plan_id,(item->>'task_id')::uuid,(item->>'starts_at')::timestamptz,(item->>'ends_at')::timestamptz,(item->>'planned_seconds')::integer from pg_catalog.jsonb_array_elements(v_proposal.changes) item;
  get diagnostics v_inserted=row_count;
  if v_inserted<>v_expected or (select count(*) from public.task_time_blocks where user_id=v_user and plan_version_id=v_plan_id and deleted_at is null)<>v_expected then raise exception using errcode='P0001',message='READBACK_MISMATCH'; end if;
  update public.agent_plan_proposals set status='applied',applied_at=pg_catalog.clock_timestamp() where id=v_proposal.id and user_id=v_user;
  -- Rotate the trusted opaque version so a second proposal based on the same
  -- snapshot cannot apply. A future snapshot builder must recompute the real
  -- data digest; this chain is a concurrency fence, not that digest.
  v_next_snapshot_version:=pg_catalog.encode(extensions.digest(
    v_snapshot.snapshot_version||':'||v_proposal.id::text||':'||v_proposal.change_digest,'sha256'),'hex');
  update public.agent_user_snapshot_versions set snapshot_version=v_next_snapshot_version,
    computed_at=pg_catalog.clock_timestamp() where user_id=v_user;
  v_result:=pg_catalog.jsonb_build_object('status','applied','plan_version_id',v_plan_id,
    'readback_verified',true,'block_count',v_inserted,'next_snapshot_version',v_next_snapshot_version);
  update public.agent_plan_apply_idempotency set status='applied',result=v_result where user_id=v_user and idempotency_key=p_idempotency_key;
  return v_result;
end $$;
revoke all on function public.apply_approved_plan(uuid,uuid,text) from public,anon;
grant execute on function public.apply_approved_plan(uuid,uuid,text) to authenticated;

create or replace function public.claim_agent_risk_events(p_limit integer default 20)
returns setof public.agent_risk_events language sql security definer set search_path = '' as $$
  with candidates as (
    select id from public.agent_risk_events
    where (status in ('pending','retry') and next_retry_at<=pg_catalog.clock_timestamp())
       or (status='processing' and lease_until<=pg_catalog.clock_timestamp())
    order by next_retry_at,created_at for update skip locked limit greatest(1,least(p_limit,100))
  )
  update public.agent_risk_events e set status='processing',attempts=e.attempts+1,
    lease_until=pg_catalog.clock_timestamp()+interval '60 seconds',lease_token=pg_catalog.gen_random_uuid(),updated_at=pg_catalog.clock_timestamp()
  from candidates c where e.id=c.id returning e.*
$$;
revoke all on function public.claim_agent_risk_events(integer) from public,anon,authenticated;
grant execute on function public.claim_agent_risk_events(integer) to service_role;

create or replace function public.finish_agent_risk_event(
  p_event_id uuid,p_lease_token uuid,p_error_code text default null,
  p_retry_at timestamptz default null,p_result jsonb default null,p_max_attempts integer default 8
) returns text language plpgsql security definer set search_path = '' as $$
declare v_event public.agent_risk_events%rowtype; v_next text;
begin
  select * into v_event from public.agent_risk_events where id=p_event_id for update;
  if not found or v_event.status<>'processing' or v_event.lease_token is distinct from p_lease_token
     or v_event.lease_until is null or v_event.lease_until<=pg_catalog.clock_timestamp() then
    return 'lease_lost';
  end if;
  if p_error_code is null then v_next:='done';
  elsif v_event.attempts>=greatest(1,p_max_attempts) then v_next:='dead';
  else v_next:='retry'; end if;
  update public.agent_risk_events set status=v_next,
    next_retry_at=coalesce(p_retry_at,next_retry_at),lease_until=null,lease_token=null,
    last_error_code=p_error_code,result=p_result,updated_at=pg_catalog.clock_timestamp()
    where id=p_event_id;
  return v_next;
end $$;
revoke all on function public.finish_agent_risk_event(uuid,uuid,text,timestamptz,jsonb,integer) from public,anon,authenticated;
grant execute on function public.finish_agent_risk_event(uuid,uuid,text,timestamptz,jsonb,integer) to service_role;

-- Persist one server-side risk evaluation idempotently and resolve risks that
-- disappeared from the new snapshot. Notifications remain queued, not sent.
create or replace function public.persist_agent_risk_snapshot(
  p_user_id uuid,p_snapshot_version text,p_risks jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_item jsonb;
  v_key text;
  v_type text;
  v_severity text;
  v_fingerprint text;
  v_prior public.agent_risk_states%rowtype;
  v_count integer:=0;
  v_queued integer:=0;
  v_escalated boolean;
  v_suppressed boolean;
  v_cooldown_elapsed boolean;
begin
  if p_user_id is null or p_snapshot_version is null or p_snapshot_version='' or p_risks is null or jsonb_typeof(p_risks)<>'array' then
    raise exception using errcode='22023',message='INVALID_RISK_SNAPSHOT';
  end if;
  for v_item in select value from pg_catalog.jsonb_array_elements(p_risks) loop
    v_key:=v_item->>'risk_key'; v_type:=v_item->>'risk_type'; v_severity:=v_item->>'severity';
    if v_key is null or v_type is null or v_severity is null or v_severity not in ('low','medium','high','critical') then
      raise exception using errcode='22023',message='INVALID_RISK_ITEM';
    end if;
    v_fingerprint:=pg_catalog.encode(extensions.digest(
      pg_catalog.jsonb_build_object('risk_type',v_type,'severity',v_severity,'payload',coalesce(v_item->'payload','{}'::jsonb))::text,
      'sha256'),'hex');
    select * into v_prior from public.agent_risk_states where user_id=p_user_id and risk_key=v_key for update;
    v_escalated:=v_prior.risk_key is not null
      and (case v_severity when 'critical' then 4 when 'high' then 3 when 'medium' then 2 else 1 end)
        > (case v_prior.severity when 'critical' then 4 when 'high' then 3 when 'medium' then 2 else 1 end);
    v_suppressed:=coalesce(v_prior.status='dismissed'
      and v_prior.cooldown_until>pg_catalog.clock_timestamp() and not v_escalated,false);
    v_cooldown_elapsed:=coalesce(v_prior.status='dismissed'
      and v_prior.cooldown_until<=pg_catalog.clock_timestamp(),false);
    insert into public.agent_risk_states(user_id,risk_key,snapshot_version,fingerprint,risk_type,severity,status,payload,evaluated_at,last_notified_at,cooldown_until)
    values(p_user_id,v_key,p_snapshot_version,v_fingerprint,v_type,v_severity,
      case when v_suppressed then 'dismissed' else 'active' end,
      coalesce(v_item->'payload','{}'::jsonb),pg_catalog.clock_timestamp(),v_prior.last_notified_at,
      case when v_suppressed then v_prior.cooldown_until else null end)
    on conflict(user_id,risk_key) do update set snapshot_version=excluded.snapshot_version,
      fingerprint=excluded.fingerprint,risk_type=excluded.risk_type,severity=excluded.severity,
      status=excluded.status,payload=excluded.payload,evaluated_at=excluded.evaluated_at,
      cooldown_until=excluded.cooldown_until;
    if not v_suppressed and (v_prior.risk_key is null or v_prior.fingerprint<>v_fingerprint or v_escalated or v_cooldown_elapsed) then
      insert into public.agent_risk_notifications(user_id,dedupe_key,risk_key,status,available_at,payload)
      values(p_user_id,v_key||':'||v_fingerprint||':'||p_snapshot_version,v_key,'pending',pg_catalog.clock_timestamp(),v_item)
      on conflict(user_id,dedupe_key) do nothing;
      if found then v_queued:=v_queued+1; end if;
    end if;
    v_count:=v_count+1;
  end loop;
  update public.agent_risk_states s set status='resolved',snapshot_version=p_snapshot_version,
    evaluated_at=pg_catalog.clock_timestamp(),cooldown_until=null
  where s.user_id=p_user_id and s.status in ('active','dismissed')
    and not exists(select 1 from pg_catalog.jsonb_array_elements(p_risks) i where i->>'risk_key'=s.risk_key);
  return pg_catalog.jsonb_build_object('evaluated_count',v_count,'notifications_queued',v_queued,'snapshot_version',p_snapshot_version);
end $$;
revoke all on function public.persist_agent_risk_snapshot(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.persist_agent_risk_snapshot(uuid,text,jsonb) to service_role;

create or replace function public.dismiss_agent_risk(p_risk_key text,p_cooldown interval default interval '12 hours')
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_updated integer;
begin
  if v_user is null then raise exception using errcode='28000',message='AUTH_REQUIRED'; end if;
  if p_cooldown<interval '0 seconds' or p_cooldown>interval '30 days' then
    raise exception using errcode='22023',message='INVALID_COOLDOWN';
  end if;
  update public.agent_risk_states set status='dismissed',cooldown_until=pg_catalog.clock_timestamp()+p_cooldown
    where user_id=v_user and risk_key=p_risk_key and status='active';
  get diagnostics v_updated=row_count;
  update public.agent_risk_notifications set status='suppressed'
    where user_id=v_user and risk_key=p_risk_key and status='pending';
  return v_updated=1;
end $$;
revoke all on function public.dismiss_agent_risk(text,interval) from public,anon;
grant execute on function public.dismiss_agent_risk(text,interval) to authenticated;

commit;
