-- Stage 04 隔离库行为验证。
-- 前提：已执行 00_supabase_stub.sql + 9 个既有 migration + 3 个 stage04 migration。
-- 所有账号、任务、事件均为合成数据，不含任何真实用户信息。
--
-- 每段自成一个事务，用 `set local role` + `request.jwt.claims` 模拟不同登录身份；
-- 事务结束即恢复，不会污染后续用例。

\set ON_ERROR_STOP 0
\pset pager off

-- 两个合成测试账号
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'acct-a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'acct-b@test.local')
on conflict do nothing;

-- 给两个账号各建一条任务（走 postgres 身份，模拟"数据已存在"）
insert into public.tasks (id, user_id, name, type, color, status)
values
  ('a0000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'A的任务', 'one_time', 1, 'active'),
  ('b0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'B的任务', 'one_time', 1, 'active')
on conflict do nothing;

\echo ''
\echo '================ A. 无身份调用写函数（应 AUTH_REQUIRED）================'
begin;
set local role authenticated;
set local request.jwt.claims = '{}';
do $$
begin
  perform public.append_behavior_event(
    '{"event_id":"e0000000-0000-0000-0000-000000000001","event_type":"task_completed",
      "occurred_at":"2026-11-26T10:00:00Z","source":"test"}'::jsonb);
  raise notice 'A => FAIL 没抛错';
exception when others then
  raise notice 'A => SQLSTATE % / %', SQLSTATE, SQLERRM;
end $$;
rollback;

\echo ''
\echo '================ B. A 账号写事件（应成功 inserted=true）================'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
do $$
declare r jsonb;
begin
  r := public.append_behavior_event(
    '{"event_id":"e0000000-0000-0000-0000-000000000002","event_type":"task_completed",
      "task_id":"a0000000-0000-0000-0000-00000000000a",
      "occurred_at":"2026-11-26T10:00:00Z","actual_minutes":30,"source":"test"}'::jsonb);
  raise notice 'B => %', r;
exception when others then
  raise notice 'B => FAIL % / %', SQLSTATE, SQLERRM;
end $$;
-- 同一 event_id 再写一次，应 inserted=false
do $$
declare r jsonb;
begin
  r := public.append_behavior_event(
    '{"event_id":"e0000000-0000-0000-0000-000000000002","event_type":"task_completed",
      "task_id":"a0000000-0000-0000-0000-00000000000a",
      "occurred_at":"2026-11-26T10:00:00Z","actual_minutes":30,"source":"test"}'::jsonb);
  raise notice 'C(幂等重放) => %', r;
exception when others then
  raise notice 'C => FAIL % / %', SQLSTATE, SQLERRM;
end $$;
rollback;

\echo ''
\echo '================ D. A 账号直写表（表级权限已收回，应 permission denied）================'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
do $$
begin
  insert into public.behavior_events
    (user_id, event_id, event_type, occurred_at, source)
  values
    ('11111111-1111-1111-1111-111111111111','e0000000-0000-0000-0000-0000000000ff',
     'manual_note','2026-11-26T10:00:00Z','test');
  raise notice 'D => FAIL 直写成功了（权限没收回）';
exception when others then
  raise notice 'D => SQLSTATE % / %', SQLSTATE, SQLERRM;
end $$;
rollback;

\echo ''
\echo '================ E. B 账号读事件（RLS 隔离，应 0 行）================'
-- 先用 A 身份提交一条真实事件
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.append_behavior_event(
  '{"event_id":"e0000000-0000-0000-0000-000000000003","event_type":"manual_note",
    "occurred_at":"2026-11-26T10:05:00Z","source":"test","reason":"A 的备注"}'::jsonb);
commit;
-- 换 B 读
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select 'E(B 看到的事件数) => ' || count(*) as b_sees from public.behavior_events;
rollback;
-- 换回 A 读
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'E(A 看到的事件数) => ' || count(*) as a_sees from public.behavior_events;
rollback;

\echo ''
\echo '================ F. A 账号写自己的事件挂 B 的任务（应 TASK_NOT_OWNED）================'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
do $$
begin
  perform public.append_behavior_event(
    '{"event_id":"e0000000-0000-0000-0000-000000000004","event_type":"task_started",
      "task_id":"b0000000-0000-0000-0000-00000000000b",
      "occurred_at":"2026-11-26T10:10:00Z","source":"test"}'::jsonb);
  raise notice 'F => FAIL 没抛错';
exception when others then
  raise notice 'F => SQLSTATE % / %', SQLSTATE, SQLERRM;
end $$;
rollback;

\echo ''
\echo '================ G. 偏好：未确认应 CONFIRMATION_REQUIRED ================'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
do $$
begin
  perform public.upsert_preference_profile('{"preferred_slots":[]}'::jsonb);
  raise notice 'G => FAIL 没抛错';
exception when others then
  raise notice 'G => SQLSTATE % / %', SQLSTATE, SQLERRM;
end $$;
rollback;

\echo ''
\echo '================ H. 偏好：首次写入（data_version 应为 1）================'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
do $$
declare r jsonb;
begin
  r := public.upsert_preference_profile(
        '{"confirm":true,"preferred_slots":[{"weekday":null,"start_minute":1140,"end_minute":1260},
                                             {"weekday":6,"start_minute":540,"end_minute":660}],
          "focus_minutes":25}'::jsonb, 0);
  raise notice 'H => %', r;
exception when others then
  raise notice 'H => FAIL % / %', SQLSTATE, SQLERRM;
end $$;
-- 版本冲突：expected_version=9 但当前是 1
do $$
begin
  perform public.upsert_preference_profile('{"confirm":true,"preferred_slots":[]}'::jsonb, 9);
  raise notice 'I => FAIL 没抛冲突';
exception when others then
  raise notice 'I(版本冲突) => SQLSTATE % / %', SQLSTATE, SQLERRM;
end $$;
rollback;

\echo ''
\echo '================ J. B 账号读 A 的偏好（应 absent）================'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select 'J(B 读偏好) => ' || public.get_preference_profile()::text;
rollback;

\echo ''
\echo '================ K. 情境快照：occurrence 表不存在（应 UNAVAILABLE / partial）================'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'K => status=' || (public.checkd_context_snapshot('2026-11-26','2026-11-28')::jsonb ->> 'status')
       || ' | blocking=' || (public.checkd_context_snapshot('2026-11-26','2026-11-28')::jsonb -> 'blocking')::text;
rollback;
