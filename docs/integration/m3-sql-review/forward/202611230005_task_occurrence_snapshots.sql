-- CheckD long-term / recurring task occurrence evidence chain (M3, 2026-11-23).
--
-- Mirrors public.agent_course_occurrence_snapshots (202611160001) exactly.
-- The SERVER NEVER expands a long-term task into occurrences. Only the client
-- (M2) may publish the already-expanded instances; this migration only stores
-- and validates that attestation. Clearing the planning blocker without a
-- version-consistent, device-owned, digest-consistent client snapshot would
-- fabricate the evidence chain and is forbidden by M0's red lines.
--
-- This file is IDEMPOTENT. It is NOT executed by this change set: it is handed
-- to M0 for review together with its rollback (202611230006) before any
-- production schema change, per the 2026-11-23 16:04 ruling.

create table if not exists public.agent_task_occurrence_snapshots (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  local_generation bigint not null check (local_generation >= 0),
  from_date date not null,
  through_date date not null,
  timezone text not null check (timezone = 'Asia/Shanghai'),
  builder_version text not null,
  task_data_version text not null,
  generated_at timestamptz not null,
  server_data_version bigint not null check (server_data_version >= 0),
  occurrence_digest text not null,
  occurrences jsonb not null check (jsonb_typeof(occurrences) = 'array'),
  created_at timestamptz not null default now(),
  primary key (user_id, device_id, from_date, through_date),
  check (through_date >= from_date),
  check (through_date - from_date between 0 and 30)
);

alter table public.agent_task_occurrence_snapshots enable row level security;

drop policy if exists agent_task_occurrence_snapshots_owner on public.agent_task_occurrence_snapshots;
create policy agent_task_occurrence_snapshots_owner
  on public.agent_task_occurrence_snapshots for select to authenticated
  using (auth.uid() = user_id);

revoke all on public.agent_task_occurrence_snapshots from public, anon, authenticated;
grant select on public.agent_task_occurrence_snapshots to authenticated;

create or replace function public.publish_agent_task_occurrence_snapshot(
  p_device_id uuid,
  p_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_from date;
  v_through date;
  v_generation bigint;
  v_current_version bigint;
  v_count integer;
  v_digest text;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if jsonb_typeof(p_snapshot) <> 'object'
     or p_snapshot->>'timezone' <> 'Asia/Shanghai'
     or p_snapshot->>'builder_version' <> 'checkd_flutter_task_occurrence_v1'
     or p_snapshot->>'device_id' <> p_device_id::text then
    raise exception using errcode = '22023', message = 'INVALID_SNAPSHOT';
  end if;
  v_from := (p_snapshot->>'from_date')::date;
  v_through := (p_snapshot->>'through_date')::date;
  v_generation := (p_snapshot->>'local_generation')::bigint;
  if v_through < v_from or v_through - v_from > 30 or v_generation < 0 then
    raise exception using errcode = '22023', message = 'INVALID_SNAPSHOT_RANGE';
  end if;
  if jsonb_typeof(p_snapshot->'occurrences') <> 'array' then
    raise exception using errcode = '22023', message = 'INVALID_OCCURRENCES';
  end if;

  -- Structural validation of every published occurrence. Out-of-window items
  -- are rejected here (unlike course snapshots, the client is expected to
  -- publish exactly the requested horizon); the read path still crops them.
  select count(*) into v_count
  from pg_catalog.jsonb_array_elements(p_snapshot->'occurrences') as x(value)
  where jsonb_typeof(x.value) <> 'object'
     or x.value->>'timezone' <> 'Asia/Shanghai'
     or (x.value->>'local_date')::date not between v_from and v_through
     or (x.value->>'start_minute')::integer < 0
     or (x.value->>'start_minute')::integer >= 1440
     or (x.value->>'end_minute')::integer <= (x.value->>'start_minute')::integer
     or (x.value->>'end_minute')::integer > 1440
     or coalesce(x.value->>'task_id', '') = ''
     or coalesce(x.value->>'occurrence_id', '') = '';
  if v_count <> 0 then
    raise exception using errcode = '22023', message = 'INVALID_OCCURRENCE_RANGE';
  end if;

  -- Ownership + "genuinely recurring" check. A one_time task must not be
  -- smuggled into the long-term occurrence channel, and a task owned by
  -- another account must never be accepted.
  select count(*) into v_count
  from pg_catalog.jsonb_array_elements(p_snapshot->'occurrences') as x(value)
  where not exists (
      select 1 from public.tasks t
      where t.id = (x.value->>'task_id')::uuid
        and t.user_id = v_user
        and t.deleted_at is null
        and t.status = 'active'
        and t.type::text <> 'one_time'
    );
  if v_count <> 0 then
    raise exception using errcode = '42501', message = 'OCCURRENCE_RESOURCE_NOT_OWNED';
  end if;

  select coalesce(data_version, 0) into v_current_version
  from public.agent_user_data_versions where user_id = v_user;
  v_current_version := coalesce(v_current_version, 0);
  v_digest := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to((p_snapshot->'occurrences')::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into public.agent_task_occurrence_snapshots(
    user_id, device_id, local_generation, from_date, through_date, timezone,
    builder_version, task_data_version, generated_at, server_data_version,
    occurrence_digest, occurrences
  ) values (
    v_user, p_device_id, v_generation, v_from, v_through, 'Asia/Shanghai',
    p_snapshot->>'builder_version', p_snapshot->>'task_data_version',
    (p_snapshot->>'generated_at')::timestamptz, v_current_version,
    v_digest, p_snapshot->'occurrences'
  ) on conflict (user_id, device_id, from_date, through_date) do update set
    local_generation = excluded.local_generation,
    builder_version = excluded.builder_version,
    task_data_version = excluded.task_data_version,
    generated_at = excluded.generated_at,
    server_data_version = excluded.server_data_version,
    occurrence_digest = excluded.occurrence_digest,
    occurrences = excluded.occurrences,
    created_at = now()
  where public.agent_task_occurrence_snapshots.local_generation <= excluded.local_generation;

  return jsonb_build_object(
    'ok', true, 'server_data_version', v_current_version,
    'occurrence_digest', v_digest
  );
end;
$$;

revoke all on function public.publish_agent_task_occurrence_snapshot(uuid, jsonb) from public, anon;
grant execute on function public.publish_agent_task_occurrence_snapshot(uuid, jsonb) to authenticated;

notify pgrst, 'reload schema';
