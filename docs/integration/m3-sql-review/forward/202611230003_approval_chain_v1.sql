-- =====================================================================
-- CheckD 审批链迁移 v1（M3 选型 A：token_digest 契约，服务端现状）
-- 幂等：可重复执行；仅新增表/函数/策略，不修改任何既有表与真实数据
-- 回滚：执行同目录 202611230002_rollback.sql（drop 4 表 + 6 函数）
-- 依据：M0 2026-11-23 补充授权（自主选型 + 允许生产 schema 必要变更）
-- 契约来源：tools/m1-server/checkd_planning_engine/supabase_remote.py
--   create_plan_proposal / request_plan_approval / bind_plan_approval_token
--   （用户 JWT）；get_plan_approval_preview / apply_approved_plan /
--   reject_plan_proposal（公开 token_digest 门禁）
-- =====================================================================

-- ---------- 表 1：agent_plan_proposals ----------
create table if not exists public.agent_plan_proposals (
    id                       uuid primary key default gen_random_uuid(),
    user_id                  uuid not null references auth.users(id) on delete cascade,
    source_snapshot_version  text not null,
    source_data_version      bigint,
    course_occurrence_digest text not null,
    changes                  jsonb not null,
    change_digest            text not null,
    rules_version            text not null,
    starts_on                date not null,
    ends_on                  date not null,
    status                   text not null default 'proposed'
        check (status in ('proposed','approved','rejected','applied','expired')),
    expires_at               timestamptz not null,
    created_at               timestamptz not null default now(),
    decided_at               timestamptz,
    applied_at               timestamptz,
    buffer_minutes           integer,
    risk_summary             jsonb,
    apply_result             jsonb,
    idempotency_key          text not null
);
create unique index if not exists agent_plan_proposals_uidx_ik
    on public.agent_plan_proposals (user_id, idempotency_key);
create index if not exists agent_plan_proposals_idx_owner
    on public.agent_plan_proposals (user_id, created_at desc);

-- ---------- 表 2：agent_plan_approvals ----------
create table if not exists public.agent_plan_approvals (
    id                      uuid primary key default gen_random_uuid(),
    proposal_id             uuid not null references public.agent_plan_proposals(id) on delete cascade,
    user_id                 uuid not null references auth.users(id) on delete cascade,
    status                  text not null default 'pending'
        check (status in ('pending','approved','rejected','expired')),
    token_digest            text check (token_digest is null or token_digest ~ '^[0-9a-f]{64}$'),
    request_idempotency_key text,
    expires_at              timestamptz not null,
    created_at              timestamptz not null default now(),
    decided_at              timestamptz
);
create unique index if not exists agent_plan_approvals_uidx_req
    on public.agent_plan_approvals (proposal_id, request_idempotency_key)
    where request_idempotency_key is not null;
create index if not exists agent_plan_approvals_idx_token
    on public.agent_plan_approvals (token_digest);

-- ---------- 表 3：task_plan_versions（apply 落点，服务端快照回读） ----------
create table if not exists public.task_plan_versions (
    id                      uuid primary key default gen_random_uuid(),
    user_id                 uuid not null references auth.users(id) on delete cascade,
    revision                integer not null,
    source_snapshot_version text not null,
    starts_on               date not null,
    ends_on                 date not null,
    status                  text not null default 'applied'
        check (status in ('applied','superseded')),
    created_at              timestamptz not null default now(),
    applied_at              timestamptz,
    sync_version            bigint not null default 1
);
create index if not exists task_plan_versions_idx_owner_rev
    on public.task_plan_versions (user_id, revision desc);

-- ---------- 表 4：task_time_blocks（apply 落点，服务端快照回读） ----------
create table if not exists public.task_time_blocks (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null references auth.users(id) on delete cascade,
    plan_version_id  uuid not null references public.task_plan_versions(id) on delete cascade,
    task_id          uuid not null,
    starts_at        timestamptz not null,
    ends_at          timestamptz not null,
    planned_seconds  integer not null,
    sync_version     bigint not null default 1,
    deleted_at       timestamptz,
    created_at       timestamptz not null default now(),
    check (ends_at > starts_at),
    check (planned_seconds > 0)
);
create index if not exists task_time_blocks_idx_owner
    on public.task_time_blocks (user_id, starts_at);
create index if not exists task_time_blocks_idx_plan
    on public.task_time_blocks (plan_version_id);

-- ---------- RLS：仅所有者可读，任何角色不可直写 ----------
alter table public.agent_plan_proposals  enable row level security;
alter table public.agent_plan_approvals  enable row level security;
alter table public.task_plan_versions    enable row level security;
alter table public.task_time_blocks      enable row level security;

drop policy if exists agent_plan_proposals_own_select on public.agent_plan_proposals;
create policy agent_plan_proposals_own_select on public.agent_plan_proposals
    for select to authenticated using (user_id = auth.uid());

drop policy if exists agent_plan_approvals_own_select on public.agent_plan_approvals;
create policy agent_plan_approvals_own_select on public.agent_plan_approvals
    for select to authenticated using (user_id = auth.uid());

drop policy if exists task_plan_versions_own_select on public.task_plan_versions;
create policy task_plan_versions_own_select on public.task_plan_versions
    for select to authenticated using (user_id = auth.uid());

drop policy if exists task_time_blocks_own_select on public.task_time_blocks;
create policy task_time_blocks_own_select on public.task_time_blocks
    for select to authenticated using (user_id = auth.uid());

-- 不为四张表创建 insert/update/delete 策略：用户与 anon 均不可直写，
-- 唯一写入路径是下列 security definer 函数。
revoke all on public.agent_plan_proposals from anon;
revoke all on public.agent_plan_approvals from anon;
revoke all on public.task_plan_versions from anon;
revoke all on public.task_time_blocks from anon;
revoke insert, update, delete, truncate on public.agent_plan_proposals from authenticated;
revoke insert, update, delete, truncate on public.agent_plan_approvals from authenticated;
revoke insert, update, delete, truncate on public.task_plan_versions from authenticated;
revoke insert, update, delete, truncate on public.task_time_blocks from authenticated;

-- =====================================================================
-- 函数 1：create_plan_proposal（用户 JWT；幂等）
-- =====================================================================
create or replace function public.create_plan_proposal(
    p_from date,
    p_through date,
    p_expected_snapshot_version text,
    p_expected_course_digest text,
    p_rules_version text,
    p_idempotency_key text,
    p_changes jsonb,
    p_risk_summary jsonb,
    p_buffer_minutes integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_proposal public.agent_plan_proposals%rowtype;
    v_blockers text[] := '{}';
    v_item jsonb;
    v_task_ids uuid[];
    v_existing public.agent_plan_proposals%rowtype;
    v_digest text;
    v_bad_task_count integer;
begin
    if v_user is null then
        return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
    end if;

    -- 幂等重放：同 (user, idempotency_key) 直接返回既有提案
    select * into v_existing
      from public.agent_plan_proposals
     where user_id = v_user and idempotency_key = p_idempotency_key
     limit 1;
    if found then
        return jsonb_build_object('ok', true, 'replayed', true,
            'proposal', to_jsonb(v_existing));
    end if;

    -- 参数校验
    if p_from is null or p_through is null or p_through < p_from
       or (p_through - p_from) > 30 then
        v_blockers := array_append(v_blockers, 'invalid_date_range');
    end if;
    if coalesce(p_expected_snapshot_version, '') = ''
       or coalesce(p_expected_course_digest, '') = ''
       or coalesce(p_rules_version, '') = '' then
        v_blockers := array_append(v_blockers, 'missing_snapshot_contract');
    end if;
    if coalesce(p_idempotency_key, '') = '' then
        v_blockers := array_append(v_blockers, 'missing_idempotency_key');
    end if;
    if p_buffer_minutes is not null and p_buffer_minutes < 0 then
        v_blockers := array_append(v_blockers, 'invalid_buffer_minutes');
    end if;
    if jsonb_typeof(p_changes) <> 'array' or coalesce(jsonb_array_length(p_changes), 0) = 0 then
        v_blockers := array_append(v_blockers, 'invalid_changes');
    else
        for v_item in select jsonb_array_elements(p_changes)
        loop
            if not (v_item ? 'task_id' and v_item ? 'starts_at'
                    and v_item ? 'ends_at' and v_item ? 'planned_seconds') then
                v_blockers := array_append(v_blockers, 'invalid_change_item');
                exit;
            end if;
        end loop;
    end if;

    if 'invalid_changes' = any(v_blockers) or 'invalid_change_item' = any(v_blockers) then
        return jsonb_build_object('ok', false, 'code', 'INVALID_CHANGES',
            'blockers', to_jsonb(v_blockers));
    end if;

    -- 任务归属校验：所有 task_id 必须是本人未删除的 active 任务
    select count(*) into v_bad_task_count
      from (select jsonb_array_elements(p_changes)->>'task_id' as tid) c
     where not exists (
        select 1 from public.tasks t
         where t.id::text = c.tid
           and t.user_id = v_user
           and t.deleted_at is null
           and t.status = 'active');

    if v_bad_task_count > 0 then
        v_blockers := array_append(v_blockers, 'task_not_owned_or_inactive');
    end if;

    -- 时间窗口校验：所有块必须落在 [p_from, p_through] 内
    if (select count(*) from (select jsonb_array_elements(p_changes) as blk) x
        where (x.blk->>'starts_at')::timestamptz::date < p_from
           or (x.blk->>'ends_at')::timestamptz::date > p_through) > 0 then
        v_blockers := array_append(v_blockers, 'change_outside_window');
    end if;

    if array_length(v_blockers, 1) > 0 then
        return jsonb_build_object('ok', false, 'code', 'PROPOSAL_REJECTED',
            'blockers', to_jsonb(v_blockers));
    end if;

    v_digest := encode(sha256(convert_to(p_changes::text, 'utf8')), 'hex');

    insert into public.agent_plan_proposals (
        user_id, source_snapshot_version, source_data_version,
        course_occurrence_digest, changes, change_digest, rules_version,
        starts_on, ends_on, status, expires_at, buffer_minutes, risk_summary,
        idempotency_key)
    values (
        v_user, p_expected_snapshot_version, null,
        p_expected_course_digest, p_changes, v_digest, p_rules_version,
        p_from, p_through, 'proposed', now() + interval '24 hours',
        p_buffer_minutes, p_risk_summary, p_idempotency_key)
    returning * into v_proposal;

    return jsonb_build_object('ok', true, 'replayed', false,
        'proposal', to_jsonb(v_proposal));
exception when unique_violation then
    -- 并发重放
    select * into v_existing
      from public.agent_plan_proposals
     where user_id = v_user and idempotency_key = p_idempotency_key
     limit 1;
    return jsonb_build_object('ok', true, 'replayed', true,
        'proposal', to_jsonb(v_existing));
end;
$$;

-- =====================================================================
-- 函数 2：request_plan_approval（用户 JWT；幂等）
-- =====================================================================
create or replace function public.request_plan_approval(
    p_proposal_id uuid,
    p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_proposal public.agent_plan_proposals%rowtype;
    v_approval public.agent_plan_approvals%rowtype;
begin
    if v_user is null then
        return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
    end if;

    select * into v_proposal
      from public.agent_plan_proposals
     where id = p_proposal_id and user_id = v_user
     limit 1;
    if not found then
        return jsonb_build_object('ok', false, 'code', 'PROPOSAL_NOT_FOUND');
    end if;
    if v_proposal.status <> 'proposed' then
        return jsonb_build_object('ok', false, 'code', 'PROPOSAL_NOT_ELIGIBLE');
    end if;
    if now() >= v_proposal.expires_at then
        update public.agent_plan_proposals
           set status = 'expired'
         where id = v_proposal.id and status = 'proposed';
        return jsonb_build_object('ok', false, 'code', 'PROPOSAL_EXPIRED');
    end if;

    -- 幂等重放
    select * into v_approval
      from public.agent_plan_approvals
     where proposal_id = p_proposal_id
       and request_idempotency_key = p_idempotency_key
     limit 1;
    if found then
        return jsonb_build_object('ok', true, 'replayed', true,
            'approval_id', v_approval.id, 'proposal_id', v_proposal.id,
            'status', v_approval.status, 'expires_at', v_approval.expires_at);
    end if;

    insert into public.agent_plan_approvals (
        proposal_id, user_id, status, token_digest,
        request_idempotency_key, expires_at)
    values (
        v_proposal.id, v_user, 'pending', null,
        p_idempotency_key, now() + interval '30 minutes')
    returning * into v_approval;

    return jsonb_build_object('ok', true, 'replayed', false,
        'approval_id', v_approval.id, 'proposal_id', v_proposal.id,
        'status', v_approval.status, 'expires_at', v_approval.expires_at);
end;
$$;

-- =====================================================================
-- 函数 3：bind_plan_approval_token（用户 JWT；一次性绑定）
-- =====================================================================
create or replace function public.bind_plan_approval_token(
    p_approval_id uuid,
    p_token_digest text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_approval public.agent_plan_approvals%rowtype;
begin
    if v_user is null then
        return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
    end if;
    if p_token_digest is null or p_token_digest !~ '^[0-9a-f]{64}$' then
        return jsonb_build_object('ok', false, 'code', 'INVALID_TOKEN_DIGEST');
    end if;

    select * into v_approval
      from public.agent_plan_approvals
     where id = p_approval_id and user_id = v_user
     limit 1;
    if not found then
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_NOT_FOUND');
    end if;
    if v_approval.status <> 'pending' then
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_NOT_PENDING');
    end if;
    if now() >= v_approval.expires_at then
        update public.agent_plan_approvals set status = 'expired'
         where id = v_approval.id and status = 'pending';
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_EXPIRED');
    end if;

    if v_approval.token_digest is null then
        update public.agent_plan_approvals set token_digest = p_token_digest
         where id = v_approval.id and token_digest is null
        returning * into v_approval;
        if not found then
            return jsonb_build_object('ok', false, 'code', 'TOKEN_ALREADY_BOUND');
        end if;
        return jsonb_build_object('ok', true);
    elsif v_approval.token_digest = p_token_digest then
        return jsonb_build_object('ok', true);
    else
        return jsonb_build_object('ok', false, 'code', 'TOKEN_ALREADY_BOUND');
    end if;
end;
$$;

-- =====================================================================
-- 函数 4：get_plan_approval_preview（公开；token_digest 门禁）
-- =====================================================================
create or replace function public.get_plan_approval_preview(
    p_approval_id uuid,
    p_token_digest text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_approval public.agent_plan_approvals%rowtype;
    v_proposal public.agent_plan_proposals%rowtype;
begin
    select * into v_approval
      from public.agent_plan_approvals
     where id = p_approval_id and token_digest = p_token_digest
     limit 1;
    if not found or v_approval.status <> 'pending' or now() >= v_approval.expires_at then
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_UNAVAILABLE');
    end if;

    select * into v_proposal
      from public.agent_plan_proposals
     where id = v_approval.proposal_id
     limit 1;
    if not found or v_proposal.status <> 'proposed' or now() >= v_proposal.expires_at then
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_UNAVAILABLE');
    end if;

    return jsonb_build_object(
        'ok', true,
        'proposal_id', v_proposal.id,
        'user_id', v_proposal.user_id,
        'status', v_approval.status,
        'expires_at', v_approval.expires_at,
        'starts_on', v_proposal.starts_on,
        'ends_on', v_proposal.ends_on,
        'changes', v_proposal.changes,
        'risk_summary', v_proposal.risk_summary,
        'buffer_minutes', v_proposal.buffer_minutes);
end;
$$;

-- =====================================================================
-- 函数 5：apply_approved_plan（公开；token_digest 门禁；原子幂等落盘）
-- apply = 新建 task_plan_versions(applied) + task_time_blocks + 提案标记 applied
-- =====================================================================
create or replace function public.apply_approved_plan(
    p_approval_id uuid,
    p_token_digest text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_approval public.agent_plan_approvals%rowtype;
    v_proposal public.agent_plan_proposals%rowtype;
    v_version public.task_plan_versions%rowtype;
    v_rev integer;
    v_block jsonb;
begin
    select * into v_approval
      from public.agent_plan_approvals
     where id = p_approval_id and token_digest = p_token_digest
     for update;
    if not found then
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_UNAVAILABLE');
    end if;
    if v_approval.status = 'approved' then
        select * into v_proposal from public.agent_plan_proposals
         where id = v_approval.proposal_id limit 1;
        if v_proposal.status = 'applied' then
            return jsonb_build_object('ok', true, 'status', 'applied',
                'replayed', true, 'apply_result', v_proposal.apply_result);
        end if;
        return jsonb_build_object('ok', false, 'code', 'APPLY_STATE_INVALID');
    end if;
    if v_approval.status <> 'pending' or now() >= v_approval.expires_at then
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_UNAVAILABLE');
    end if;

    select * into v_proposal from public.agent_plan_proposals
     where id = v_approval.proposal_id for update;
    if not found or v_proposal.status <> 'proposed' then
        return jsonb_build_object('ok', false, 'code', 'PROPOSAL_NOT_ELIGIBLE');
    end if;
    if now() >= v_proposal.expires_at then
        update public.agent_plan_proposals set status='expired' where id = v_proposal.id;
        return jsonb_build_object('ok', false, 'code', 'PROPOSAL_EXPIRED');
    end if;

    update public.agent_plan_approvals
       set status = 'approved', decided_at = now()
     where id = v_approval.id;

    select coalesce(max(revision), 0) + 1 into v_rev
      from public.task_plan_versions where user_id = v_proposal.user_id;

    insert into public.task_plan_versions (
        user_id, revision, source_snapshot_version,
        starts_on, ends_on, status, applied_at)
    values (
        v_proposal.user_id, v_rev, v_proposal.source_snapshot_version,
        v_proposal.starts_on, v_proposal.ends_on, 'applied', now())
    returning * into v_version;

    for v_block in select jsonb_array_elements(v_proposal.changes)
    loop
        insert into public.task_time_blocks (
            user_id, plan_version_id, task_id, starts_at, ends_at, planned_seconds)
        values (
            v_proposal.user_id, v_version.id,
            (v_block->>'task_id')::uuid,
            (v_block->>'starts_at')::timestamptz,
            (v_block->>'ends_at')::timestamptz,
            (v_block->>'planned_seconds')::integer);
    end loop;

    update public.agent_plan_proposals
       set status = 'applied', applied_at = now(),
           apply_result = jsonb_build_object(
               'revision', v_rev, 'plan_version_id', v_version.id,
               'blocks', jsonb_array_length(v_proposal.changes),
               'applied_at', now())
     where id = v_proposal.id;

    return jsonb_build_object('ok', true, 'status', 'applied', 'replayed', false,
        'plan_version_id', v_version.id, 'revision', v_rev);
end;
$$;

-- =====================================================================
-- 函数 6：reject_plan_proposal（公开；token_digest 门禁；幂等）
-- =====================================================================
create or replace function public.reject_plan_proposal(
    p_approval_id uuid,
    p_token_digest text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_approval public.agent_plan_approvals%rowtype;
begin
    select * into v_approval
      from public.agent_plan_approvals
     where id = p_approval_id and token_digest = p_token_digest
     for update;
    if not found then
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_UNAVAILABLE');
    end if;
    if v_approval.status = 'rejected' then
        return jsonb_build_object('ok', true, 'status', 'rejected', 'replayed', true);
    end if;
    if v_approval.status <> 'pending' or now() >= v_approval.expires_at then
        return jsonb_build_object('ok', false, 'code', 'APPROVAL_UNAVAILABLE');
    end if;

    update public.agent_plan_approvals
       set status = 'rejected', decided_at = now()
     where id = v_approval.id;
    update public.agent_plan_proposals
       set status = 'rejected', decided_at = now()
     where id = v_approval.proposal_id and status = 'proposed';

    return jsonb_build_object('ok', true, 'status', 'rejected', 'replayed', false);
end;
$$;

-- ---------- 执行权限 ----------
revoke all on function public.create_plan_proposal(date,date,text,text,text,text,jsonb,jsonb,integer) from public;
revoke all on function public.request_plan_approval(uuid,text) from public;
revoke all on function public.bind_plan_approval_token(uuid,text) from public;
revoke all on function public.get_plan_approval_preview(uuid,text) from public;
revoke all on function public.apply_approved_plan(uuid,text) from public;
revoke all on function public.reject_plan_proposal(uuid,text) from public;

grant execute on function public.create_plan_proposal(date,date,text,text,text,text,jsonb,jsonb,integer) to authenticated;
grant execute on function public.request_plan_approval(uuid,text) to authenticated;
grant execute on function public.bind_plan_approval_token(uuid,text) to authenticated;

-- 公开（审批 URL 页面经 PostgREST anon 调用，token_digest 即门禁）
grant execute on function public.get_plan_approval_preview(uuid,text) to anon, authenticated;
grant execute on function public.apply_approved_plan(uuid,text) to anon, authenticated;
grant execute on function public.reject_plan_proposal(uuid,text) to anon, authenticated;
