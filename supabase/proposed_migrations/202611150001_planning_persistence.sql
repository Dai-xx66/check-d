-- PROPOSAL ONLY. This file is outside supabase/migrations and is NOT applied
-- by the normal Supabase migration workflow. Requires schema/security review.
-- It describes cloud sync storage for the Android-first local planning model.

create table if not exists public.task_effort_estimates (
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null,
  estimated_seconds integer,
  remaining_seconds integer,
  source text not null check (source in ('user_confirmed', 'imported')),
  updated_at timestamptz not null default now(),
  primary key (user_id, task_id),
  check (estimated_seconds is null or estimated_seconds > 0),
  check (remaining_seconds is null or remaining_seconds > 0)
);

create table if not exists public.task_plan_versions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  revision bigint not null check (revision > 0),
  source_snapshot_version text not null,
  proposal_digest text not null,
  rules_version text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null check (status in (
    'draft', 'confirmed', 'applied', 'superseded', 'failed'
  )),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  applied_at timestamptz,
  unique (user_id, id),
  unique (user_id, revision),
  unique (user_id, idempotency_key),
  check (starts_on <= ends_on)
);

create table if not exists public.task_time_blocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  plan_version_id uuid not null,
  task_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  planned_seconds integer not null check (planned_seconds > 0),
  unique (user_id, plan_version_id, task_id, starts_at),
  foreign key (user_id, plan_version_id)
    references public.task_plan_versions(user_id, id) on delete cascade,
  check (ends_at > starts_at)
);

create table if not exists public.planned_block_timer_links (
  user_id uuid not null references auth.users(id) on delete cascade,
  planned_block_id uuid not null,
  timer_session_id uuid not null,
  linked_at timestamptz not null default now(),
  primary key (user_id, planned_block_id, timer_session_id),
  foreign key (planned_block_id) references public.task_time_blocks(id)
    on delete cascade
);

alter table public.task_effort_estimates enable row level security;
alter table public.task_plan_versions enable row level security;
alter table public.task_time_blocks enable row level security;
alter table public.planned_block_timer_links enable row level security;

create policy planning_effort_read_own on public.task_effort_estimates
  for select to authenticated using (auth.uid() = user_id);
create policy planning_version_read_own on public.task_plan_versions
  for select to authenticated using (auth.uid() = user_id);
create policy planning_block_read_own on public.task_time_blocks
  for select to authenticated using (auth.uid() = user_id);
create policy planning_timer_link_read_own on public.planned_block_timer_links
  for select to authenticated using (auth.uid() = user_id);

grant select on public.task_effort_estimates to authenticated;
grant select on public.task_plan_versions to authenticated;
grant select on public.task_time_blocks to authenticated;
grant select on public.planned_block_timer_links to authenticated;

-- Write policies/grants and task/timer ownership constraints are intentionally
-- omitted pending the server snapshot, atomic approval, and sync design review.
