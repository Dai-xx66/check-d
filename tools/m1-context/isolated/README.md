# 隔离库验证（local PostgreSQL）

三个 migration 在正式库里**一次都没执行过**。静态检查只能证明源码口径，证明不了三件事：
能不能建、函数能不能调、权限和 RLS 到底拦不拦得住。这套脚本就是为了补上这一段。

## 它证明什么、不证明什么

**能证明**

- 三个 migration 在一套**真实的 PostgreSQL 17** 上从头执行无错（含 9 个既有 migration 作为前置）
- 函数**能真的被调用**并返回设计中的结构（这一点静态检查完全覆盖不到）
- RLS 双账号隔离：A 看不到 B 的事件与偏好
- 表级写权限确实被收回：登录用户直写表被 `permission denied`，只能走 RPC
- 幂等：同 `event_id` 写三次，表里仍 1 行
- 偏好版本 CAS：`expected_version` 不符抛 `40001`
- 学期归属与长期任务排期：上学期课不混入、周末任务不进工作日

**不证明**

- 不是 Supabase。`auth.uid()` 由本地 session 变量模拟，**没有真的 JWT 签名校验**
- 没有 PostgREST 层，函数调用绕过 HTTP 与 schema cache；线上 403/401 行为不在这里覆盖
- 角色权限的默认值由 `00_supabase_stub.sql` 显式设定，可能与某个 Supabase 版本有出入
- **不能据此说「生产库已验证」**。正式库执行仍然是 0 次。

## 怎么跑

```bash
# 1) 取 PostgreSQL binaries（Windows 无安装版）
curl -L -o pg.zip https://get.enterprisedb.com/postgresql/postgresql-17.2-1-windows-x64-binaries.zip
python -c "import zipfile; zipfile.ZipFile('pg.zip').extractall('.')"
# 解压后得到 pgsql/bin

# 2) 初始化（只做一次）
pgsql/bin/initdb.exe -D "$(pwd)/data" -U postgres -A trust -E UTF8 --locale=C

# 3) 起服务（单独一条命令，别放进脚本，否则自己会被阻塞）
pgsql/bin/pg_ctl.exe -D "$(pwd)/data" -o "-p 55432 -c listen_addresses=127.0.0.1" -l "$(pwd)/pg.log" start

# 4) 跑验证
PG_BIN="$(pwd)/pgsql/bin" python tools/m1-context/isolated/run_isolated_verify.py
```

输出 17 项 PASS/FAIL，并把证据写到 `isolated/evidence/isolated-db-verification-<日期>.json`。

## 文件

| 文件 | 作用 |
|---|---|
| `00_supabase_stub.sql` | 复刻 Supabase 里影响 migration 行为的几样东西：`auth` schema、`auth.users`、`auth.uid()`、三个角色、默认授权 |
| `02_verify.sql` | 身份 / 权限 / RLS / 幂等 / 版本 CAS / 信任边界共 11 段 |
| `03_snapshot.sql` | 学期归属、长期任务排期、occurrence 两态、空闲切分共 6 段 |
| `run_isolated_verify.py` | 建库 → 跑 9 个既有 migration + 3 个新 migration → 跑两段验证 → 逐项判 PASS/FAIL → 落 JSON |

## 第一次跑就抓到的真 bug

`checkd_context_snapshot` 里 `cand` CTE 没有把 `r.interval_weeks` 投影出来，但下游 `kept` CTE 直接用了它。
**函数创建成功、执行成功，一调用就报 `column "interval_weeks" does not exist`**，整条快照 500。

静态检查（解析文本）和 Python 参考实现（从原始 dict 取值）都发现不了——只有真跑 SQL 才会暴露。
这正是「migration 未执行」这件事的真正代价。

## 数据

全部为合成数据（两个 `@test.local` 账号、三门课、三个长期任务），不含任何真实用户信息，也不连任何线上地址。
