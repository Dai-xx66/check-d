-- 隔离库：快照语义验证（学期归属 + 长期任务排期 + occurrence 两态）
-- 专门验 PR #23 修的两处：
--   ① 只展开属于当前学期的课程（上学期课不能混进来）
--   ② 长期任务按 task_schedules 判断本窗口该不该做
-- 以及 occurrence 表的两种缺失状态（不存在 → UNAVAILABLE；存在但无覆盖 → MISSING）

\set ON_ERROR_STOP 1
\pset pager off

-- 清掉上一段可能留下的业务数据，保证可重跑
delete from public.behavior_events;
delete from public.preference_profiles;
delete from public.one_time_reminders;
delete from public.task_completions;
delete from public.task_schedules;
delete from public.long_term_tasks;
delete from public.tasks;
delete from public.course_schedule_rules;
delete from public.courses;
delete from public.semesters;

-- 两个学期：当前学期 + 上学期
insert into public.semesters (id, user_id, name, first_week_start_date, total_weeks, is_current)
values
  ('50000000-0000-0000-0000-0000000000aa', '11111111-1111-1111-1111-111111111111',
   '2026 秋季学期', '2026-08-31', 18, true),
  ('50000000-0000-0000-0000-0000000000bb', '11111111-1111-1111-1111-111111111111',
   '2026 春季学期', '2026-02-23', 18, false);

-- 课程：本学期课、上学期课、无学期历史课
insert into public.courses (id, user_id, name, color, status, semester_id)
values
  ('60000000-0000-0000-0000-0000000000a1', '11111111-1111-1111-1111-111111111111',
   '本学期-数据结构', 1, 'active', '50000000-0000-0000-0000-0000000000aa'),
  ('60000000-0000-0000-0000-0000000000a2', '11111111-1111-1111-1111-111111111111',
   '上学期-不该出现', 2, 'active', '50000000-0000-0000-0000-0000000000bb'),
  ('60000000-0000-0000-0000-0000000000a3', '11111111-1111-1111-1111-111111111111',
   '无学期-历史课', 3, 'active', null);

-- 三门课都排在周四，便于一眼看出谁被过滤掉
insert into public.course_schedule_rules
  (course_id, user_id, weekday, week_rule_type, week_numbers, starts_at_minute, ends_at_minute)
values
  ('60000000-0000-0000-0000-0000000000a1', '11111111-1111-1111-1111-111111111111',
   4, 'everyWeek', '[]'::jsonb, 490, 710),
  ('60000000-0000-0000-0000-0000000000a2', '11111111-1111-1111-1111-111111111111',
   4, 'everyWeek', '[]'::jsonb, 600, 660),
  ('60000000-0000-0000-0000-0000000000a3', '11111111-1111-1111-1111-111111111111',
   4, 'everyWeek', '[]'::jsonb, 800, 860);

-- 三个长期任务：只在工作日 / 只在周末 / 无排期（老数据）
insert into public.tasks (id, user_id, name, type, color, status)
values
  ('a0000000-0000-0000-0000-0000000000c1', '11111111-1111-1111-1111-111111111111', '工作日任务', 'long_term', 1, 'active'),
  ('a0000000-0000-0000-0000-0000000000c2', '11111111-1111-1111-1111-111111111111', '周末任务',   'long_term', 1, 'active'),
  ('a0000000-0000-0000-0000-0000000000c3', '11111111-1111-1111-1111-111111111111', '无排期老任务', 'long_term', 1, 'active');

insert into public.long_term_tasks (task_id, user_id, check_mode, target_duration_seconds)
values
  ('a0000000-0000-0000-0000-0000000000c1', '11111111-1111-1111-1111-111111111111', 'timed', 1800),
  ('a0000000-0000-0000-0000-0000000000c2', '11111111-1111-1111-1111-111111111111', 'timed', 3600),
  ('a0000000-0000-0000-0000-0000000000c3', '11111111-1111-1111-1111-111111111111', 'untimed', null);

insert into public.task_schedules
  (task_id, user_id, schedule_type, weekdays, weekdays_mask, starts_on)
values
  ('a0000000-0000-0000-0000-0000000000c1', '11111111-1111-1111-1111-111111111111',
   'weekdays', '{1,2,3,4,5}'::smallint[], 31, '2026-08-31'),
  ('a0000000-0000-0000-0000-0000000000c2', '11111111-1111-1111-1111-111111111111',
   'weekends', '{6,7}'::smallint[], 96, '2026-08-31');
-- c3 「无排期老任务」故意不插 task_schedules

\echo ''
\echo '===== L. 周四窗口（11-26）：课程应只有 本学期 + 无学期，任务应只有 工作日 + 无排期 ===='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'L1 课程 => ' || coalesce(string_agg(x->>'title', ' | '), '(空)')
from jsonb_array_elements(public.checkd_context_snapshot('2026-11-26','2026-11-26')::jsonb -> 'fixed_events') x;
select 'L2 任务 => ' || coalesce(string_agg(x->>'name', ' | '), '(空)')
from jsonb_array_elements(public.checkd_context_snapshot('2026-11-26','2026-11-26')::jsonb -> 'tasks') x;
select 'L3 负荷 => ' || (public.checkd_context_snapshot('2026-11-26','2026-11-26')::jsonb -> 'workload')::text;
select 'L4 空闲 => ' || count(*) || ' 段 / 共 ' || coalesce(sum((x->>'minutes')::int),0) || ' 分钟'
from jsonb_array_elements(public.checkd_context_snapshot('2026-11-26','2026-11-26')::jsonb -> 'free_slots') x;
rollback;

\echo ''
\echo '===== M. 周六窗口（11-28）：周末任务应出现，工作日任务应消失 ===='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'M1 任务 => ' || coalesce(string_agg(x->>'name', ' | '), '(空)')
from jsonb_array_elements(public.checkd_context_snapshot('2026-11-28','2026-11-28')::jsonb -> 'tasks') x;
rollback;

\echo ''
\echo '===== N. occurrence 表建起来后：应变成 MISSING（表在、无覆盖），不是 UNAVAILABLE ===='
create table if not exists public.agent_task_occurrence_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  from_date date not null,
  through_date date not null,
  digest text,
  local_generation bigint default 0,
  created_at timestamptz not null default now()
);
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select 'N => status=' || (public.checkd_context_snapshot('2026-11-26','2026-11-26')::jsonb ->> 'status')
       || ' | freshness=' || (public.checkd_context_snapshot('2026-11-26','2026-11-26')::jsonb -> 'freshness')::text;
rollback;

\echo ''
\echo '===== O. 同一事件 ID 在真实约束下重放三次，行数应仍为 1 ===='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.append_behavior_event('{"event_id":"e0000000-0000-0000-0000-0000000000aa","event_type":"manual_note","occurred_at":"2026-11-26T11:00:00Z","source":"test"}'::jsonb);
select public.append_behavior_event('{"event_id":"e0000000-0000-0000-0000-0000000000aa","event_type":"manual_note","occurred_at":"2026-11-26T11:00:00Z","source":"test"}'::jsonb);
commit;
select 'O 行数（应为 1）=> ' || count(*) from public.behavior_events where event_id = 'e0000000-0000-0000-0000-0000000000aa';
