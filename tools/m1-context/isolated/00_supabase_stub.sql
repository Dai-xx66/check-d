-- 本地隔离环境用的 Supabase 最小底座。
--
-- 目的：让真实的 migration 能在本地 PostgreSQL 上原样执行，从而验证
--   ① SQL 语法与对象依赖是否成立
--   ② RLS 策略、表级权限、DEFINER 函数的行为
--   ③ 幂等 / 双账号隔离
--
-- 这不是 Supabase，只是复刻它影响 migration 行为的几样东西：
--   · auth schema 与 auth.users 表（migration 里有 references auth.users(id)）
--   · auth.uid()：Supabase 从 JWT claims 里取 sub，这里同样从 session 变量取，
--     因此可以用 `set request.jwt.claims = '{"sub":"<uuid>"}'` 模拟身份切换
--   · anon / authenticated / service_role 三个角色
--   · public schema 的默认授权（Supabase 默认给 authenticated 授表权限，
--     所以 migration 里的 revoke/grant 才有对比意义）
--
-- 与真实 Supabase 的已知差异（必须如实标注，不能声称等价于生产验证）：
--   · 没有 PostgREST 层，函数调用绕过 HTTP 与 schema cache
--   · auth.uid() 由本地 session 变量驱动，不经过真的 JWT 签名校验
--   · 没有 supabase_realtime publication、storage、edge functions
--   · 角色权限的默认值由本文件显式设定，可能与某个 Supabase 版本有出入

begin;

create schema if not exists auth;

-- 列集合按仓库里 handle_new_user() 触发器实际读取的字段确定：
-- 它读 new.id 与 new.raw_user_meta_data ->> 'display_name'。
create table if not exists auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- 兼容"表已建过"的情况
alter table auth.users
  add column if not exists raw_user_meta_data jsonb not null default '{}'::jsonb;

-- 与 Supabase 的 auth.uid() 同语义：优先取 request.jwt.claim.sub，
-- 否则从 request.jwt.claims 的 JSON 里取 sub。
create or replace function auth.uid() returns uuid
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth   to anon, authenticated, service_role;
grant select on auth.users   to authenticated, service_role;

-- Supabase 的默认授权行为：新建表默认给这三个角色 ALL。
-- 复刻它是为了让 migration 里的 revoke 成为有意义的动作，而不是在空权限上做无用功。
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

commit;
