# Stage 04 · M1 · 情境感知与数据基础

负责人 M1。对应任务书 §2 模块 03 + §6 共享协议 v1 的 `ContextSnapshot` 与 `BehaviorEvent`。

## 交付清单

| 文件 | 作用 |
|---|---|
| `supabase/migrations/202611260001_stage04_behavior_events.sql` | 新表 `behavior_events`（append-only）+ 2 个函数 + RLS |
| `supabase/migrations/202611260002_stage04_context_snapshot.sql` | `checkd_context_snapshot()`：情境快照读模型 |
| `supabase/migrations/202611260003_stage04_preference_profiles.sql` | 新表 `preference_profiles`（存储契约归 M1，语义归 M2）+ 2 个函数 + RLS；强制 `confirm=true` |
| `tools/m1-context/context_snapshot.py` | 与 SQL 同算法的 Python 参考实现（可离线跑） |
| `tools/m1-context/fixtures/seed.json` | fixture（结构取自真实表语义，值已脱敏） |
| `tools/m1-context/test_context_snapshot.py` | 25 项验收测试 |
| `tools/m1-context/preference_profile.py` | 偏好契约的 Python 参考实现（weekday 每日默认 / 版本 CAS / 上限校验） |
| `tools/m1-context/test_preference_profile.py` | 35 项验收测试 |
| `tools/m1-context/test_migration_permissions.py` | 14 项迁移权限静态检查（表级写权限、写策略、DEFINER 加固、含反向自检） |
| `tools/m1-context/samples/context_snapshot_sample.json` | 契约样例，M0 可直接对着它写适配 |
| `tools/m1-context/samples/preference_profile_sample.json` | 偏好固定样例（input / expected / resolved 三段） |
| `docs/contracts/stage04-shared-contract-v1-freeze.md` | **冻结版共享契约**（偏好映射 / 三版本号 / 写入授权 / 事件约束 / 三态 / 变更流程） |
| `tools/m1-context/DATA_MAPPING.md` | 每个快照字段的来源表/列与缺失行为 |
| `tools/m1-context/ERROR_CODES.md` | 缺失状态与 reason code / SQLSTATE 全集 |
| `tools/m1-context/G2_ACCEPTANCE.md` | G2 四要素结论、验收清单逐条、复现命令、降级声明 |

## 一、ContextSnapshot

签名：

```sql
public.checkd_context_snapshot(
  p_from date, p_through date,
  p_timezone text default 'Asia/Shanghai',
  p_energy_self_report integer default null,   -- 1..5，用户主动自评，可空
  p_day_start_minute integer default 480,      -- 08:00
  p_day_end_minute   integer default 1380      -- 23:00
) returns jsonb
```

返回字段（与任务书 §6 逐条对应）：

| 字段 | 含义 | 缺数据时的行为 |
|---|---|---|
| `as_of` | 生成时刻（UTC ISO 8601） | — |
| `timezone` | 用户时区（只回显，日期按本地日历日解释） | — |
| `window` | `{from, through}`，跨度上限 31 天 | 超限报 `RANGE_TOO_LARGE` |
| `semester` | `{status, first_week_start_date, total_weeks}` | 无当前学期 → `status=missing` |
| `fixed_events` | 课程实例：`kind/ref_id/title/date/start_minute/end_minute/week_no/source` | 学期缺失 → `[]`（不猜） |
| `free_slots` | `date/start_minute/end_minute/minutes`，已扣课程段 | 无可用 → `[]`（不编造） |
| `tasks` | `task_id/name/type/due_date/due_at/planned_date/available_from/completed/estimated_minutes/estimated_status` | 无预计时长 → `estimated_status=unknown` |
| `workload` | `known_minutes / unknown_estimate_count / open_task_count / status` | 有未知时长 → `status=partial` |
| `energy_self_report` | 用户自评精力，原样回传 | 未提供 → `null` |
| `freshness` | `semester / task_occurrences / completions / overall` | — |
| `status` | `ok` \| `partial` \| `blocked` | — |
| `blocking` | `[{code, message}]`，机器可读的阻断原因 | 无 → `[]` |

`blocking.code` 目前有三种：`SEMESTER_MISSING`、`TASK_OCCURRENCES_UNAVAILABLE`、`TASK_OCCURRENCES_MISSING`。

## 二、BehaviorEvent

表 `behavior_events`，主键 `(user_id, event_id)`。**只能追加，不授权 update/delete**。

| 列 | 说明 |
|---|---|
| `event_id` | 客户端生成的幂等键；同一 ID 重试不新增行 |
| `task_id` | 可空；非空时必须属于当前账号，否则 `TASK_NOT_OWNED` |
| `plan_id` | 可空，不透明引用 |
| `event_type` | `plan_accepted` / `plan_rejected` / `plan_modified` / `task_started` / `task_completed` / `task_deferred` / `preference_confirmed` / `manual_note` |
| `occurred_at` | 带时区时间戳 |
| `planned_minutes` / `actual_minutes` | 可空；**actual 不能用计时器时长自动等同完成** |
| `source` | `app` / `workbuddy` / `import` / `test`，`test` 必须能被区分出来 |
| `reason` | 可空，≤500 字符 |
| `schema_version` | 默认 1 |

调用：

```sql
select public.append_behavior_event('{
  "event_id": "0f6a1c1e-5b2a-4a1e-9b1f-7c2e2a6d1b34",
  "task_id": "…",
  "event_type": "plan_accepted",
  "occurred_at": "2026-11-26T02:10:00Z",
  "planned_minutes": 60,
  "source": "app"
}'::jsonb);
-- → {"event_id": "...", "inserted": true, "owner": "auth.uid()", "schema_version": 1}
```

owner 一律由 `auth.uid()` 决定，调用方**无法**指定别人的 `user_id`。

## 三、两条不能碰的边界

**1. 长周期任务不由服务端展开。**
M3 的 `202611230005_task_occurrence_snapshots.sql` 明确写着「服务端从不展开长周期任务，只有客户端可发布已展开实例」。本实现遵守：只有在 `agent_task_occurrence_snapshots` 存在且覆盖窗口时读它，否则标 `missing` 并写进 `blocking`。

**副作用（对 M0 重要）**：在客户端开始发布 occurrence 之前，`freshness.task_occurrences` 恒为 `missing`，快照整体恒为 `partial`。这是**如实反映**，不是缺陷。要变 `ok` 需要 #20/#21 落地。

**2. 课程由本函数展开。**
`courses` + `course_schedule_rules` + `semesters` 三者足以确定某天是否上课（`week_rule_type` 与 `week_numbers` 是确定的），不需要客户端 attestation。周次算法：

```
week_no = (day - first_week_start_date) / 7 + 1     -- 整数除法
```

规则匹配顺序（与代码一致，改一处必须改两处）：`week_numbers` 非空则**优先**按清单；否则 `everyWeek` / `oddWeeks` / `evenWeeks` / `everyNWeeks`；再叠加 `start_week`/`end_week` 与 `1..total_weeks` 的边界。

## 四、验证状态（请按这个强度引用，不要拔高）

**已验证：**

| 项 | 怎么验的 | 结果 |
|---|---|---|
| 快照算法（周次、单双周、week_numbers 优先、空闲切分、负荷口径、缺失回退） | `python -m unittest test_context_snapshot` | **25 项通过 / 0 失败** |
| 引用的表列真实存在 | 解析 9 份既有 migration（含 M3 的）得 33 张表，逐个核对 | **8 张表、全部列命中，0 处不符** |
| 输出结构与契约字段一致 | `test_output_shape_matches_contract` | 通过 |

**未验证（M1 侧无数据库，必须由有权环境补）：**

| 项 | 为什么没验 | 谁来补 |
|---|---|---|
| 三个 migration 能否在真实库执行 | 本机无 psql / 无容器；到 Supabase 的 5432 直连超时（443 可达但只能做表级 CRUD，跑不了 DDL） | M0 或任意有库权限的成员执行一次 |
| RLS 是否真的隔离两个账号 | 同上 | 需两个测试账号各跑一次读写 |
| 表级写权限收回是否真生效 | 同上 | 用 authenticated 直接 POST 表应被拒（403/42501），调 RPC 应成功 |
| `event_id` 幂等是否真的不重复 | 需要真实 INSERT … ON CONFLICT | 同上 |
| 真实任务/课程数据下的快照 | 需要用户 JWT | 同上 |

**说清楚：这份交付的强度是「算法可复现、结构可审查、SQL 未经执行」。** 不要对外表述为「已跑通」。

## 五、怎么跑

```bash
cd tools/m1-context
python -m unittest test_context_snapshot -v          # 25 项：快照算法
python -m unittest test_preference_profile -v        # 35 项：偏好契约
python -m unittest discover -p 'test_*.py' -v        # 一次跑全部 74 项
python context_snapshot.py fixtures/seed.json \
       --from 2026-11-26 --through 2026-11-28 --energy 3   # 打印样例
```

无第三方依赖，纯标准库。

## 六、并入主线的前置

1. 三个 migration 需在测试库跑一次，把 `\d+ behavior_events` 与一次 `checkd_context_snapshot` 的真实输出贴进 PR。
2. 与 #20/#21 的 occurrence 契约对齐：确认 `agent_task_occurrence_snapshots` 的窗口字段名（`from_date`/`through_date`）与本实现一致。
3. RLS 双账号验证通过后再谈并入 main。
