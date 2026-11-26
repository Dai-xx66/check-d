-- Stage 04 · M1 · 情境感知与数据基础
--
-- 负责人 M1。范围：模块 03（ContextSnapshot）+ 共享数据基础（BehaviorEvent 追加存储）。
-- 依据：STAGE 04 任务书 §6 共享协议 v1、§8 红线、M1 工作包 A/B/C。
--
-- 边界（三条，改之前先读）
--   1) 本迁移**不展开**长周期任务。`agent_task_occurrence_snapshots` 只能由客户端发布，
--      这里只读它；缺失或过期时快照标 stale/missing，**不伪造可用时段**。
--   2) 课程固定事件由本迁移展开：`courses` + `course_schedule_rules` + `semesters` 三者
--      足以确定某天是否上课，不依赖客户端 attestation。
--   3) 不修改任何既有表结构。只新增 1 张表（append-only）与 3 个函数。
--
-- 幂等：所有 DDL 均可重跑。函数用 create or replace。
-- 未执行说明：本文件提交时**未在任何真实库执行**（M1 侧无数据库连接），执行前需 M0 审核。

begin;

-- ============================================================
-- 1. behavior_events：按账号追加、只读查询的最小事件存储
-- ============================================================
-- 幂等键 = (user_id, event_id)。同一 event_id 重试不重复计数。
-- 没有 update/delete 授权：事件是事实记录，不允许改写。
create table if not exists public.behavior_events (
  user_id         uuid not null references auth.users(id) on delete cascade,
  event_id        uuid not null,
  task_id         uuid references public.tasks(id) on delete set null,
  plan_id         text,
  event_type      text not null
    check (event_type in (
      'plan_accepted', 'plan_rejected', 'plan_modified',
      'task_started', 'task_completed', 'task_deferred',
      'preference_confirmed', 'manual_note')),
  occurred_at     timestamptz not null,
  planned_minutes integer check (planned_minutes is null or planned_minutes >= 0),
  actual_minutes  integer check (actual_minutes is null or actual_minutes >= 0),
  source          text not null
    check (source in ('app', 'workbuddy', 'import', 'test')),
  reason          text check (reason is null or char_length(reason) <= 500),
  schema_version  integer not null default 1 check (schema_version >= 1),
  created_at      timestamptz not null default now(),
  primary key (user_id, event_id)
);

comment on table public.behavior_events is
  'Append-only behavior events for stage 04 module 02/03. Never updated in place.';
comment on column public.behavior_events.event_id is
  'Client-generated idempotency key; a retried append must not create a second row.';
comment on column public.behavior_events.plan_id is
  'Opaque plan/proposal reference. Null when the event is not tied to a plan.';
comment on column public.behavior_events.source is
  'Where the event came from. test = explicit test/mock data, must stay distinguishable.';
comment on column public.behavior_events.actual_minutes is
  'Real elapsed minutes when known. Timer events alone must not be read as completion.';

create index if not exists behavior_events_user_occurred_idx
  on public.behavior_events (user_id, occurred_at desc);
create index if not exists behavior_events_user_task_idx
  on public.behavior_events (user_id, task_id)
  where task_id is not null;

alter table public.behavior_events enable row level security;

drop policy if exists behavior_events_owner_select on public.behavior_events;
create policy behavior_events_owner_select
  on public.behavior_events for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists behavior_events_owner_insert on public.behavior_events;
create policy behavior_events_owner_insert
  on public.behavior_events for insert to authenticated
  with check (auth.uid() = user_id);

revoke all on public.behavior_events from public, anon, authenticated;
grant select, insert on public.behavior_events to authenticated;

-- 追加一条事件。幂等：同一 event_id 重复调用返回 inserted=false，不新增行。
-- owner 一律由 auth.uid() 决定，调用方无法指定别人的 user_id。
-- task_id 必须属于当前账号（父子归属校验）。
create or replace function public.append_behavior_event(p_event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_event_id  uuid;
  v_task_id   uuid;
  v_type      text;
  v_source    text;
  v_occurred  timestamptz;
  v_planned   integer;
  v_actual    integer;
  v_inserted  boolean := false;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if jsonb_typeof(p_event) <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_EVENT';
  end if;

  begin
    v_event_id := (p_event->>'event_id')::uuid;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_EVENT_ID';
  end;

  v_type   := p_event->>'event_type';
  v_source := p_event->>'source';
  if v_type is null or v_source is null then
    raise exception using errcode = '22023', message = 'INVALID_EVENT';
  end if;

  begin
    v_occurred := (p_event->>'occurred_at')::timestamptz;
    v_task_id  := nullif(p_event->>'task_id', '')::uuid;
    v_planned  := nullif(p_event->>'planned_minutes', '')::integer;
    v_actual   := nullif(p_event->>'actual_minutes', '')::integer;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_EVENT_FIELD';
  end;

  if v_occurred is null then
    raise exception using errcode = '22023', message = 'INVALID_EVENT_FIELD';
  end if;

  -- 父子归属：不允许把事件挂到别人的任务上。
  if v_task_id is not null and not exists (
    select 1 from public.tasks t
    where t.id = v_task_id and t.user_id = v_user
  ) then
    raise exception using errcode = '42501', message = 'TASK_NOT_OWNED';
  end if;

  insert into public.behavior_events (
    user_id, event_id, task_id, plan_id, event_type,
    occurred_at, planned_minutes, actual_minutes, source, reason, schema_version
  ) values (
    v_user, v_event_id, v_task_id,
    nullif(p_event->>'plan_id', ''),
    v_type, v_occurred, v_planned, v_actual, v_source,
    nullif(p_event->>'reason', ''),
    coalesce(nullif(p_event->>'schema_version', '')::integer, 1)
  )
  on conflict (user_id, event_id) do nothing;

  v_inserted := found;

  return jsonb_build_object(
    'event_id', v_event_id,
    'inserted', v_inserted,
    'owner', 'auth.uid()',
    'schema_version', 1
  );
end;
$$;

revoke all on function public.append_behavior_event(jsonb) from public, anon;
grant execute on function public.append_behavior_event(jsonb) to authenticated;

-- 读事件：按账号 + 时间窗，可选按任务过滤。只读。
create or replace function public.list_behavior_events(
  p_from timestamptz,
  p_through timestamptz,
  p_task_id uuid default null,
  p_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 2000);
  v_rows  jsonb;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_from is null or p_through is null or p_through < p_from then
    raise exception using errcode = '22023', message = 'INVALID_RANGE';
  end if;

  select coalesce(jsonb_agg(row_to_json(e)::jsonb order by e.occurred_at), '[]'::jsonb)
    into v_rows
  from (
    select event_id, task_id, plan_id, event_type, occurred_at,
           planned_minutes, actual_minutes, source, reason, schema_version
    from public.behavior_events
    where user_id = v_user
      and occurred_at >= p_from
      and occurred_at <= p_through
      and (p_task_id is null or task_id = p_task_id)
    order by occurred_at
    limit v_limit
  ) e;

  return jsonb_build_object(
    'events', v_rows,
    'count', jsonb_array_length(v_rows),
    'window', jsonb_build_object('from', p_from, 'through', p_through),
    'timezone', 'UTC'
  );
end;
$$;

revoke all on function public.list_behavior_events(timestamptz, timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.list_behavior_events(timestamptz, timestamptz, uuid, integer)
  to authenticated;

commit;
