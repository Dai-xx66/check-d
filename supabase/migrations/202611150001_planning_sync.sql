-- Planning records synced from the local-first Android database.
-- This is a new migration; it must only be exercised in an isolated local DB
-- until the schema and RLS change receives Production review.
begin;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tasks_user_id_id_unique'
      and conrelid = 'public.tasks'::regclass) then
    alter table public.tasks add constraint tasks_user_id_id_unique unique (user_id, id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'timer_sessions_user_id_id_unique'
      and conrelid = 'public.timer_sessions'::regclass) then
    alter table public.timer_sessions add constraint timer_sessions_user_id_id_unique unique (user_id, id);
  end if;
end $$;

create table if not exists public.task_effort_estimates (
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null,
  estimated_seconds integer,
  remaining_seconds integer,
  source text not null check (char_length(trim(source)) > 0),
  updated_at timestamptz not null default now(),
  sync_version bigint not null default 1 check (sync_version > 0),
  primary key (user_id, task_id),
  foreign key (user_id, task_id) references public.tasks(user_id, id) on delete cascade,
  check (estimated_seconds is null or estimated_seconds > 0),
  check (remaining_seconds is null or remaining_seconds > 0)
);

create table if not exists public.task_plan_versions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  revision bigint not null check (revision > 0),
  source_snapshot_version text not null,
  proposal_digest text not null,
  rules_version text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null check (status in ('draft', 'confirmed', 'applied', 'superseded', 'failed')),
  idempotency_key text not null,
  created_at timestamptz not null,
  confirmed_at timestamptz,
  applied_at timestamptz,
  updated_at timestamptz not null default now(),
  sync_version bigint not null default 1 check (sync_version > 0),
  unique (user_id, id),
  unique (user_id, revision),
  unique (user_id, idempotency_key),
  check (starts_on <= ends_on)
);

create table if not exists public.task_time_blocks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_version_id uuid not null,
  task_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  planned_seconds integer not null check (planned_seconds > 0),
  sync_version bigint not null default 1 check (sync_version > 0),
  unique (user_id, id),
  unique (user_id, plan_version_id, task_id, starts_at),
  foreign key (user_id, plan_version_id) references public.task_plan_versions(user_id, id) on delete cascade,
  foreign key (user_id, task_id) references public.tasks(user_id, id) on delete cascade,
  check (ends_at > starts_at)
);

create table if not exists public.planned_block_timer_links (
  user_id uuid not null references auth.users(id) on delete cascade,
  planned_block_id uuid not null,
  timer_session_id uuid not null,
  linked_at timestamptz not null default now(),
  sync_version bigint not null default 1 check (sync_version > 0),
  primary key (user_id, planned_block_id, timer_session_id),
  foreign key (user_id, planned_block_id) references public.task_time_blocks(user_id, id) on delete cascade,
  foreign key (user_id, timer_session_id) references public.timer_sessions(user_id, id) on delete cascade
);

create or replace function public.bump_planning_sync_version()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := pg_catalog.clock_timestamp();
  new.sync_version := old.sync_version + 1;
  return new;
end $$;
revoke all on function public.bump_planning_sync_version() from public, anon, authenticated;
drop trigger if exists task_effort_estimates_bump_version on public.task_effort_estimates;
create trigger task_effort_estimates_bump_version before update on public.task_effort_estimates
  for each row execute function public.bump_planning_sync_version();
drop trigger if exists task_plan_versions_bump_version on public.task_plan_versions;
create trigger task_plan_versions_bump_version before update on public.task_plan_versions
  for each row execute function public.bump_planning_sync_version();

alter table public.task_effort_estimates enable row level security;
alter table public.task_plan_versions enable row level security;
alter table public.task_time_blocks enable row level security;
alter table public.planned_block_timer_links enable row level security;
drop policy if exists task_effort_estimates_owner_sync on public.task_effort_estimates;
create policy task_effort_estimates_owner_sync on public.task_effort_estimates for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists task_plan_versions_owner_sync on public.task_plan_versions;
create policy task_plan_versions_owner_sync on public.task_plan_versions for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists task_time_blocks_owner_sync on public.task_time_blocks;
create policy task_time_blocks_owner_sync on public.task_time_blocks for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists planned_block_timer_links_owner_sync on public.planned_block_timer_links;
create policy planned_block_timer_links_owner_sync on public.planned_block_timer_links for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update on public.task_effort_estimates to authenticated;
grant select, insert, update on public.task_plan_versions to authenticated;
grant select, insert, update on public.task_time_blocks to authenticated;
grant select, insert, update on public.planned_block_timer_links to authenticated;
commit;
