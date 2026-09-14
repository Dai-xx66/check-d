-- Stage 13B: temporary course-share transport storage.
-- This is deliberately separate from synced course data.

create table if not exists public.course_share_packages (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  code text not null unique,
  schema_version integer not null check (schema_version > 0),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint course_share_packages_code_format
    check (code ~ '^[A-HJ-KM-NP-Z2-9]{8}$'),
  constraint course_share_packages_expiry
    check (expires_at > created_at)
);

create index if not exists course_share_packages_expiry_idx
  on public.course_share_packages(expires_at);

create index if not exists course_share_packages_owner_idx
  on public.course_share_packages(owner_user_id, created_at desc);

alter table public.course_share_packages enable row level security;

revoke all on table public.course_share_packages from anon, authenticated;

create or replace function public.create_course_share(
  p_code text,
  p_schema_version integer,
  p_payload jsonb,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(regexp_replace(p_code, '[[:space:]-]', '', 'g'));
  v_course_count integer;
  v_inserted integer;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if v_code !~ '^[A-HJ-KM-NP-Z2-9]{8}$' then
    raise exception 'invalid share code' using errcode = '22023';
  end if;
  if p_schema_version is null or p_schema_version <= 0 or
      coalesce((p_payload ->> 'schemaVersion')::integer, -1) <> p_schema_version then
    raise exception 'invalid schema version' using errcode = '22023';
  end if;
  if p_payload is null or
      jsonb_typeof(p_payload) <> 'object' or
      jsonb_typeof(p_payload -> 'courses') <> 'array' then
    raise exception 'invalid share payload' using errcode = '22023';
  end if;
  v_course_count := jsonb_array_length(p_payload -> 'courses');
  if v_course_count < 1 or v_course_count > 50 then
    raise exception 'invalid course count' using errcode = '22023';
  end if;
  if octet_length(convert_to(p_payload::text, 'UTF8')) > 65536 then
    raise exception 'share payload too large' using errcode = '22023';
  end if;
  if p_expires_at is null or p_expires_at <= now() or
      p_expires_at > now() + interval '30 days 5 minutes' then
    raise exception 'invalid expiry' using errcode = '22023';
  end if;

  insert into public.course_share_packages(
    owner_user_id, code, schema_version, payload, expires_at
  ) values (
    v_user_id, v_code, p_schema_version, p_payload, p_expires_at
  ) on conflict (code) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    return jsonb_build_object('status', 'collision');
  end if;
  return jsonb_build_object(
    'status', 'ok',
    'code', v_code,
    'expires_at', p_expires_at
  );
end;
$$;

create or replace function public.fetch_course_share(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text := upper(regexp_replace(p_code, '[[:space:]-]', '', 'g'));
  v_share public.course_share_packages%rowtype;
begin
  if v_code !~ '^[A-HJ-KM-NP-Z2-9]{8}$' then
    return jsonb_build_object('status', 'not_found');
  end if;
  select * into v_share
  from public.course_share_packages
  where code = v_code
  limit 1;

  if v_share.id is null then
    return jsonb_build_object('status', 'not_found');
  end if;
  if v_share.expires_at <= now() then
    return jsonb_build_object('status', 'expired');
  end if;
  return jsonb_build_object(
    'status', 'ok',
    'code', v_share.code,
    'schema_version', v_share.schema_version,
    'payload', v_share.payload,
    'expires_at', v_share.expires_at
  );
end;
$$;

create or replace function public.delete_course_share(p_code text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.course_share_packages
  where owner_user_id = auth.uid()
    and code = upper(regexp_replace(p_code, '[[:space:]-]', '', 'g'));
$$;

revoke all on function public.create_course_share(text, integer, jsonb, timestamptz) from public;
revoke all on function public.fetch_course_share(text) from public;
revoke all on function public.delete_course_share(text) from public;

grant execute on function public.create_course_share(text, integer, jsonb, timestamptz)
  to authenticated;
grant execute on function public.fetch_course_share(text)
  to anon, authenticated;
grant execute on function public.delete_course_share(text)
  to authenticated;
