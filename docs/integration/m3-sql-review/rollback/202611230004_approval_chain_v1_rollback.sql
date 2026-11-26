-- =====================================================================
-- CheckD 审批链 v1 回滚脚本（与 202611230003_approval_chain_v1.sql 配对）
-- 安全性：四张表均为本次新增，drop 不影响任何既有业务数据。
-- 执行前请先确认无待用提案（可选）：
--   select count(*) from public.agent_plan_proposals where status='proposed';
-- =====================================================================

-- 函数（先删函数，避免表 drop 时级联引用悬空）
drop function if exists public.create_plan_proposal(date,date,text,text,text,text,jsonb,jsonb,integer);
drop function if exists public.request_plan_approval(uuid,text);
drop function if exists public.bind_plan_approval_token(uuid,text);
drop function if exists public.get_plan_approval_preview(uuid,text);
drop function if exists public.apply_approved_plan(uuid,text);
drop function if exists public.reject_plan_proposal(uuid,text);

-- 表（级联删除策略/索引）
drop table if exists public.task_time_blocks cascade;
drop table if exists public.task_plan_versions cascade;
drop table if exists public.agent_plan_approvals cascade;
drop table if exists public.agent_plan_proposals cascade;

-- 验证：全部应返回 0 行
-- select * from pg_tables where schemaname='public' and tablename in
--   ('agent_plan_proposals','agent_plan_approvals','task_plan_versions','task_time_blocks');
