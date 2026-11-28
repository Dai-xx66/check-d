-- M1 数据层完整链路验证：偏好 → 情境快照 → 决策输入 → 行为事件 → 读回
--
-- 目的：之前每一段都单独验过（02 验权限/RLS/幂等，03 验学期/排期/空闲），
-- 但从来没过一条「从用户偏好出发，一路走到事件读回」的完整路径。
-- M0 要的第四阶段链路是「数据采集→情境/偏好/行为特征→评分→候选排序→用户确认→执行/回读」，
-- 其中**评分与排序属 M2**，本脚本只验 M1 负责的那一段：偏好与情境读、决策输入、事件写与回读。
--
-- 依赖：00_supabase_stub.sql + 9 个既有 migration + 3 个 stage04 migration + 03_snapshot.sql 的数据
-- （03 已插入：学期、3 门课、3 个长期任务及其排期；账号 a=1111…111111）

\set ON_ERROR_STOP 1
\pset pager off

-- 可重跑：清掉本账号上一轮的偏好（postgres 身份，直接写表）
delete from public.preference_profiles
where user_id = '11111111-1111-1111-1111-111111111111';

\echo ''
\echo '========== S1. 用户确认偏好（写入）=========='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'S1 写偏好 => ' || public.upsert_preference_profile(
  '{"confirm":true,
    "preferred_slots":[{"weekday":null,"start_minute":1140,"end_minute":1260},
                       {"weekday":6,"start_minute":540,"end_minute":660}],
    "focus_minutes":25,"break_minutes":5,
    "source":"explicit"}'::jsonb, 0)::text;
commit;

\echo ''
\echo '========== S2. 读回偏好（应 data_version=1、source=explicit、2 段）=========='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'S2 读偏好 => status=' || (p->>'status')
       || ' data_version=' || (p->>'data_version')
       || ' source=' || (p->>'source')
       || ' slots=' || jsonb_array_length(p->'preferred_slots')
       || ' focus=' || (p->>'focus_minutes')
from (select public.get_preference_profile() as p) t;
rollback;

\echo ''
\echo '========== S3. 取周四情境快照（课程/空闲/任务/负荷都要有）=========='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'S3 快照 => status=' || (s->>'status')
       || ' | 课=' || jsonb_array_length(s->'fixed_events')
       || ' | 空闲段=' || jsonb_array_length(s->'free_slots')
       || ' | 任务=' || jsonb_array_length(s->'tasks')
       || ' | 已知负荷=' || (s->'workload'->>'known_minutes') || '分钟'
from (select public.checkd_context_snapshot('2026-11-26','2026-11-26') as s) t;
-- 空闲段明细（决策输入就是从这里挑的）
select 'S3 空闲明细 => ' || string_agg(
         (x->>'start_minute') || '–' || (x->>'end_minute') || '(' || (x->>'minutes') || '分)', ' | '
         order by (x->>'start_minute')::int)
from jsonb_array_elements(public.checkd_context_snapshot('2026-11-26','2026-11-26')::jsonb -> 'free_slots') x;
rollback;

\echo ''
\echo '========== S4. 用快照产出一次决策输入（M1 不做评分排序，只给可行输入）=========='
-- 从快照里挑第一个 ≥25 分钟的空闲段，绑定第一个未完成任务。
-- 真实系统里这一步由 M2 的排序决定；这里只证明「快照的字段足够支撑决策」。
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
drop table if exists decision_input;
create temp table decision_input as
select
  (select x->>'start_minute' from jsonb_array_elements(s->'free_slots') x
    where (x->>'minutes')::int >= coalesce((p->>'focus_minutes')::int, 25)
    order by (x->>'start_minute')::int limit 1)                       as slot_start,
  (select x->>'end_minute' from jsonb_array_elements(s->'free_slots') x
    where (x->>'minutes')::int >= coalesce((p->>'focus_minutes')::int, 25)
    order by (x->>'start_minute')::int limit 1)                       as slot_end,
  (select x->>'task_id' from jsonb_array_elements(s->'tasks') x
    where (x->>'completed')::boolean = false limit 1)                 as task_id,
  (p->>'focus_minutes')::int                                          as focus_minutes,
  (p->>'data_version')::int                                           as preference_version
from (select public.checkd_context_snapshot('2026-11-26','2026-11-26') as s,
             public.get_preference_profile() as p) t;
select 'S4 决策输入 => 时段' || coalesce(slot_start,'(无)') || '–' || coalesce(slot_end,'(无)')
       || ' | 任务=' || coalesce(task_id,'(无)')
       || ' | 单次时长=' || coalesce(focus_minutes::text,'(空)')
       || ' | 依据偏好版本=' || coalesce(preference_version::text,'(空)')
from decision_input;
commit;

\echo ''
\echo '========== S5. 按决策写行为事件（接受 → 开始 → 完成）=========='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
do $$
declare
  d record;
  v_plan text := 'plan-chain-20261126';
  v_task uuid;
begin
  select * into d from decision_input;
  v_task := coalesce(d.task_id::uuid, 'a0000000-0000-0000-0000-0000000000c1'::uuid);

  raise notice 'S5a 接受 => %', public.append_behavior_event(jsonb_build_object(
    'event_id','c0000000-0000-0000-0000-000000000001','event_type','plan_accepted',
    'plan_id', v_plan, 'occurred_at','2026-11-26T11:00:00Z','source','test'));
  raise notice 'S5b 开始 => %', public.append_behavior_event(jsonb_build_object(
    'event_id','c0000000-0000-0000-0000-000000000002','event_type','task_started',
    'task_id', v_task, 'plan_id', v_plan,
    'occurred_at','2026-11-26T11:01:00Z','planned_minutes', d.focus_minutes, 'source','test'));
  -- actual_minutes 只填实测值；这里模拟"计时器真的跑了 25 分钟"
  raise notice 'S5c 完成 => %', public.append_behavior_event(jsonb_build_object(
    'event_id','c0000000-0000-0000-0000-000000000003','event_type','task_completed',
    'task_id', v_task, 'plan_id', v_plan,
    'occurred_at','2026-11-26T11:26:00Z','planned_minutes', d.focus_minutes,
    'actual_minutes', 25, 'source','test'));
end $$;
commit;

\echo ''
\echo '========== S6. 读回事件链（应 3 条、同一 plan_id、actual=25）=========='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'S6 本链路事件数 => ' || count(*)
from jsonb_array_elements(public.list_behavior_events('2026-11-26T00:00:00Z','2026-11-27T00:00:00Z')::jsonb -> 'events') e
where e->>'plan_id' = 'plan-chain-20261126';
select 'S6 事件链 => ' || string_agg(e->>'event_type', ' → ' order by e->>'occurred_at')
from jsonb_array_elements(public.list_behavior_events('2026-11-26T00:00:00Z','2026-11-27T00:00:00Z')::jsonb -> 'events') e
where e->>'plan_id' = 'plan-chain-20261126';
select 'S6 plan 一致性 => '
       || count(*) || ' 条带 plan_id，去重后 ' || count(distinct e->>'plan_id') || ' 个 plan，'
       || 'actual_minutes 合计 = ' || coalesce(sum((e->>'actual_minutes')::int), 0)
from jsonb_array_elements(public.list_behavior_events('2026-11-26T00:00:00Z','2026-11-27T00:00:00Z')::jsonb -> 'events') e
where e->>'plan_id' is not null;
rollback;

\echo ''
\echo '========== S7. 跨账号：B 读不到这条链 =========='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select 'S7 B 看到的事件数 => ' || (public.list_behavior_events('2026-11-26T00:00:00Z','2026-11-27T00:00:00Z')::jsonb ->> 'count');
rollback;