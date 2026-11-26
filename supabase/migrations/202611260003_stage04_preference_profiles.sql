-- Stage 04 · M1 · 偏好存储契约（PreferenceProfile）
--
-- 分工依据任务书 §2/§6：**存储契约与 RLS 归 M1，画像语义与采集触点归 M2**。
-- M1 只提供「按账号持久化 + 用户确认后才落库」这一层，不解释偏好含义、不做推断。
--
-- 三条约束来自红线与共享协议：
--   1) 用户确认后才持久化 —— 未传 confirm=true 直接拒绝，不允许静默保存。
--   2) 显式（explicit）与推断（inferred）分开记录，不混成一个字段。
--   3) 用户可查看、可修正 —— 允许 update，且不提供删除整行的入口（清空用空数组表达）。
--
-- 幂等：可重跑。函数用 create or replace。

begin;

create table if not exists public.preference_profiles (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  preferred_slots jsonb not null default '[]'::jsonb,
  focus_minutes  integer check (focus_minutes is null
                                or (focus_minutes >= 5 and focus_minutes <= 480)),
  break_minutes  integer check (break_minutes is null
                                or (break_minutes >= 0 and break_minutes <= 120)),
  source         text not null default 'explicit'
    check (source in ('explicit', 'inferred')),
  confirmed_at   timestamptz,
  schema_version integer not null default 1 check (schema_version >= 1),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.preference_profiles is
  'Stage 04 module 01 storage contract. Semantics/collection belong to M2.';
comment on column public.preference_profiles.preferred_slots is
  'Array of {weekday:1-7, start_minute:0-1439, end_minute:1-1440}. Empty array = no explicit preference.';
comment on column public.preference_profiles.source is
  'explicit = user stated it; inferred = derived by M2 and must stay distinguishable.';
comment on column public.preference_profiles.confirmed_at is
  'Set only when the user confirmed. Null means not confirmed and must not be consumed as a preference.';

alter table public.preference_profiles enable row level security;

drop policy if exists preference_profiles_owner_select on public.preference_profiles;
create policy preference_profiles_owner_select
  on public.preference_profiles for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists preference_profiles_owner_insert on public.preference_profiles;
create policy preference_profiles_owner_insert
  on public.preference_profiles for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists preference_profiles_owner_update on public.preference_profiles;
create policy preference_profiles_owner_update
  on public.preference_profiles for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on public.preference_profiles from public, anon, authenticated;
grant select, insert, update on public.preference_profiles to authenticated;

-- 保存偏好。必须显式确认；未确认为 null 时拒绝。
-- owner 一律 auth.uid()，调用方不能写别人的行。
create or replace function public.upsert_preference_profile(p_profile jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_slots     jsonb;
  v_focus     integer;
  v_break     integer;
  v_source    text;
  v_confirm   boolean;
  v_confirmed_at timestamptz;
  v_slot      jsonb;
  v_wd        integer;
  v_start     integer;
  v_end       integer;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if jsonb_typeof(p_profile) <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_PROFILE';
  end if;

  v_confirm := coalesce((p_profile->>'confirm')::boolean, false);
  if not v_confirm then
    -- 红线：用户确认后才持久化。这里不是「先存着待确认」，是直接不写。
    raise exception using errcode = '22023', message = 'CONFIRMATION_REQUIRED';
  end if;

  v_slots := coalesce(p_profile->'preferred_slots', '[]'::jsonb);
  if jsonb_typeof(v_slots) <> 'array' then
    raise exception using errcode = '22023', message = 'INVALID_PREFERRED_SLOTS';
  end if;
  if jsonb_array_length(v_slots) > 32 then
    raise exception using errcode = '22023', message = 'TOO_MANY_SLOTS';
  end if;
  for v_slot in select * from jsonb_array_elements(v_slots) loop
    if jsonb_typeof(v_slot) <> 'object' then
      raise exception using errcode = '22023', message = 'INVALID_SLOT';
    end if;
    v_wd    := (v_slot->>'weekday')::integer;
    v_start := (v_slot->>'start_minute')::integer;
    v_end   := (v_slot->>'end_minute')::integer;
    if v_wd is null or v_wd < 1 or v_wd > 7
       or v_start is null or v_start < 0 or v_start > 1439
       or v_end is null or v_end < 1 or v_end > 1440
       or v_end <= v_start then
      raise exception using errcode = '22023', message = 'INVALID_SLOT_RANGE';
    end if;
  end loop;

  v_focus  := nullif(p_profile->>'focus_minutes', '')::integer;
  v_break  := nullif(p_profile->>'break_minutes', '')::integer;
  v_source := coalesce(nullif(p_profile->>'source', ''), 'explicit');
  if v_source not in ('explicit', 'inferred') then
    raise exception using errcode = '22023', message = 'INVALID_SOURCE';
  end if;

  v_confirmed_at := case when v_source = 'explicit' then now() else null end;

  insert into public.preference_profiles as p (
    user_id, preferred_slots, focus_minutes, break_minutes,
    source, confirmed_at, schema_version, updated_at
  ) values (
    v_user, v_slots, v_focus, v_break, v_source, v_confirmed_at, 1, now()
  )
  on conflict (user_id) do update set
    preferred_slots = excluded.preferred_slots,
    focus_minutes   = excluded.focus_minutes,
    break_minutes   = excluded.break_minutes,
    source          = excluded.source,
    confirmed_at    = excluded.confirmed_at,
    schema_version  = excluded.schema_version,
    updated_at      = now();

  return jsonb_build_object(
    'user_id', v_user,
    'source', v_source,
    'confirmed_at', v_confirmed_at,
    'saved', true
  );
end;
$$;

revoke all on function public.upsert_preference_profile(jsonb) from public, anon;
grant execute on function public.upsert_preference_profile(jsonb) to authenticated;

-- 读取自己的偏好。未确认（confirmed_at 为空）的 inferred 行也返回，但带标记，
-- 由 M2 决定能否当作有效偏好使用。
create or replace function public.get_preference_profile()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_row  record;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  select preferred_slots, focus_minutes, break_minutes, source,
         confirmed_at, schema_version, updated_at
    into v_row
  from public.preference_profiles
  where user_id = v_user;

  if not found then
    return jsonb_build_object(
      'status', 'absent',
      'preferred_slots', '[]'::jsonb,
      'focus_minutes', null,
      'break_minutes', null,
      'source', null,
      'confirmed_at', null
    );
  end if;

  return jsonb_build_object(
    'status', case when v_row.confirmed_at is null then 'unconfirmed' else 'ok' end,
    'preferred_slots', v_row.preferred_slots,
    'focus_minutes', v_row.focus_minutes,
    'break_minutes', v_row.break_minutes,
    'source', v_row.source,
    'confirmed_at', v_row.confirmed_at,
    'schema_version', v_row.schema_version,
    'updated_at', v_row.updated_at
  );
end;
$$;

revoke all on function public.get_preference_profile() from public, anon;
grant execute on function public.get_preference_profile() to authenticated;

commit;
