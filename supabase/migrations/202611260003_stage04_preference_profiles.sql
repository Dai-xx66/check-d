-- Stage 04 · M1 · 偏好存储契约（PreferenceProfile）
--
-- 分工依据任务书 §2/§6：**存储契约与 RLS 归 M1，画像语义与采集触点归 M2**。
-- M1 只提供「按账号持久化 + 用户确认后才落库 + 并发版本」这一层，不解释偏好含义、不做推断。
--
-- 本文件是 11-26 冻结前的修订版，**从未在任何真实库执行过**（M3 11-26 14:1x 只读探测：
-- 表不存在，PGRST205），因此直接改本文件而不另开新迁移，不产生迁移成本。
--
-- 三条约束来自红线与共享协议：
--   1) 用户确认后才持久化 —— 未传 confirm=true 直接拒绝，不允许静默保存。
--   2) 显式（explicit）与推断（inferred）分开记录，不混成一个字段。
--   3) 用户可查看、可修正 —— 允许更新，且不提供删除整行的入口（清空用空数组表达）。
--
-- 11-26 修订四项（对应 M0 14:35 联合收口任务单第二节 1/2/3/5）：
--   A) preferred_slots 的 weekday 允许为 null：null = 每日默认，显式 weekday 覆盖之；不归一化。
--   B) 区分 schema_version（结构版本）与 data_version（用户数据并发版本），另加 expected_version 乐观锁。
--   C) 表级 insert/update 权限收回，写入只能走 upsert_preference_profile()，防绕过 confirm。
--   D) 时段超过 32 条硬失败，不截断（截断会静默丢用户偏好）。
--
-- 幂等：可重跑。函数用 create or replace；列用 add column if not exists。

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

-- 兼容已建过的表（本文件从未执行，这里只是保障可重跑）。
alter table public.preference_profiles
  add column if not exists created_at timestamptz not null default now();

-- B) 结构版本之外的「用户数据并发版本」。0 = 从未成功写入过。
alter table public.preference_profiles
  add column if not exists data_version integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.preference_profiles'::regclass
      and conname = 'preference_profiles_data_version_check'
  ) then
    alter table public.preference_profiles
      add constraint preference_profiles_data_version_check
      check (data_version >= 0);
  end if;
end $$;

comment on table public.preference_profiles is
  'Stage 04 module 01 storage contract. Semantics/collection belong to M2.';
comment on column public.preference_profiles.preferred_slots is
  'Array of {weekday:1-7|null, start_minute:0-1439, end_minute:1-1440}. '
  'weekday null = daily default; an entry with weekday=d overrides the daily default for that day. '
  'Empty array = no explicit preference. Never normalized (daily default and 7 explicit days stay distinguishable).';
comment on column public.preference_profiles.source is
  'explicit = user stated it; inferred = derived by M2 and must stay distinguishable.';
comment on column public.preference_profiles.confirmed_at is
  'Set only when the user confirmed. Null means not confirmed and must not be consumed as a preference.';
comment on column public.preference_profiles.schema_version is
  'STRUCTURE version of the stored JSON/columns. Owned by M1. Not a concurrency token.';
comment on column public.preference_profiles.data_version is
  'CONCURRENCY version of this user row, incremented by 1 on every successful upsert. '
  'Compare with expected_version; never confused with schema_version.';

alter table public.preference_profiles enable row level security;

drop policy if exists preference_profiles_owner_select on public.preference_profiles;
create policy preference_profiles_owner_select
  on public.preference_profiles for select to authenticated
  using (auth.uid() = user_id);

-- C) 与 behavior_events 同一模式：只建 SELECT 策略，不建 insert/update 策略。
--    这里的 drop 是给「曾经建过这些策略」的库做清理，保证迁移可重跑。
drop policy if exists preference_profiles_owner_insert on public.preference_profiles;
drop policy if exists preference_profiles_owner_update on public.preference_profiles;

-- C) 只读权限；写权限不授予任何客户端角色。
--    这条是唯一能真正拦住「绕过 confirm 直接写表」的手段：只靠 RLS 不行，
--    因为 authenticated 一旦拿到 insert/update，就可以自己写 confirmed_at=now() 跳过函数校验。
revoke all on public.preference_profiles from public, anon, authenticated;
grant select on public.preference_profiles to authenticated;

-- 归属保证在哪：函数是 security definer，以属主身份写表；表属主默认 bypass RLS，
-- 所以 RLS 策略在函数里并不生效，真正决定 user_id 的是函数内的 v_user := auth.uid()。
-- 这也正是「客户端不许直接写表」的原因——直写时归属只由 RLS 决定，而确认流程无人强制。

-- 保存偏好。必须显式确认；未确认直接拒绝。
-- owner 一律 auth.uid()，调用方不能写别人的行。
--
-- p_expected_version：
--   null  = 不校验（首次写入或客户端不关心并发）
--   整数  = 期望的 data_version；与当前值不等则抛 VERSION_CONFLICT（SQLSTATE 40001）
create or replace function public.upsert_preference_profile(
  p_profile jsonb,
  p_expected_version integer default null
)
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
  v_current   integer;
  v_next      integer;
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
  -- D) 上限 32：7 天 × 4 段 + 4 条每日默认，足够覆盖真实用例。
  --    超限直接拒绝，绝不截断——静默丢偏好比报错更糟。
  if jsonb_array_length(v_slots) > 32 then
    raise exception using errcode = '22023', message = 'TOO_MANY_SLOTS',
      detail = jsonb_array_length(v_slots)::text;
  end if;
  for v_slot in select * from jsonb_array_elements(v_slots) loop
    if jsonb_typeof(v_slot) <> 'object' then
      raise exception using errcode = '22023', message = 'INVALID_SLOT';
    end if;
    -- A) weekday 允许缺省或显式 null，含义是「每日默认」。
    if (v_slot ? 'weekday') and jsonb_typeof(v_slot->'weekday') = 'null' then
      v_wd := null;
    else
      v_wd := nullif(v_slot->>'weekday', '')::integer;
    end if;
    v_start := (v_slot->>'start_minute')::integer;
    v_end   := (v_slot->>'end_minute')::integer;
    if v_wd is not null and (v_wd < 1 or v_wd > 7) then
      raise exception using errcode = '22023', message = 'INVALID_SLOT_RANGE';
    end if;
    if v_start is null or v_start < 0 or v_start > 1439
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

  -- B) 乐观锁：先按用户加事务级咨询锁，把同一账号的并发写入串行化，
  --    否则「读版本 → 比较 → 写」之间有 TOCTOU 窗口，CAS 只是摆设。
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 0));

  select data_version into v_current
  from public.preference_profiles
  where user_id = v_user;

  if v_current is null then
    if p_expected_version is not null and p_expected_version <> 0 then
      raise exception using errcode = '40001', message = 'VERSION_CONFLICT',
        detail = '0';
    end if;
  else
    if p_expected_version is not null and p_expected_version <> v_current then
      raise exception using errcode = '40001', message = 'VERSION_CONFLICT',
        detail = v_current::text;
    end if;
  end if;

  insert into public.preference_profiles as p (
    user_id, preferred_slots, focus_minutes, break_minutes,
    source, confirmed_at, schema_version, data_version, updated_at
  ) values (
    v_user, v_slots, v_focus, v_break, v_source, v_confirmed_at, 1, 1, now()
  )
  on conflict (user_id) do update set
    preferred_slots = excluded.preferred_slots,
    focus_minutes   = excluded.focus_minutes,
    break_minutes   = excluded.break_minutes,
    source          = excluded.source,
    confirmed_at    = excluded.confirmed_at,
    schema_version  = excluded.schema_version,
    data_version    = p.data_version + 1,
    updated_at      = now()
  returning data_version into v_next;

  return jsonb_build_object(
    'user_id', v_user,
    'source', v_source,
    'confirmed_at', v_confirmed_at,
    'schema_version', 1,
    'data_version', v_next,
    'saved', true
  );
end;
$$;

revoke all on function public.upsert_preference_profile(jsonb, integer) from public, anon;
grant execute on function public.upsert_preference_profile(jsonb, integer) to authenticated;

-- 旧签名（单参）若曾存在，也一并收回执行权，避免绕过 expected_version。
-- 注意：函数不存在时直接 revoke 会报 42883 让整个迁移失败，所以先判存在。
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'upsert_preference_profile'
      and pg_get_function_identity_arguments(p.oid) = 'p_profile jsonb'
  ) then
    revoke all on function public.upsert_preference_profile(jsonb) from public, anon, authenticated;
  end if;
end $$;

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
         confirmed_at, schema_version, data_version, updated_at
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
      'confirmed_at', null,
      'schema_version', 1,
      'data_version', 0
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
    'data_version', v_row.data_version,
    'updated_at', v_row.updated_at
  );
end;
$$;

revoke all on function public.get_preference_profile() from public, anon;
grant execute on function public.get_preference_profile() to authenticated;

commit;
