-- New assistant-only cost guard. No task, timer, course or auth schema changes.
create table if not exists public.checkd_agent_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null,
  request_count integer not null default 0 check (request_count >= 0),
  last_requested_at timestamptz,
  primary key (user_id, usage_date)
);
alter table public.checkd_agent_usage enable row level security;
revoke all on public.checkd_agent_usage from anon, authenticated;
grant select on public.checkd_agent_usage to authenticated;
create policy checkd_agent_usage_read_own on public.checkd_agent_usage
  for select to authenticated using (user_id = auth.uid());

-- The old public JWT-only reservation could be called directly to burn the
-- app-wide allowance without making any model request. Only the gateway's
-- server credential can reserve, for the user it just verified with Auth.
drop function if exists public.reserve_checkd_agent_request();
create or replace function public.reserve_checkd_agent_request(p_user_id uuid)
returns boolean language plpgsql security definer set search_path = public
as $$
declare
  caller uuid := p_user_id;
  today date := (now() at time zone 'Asia/Shanghai')::date;
  own_count integer;
  last_request timestamptz;
  all_count bigint;
begin
  if auth.role() is distinct from 'service_role' or caller is null then return false; end if;
  -- Serializes the short reservation only, not the model request. Both the
  -- global and per-user caps must remain atomic across function instances.
  perform pg_advisory_xact_lock(724196310);
  select coalesce(sum(request_count), 0) into all_count
    from public.checkd_agent_usage where usage_date = today;
  if all_count >= 300 then return false; end if;
  insert into public.checkd_agent_usage(user_id, usage_date)
    values (caller, today) on conflict do nothing;
  select request_count, last_requested_at into own_count, last_request
    from public.checkd_agent_usage where user_id = caller and usage_date = today for update;
  if own_count >= 30 or (last_request is not null and last_request > now() - interval '3 seconds') then
    return false;
  end if;
  update public.checkd_agent_usage set request_count = request_count + 1, last_requested_at = now()
    where user_id = caller and usage_date = today;
  return true;
end;
$$;
revoke all on function public.reserve_checkd_agent_request(uuid) from public, anon, authenticated;
grant execute on function public.reserve_checkd_agent_request(uuid) to service_role;
