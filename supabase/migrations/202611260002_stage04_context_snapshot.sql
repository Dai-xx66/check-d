-- Stage 04 · M1 · ContextSnapshot 读模型
--
-- 依赖：202611260001_stage04_behavior_events.sql（同批）
--       既有表 tasks / one_time_reminders / long_term_tasks / task_completions /
--             courses / course_schedule_rules / semesters
-- 可选：agent_task_occurrence_snapshots（M3 的 occurrence 快照，**可能尚未建表**）
--
-- 三条硬规则
--   1) 长周期任务**不在这里展开**。只在 agent_task_occurrence_snapshots 存在且覆盖窗口时
--      读取客户端已发布的实例；不存在就标 missing，并把它写进 blocking，不伪造占用。
--   2) 课程序列由本函数展开（courses + rules + semesters）。学期缺失 => 无法定位周次 =>
--      课程固定事件返回空且 semester.status='missing'，**不猜**。
--   3) 缺字段一律返回 unknown，不用 0 或默认值冒充。

begin;

create or replace function public.checkd_context_snapshot(
  p_from date,
  p_through date,
  p_timezone text default 'Asia/Shanghai',
  p_energy_self_report integer default null,
  p_day_start_minute integer default 480,   -- 08:00
  p_day_end_minute integer default 1380     -- 23:00
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_occ_table boolean;
  v_occ_shape_ok boolean := false;
  v_sem       record;
  v_courses   jsonb := '[]'::jsonb;
  v_free      jsonb := '[]'::jsonb;
  v_tasks     jsonb := '[]'::jsonb;
  v_known     integer := 0;
  v_unknown_n integer := 0;
  v_open_n    integer := 0;
  v_blocking  jsonb := '[]'::jsonb;
  v_sem_status text;
  v_occ_status text;
  v_overall   text;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_from is null or p_through is null or p_through < p_from then
    raise exception using errcode = '22023', message = 'INVALID_RANGE';
  end if;
  if p_through - p_from > 31 then
    raise exception using errcode = '22023', message = 'RANGE_TOO_LARGE';
  end if;
  if p_day_end_minute <= p_day_start_minute
     or p_day_start_minute < 0 or p_day_end_minute > 1440 then
    raise exception using errcode = '22023', message = 'INVALID_DAY_WINDOW';
  end if;
  if p_energy_self_report is not null
     and (p_energy_self_report < 1 or p_energy_self_report > 5) then
    raise exception using errcode = '22023', message = 'INVALID_ENERGY';
  end if;

  -- ---------- 学期锚点 ----------
  select s.first_week_start_date as fw, s.total_weeks as tw, s.id as sid
    into v_sem
  from public.semesters s
  where s.user_id = v_user and s.is_current and s.deleted_at is null
  order by s.updated_at desc
  limit 1;

  if v_sem.fw is null then
    v_sem_status := 'missing';
    v_blocking := v_blocking || jsonb_build_object(
      'code', 'SEMESTER_MISSING',
      'message', 'No current semester; course weekly expansion is impossible.');
  else
    v_sem_status := 'ok';
  end if;

  -- ---------- 固定事件：课程展开 ----------
  if v_sem.fw is not null then
    with days as (
      select g::date as d
      from generate_series(p_from::timestamp, p_through::timestamp, interval '1 day') g
    ),
    cand as (
      select
        d.d,
        c.id            as course_id,
        c.name          as course_name,
        r.starts_at_minute as start_minute,
        r.ends_at_minute   as end_minute,
        ((d.d - v_sem.fw) / 7) + 1 as week_no,
        r.week_rule_type,
        r.start_week,
        r.end_week,
        coalesce(r.week_numbers, '[]'::jsonb) as week_numbers
      from days d
      join public.course_schedule_rules r
        on r.user_id = v_user and r.deleted_at is null
      join public.courses c
        on c.id = r.course_id and c.user_id = v_user
       and c.deleted_at is null and c.status = 'active'
       -- 只展开属于当前学期的课程。semester_id 为 null 的历史课程（在 semesters 表
       -- 出现之前创建的）继续纳入，否则老用户会整张课表消失。
       -- 判据是「属于任意一个 is_current 学期」而非某一个 id：数据异常下若有多条
       -- is_current，按单 id 过滤会把挂在另一条上的课整批丢掉。
       and (
         c.semester_id is null
         or c.semester_id in (
           select s2.id from public.semesters s2
           where s2.user_id = v_user and s2.is_current and s2.deleted_at is null
         )
       )
      where extract(isodow from d.d)::int = r.weekday
    ),
    kept as (
      select *
      from cand
      where week_no between 1 and v_sem.tw
        and (start_week is null or week_no >= start_week)
        and (end_week   is null or week_no <= end_week)
        and (
          case
            when jsonb_array_length(week_numbers) > 0 then
              exists (
                select 1 from jsonb_array_elements_text(week_numbers) w
                where w::int = week_no)
            when week_rule_type = 'everyWeek'  then true
            when week_rule_type = 'oddWeeks'   then (week_no % 2) = 1
            when week_rule_type = 'evenWeeks'  then (week_no % 2) = 0
            when week_rule_type = 'everyNWeeks' then
              week_no >= coalesce(start_week, 1)
              and coalesce(interval_weeks, 1) > 0
              and ((week_no - coalesce(start_week, 1)) % coalesce(interval_weeks, 1)) = 0
            else false
          end
        )
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'kind', 'course',
             'ref_id', course_id,
             'title', course_name,
             'date', d,
             'start_minute', start_minute,
             'end_minute', end_minute,
             'week_no', week_no,
             'source', 'courses+course_schedule_rules'
           ) order by d, start_minute), '[]'::jsonb)
      into v_courses
    from kept;
  end if;

  -- ---------- 空闲时段：每天 [day_start, day_end) 减去课程段 ----------
  -- 按分钟打点求差集，再合并连续区间。窗口最长 31 天，单用户量级可接受。
  with days as (
    select g::date as d
    from generate_series(p_from::timestamp, p_through::timestamp, interval '1 day') g
  ),
  course_slots as (
    select (e->>'date')::date as d,
           (e->>'start_minute')::int as s,
           (e->>'end_minute')::int as en
    from jsonb_array_elements(v_courses) e
  ),
  busy as (
    select d, generate_series(s, en - 1) as m
    from course_slots
    where en > s
  ),
  all_min as (
    select d.d, generate_series(p_day_start_minute, p_day_end_minute - 1) as m
    from days d
  ),
  free_min as (
    select d, m from all_min
    except
    select d, m from busy
  ),
  islands as (
    select d, m,
           m - row_number() over (partition by d order by m) as grp
    from free_min
  ),
  merged as (
    select d, min(m) as start_minute, max(m) + 1 as end_minute
    from islands
    group by d, grp
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'date', d,
           'start_minute', start_minute,
           'end_minute', end_minute,
           'minutes', end_minute - start_minute
         ) order by d, start_minute), '[]'::jsonb)
    into v_free
  from merged
  where end_minute - start_minute >= 5;   -- 小于 5 分钟的碎片不算可用窗口

  -- ---------- 任务与负荷 ----------
  with open_tasks as (
    select t.id, t.name, t.type,
           ot.planned_date, ot.due_date, ot.due_at, ot.available_from,
           lt.target_duration_seconds,
           exists (
             select 1 from public.task_completions tc
             where tc.task_id = t.id and tc.user_id = v_user
               and tc.deleted_at is null and tc.is_success
           ) as completed
    from public.tasks t
    left join public.one_time_reminders ot on ot.task_id = t.id
    left join public.long_term_tasks   lt on lt.task_id = t.id
    where t.user_id = v_user and t.deleted_at is null and t.status = 'active'
      -- 长期任务只有在排期覆盖本窗口时才算「本窗口该做」。
      -- 没有 task_schedules 行 = 老数据/未设排期，保留（否则长期任务会整批消失）。
      and (
        t.type <> 'long_term'
        or not exists (
          select 1 from public.task_schedules ts
          where ts.task_id = t.id and ts.user_id = v_user)
        or exists (
          select 1 from public.task_schedules ts
          where ts.task_id = t.id and ts.user_id = v_user
            and ts.starts_on <= p_through
            and (ts.ends_on is null or ts.ends_on >= p_from)
            and exists (
              select 1
              from generate_series(p_from::timestamp, p_through::timestamp, interval '1 day') g
              where g::date >= ts.starts_on
                and (ts.ends_on is null or g::date <= ts.ends_on)
                -- weekdays_mask 位序：bit0 = 周一 … bit6 = 周日（与客户端 WeekdayMask 一致）
                and (ts.weekdays_mask & (1 << (extract(isodow from g)::int - 1))) <> 0
            )
        )
      )
      and (
        t.type = 'long_term'
        or ot.due_date between p_from and p_through
        or ot.planned_date between p_from and p_through
        or (ot.due_at is not null
            and ot.due_at >= p_from::timestamptz
            and ot.due_at <  (p_through + 1)::timestamptz)
        or (ot.task_id is null)   -- one_time 但提醒行缺失：保留可见，标 unknown
      )
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'task_id', id,
      'name', name,
      'type', type,
      'due_date', due_date,
      'due_at', due_at,
      'planned_date', planned_date,
      'available_from', available_from,
      'completed', completed,
      'estimated_minutes',
        case when target_duration_seconds is not null
             then (target_duration_seconds + 59) / 60
             else null end,
      'estimated_status',
        case when target_duration_seconds is not null then 'known' else 'unknown' end
    ) order by coalesce(due_date, planned_date, p_through), name), '[]'::jsonb),
    coalesce(sum(case when not completed and target_duration_seconds is not null
                      then (target_duration_seconds + 59) / 60 else 0 end), 0),
    coalesce(sum(case when not completed and target_duration_seconds is null
                      then 1 else 0 end), 0),
    coalesce(sum(case when not completed then 1 else 0 end), 0)
    into v_tasks, v_known, v_unknown_n, v_open_n
  from open_tasks;

  -- ---------- occurrence 快照可用性（M3 的表可能还没建） ----------
  -- 注意：这张表的建表迁移不在本分支（M3 的 #20 仍是 open），所以 from_date /
  -- through_date 这两个列名是**推断**的，没有本地 migration 可核。
  -- 若真实库列名不同，直接查会抛 undefined_column 让整个函数挂掉。
  -- 因此先验列存在，缺列时降级为 missing 并说明原因，绝不让快照整体报错。
  v_occ_table := to_regclass('public.agent_task_occurrence_snapshots') is not null;
  if v_occ_table then
    select count(*) = 3 into v_occ_shape_ok
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'agent_task_occurrence_snapshots'
      and column_name in ('user_id', 'from_date', 'through_date');
  else
    v_occ_shape_ok := false;
  end if;

  if not v_occ_table then
    v_occ_status := 'missing';
    v_blocking := v_blocking || jsonb_build_object(
      'code', 'TASK_OCCURRENCES_UNAVAILABLE',
      'message', 'Occurrence snapshot table is absent; long-term instances are not expanded here.');
  elsif not v_occ_shape_ok then
    v_occ_status := 'missing';
    v_blocking := v_blocking || jsonb_build_object(
      'code', 'TASK_OCCURRENCES_MISSING',
      'message', 'Occurrence snapshot table exists but user_id/from_date/through_date are not all present; coverage cannot be judged.');
  else
    execute format(
      'select case when count(*) > 0 then ''published'' else ''missing'' end
         from public.agent_task_occurrence_snapshots
        where user_id = %L and from_date <= %L and through_date >= %L',
      v_user, p_from, p_through)
      into v_occ_status;
    if v_occ_status <> 'published' then
      v_blocking := v_blocking || jsonb_build_object(
        'code', 'TASK_OCCURRENCES_MISSING',
        'message', 'No published occurrence snapshot covers this window.');
    end if;
  end if;

  -- ---------- 总体新鲜度 ----------
  v_overall := case
    when v_sem_status <> 'ok' then 'blocked'
    when v_occ_status <> 'published' or v_unknown_n > 0 then 'partial'
    else 'ok'
  end;

  return jsonb_build_object(
    'as_of', to_jsonb(now()),
    'timezone', p_timezone,
    'window', jsonb_build_object('from', p_from, 'through', p_through),
    'semester', case when v_sem.fw is null then
                   jsonb_build_object('status', 'missing')
                 else
                   jsonb_build_object(
                     'status', 'ok',
                     'first_week_start_date', v_sem.fw,
                     'total_weeks', v_sem.tw)
                 end,
    'fixed_events', v_courses,
    'free_slots', v_free,
    'tasks', v_tasks,
    'workload', jsonb_build_object(
      'known_minutes', v_known,
      'unknown_estimate_count', v_unknown_n,
      'open_task_count', v_open_n,
      'status', case when v_unknown_n = 0 then 'known' else 'partial' end),
    'energy_self_report', p_energy_self_report,
    'day_window', jsonb_build_object(
      'start_minute', p_day_start_minute,
      'end_minute', p_day_end_minute),
    'freshness', jsonb_build_object(
      'semester', v_sem_status,
      'task_occurrences', v_occ_status,
      'completions', 'ok',
      'overall', v_overall),
    'status', v_overall,
    'blocking', v_blocking
  );
end;
$$;

comment on function public.checkd_context_snapshot(date, date, text, integer, integer, integer) is
  'Stage 04 M1 ContextSnapshot. Never expands long-term tasks; reads client-published occurrences only.';

revoke all on function public.checkd_context_snapshot(date, date, text, integer, integer, integer)
  from public, anon;
grant execute on function public.checkd_context_snapshot(date, date, text, integer, integer, integer)
  to authenticated;

commit;
