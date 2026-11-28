# G2 收口与验收口径（M1 模块 03）

对照依据：`CheckD_M1_Task.md` §5 里程碑（11.26 18:00 G2 = 三模块可运行接口、最小真实数据验证、测试及 PR）、§「最低验收清单」五条、§6 共享协议 v1。

本文件只声明**能证到什么、不能证什么**。任何「已通过」都附带可复现命令；任何「未通过」都写清阻塞原因与解除条件。

## 一、G2 四要素逐项结论

| G2 要求 | 结论 | 依据 |
|---|---|---|
| 可运行接口 | **PASS** | 新增 2 张表（`behavior_events` / `preference_profiles`）+ 5 个函数（`append_behavior_event` / `list_behavior_events` / `checkd_context_snapshot` / `upsert_preference_profile` / `get_preference_profile`）+ 5 条 RLS 策略；Python 参考实现一条命令出快照 JSON |
| 测试 | **PASS** | `python -m unittest discover -p 'test_*.py'` → **91 项通过 / 0 失败**（快照 25 + 偏好契约 35 + 迁移权限静态 14 + 跨学期与排期 17，0.016s） |
| PR | **PASS** | PR #22（`Dai-xx66/check-d` ← `Tony2215:feat/m1-stage04-context-snapshot`），分支 head 以 PR 页面为准；本文件所在提交之后可能再更新一两次文档，head 会变，**引用时请取 PR 页面上当时的 head** |
| 最小真实数据验证 | **PASS（隔离库）/ BLOCKED（正式库）** | 已在本地 PostgreSQL 17 + Supabase 适配底座上完整执行三个 migration，24 项行为验证全过（见 §七）；**正式库执行次数仍为 0** |

> **两句话必须一起说，缺一句就是误导**：
> ① 三个 migration 现在**在一套真实 PostgreSQL 上跑通了**，包括建表、函数调用、RLS、幂等、权限拒绝；
> ② 但**正式库（Supabase 项目）里一次都没执行过**，表仍然不存在。前者证明代码可用，后者证明线上还没上。

### 关于 BLOCKED 的准确含义

不是「试过失败了」，是**执行条件不具备**。11-26 13:5x 实测：

| 检查 | 结果 |
|---|---|
| `psql` | 不存在 |
| `docker` / `podman` | 不存在 |
| `cjnrmgxaxkjzvezrurcc.supabase.co:5432`（Postgres 直连） | TCP 超时 |
| `cjnrmgxaxkjzvezrurcc.supabase.co:443`（PostgREST/HTTPS） | TCP 通（0.22s） |

即：**能走 HTTPS，不能走 Postgres 直连**。执行 DDL 必须有 Postgres 连接或库内 SQL 控制台，443 只能做表级 CRUD，跑不了 migration。

**更弱的那条路径已由 M3 代做**（11-26 14:1x，在她已获授权的 Supabase 只读测试范围内，纯 select、不带 service key）：
`behavior_events` / `agent_behavior_events` / `preference_profiles` / `context_snapshots` 四张表**全部返回 404 + PGRST205**（schema cache 中找不到表）。
⇒ 三个 migration 一个都没执行过，**从「自述」升级为「有第三方只读证据」**。这是**采信 M3 实测，非我本人实测**。

解除条件是三者任一：①M0 或任意有库权限的成员代跑三个 migration 并回贴输出；②给 M1 一个隔离测试库的连接（不碰生产）；③M0 明确接受本轮的降级交付形态。

## 二、最低验收清单五条逐条

| # | 任务书原文（摘要） | 当前状态 | 证据 / 缺口 |
|---|---|---|---|
| 1 | 同一测试账号写入行为事件，重读仍有效；相同 `event_id` 重试不重复计数 | **PASS（隔离库）** | 隔离库实测：写入返回 `inserted:true`，同 ID 重放返回 `inserted:false`，连写三次表里仍 1 行（用例 B/C/O）。正式库仍未执行 |
| 2 | 账号 A 不能读取/修改账号 B 的行为、偏好或任务；匿名/过期身份被拒绝 | **PASS（隔离库）** | 隔离库双账号实测：B 读到 A 的事件 0 行、A 读到自己的 1 行；B 读 A 的偏好返回 `absent`；无身份调用抛 `AUTH_REQUIRED`；A 直写表被 `permission denied`（用例 A/D/E1/E2/J）。正式库仍未验证 |
| 3 | 固定课程改变后 `free_slots` 与 `workload` 随之变化；过期/不完整/未展开数据被标记，不生成虚假可用时段 | **PASS（fixture）** | `test_free_slots_change_when_course_changes`（同名断言：改课 → 空闲段跟着变）、`test_no_free_slot_when_day_fully_booked`（不编造时段）、`test_occurrences_missing_marks_partial`（未展开标 `partial`）、`test_missing_semester_blocks_courses`（学期缺失标 `blocked`）、`test_tiny_gap_dropped`、`test_three_days_two_segments_on_course_day`、`test_workload_splits_known_and_unknown`，共 7 项 |
| 4 | 真实任务、计时与完成记录可读取；缺字段返回 `unknown`；不改变原有完成事实 | **部分 PASS（字段映射可审查），真实读取 BLOCKED** | 字段来源见 `DATA_MAPPING.md` 第四节；`one_time_reminders` 无时长列 ⇒ 单次任务 `estimated_minutes` 恒 `null`、`estimated_status=unknown`（`test_missing_estimate_is_unknown_not_zero`）；**真实数据读取需用户 JWT，M1 无** |
| 5 | 时区、跨日、空数据、无可用窗口测试通过；原有任务/课程/同步不回归 | **PASS（算法层）** | 时区：`test_timezone_is_echoed_not_used_for_date_math`；跨日：`test_cross_day_window_covers_each_day`；空数据：`test_empty_data_does_not_crash`；无可用窗口：`test_no_free_slot_when_day_fully_booked`；边界：`test_window_over_31_days_rejected`、`test_reversed_window_rejected`、`test_invalid_energy_rejected`；不回归：`test_archived_course_excluded`、`test_archived_task_excluded`、`test_outside_semester_weeks_ignored`。迁移只新增对象，**不改既有表结构** |

第 5 条的「不回归」是结构性的：迁移只做 `create table if not exists` / `create or replace function` / 新增策略 / 对**本次新建的表**做 `add column if not exists` 与 `drop policy if exists` 重建，不 `alter` 任何既有表、不 `drop` 任何既有对象。

### 补充：第四阶段接口冻结项（M0 11-26 14:35 第二节）

| 项 | 结论 | 证据 |
|---|---|---|
| `preferred_slots` 的「未指定 weekday = 每日」无损映射 | **PASS（Python 层）** | `test_missing_weekday_means_daily`、`test_explicit_overrides_daily`、`test_not_normalized_storage_stays_distinct` |
| `schema_version` / `data_version` / `expected_version` 三分 | **PASS（Python 层）** | `test_schema_version_never_bumped_by_upsert`、`test_mismatch_reports_current_version`、`test_null_expected_skips_check` |
| 写入授权收紧（表级 insert/update 收回，只走 RPC） | **代码已改，真实库未验** | `ERROR_CODES.md` §四之二；迁移 §3；需执行后用 authenticated 试直写被拒才算 PASS |
| 八种 `event_type` 与计时事实（不从 `task_completed` 推算时长） | **契约已写** | 冻结契约 §4；存储侧约束已存在，语义对齐待 M2 确认 |
| `estimated_minutes` 三态（`null` / `unknown` / `missing`） | **PASS（契约 + 测试）** | 冻结契约 §6；`test_missing_estimate_is_unknown_not_zero` |
| 跨学期课程不混入当前周（盘点 Drift 后补的缺口） | **PASS（fixture）** | `test_previous_semester_course_excluded`、`test_legacy_course_without_semester_still_appears`、`test_multiple_current_semesters_keep_all_their_courses` |
| 长期任务按 `task_schedules` 判断本窗口该不该做（同批补的缺口） | **PASS（fixture）** | `test_weekend_only_excluded_on_thursday`、`test_schedule_starting_after_window_excluded`、`test_ended_schedule_excluded`、`test_task_without_schedule_row_kept`、`test_empty_mask_and_no_weekdays_means_never` |

## 三、可复现命令（M0 本地照跑）

```bash
# 0) 取代码
git clone https://github.com/Tony2215/check-d.git && cd check-d
git checkout feat/m1-stage04-context-snapshot     # 分支 head 见 PR #22 页面
cd tools/m1-context

# 1) 测例（91 项，纯标准库，无网络无数据库）
python -m unittest discover -p 'test_*.py' -v
# 实测：Ran 91 tests in 0.016s / OK
# 分项：test_context_snapshot 25 · test_preference_profile 35 · test_migration_permissions 14 · test_semester_and_schedule 17

# 2) 出快照（固定 fixture，可直接给适配层当输入）
python context_snapshot.py fixtures/seed.json \
       --from 2026-11-26 --through 2026-11-28 --energy 3

# 3) 与仓库内样例逐字段比对（应只差 as_of）
python context_snapshot.py fixtures/seed.json \
       --from 2026-11-26 --through 2026-11-28 --energy 3 --out /tmp/now.json
python - <<'PY'
import json
a=json.load(open('/tmp/now.json')); b=json.load(open('samples/context_snapshot_sample.json'))
a.pop('as_of'); b.pop('as_of')
print('identical:', a==b)      # 实测 True
PY
```

## 四、fixture 与样例的固定件指纹

| 文件 | sha256 | 用途 |
|---|---|---|
| `fixtures/seed.json` | `bcc767af25819230da37a57b0620a5b349638c9dbf4b6b4efde10083be0be805` | 联调输入（结构取自真实表语义，值已脱敏） |
| `samples/context_snapshot_sample.json` | `79a9b2e816233e798d67d8588599c879bba5d620e34024f45ed42acf5ddab716` | 期望输出（除 `as_of` 外可与 CLI 输出逐字段比对） |
| `context_snapshot.py` | `a8e75c40da779231b52bc2bd03b425ca8671fe559b44f87a0708596d77c987df` | 参考实现 |
| `test_context_snapshot.py` | `f8e18949658d19af930ddb3d31b3693790bc2d8be3f4844a92f88439f2611fba` | 25 项测试（快照） |
| `preference_profile.py` | 见 `sha256sum` 现算 | 偏好契约参考实现 |
| `test_preference_profile.py` | 见 `sha256sum` 现算 | 35 项测试（偏好） |
| `samples/preference_profile_sample.json` | 见 `sha256sum` 现算 | 偏好固定样例（input / expected / resolved） |

> 前三行是提交时算的固定值；后三行留「现算」，因为本文件还会随契约微调更新，写死会立刻过期。取法：`sha256sum <文件>`。

样例的 `status=partial` 是**预期结果，不是失败**：`blocking[0].code = TASK_OCCURRENCES_UNAVAILABLE`，原因见 `DATA_MAPPING.md` 第六节。

**这一条按 M3 11-26 的提醒订正过**：`UNAVAILABLE`（表不存在）与 `MISSING`（表在但该窗口未发布）是两种状态，不能合并成一句「表不存在」。
fixture 给的是 `UNAVAILABLE`；按 M3 报告，真实库的 occurrence 表**已建**，因此真实快照会是 `MISSING`。执行 migration 后必须复验这一判定，不能拿 fixture 的 code 当现网事实。

## 五、降级交付声明（按任务书 §5「G2 未通过时」条款）

任务书原文允许：*保留已通过模块，用标明测试数据的 fixture 完成集成；生产真实数据仍可做只读预览，缺失硬约束时不得宣称可执行。*

本轮据此交付：

- **可给 M0 直接消费的**：快照与偏好的 JSON 结构与语义、字段映射、错误码、91 项测试、固定 fixture 与样例、冻结版共享契约。适配层可以现在开始写，接口不会因为 SQL 未执行而变。
- **不得对外表述为「已跑通」的**：三个 migration 是否能在真实库执行、RLS 是否真的隔离两账号、表级写权限收回是否真的生效、`event_id` 幂等是否真的不重复、真实数据下的快照值。
- **M0 集成时的硬提醒**：`status=partial` 时 `free_slots` 只保证「没有课」，不保证「没有任务」；缺失硬约束时不得宣称方案可执行。

## 六、责任与解除

| 项 | 责任人 | 解除条件 |
|---|---|---|
| 执行三个 migration | M0 或任一有库权限的成员 | 在隔离/测试库跑一次，回贴 `\d+ behavior_events` 与一次 `checkd_context_snapshot(...)` 的真实输出 |
| RLS 双账号越权验证 | 同上（需两个测试账号） | A 读 B 的 `behavior_events` / `preference_profiles` 返回 0 行；匿名调用返回 `AUTH_REQUIRED` |
| `event_id` 幂等实测 | 同上 | 同 ID 连调两次，第二次返回 `inserted:false`，表行数不变 |
| 表级写权限收回验证 | 同上 | 用 authenticated 角色 `POST /rest/v1/preference_profiles` 应返回 403 / `42501`；`rpc/upsert_preference_profile` 应正常 |
| 真实数据快照 | M1（拿到只读 JWT 后）或 M0 代跑 | 用真实账号调一次，与 App 内课程/任务列表对照 |

隔离库实测完成后，「事件写入 / 幂等」与「双账号隔离」两项已改为 PASS（隔离库）；**正式库部分仍为 BLOCKED**，需在正式库或正式隔离项目执行后另行更新，并附脱敏输出。

## 七、隔离库验证结果（2026-11-26）

因为正式库无法执行、而「能建」不等于「能调」，我用本地 PostgreSQL 17 + 一层 Supabase 适配底座搭了隔离环境，
把三个 migration 连同 9 个既有 migration 从头跑了一遍。M0 2026-11-26 19:12 已正式授权自行搭建隔离测试环境。

**环境**：`127.0.0.1:55432`，PostgreSQL 17.2，数据库 `checkd_isolated`，全部合成数据（两个 `@test.local` 账号）。
**不是** Supabase、**不是**正式库；`auth.uid()` 由本地 session 变量模拟，没有真 JWT 签名校验。

```bash
PG_BIN=<pgsql/bin> python tools/m1-context/isolated/run_isolated_verify.py
# → 24/24 项通过，证据写 isolated/evidence/isolated-db-verification-<日期>.json
```

| 组 | 用例 | 结果 |
|---|---|---|
| 迁移执行 | 9 个既有 migration + 3 个 stage04 migration，从头执行 | **全部 OK** |
| 身份 | 无身份调用写函数 → `AUTH_REQUIRED` | PASS |
| 写入 | 正常写事件 → `inserted:true` | PASS |
| 幂等 | 同 ID 重放 → `inserted:false`；连写三次仍 1 行 | PASS |
| 权限 | 登录用户直写表 → `permission denied`（表级写权限确实收回） | PASS |
| RLS | B 看不到 A 的事件（0 行），A 看得到自己的（1 行） | PASS |
| 归属 | 事件挂他人 task → `TASK_NOT_OWNED` | PASS |
| 确认 | 偏好未带 confirm → `CONFIRMATION_REQUIRED` | PASS |
| 版本 | 首次写入 `data_version=1`；`expected_version` 不符 → `40001 VERSION_CONFLICT` | PASS |
| 偏好隔离 | B 读 A 的偏好 → `absent` | PASS |
| 学期归属 | 周四课程只含「本学期课 + 无学期历史课」，上学期课被排除 | PASS |
| 排期 | 周四只剩工作日任务；周六只剩周末任务；无排期老任务始终保留 | PASS |
| 空闲切分 | 周四 3 段 / 共 620 分钟（与手算一致） | PASS |
| occurrence 两态 | 表不存在 → `UNAVAILABLE`；表存在但无覆盖 → `MISSING` | PASS |
| **完整链路** | 偏好写入→读回（data_version=1）→ 快照（课/空闲/任务/负荷）→ 挑出时段与任务 → 写接受/开始/完成三事件 → 读回 plan 一致、实测 25 分钟 → 另一账号 0 条 | PASS |

**这一轮抓到的真 bug（静态检查与 Python 测试都发现不了）**

`checkd_context_snapshot` 的 `cand` CTE 没有投影 `r.interval_weeks`，下游 `kept` CTE 直接用了它。
函数**创建成功、执行成功**，一被调用就报 `column "interval_weeks" does not exist`，整条快照 500。
Python 参考实现从原始 dict 取值，所以测试全绿也测不出来。已修并固化进上面的脚本。

**这次验证改变不了的事**

正式库仍是 0 次执行，表仍不存在。隔离库 PASS ≠ 生产可用。
