alter table public.long_term_tasks
  drop constraint if exists timer_requires_duration;

alter table public.long_term_tasks
  alter column check_mode type text using check_mode::text;

update public.long_term_tasks
set check_mode = 'target_timer'
where check_mode = 'timer';

alter table public.long_term_tasks
  add constraint timer_requires_duration check (
    (check_mode = 'target_timer' and target_duration_seconds is not null)
    or (check_mode in ('free_timer', 'simple') and target_duration_seconds is null)
  );

alter table public.one_time_reminders
  add column if not exists is_timed boolean not null default false;

alter table public.task_completions
  add column if not exists target_reached boolean not null default false;

update public.task_completions as completion
set target_reached = completion.actual_duration_seconds >= task.target_duration_seconds
from public.long_term_tasks as task
where completion.task_id = task.task_id
  and task.check_mode = 'target_timer';

comment on column public.task_completions.target_reached is
  'Whether the independent duration target was reached; task completion remains in is_success.';
