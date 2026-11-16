-- CheckD planning preflight foundation.
-- This records per-device sync attestations and Flutter-built course
-- occurrences. It is not an execution grant: callers must still validate the
-- live business-data version and a trusted approval in the apply transaction.

create table if not exists public.agent_user_data_versions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data_version bigint not null default 0 check (data_version >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.agent_device_sync_watermarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  local_generation bigint not null check (local_generation >= 0),
  server_data_version bigint not null check (server_data_version >= 0),
  acknowledged_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

create table if not exists public.agent_course_occurrence_snapshots (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  local_generation bigint not null check (local_generation >= 0),
  from_date date not null,
  through_date date not null,
  timezone text not null check (timezone = 'Asia/Shanghai'),
  builder_version text not null,
  course_data_version text not null,
  generated_at timestamptz not null,
  server_data_version bigint not null check (server_data_version >= 0),
  occurrence_digest text not null,
  occurrences jsonb not null check (jsonb_typeof(occurrences) = 'array'),
  created_at timestamptz not null default now(),
  primary key (user_id, device_id, from_date, through_date),
  check (through_date >= from_date),
  check (through_date - from_date between 0 and 30)
);

alter table public.agent_user_data_versions enable row level security;
alter table public.agent_device_sync_watermarks enable row level security;
alter table public.agent_course_occurrence_snapshots enable row level security;

drop policy if exists agent_user_data_versions_owner on public.agent_user_data_versions;
create policy agent_user_data_versions_owner
  on public.agent_user_data_versions for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists agent_device_sync_watermarks_owner on public.agent_device_sync_watermarks;
create policy agent_device_sync_watermarks_owner
  on public.agent_device_sync_watermarks for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists agent_course_occurrence_snapshots_owner on public.agent_course_occurrence_snapshots;
create policy agent_course_occurrence_snapshots_owner
  on public.agent_course_occurrence_snapshots for select to authenticated
  using (auth.uid() = user_id);

revoke all on public.agent_user_data_versions from public, anon, authenticated;
revoke all on public.agent_device_sync_watermarks from public, anon, authenticated;
revoke all on public.agent_course_occurrence_snapshots from public, anon, authenticated;
grant select on public.agent_user_data_versions to authenticated;
grant select on public.agent_device_sync_watermarks to authenticated;
grant select on public.agent_course_occurrence_snapshots to authenticated;

create or replace function public.bump_agent_user_data_version()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  old_user uuid;
  new_user uuid;
begin
  if tg_op <> 'INSERT' then
    old_user := (to_jsonb(old)->>'user_id')::uuid;
  end if;
  if tg_op <> 'DELETE' then
    new_user := (to_jsonb(new)->>'user_id')::uuid;
  end if;
  if old_user is not null then
    insert into public.agent_user_data_versions(user_id, data_version)
    values (old_user, 1)
    on conflict (user_id) do update
      set data_version = public.agent_user_data_versions.data_version + 1,
          updated_at = now();
  end if;
  if new_user is not null and new_user is distinct from old_user then
    insert into public.agent_user_data_versions(user_id, data_version)
    values (new_user, 1)
    on conflict (user_id) do update
      set data_version = public.agent_user_data_versions.data_version + 1,
          updated_at = now();
  elsif new_user is not null and old_user is null then
    insert into public.agent_user_data_versions(user_id, data_version)
    values (new_user, 1)
    on conflict (user_id) do update
      set data_version = public.agent_user_data_versions.data_version + 1,
          updated_at = now();
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke all on function public.bump_agent_user_data_version() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array[
    'tasks', 'task_schedules', 'one_time_reminders', 'task_completions',
    'courses', 'course_schedule_rules', 'schedule_templates',
    'schedule_template_segments', 'semesters', 'daily_item_overrides'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists bump_agent_user_data_version on public.%I', t);
      execute format(
        'create trigger bump_agent_user_data_version after insert or update or delete on public.%I for each row execute function public.bump_agent_user_data_version()',
        t
      );
    end if;
  end loop;
end;
$$;

create or replace function public.publish_agent_course_occurrence_snapshot(
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
     or p_snapshot->>'builder_version' <> 'checkd_flutter_course_occurrence_v1'
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
  select count(*) into v_count
  from pg_catalog.jsonb_array_elements(p_snapshot->'occurrences') as x(value)
  where jsonb_typeof(x.value) <> 'object'
     or x.value->>'timezone' <> 'Asia/Shanghai'
     or (x.value->>'local_date')::date not between v_from and v_through
     or (x.value->>'start_minute')::integer < 0
     or (x.value->>'start_minute')::integer >= 1440
     or (x.value->>'end_minute')::integer <= (x.value->>'start_minute')::integer
     or (x.value->>'end_minute')::integer > 1440
     or coalesce(x.value->>'course_id', '') = ''
     or coalesce(x.value->>'occurrence_id', '') = '';
  if v_count <> 0 then
    raise exception using errcode = '22023', message = 'INVALID_OCCURRENCE_RANGE';
  end if;
  select count(*) into v_count
  from pg_catalog.jsonb_array_elements(p_snapshot->'occurrences') as x(value)
  where not exists (
      select 1 from public.courses c
      where c.id = (x.value->>'course_id')::uuid
        and c.user_id = v_user
        and c.deleted_at is null
        and c.status = 'active'
    )
    or (
      nullif(x.value->>'schedule_rule_id', '') is not null
      and not exists (
        select 1 from public.course_schedule_rules r
        where r.id = (x.value->>'schedule_rule_id')::uuid
          and r.course_id = (x.value->>'course_id')::uuid
          and r.user_id = v_user
          and r.deleted_at is null
      )
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
  insert into public.agent_course_occurrence_snapshots(
    user_id, device_id, local_generation, from_date, through_date, timezone,
    builder_version, course_data_version, generated_at, server_data_version,
    occurrence_digest, occurrences
  ) values (
    v_user, p_device_id, v_generation, v_from, v_through, 'Asia/Shanghai',
    p_snapshot->>'builder_version', p_snapshot->>'course_data_version',
    (p_snapshot->>'generated_at')::timestamptz, v_current_version,
    v_digest, p_snapshot->'occurrences'
  ) on conflict (user_id, device_id, from_date, through_date) do update set
    local_generation = excluded.local_generation,
    builder_version = excluded.builder_version,
    course_data_version = excluded.course_data_version,
    generated_at = excluded.generated_at,
    server_data_version = excluded.server_data_version,
    occurrence_digest = excluded.occurrence_digest,
    occurrences = excluded.occurrences,
    created_at = now()
  where public.agent_course_occurrence_snapshots.local_generation <= excluded.local_generation;
  return jsonb_build_object(
    'ok', true, 'server_data_version', v_current_version,
    'occurrence_digest', v_digest
  );
end;
$$;

create or replace function public.acknowledge_agent_device_sync_checkpoint(
  p_device_id uuid,
  p_local_generation bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_current_version bigint;
  v_saved_generation bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_local_generation < 0 then
    raise exception using errcode = '22023', message = 'INVALID_GENERATION';
  end if;
  select coalesce(data_version, 0) into v_current_version
  from public.agent_user_data_versions where user_id = v_user;
  v_current_version := coalesce(v_current_version, 0);
  if not exists (
    select 1 from public.agent_course_occurrence_snapshots s
    where s.user_id = v_user and s.device_id = p_device_id
      and s.local_generation = p_local_generation
      and s.server_data_version = v_current_version
  ) then
    raise exception using errcode = '40001', message = 'COURSE_SNAPSHOT_STALE';
  end if;
  insert into public.agent_device_sync_watermarks(
    user_id, device_id, local_generation, server_data_version, acknowledged_at
  ) values (v_user, p_device_id, p_local_generation, v_current_version, now())
  on conflict (user_id, device_id) do update set
    local_generation = excluded.local_generation,
    server_data_version = excluded.server_data_version,
    acknowledged_at = excluded.acknowledged_at
  where public.agent_device_sync_watermarks.local_generation <= excluded.local_generation
  returning local_generation into v_saved_generation;
  if v_saved_generation is null then
    raise exception using errcode = '40001', message = 'GENERATION_REGRESSION';
  end if;
  return jsonb_build_object(
    'ok', true, 'local_generation', v_saved_generation,
    'server_data_version', v_current_version, 'acknowledged_at', now()
  );
end;
$$;

create or replace function public.get_agent_planning_checkpoint_status(
  p_from_date date,
  p_through_date date
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_version bigint;
  v_devices integer;
  v_valid_devices boolean;
  v_valid_occurrences boolean;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_through_date < p_from_date or p_through_date - p_from_date > 30 then
    raise exception using errcode = '22023', message = 'INVALID_SNAPSHOT_RANGE';
  end if;
  select coalesce(data_version, 0) into v_version
  from public.agent_user_data_versions where user_id = v_user;
  v_version := coalesce(v_version, 0);
  select count(*), coalesce(bool_and(
      w.server_data_version = v_version
      and w.acknowledged_at >= now() - interval '15 minutes'
    ), false)
    into v_devices, v_valid_devices
  from public.agent_device_sync_watermarks w where w.user_id = v_user;
  select v_devices > 0 and not exists (
    select 1 from public.agent_device_sync_watermarks w
    where w.user_id = v_user and (
      w.server_data_version <> v_version
      or w.acknowledged_at < now() - interval '15 minutes'
      or not exists (
        select 1 from public.agent_course_occurrence_snapshots s
        where s.user_id = w.user_id and s.device_id = w.device_id
          and s.server_data_version = v_version
          and s.from_date <= p_from_date and s.through_date >= p_through_date
          and s.builder_version = 'checkd_flutter_course_occurrence_v1'
          and s.generated_at <= now()
          and s.generated_at >= now() - interval '15 minutes'
      )
    )
  ) into v_valid_occurrences;
  return jsonb_build_object(
    'server_data_version', v_version,
    'known_device_count', v_devices,
    'device_checkpoints_current', v_valid_devices and v_devices > 0,
    'course_occurrences_cover_window', coalesce(v_valid_occurrences, false),
    'course_snapshot_ttl_seconds', 900,
    -- This foundation is necessary, not sufficient. No executable proposal is
    -- authorized by this status endpoint.
    'planning_ready', v_valid_devices and coalesce(v_valid_occurrences, false),
    'execution_eligible', false,
    'reason', 'proposal_and_trusted_approval_gate_not_integrated'
  );
end;
$$;

revoke all on function public.publish_agent_course_occurrence_snapshot(uuid, jsonb) from public, anon;
revoke all on function public.acknowledge_agent_device_sync_checkpoint(uuid, bigint) from public, anon;
revoke all on function public.get_agent_planning_checkpoint_status(date, date) from public, anon;
grant execute on function public.publish_agent_course_occurrence_snapshot(uuid, jsonb) to authenticated;
grant execute on function public.acknowledge_agent_device_sync_checkpoint(uuid, bigint) to authenticated;
grant execute on function public.get_agent_planning_checkpoint_status(date, date) to authenticated;

notify pgrst, 'reload schema';
