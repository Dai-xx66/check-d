-- Shared task labels and immutable per-session attribution.
alter table public.tags add column archived boolean not null default false;
alter table public.tags alter column color type bigint;
alter table public.tags add constraint tags_owner_id_unique unique (user_id, id);

alter table public.tasks add column tag_id uuid;
update public.tasks t set tag_id = l.tag_id
  from public.long_term_tasks l where l.task_id = t.id;
alter table public.tasks add constraint tasks_tag_owner_fk
  foreign key (user_id, tag_id) references public.tags(user_id, id);
alter table public.timer_sessions add constraint sessions_tag_owner_fk
  foreign key (user_id, tag_id) references public.tags(user_id, id);

create table public.tag_revisions (
  id uuid primary key default gen_random_uuid(),
  tag_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  snapshot_json jsonb not null,
  changed_at timestamptz not null default now(),
  foreign key (user_id, tag_id) references public.tags(user_id, id)
);
alter table public.tag_revisions enable row level security;
create policy tag_revisions_owner_access on public.tag_revisions
  for all to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create index tag_revisions_owner_changed_idx on public.tag_revisions(user_id, changed_at);
