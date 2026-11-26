-- 0001_snapshot_r3.sql —— 独立 DEMO 快照库 · 修订版 R3（取代 R2）
--
-- 修订依据（逐条对应，不是我自己想的）：
--   M2 2026-11-07T02:54:35Z / 03:07:56Z  三项 P0 初审
--   M0 2026-11-07T03:07:56Z              工单 §二 P0-1~3、§三 P1-1~3、§四 1
--   M2 2026-11-07T03:44:08Z              R2 复审：5 项认可 + 新增 1 个 P1 + 4 条 P2
-- 目标库：全新独立 DEMO，Postgres 14+，不触碰任何既有 / PRODUCTION 库
-- 执行属性：**幂等**，可重复执行；检测到旧版 schema 时显式失败，且**本脚本不做任何自动清理**
--
-- R2 → R3 变更（R2 已认可的 5 项全部原样保留，不推翻）：
--   P1    applied_change 增 (proposal_id, snapshot_id) 复合 FK 指向 proposal
--         —— R2 只保证"各自同属一个 user"，没保证"两者指向同一份快照"；
--            同 user 下可写出 proposal 指 A 快照、apply 记 B 快照的审计不一致。
--   P2-1  snapshot / proposal 增 expires_at > created_at 约束（TTL 不能早于创建）
--   P2-2  guard 的报错文案删掉 "drop schema cascade" 指导
--         —— 报错文本会被照抄执行，一句指导就是一次误删风险；改为要求人工确认
--   P2-3  删掉 snapshot_lookup 索引：与 snapshot_version_uk 列完全相同，纯冗余
--   P2-4  权限语句并入本文件（原先散在文档里，漏执行就前功尽弃）
--
-- 相对 R1 的变更（历史保留，说明为什么改）：
--   P0-1  snapshot 增 unique(snapshot_id,user_id)；proposal / applied_change 改复合 FK
--   P0-2  date_range text 拆为 date_from / date_to（date 类型），据此建 latest 唯一索引
--   P1-1  全量 if not exists + 前置 guard，重复执行不报错
--   P1-2  base_version 改生成列，唯一构造入口，不漂移
--   P1-3  snapshot TTL 与 proposal TTL 两列分存分查（未合并）

-- ============================================================
-- 0. 前置 guard：拒绝在旧版 schema 上"假装成功"
--    两条 guard 分别防两种最难查的半新半旧状态。
--    注意：只 raise，不清库。清库是不可逆动作，不在迁移脚本里做。
-- ============================================================
do $$
begin
  -- 0.1 R1 特征列还在 → 主键/唯一索引与 R2+ 不兼容，且无法原地升级
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'checkd_demo'
       and table_name   = 'snapshot'
       and column_name  = 'date_range'
  ) then
    raise exception
      '检测到 R1 schema（checkd_demo.snapshot.date_range 存在）。R2/R3 改动主键与唯一索引，不支持原地升级。本脚本不会自动清理任何数据；请由库负责人确认后手工处理，或换一个全新的独立 DEMO 库执行。';
  end if;

  -- 0.2 表已在、但 R3 才有的约束不在 → 说明是 R1/R2 残留。
  --     if not exists 会静默跳过建表，于是留下"表是旧的、脚本以为建好了"的状态。
  --     这种状态最难查：跑起来不报错，约束却没生效。
  --     2026-11-07 扩为「四条必须一条不缺」：R3 中途又加了 P1-2 两条（版本维度），
  --     只查一条会放过「有旧约束、缺新约束」的半新半旧状态。
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'checkd_demo' and table_name = 'applied_change'
  ) and (
    -- 必须限定到本 schema 的这张表上。只按 conname 查，别的 schema 有同名约束
    -- 就会误判成"已存在"，于是 guard 放行、约束却没生效（M2 12:13 P2①）。
    select count(*)
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'checkd_demo'
       and c.conname in ('applied_change_proposal_snapshot_fk',
                         'proposal_id_snapshot_uk',
                         'proposal_snapshot_version_fk',
                         'snapshot_id_version_uk')
  ) < 4 then
    raise exception
      '检测到 R1/R2 残留 schema（applied_change 已存在但缺 R3 的 proposal↔snapshot 一致性约束）。本脚本不做原地升级，也不会自动清理；请换全新独立 DEMO 库执行。';
  end if;
end $$;

create schema if not exists checkd_demo;

-- ============================================================
-- 1. 发号表（P0-2：date_from / date_to 两列）
--    一行管一个 (user_id, date_from, date_to)，只用来发号
-- ============================================================
create table if not exists checkd_demo.snapshot_seq (
  user_id      text        not null,
  date_from    date        not null,
  date_to      date        not null,
  next_version integer     not null default 1,
  updated_at   timestamptz not null default now(),
  primary key (user_id, date_from, date_to),
  constraint snapshot_seq_range_ck   check (date_from <= date_to),
  constraint snapshot_seq_version_ck check (next_version > 0)
);

-- ============================================================
-- 2. 快照本体：只追加，不就地改 payload
-- ============================================================
create table if not exists checkd_demo.snapshot (
  snapshot_id    uuid        primary key default gen_random_uuid(),
  user_id        text        not null,
  date_from      date        not null,
  date_to        date        not null,
  version        integer     not null,
  payload        jsonb       not null,   -- 服务端自行读取，不采信请求体
  payload_digest text        not null,   -- sha256(规范化 json)，只做完整性，不当版本号
  payload_bytes  integer     not null,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null,   -- snapshot TTL（与 proposal TTL 分开存，P1-3）
  superseded_at  timestamptz,            -- null = 该 (user,date_from,date_to) 的 latest
  constraint snapshot_version_pos check (version > 0),
  constraint snapshot_range_ck    check (date_from <= date_to),
  constraint snapshot_bytes_ck    check (payload_bytes >= 0),
  -- P2-1：TTL 不能早于创建时刻。没有这条，一个算错的 TTL 会造出"生下来就过期"的快照，
  -- 现象是生成立刻 409，而日志里看不出是 TTL 的错。
  constraint snapshot_ttl_ck      check (expires_at > created_at),
  constraint snapshot_version_uk  unique (user_id, date_from, date_to, version),
  -- P0-1 关键：给 proposal / applied_change 的复合 FK 一个可指向的键。
  -- 单列 FK 允许 A 用户 proposal 指向 B 用户 snapshot，库不会拒；这一条才堵住。
  constraint snapshot_id_user_uk  unique (snapshot_id, user_id),
  -- P1-2（M3 2026-11-07 审查）：给 proposal.snapshot_version 一个可指向的键。
  -- 没有它，proposal 只能锁"这个 snapshot_id 属于谁"，锁不住"版本号对不对" ——
  -- 传 999 也写得进去，base_version 生成列随之变成「<uuid>:999」这种假可信版本。
  constraint snapshot_id_version_uk unique (snapshot_id, version)
);

-- 同 (user_id, date_from, date_to) 任何时刻最多一个 latest
-- P2-3：原 snapshot_lookup (user_id,date_from,date_to,version desc) 已删除——
-- 它与 snapshot_version_uk 列完全相同，只多一个 desc 方向，PG 可反向扫描，纯冗余。
create unique index if not exists snapshot_one_latest
  on checkd_demo.snapshot (user_id, date_from, date_to)
  where superseded_at is null;

create index if not exists snapshot_expiry
  on checkd_demo.snapshot (expires_at) where superseded_at is null;

-- ============================================================
-- 3. Proposal：base_version 由生成列产出（P1-2），TTL 独立（P1-3）
-- ============================================================
create table if not exists checkd_demo.proposal (
  proposal_id      uuid        primary key default gen_random_uuid(),
  user_id          text        not null,
  snapshot_id      uuid        not null,
  snapshot_version integer     not null,
  -- P1-2：生成列 = 唯一构造入口。代码里再拼一次字符串就与库不一致，
  -- 所以不允许应用层写这个字段（写入即报错），杜绝"两处拼接慢慢漂移"。
  base_version     text        generated always as
                     (snapshot_id::text || ':' || snapshot_version::text) stored,
  status           text        not null default 'pending',
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null,   -- proposal TTL，与 snapshot.expires_at 是两个字段两条语义
  applied_at       timestamptz,
  -- 2026-11-07 12:12 追加（本文件尚未在任何库执行过，故原地增补，不升版本号）：
  -- 服务端必须保存自己生成的完整提案内容。契约 L514 原文：「服务端必须加载自己保存的
  -- Proposal 和快照绑定；不接受调用方重新提交完整 Proposal 作为可信输入。」
  -- 没有这一列，apply 只能让调用方把方案再传一遍 —— 那正是契约禁止的做法。
  plan              jsonb       not null,
  validation_status text        not null default 'unvalidated',
  constraint proposal_status_ck check (status in ('pending','applied','rejected','expired')),
  constraint proposal_validation_ck check (validation_status in ('unvalidated','valid','invalid')),
  constraint proposal_plan_ck check (jsonb_typeof(plan) = 'object'),
  constraint proposal_version_pos check (snapshot_version > 0),
  -- P2-1：同 snapshot，TTL 不能早于创建
  constraint proposal_ttl_ck check (expires_at > created_at),
  -- P0-1：复合 FK。proposal.user_id 必须与自己引用的 snapshot.user_id 相同
  constraint proposal_snapshot_fk foreign key (snapshot_id, user_id)
    references checkd_demo.snapshot (snapshot_id, user_id),
  -- P1-2（M3 2026-11-07 审查）：上面那条只锁"归属"，锁不住"版本号"。
  -- 这条把 snapshot_version 钉死在该快照真实存在的 version 上，
  -- 于是 base_version 生成列的值不可能被调用方传参伪造。
  constraint proposal_snapshot_version_fk foreign key (snapshot_id, snapshot_version)
    references checkd_demo.snapshot (snapshot_id, version),
  -- 供 applied_change 复合 FK 指向（P0-1 用 user 维度）
  constraint proposal_id_user_uk unique (proposal_id, user_id),
  -- P1(R3 新增)：供 applied_change 用 snapshot 维度指向。
  -- 有了这条，"这个提案是基于哪份快照"才有库级唯一答案。
  constraint proposal_id_snapshot_uk unique (proposal_id, snapshot_id)
);

create index if not exists proposal_user
  on checkd_demo.proposal (user_id, created_at desc);
create index if not exists proposal_pending
  on checkd_demo.proposal (expires_at) where status = 'pending';

-- ============================================================
-- 4. 应用结果：apply 成功才写，与 proposal 状态同事务
-- ============================================================
create table if not exists checkd_demo.applied_change (
  apply_id     uuid        primary key default gen_random_uuid(),
  proposal_id  uuid        not null,
  user_id      text        not null,
  snapshot_id  uuid        not null,
  applied_at   timestamptz not null default now(),
  result       jsonb       not null,
  -- 幂等最后一道闸：并发两个 apply 都过了前置检查，第二个在插入时冲突 → 回滚 → ALREADY_APPLIED
  constraint applied_change_proposal_uk unique (proposal_id),
  -- P0-1：归属一致。proposal 与 snapshot 都必须同属一个 user
  constraint applied_change_proposal_fk foreign key (proposal_id, user_id)
    references checkd_demo.proposal (proposal_id, user_id),
  constraint applied_change_snapshot_fk foreign key (snapshot_id, user_id)
    references checkd_demo.snapshot (snapshot_id, user_id),
  -- P1(R3)：**指向一致**。上面两条合起来只保证"各自同属一个 user"，
  -- 仍可写出 proposal 指 A 快照、apply 记 B 快照 —— 审计链断开而库不拒。
  -- 这条复合 FK 把 applied_change.snapshot_id 钉死在 proposal 自己的那份快照上。
  constraint applied_change_proposal_snapshot_fk foreign key (proposal_id, snapshot_id)
    references checkd_demo.proposal (proposal_id, snapshot_id)
);

-- ============================================================
-- 5. 权限（P2-4：并入本文件；M2 12:13 报的 P0 已修）
--
-- 关键修正：原先把权限授给 current_user —— 在 Supabase 上那是执行 SQL 的 postgres，
-- 不是应用连接角色。而上面已经把 public 收掉了，于是应用角色既不在 grant 里、
-- 也不在 public 里 → 连上去直接 permission denied。
-- 授权必须给**应用真正使用的那个角色**，且 current_user 的权限对它没有传递性。
--
-- 角色名硬编码为 checkd_demo_app（M2 指出的方案①；SQL Editor 不支持 psql 变量）。
-- 角色不存在则建（nologin，不设密码，只用于授权）。
-- ============================================================
revoke all on schema checkd_demo from public;

do $$
declare
  app_role text := 'checkd_demo_app';
  r text;
begin
  -- 5.1 建应用角色（已存在则复用）。建不了就直接失败——不能静默跳过，
  --     否则后面的 grant 会静默失效，最后表现为"应用连不上"而脚本说成功。
  if not exists (select 1 from pg_roles where rolname = app_role) then
    begin
      execute format('create role %I nologin', app_role);
    exception when insufficient_privilege then
      raise exception
        '无法创建角色 %（缺少 CREATEROLE 权限）。请先由库管理员手工执行 create role %I nologin，再重跑本脚本。',
        app_role, app_role;
    end;
  end if;

  -- 5.2 收回 Supabase 内置角色的权限（角色不存在则跳过，纯 PG 环境不报错）
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on schema checkd_demo from %I', r);
      execute format('revoke all on all tables in schema checkd_demo from %I', r);
    end if;
  end loop;

  -- 5.3 授给应用角色：只给 usage + DML，不给 DDL
  execute format('grant usage on schema checkd_demo to %I', app_role);
  execute format('grant select, insert, update on all tables in schema checkd_demo to %I',
                 app_role);

  -- 5.4 显式收回建表/删表权。grant usage 本身不含 create，但显式收回是为了
  --     防止有人手工补过权限后这里没人再纠正。
  execute format('revoke create on schema checkd_demo from %I', app_role);
  execute format('revoke delete, truncate, references, trigger on all tables '
                 'in schema checkd_demo from %I', app_role);
end $$;

-- 5.5 以后新建的表也自动只给应用角色读写的同类权限
alter default privileges in schema checkd_demo
  revoke all on tables from public;
alter default privileges in schema checkd_demo
  grant select, insert, update on tables to checkd_demo_app;

-- ============================================================
-- 6. 发号：单语句，禁止 select max+1
--    首次插入 next_version=2 → 返回 1；并发第二次阻塞在该行 update → 3 → 返回 2
-- ============================================================
-- insert into checkd_demo.snapshot_seq (user_id, date_from, date_to, next_version)
-- values ($1, $2, $3, 2)
-- on conflict (user_id, date_from, date_to)
-- do update set next_version = checkd_demo.snapshot_seq.next_version + 1,
--               updated_at   = now()
-- returning next_version - 1 as version;

-- ============================================================
-- 7. 取新号后的同事务两步（锁序固定：seq 行 → 旧 latest 行 → 插新行）
-- ============================================================
-- update checkd_demo.snapshot set superseded_at = now()
--  where user_id = $1 and date_from = $2 and date_to = $3 and superseded_at is null;
--
-- insert into checkd_demo.snapshot
--   (user_id, date_from, date_to, version, payload, payload_digest, payload_bytes, expires_at)
-- values ($1, $2, $3, $4, $5::jsonb, $6, $7, now() + make_interval(secs => $8))
-- returning snapshot_id;
