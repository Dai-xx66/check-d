-- Student day foundation: courses, schedule templates, one-day overrides,
-- separated reminder/alarm rules, and ad-hoc timers.

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  color bigint not null,
  teacher text,
  classroom text,
  semester text,
  notes text,
  status text not null default 'active'
    check (status in ('active', 'paused', 'archived')),
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.course_schedule_rules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  week_rule_type text not null
    check (week_rule_type in ('everyWeek', 'oddWeeks', 'evenWeeks', 'everyNWeeks', 'custom')),
  start_week int check (start_week > 0),
  end_week int check (end_week is null or end_week > 0),
  interval_weeks int check (interval_weeks is null or interval_weeks > 0),
  week_numbers jsonb not null default '[]'::jsonb,
  schedule_template_id uuid,
  section_ids jsonb not null default '[]'::jsonb,
  starts_at_minute int not null check (starts_at_minute between 0 and 1439),
  ends_at_minute int not null check (ends_at_minute between 1 and 1440),
  remind_before_minutes int check (remind_before_minutes >= 0),
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ends_at_minute > starts_at_minute),
  check (end_week is null or start_week is null or end_week >= start_week)
);

create table if not exists public.schedule_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  timezone text not null default 'Asia/Shanghai',
  is_default boolean not null default false,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.schedule_template_segments (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.schedule_templates(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  starts_at_minute int not null check (starts_at_minute between 0 and 1439),
  ends_at_minute int not null check (ends_at_minute between 1 and 1440),
  segment_type text not null default 'classTime'
    check (segment_type in ('classTime', 'breakTime', 'custom')),
  sort_order int not null default 0,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ends_at_minute > starts_at_minute)
);

create table if not exists public.daily_item_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_type text not null check (item_type in ('recurring', 'oneTime', 'course')),
  item_id uuid not null,
  local_date date not null,
  action text not null
    check (action in ('none', 'skip', 'reschedule', 'retarget', 'reminder', 'courseChange')),
  planned_start_minute int check (planned_start_minute between 0 and 1439),
  planned_end_minute int check (planned_end_minute between 1 and 1440),
  reminder_minute_of_day int check (reminder_minute_of_day between 0 and 1439),
  target_duration_seconds int check (target_duration_seconds > 0),
  temporary_classroom text,
  notes text,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique(user_id, item_type, item_id, local_date),
  check (planned_end_minute is null or planned_start_minute is null or planned_end_minute > planned_start_minute)
);

create table if not exists public.reminder_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  owner_type text not null check (owner_type in ('recurring', 'oneTime', 'course')),
  owner_id uuid not null,
  reminder_kind text not null check (reminder_kind in ('due', 'advance')),
  enabled boolean not null default true,
  scheduled_minute_of_day int check (scheduled_minute_of_day between 0 and 1439),
  remind_before_minutes int check (remind_before_minutes >= 0),
  local_date date,
  timezone text not null default 'Asia/Shanghai',
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.alarm_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  owner_type text not null check (owner_type in ('recurring', 'oneTime', 'course')),
  owner_id uuid not null,
  enabled boolean not null default false,
  behavior text not null default 'once'
    check (behavior in ('once', 'duration', 'snooze', 'repeat')),
  sound_name text,
  snooze_minutes int check (snooze_minutes > 0),
  repeat_interval_minutes int check (repeat_interval_minutes > 0),
  max_ring_seconds int check (max_ring_seconds > 0),
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.ad_hoc_timers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  tag_id uuid references public.tags(id) on delete set null,
  color bigint not null,
  notes text,
  started_at timestamptz not null,
  ended_at timestamptz,
  completed_at timestamptz,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ended_at is null or ended_at >= started_at)
);

create index if not exists courses_user_status_idx
  on public.courses(user_id, status);
create index if not exists course_schedule_rules_user_weekday_idx
  on public.course_schedule_rules(user_id, weekday);
create index if not exists schedule_templates_user_idx
  on public.schedule_templates(user_id);
create index if not exists daily_item_overrides_user_date_idx
  on public.daily_item_overrides(user_id, local_date);
create index if not exists reminder_rules_user_owner_idx
  on public.reminder_rules(user_id, owner_type, owner_id);
create index if not exists alarm_rules_user_owner_idx
  on public.alarm_rules(user_id, owner_type, owner_id);
create index if not exists ad_hoc_timers_user_started_idx
  on public.ad_hoc_timers(user_id, started_at);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'courses',
    'course_schedule_rules',
    'schedule_templates',
    'schedule_template_segments',
    'daily_item_overrides',
    'reminder_rules',
    'alarm_rules',
    'ad_hoc_timers'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'drop policy if exists %I on public.%I',
      table_name || '_owner_access',
      table_name
    );
    execute format(
      'create policy %I on public.%I for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)',
      table_name || '_owner_access',
      table_name
    );
    execute format(
      'drop trigger if exists %I on public.%I',
      'set_' || table_name || '_updated_at',
      table_name
    );
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      'set_' || table_name || '_updated_at',
      table_name
    );
  end loop;
end;
$$;
