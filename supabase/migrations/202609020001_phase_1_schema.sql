create extension if not exists pgcrypto;

create type public.task_type as enum ('long_term', 'one_time');
create type public.task_status as enum ('active', 'paused', 'archived');
create type public.check_mode as enum ('timer', 'simple');
create type public.schedule_type as enum ('daily', 'weekdays', 'weekends', 'custom');
create type public.sync_operation as enum ('upsert', 'archive');
create type public.review_type as enum ('day', 'week', 'month', 'year');
create type public.plan_type as enum ('month', 'year');
create type public.holiday_type as enum ('holiday', 'adjusted_workday');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_url text,
  timezone text not null default 'Asia/Shanghai',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  type public.task_type not null,
  color int not null,
  status public.task_status not null default 'active',
  notes text,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index tasks_user_status_idx on public.tasks(user_id, status);
create index tasks_user_updated_idx on public.tasks(user_id, updated_at);

create table public.long_term_tasks (
  task_id uuid primary key references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  check_mode public.check_mode not null,
  target_duration_seconds int check (target_duration_seconds > 0),
  target_days int check (target_days > 0),
  holiday_pause boolean not null default false,
  tag_id uuid,
  reminder_time time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint timer_requires_duration check (
    (check_mode = 'timer' and target_duration_seconds is not null)
    or (check_mode = 'simple' and target_duration_seconds is null)
  )
);

create table public.task_schedules (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  schedule_type public.schedule_type not null,
  weekdays smallint[] not null default '{}',
  starts_on date not null,
  ends_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on),
  check (weekdays <@ array[1,2,3,4,5,6,7]::smallint[])
);

create table public.one_time_reminders (
  task_id uuid primary key references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  scheduled_at timestamptz not null,
  remind_before_minutes int check (remind_before_minutes >= 0),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  color int not null,
  is_default boolean not null default false,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique(user_id, name)
);

alter table public.long_term_tasks
  add constraint long_term_tasks_tag_fk
  foreign key (tag_id) references public.tags(id) on delete set null;

create table public.task_completions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_date date not null,
  timezone text not null,
  actual_duration_seconds int not null default 0 check (actual_duration_seconds >= 0),
  progress_percent numeric(6,2) not null default 0 check (progress_percent >= 0),
  is_success boolean not null default false,
  exclusion_reason text,
  completed_at timestamptz,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique(task_id, local_date)
);

create index task_completions_user_date_idx
  on public.task_completions(user_id, local_date);

create table public.timer_sessions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  tag_id uuid references public.tags(id) on delete set null,
  tag_name_snapshot text,
  tag_color_snapshot int,
  started_at timestamptz not null,
  ended_at timestamptz,
  duration_seconds int not null default 0 check (duration_seconds >= 0),
  state text not null check (state in ('running', 'paused', 'finished')),
  device_id uuid,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ended_at is null or ended_at >= started_at)
);

create index timer_sessions_user_started_idx
  on public.timer_sessions(user_id, started_at);

create unique index one_running_timer_per_user
  on public.timer_sessions(user_id)
  where state = 'running' and deleted_at is null;

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  type public.plan_type not null,
  color int not null,
  goal text,
  starts_on date not null,
  ends_on date not null,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ends_on >= starts_on)
);

create table public.plan_tasks (
  plan_id uuid not null references public.plans(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  weight numeric(7,4) not null default 1 check (weight > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (plan_id, task_id)
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type public.review_type not null,
  period_start date not null,
  period_end date not null,
  happened_text text,
  learned_text text,
  improve_text text,
  mood smallint check (mood between 1 and 5),
  objective_snapshot jsonb not null default '{}'::jsonb,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (period_end >= period_start),
  unique(user_id, type, period_start)
);

create table public.holidays (
  holiday_date date primary key,
  type public.holiday_type not null,
  name text not null,
  source text,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete cascade,
  enabled boolean not null default true,
  reminder_time time,
  remind_before_minutes int check (remind_before_minutes >= 0),
  platform_payload jsonb not null default '{}'::jsonb,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.task_revisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  changed_at timestamptz not null default now(),
  device_id uuid,
  before_data jsonb,
  after_data jsonb not null
);

create table public.devices (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null,
  display_name text,
  last_sync_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, id)
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'tasks', 'long_term_tasks', 'task_schedules',
    'one_time_reminders', 'tags', 'task_completions', 'timer_sessions',
    'plans', 'plan_tasks', 'reviews', 'holidays', 'notifications', 'devices'
  ]
  loop
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.set_updated_at()',
      'set_' || table_name || '_updated_at',
      table_name
    );
  end loop;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
create policy "profiles_owner_access"
  on public.profiles for all to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'tasks', 'long_term_tasks', 'task_schedules', 'one_time_reminders',
    'tags', 'task_completions', 'timer_sessions', 'plans', 'plan_tasks',
    'reviews', 'notifications', 'task_revisions', 'devices'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy "%s_owner_access" on public.%I for all to authenticated '
      'using ((select auth.uid()) = user_id) '
      'with check ((select auth.uid()) = user_id)',
      table_name,
      table_name
    );
  end loop;
end;
$$;

alter table public.holidays enable row level security;
create policy "authenticated_users_read_holidays"
  on public.holidays for select to authenticated
  using (true);
