-- Forward-compatible Stage 14A task date fields for the current planning branch.
-- Apply to isolated environments only until Production schema review is complete.
begin;

alter table public.one_time_reminders
  add column if not exists available_from date,
  add column if not exists planned_date date,
  add column if not exists due_date date,
  add column if not exists due_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname='one_time_reminders_deadline_shape_check'
      and conrelid='public.one_time_reminders'::regclass
  ) then
    alter table public.one_time_reminders
      add constraint one_time_reminders_deadline_shape_check
      check (num_nonnulls(due_date,due_at)<=1) not valid;
  end if;
end $$;

create index if not exists one_time_reminders_user_planned_date_idx
  on public.one_time_reminders(user_id,planned_date) where planned_date is not null;
create index if not exists one_time_reminders_user_due_date_idx
  on public.one_time_reminders(user_id,due_date) where due_date is not null;
create index if not exists one_time_reminders_user_due_at_idx
  on public.one_time_reminders(user_id,due_at) where due_at is not null;

comment on column public.one_time_reminders.available_from is
  'Local calendar date from which the one-off task may be acted on.';
comment on column public.one_time_reminders.planned_date is
  'Optional local calendar date planned by the user; not a deadline.';
comment on column public.one_time_reminders.due_date is
  'Date-only deadline, mutually exclusive with due_at.';
comment on column public.one_time_reminders.due_at is
  'Exact-time deadline instant, mutually exclusive with due_date.';

commit;
