-- Keep the established table name for existing installations, while storing
-- the unified recurring-task execution modes used by the app.
alter table public.long_term_tasks
  drop constraint if exists timer_requires_duration;

update public.long_term_tasks
set check_mode = 'timed'
where check_mode in ('timer', 'target_timer', 'free_timer');

update public.long_term_tasks
set check_mode = 'untimed'
where check_mode = 'simple';

alter table public.long_term_tasks
  add constraint timer_requires_duration check (
    (check_mode = 'timed')
    or (check_mode = 'untimed' and target_duration_seconds is null)
  );
