-- Stage 14.1A: align the cloud schema with the current Drift model.
-- This migration intentionally prepares storage only. It does not enable data
-- transfer, restore, conflict resolution, or device-side notification setup.

begin;

-- Preserve the task presentation and date-classification fields that are
-- already persisted by Drift. The legacy weekday array/time columns remain in
-- place for existing beta data; these additions are the lossless local shape
-- future sync will use.
alter table public.tasks
  add column if not exists icon_name text not null default 'target';

alter table public.long_term_tasks
  add column if not exists scheduled_minute_of_day int,
  add column if not exists reminder_minute_of_day int;

alter table public.task_schedules
  add column if not exists weekdays_mask int;

alter table public.one_time_reminders
  add column if not exists has_scheduled_date boolean not null default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'long_term_tasks_scheduled_minute_of_day_check'
      and conrelid = 'public.long_term_tasks'::regclass
  ) then
    alter table public.long_term_tasks
      add constraint long_term_tasks_scheduled_minute_of_day_check
      check (scheduled_minute_of_day is null or scheduled_minute_of_day between 0 and 1439);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'long_term_tasks_reminder_minute_of_day_check'
      and conrelid = 'public.long_term_tasks'::regclass
  ) then
    alter table public.long_term_tasks
      add constraint long_term_tasks_reminder_minute_of_day_check
      check (reminder_minute_of_day is null or reminder_minute_of_day between 0 and 1439);
  end if;
end;
$$;

-- A dedicated semester entity is required to restore the course/template
-- relationship without relying on the legacy free-text courses.semester field.
create table if not exists public.semesters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  first_week_start_date date not null,
  total_weeks int not null check (total_weeks > 0),
  schedule_template_id uuid,
  is_current boolean not null default false,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists semesters_user_updated_idx
  on public.semesters(user_id, updated_at);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'semesters_user_id_id_unique'
      and conrelid = 'public.semesters'::regclass
  ) then
    alter table public.semesters
      add constraint semesters_user_id_id_unique unique (user_id, id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'schedule_templates_user_id_id_unique'
      and conrelid = 'public.schedule_templates'::regclass
  ) then
    alter table public.schedule_templates
      add constraint schedule_templates_user_id_id_unique unique (user_id, id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'semesters_schedule_template_owner_fk'
      and conrelid = 'public.semesters'::regclass
  ) then
    alter table public.semesters
      add constraint semesters_schedule_template_owner_fk
      foreign key (user_id, schedule_template_id)
      references public.schedule_templates(user_id, id)
      on delete restrict not valid;
  end if;
end;
$$;

do $$
begin
  if exists (
    select 1
    from public.semesters
    where is_current and deleted_at is null
    group by user_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot create semesters_one_current_per_user: existing active semesters contain multiple current rows for a user.';
  end if;
end;
$$;

create unique index if not exists semesters_one_current_per_user
  on public.semesters(user_id)
  where is_current and deleted_at is null;

alter table public.semesters enable row level security;
drop policy if exists semesters_owner_access on public.semesters;
create policy semesters_owner_access on public.semesters
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop trigger if exists set_semesters_updated_at on public.semesters;
create trigger set_semesters_updated_at
  before update on public.semesters
  for each row execute function public.set_updated_at();

-- Schedule templates and stable segments already match Drift structurally.
-- Drift permits exactly one active default template for a user, so retain that
-- invariant server-side without choosing among conflicting legacy rows.
do $$
begin
  if exists (
    select 1
    from public.schedule_templates
    where is_default and deleted_at is null
    group by user_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot create schedule_templates_one_default_per_user: existing active templates contain multiple defaults for a user.';
  end if;
end;
$$;

create unique index if not exists schedule_templates_one_default_per_user
  on public.schedule_templates(user_id)
  where is_default and deleted_at is null;

-- Preserve the old text semester as a legacy display/import field, while a
-- nullable relation supports existing beta rows and staged data migration.
alter table public.courses
  add column if not exists semester_id uuid,
  add column if not exists semester_starts_on date,
  add column if not exists semester_ends_on date;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'courses_semester_owner_fk'
      and conrelid = 'public.courses'::regclass
  ) then
    alter table public.courses
      add constraint courses_semester_owner_fk
      foreign key (user_id, semester_id) references public.semesters(user_id, id)
      on delete restrict not valid;
  end if;
end;
$$;

create index if not exists courses_user_semester_idx
  on public.courses(user_id, semester_id)
  where deleted_at is null;

-- Rules already stored custom week JSON and stable segment IDs. These columns
-- add the remaining Drift fields required to distinguish period and custom time
-- rules and to retain per-occurrence classroom and notes.
alter table public.course_schedule_rules
  add column if not exists time_mode text not null default 'customTime',
  add column if not exists classroom_override text,
  add column if not exists notes text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'course_schedule_rules_time_mode_check'
      and conrelid = 'public.course_schedule_rules'::regclass
  ) then
    alter table public.course_schedule_rules
      add constraint course_schedule_rules_time_mode_check
      check (time_mode in ('periods', 'customTime'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'course_schedule_rules_schedule_template_owner_fk'
      and conrelid = 'public.course_schedule_rules'::regclass
  ) then
    alter table public.course_schedule_rules
      add constraint course_schedule_rules_schedule_template_owner_fk
      foreign key (user_id, schedule_template_id)
      references public.schedule_templates(user_id, id)
      on delete restrict not valid;
  end if;
end;
$$;

-- The local action enum includes extraCourse for a make-up/additional course.
alter table public.daily_item_overrides
  drop constraint if exists daily_item_overrides_action_check;
alter table public.daily_item_overrides
  add constraint daily_item_overrides_action_check
  check (action in (
    'none', 'skip', 'reschedule', 'retarget', 'reminder', 'courseChange', 'extraCourse'
  ));

-- Multi Timer is per task, not globally per user. A paused session remains
-- unfinished in the local model, so both running and paused participate here.
-- Refuse to silently discard existing data if a prior client created an
-- impossible duplicate that must be reconciled before adding the invariant.
do $$
begin
  if exists (
    select 1
    from public.timer_sessions
    where state in ('running', 'paused') and deleted_at is null
    group by user_id, task_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot create one_unfinished_timer_per_task: existing timer_sessions contain multiple unfinished sessions for the same user and task.';
  end if;
end;
$$;

drop index if exists public.one_running_timer_per_user;
create unique index if not exists one_unfinished_timer_per_task
  on public.timer_sessions(user_id, task_id)
  where state in ('running', 'paused') and deleted_at is null;

alter table public.timer_sessions
  add column if not exists logical_date date;

-- Parent rows retain the current UI state and elapsed cache. Intervals remain
-- the pause-aware, cross-day source of truth for an ad-hoc timer.
alter table public.ad_hoc_timers
  add column if not exists timer_status text not null default 'idle',
  add column if not exists accumulated_duration_seconds int not null default 0,
  add column if not exists current_started_at timestamptz;

update public.ad_hoc_timers
set timer_status = 'ended'
where ended_at is not null and timer_status = 'idle';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ad_hoc_timers_timer_status_check'
      and conrelid = 'public.ad_hoc_timers'::regclass
  ) then
    alter table public.ad_hoc_timers
      add constraint ad_hoc_timers_timer_status_check
      check (timer_status in ('idle', 'running', 'paused', 'ended'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ad_hoc_timers_accumulated_duration_check'
      and conrelid = 'public.ad_hoc_timers'::regclass
  ) then
    alter table public.ad_hoc_timers
      add constraint ad_hoc_timers_accumulated_duration_check
      check (accumulated_duration_seconds >= 0);
  end if;
end;
$$;

create table if not exists public.ad_hoc_timer_intervals (
  id uuid primary key default gen_random_uuid(),
  timer_id uuid not null references public.ad_hoc_timers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz,
  duration_seconds int not null default 0 check (duration_seconds >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ended_at is null or ended_at >= started_at)
);

create index if not exists ad_hoc_timer_intervals_user_timer_idx
  on public.ad_hoc_timer_intervals(user_id, timer_id, started_at);

alter table public.ad_hoc_timer_intervals enable row level security;
drop policy if exists ad_hoc_timer_intervals_owner_access on public.ad_hoc_timer_intervals;
create policy ad_hoc_timer_intervals_owner_access on public.ad_hoc_timer_intervals
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop trigger if exists set_ad_hoc_timer_intervals_updated_at on public.ad_hoc_timer_intervals;
create trigger set_ad_hoc_timer_intervals_updated_at
  before update on public.ad_hoc_timer_intervals
  for each row execute function public.set_updated_at();

-- AppSettings is deliberately not mirrored wholesale. The only current setting
-- with cross-device product value is reminder defaults. Holiday caches,
-- default-tag sentinels, mini-window geometry, compact mode, notification
-- authorization, and other device/UI state remain local by design.
create table if not exists public.user_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  preference_key text not null check (preference_key in ('reminder_defaults')),
  value jsonb not null default '{}'::jsonb,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique(user_id, preference_key)
);

alter table public.user_preferences enable row level security;
drop policy if exists user_preferences_owner_access on public.user_preferences;
create policy user_preferences_owner_access on public.user_preferences
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop trigger if exists set_user_preferences_updated_at on public.user_preferences;
create trigger set_user_preferences_updated_at
  before update on public.user_preferences
  for each row execute function public.set_updated_at();

-- reminder_rules and alarm_rules already cover every current Drift field:
-- owner type/id, local date or scheduling data, enabled state, timezone,
-- behavior, sound, snooze, repeat interval, max ring duration, timestamps,
-- sync version, and soft deletion. No schema change is needed for them.

commit;
