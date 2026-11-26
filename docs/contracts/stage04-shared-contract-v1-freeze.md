# Stage 04 共享契约 v1 · 冻结候选（M1 主责）

| 项 | 值 |
|---|---|
| 版本 | v1-freeze-candidate（2026-11-26） |
| 主责 | M1（数据结构 / 存储契约） |
| 待确认 | M2（画像与事件语义、客户端消费）、M3（服务端约束与端到端验收）、M0（拍板冻结） |
| 状态 | **契约冻结候选，尚未在任何真实库执行**（三张表不存在，M3 11-26 14:1x 只读探测 PGRST205） |
| 对应 | 任务书 §6 共享协议 v1；M0 11-26 14:35 联合收口任务单第二节 |

## 0. 怎么读

- **M0**：读 §1（偏好映射）、§2（版本）、§3（授权）——这三节是要你拍板的。
- **M2**：读 §1、§3（你的写入路径要改）、§4（事件存储约束）、§7（变更流程）。
- **M3**：读 §3（权限矩阵）、§8（验证状态，写报告时按这个强度引用）。
- 全文没有一处把「未执行」写成「已验证」。凡出现「已验证」只指 Python 层可复现测试。

## 1. PreferenceProfile

### 1.1 结构

```jsonc
{
  "preferred_slots": [
    { "weekday": 1,      "start_minute": 1140, "end_minute": 1260 },  // 周一
    { "weekday": null,   "start_minute": 540,  "end_minute": 660  }   // 每日默认
  ],
  "focus_minutes": 25,        // 可空
  "break_minutes": 5,         // 可空
  "source": "explicit",       // explicit | inferred
  "confirm": true             // 仅写入时使用，不落库
}
```

### 1.2 `preferred_slots` 的映射规则（冻结口径）

**规则 1：`weekday` 允许缺省或 `null`，含义是「每日默认」。**

- `weekday` ∈ 1..7（1=周一，与 `course_schedule_rules.weekday` 的 isodow 一致）。
- `weekday` 缺省 与 `weekday: null` 等价，服务端不再区分（两者都落成 JSON `null`）。
- 这条是为了兼容 M2 的「未指定 weekday 即每日偏好」：M2 不需要把每日偏好复制成 7 条。

**规则 2：显式 `weekday` 覆盖每日默认，不是叠加。**

某天 `d` 生效的时段 = 存在 `weekday == d` 的条目 ? 只用这些条目 : 用 `weekday is null` 的条目。

为什么不是叠加：叠加会让「周末不要按工作日的偏好排」这种需求无法表达，用户也没法用一条显式设置排除某天的默认偏好。

**规则 3：不做语义归一化，存什么样读什么样。**

`[{weekday: null, 19:00–21:00}]` 与 `[{weekday: 1..7 各一条, 19:00–21:00}]` 在**解析结果**上等价，
但存储必须保持原样、不互转。互转会丢掉「用户逐日设置过」这个事实，而这份事实在未来做逐日微调时是必要的。

已有数据兼容：旧行 `weekday` 全都有值，规则 1 只是放宽而不是改写，**既有行不需要迁移，语义不变**。

**规则 4：同一天允许多段；消费侧算可用窗口前必须合并重叠/相接的段。**

不解合并会重复计算同一段时间。Python 参考实现给 `merge_segments()`。

### 1.3 时长合法范围

| 字段 | 范围 | 越界时 |
|---|---|---|
| `start_minute` | 0–1439（本地日 00:00 起算的分钟） | `INVALID_SLOT_RANGE` |
| `end_minute` | 1–1440 | `INVALID_SLOT_RANGE` |
| 单段时长 `end - start` | > 0 且 ≤ 1440 | `INVALID_SLOT_RANGE` |
| `focus_minutes` | 5–480，可空 | SQL 侧表约束 `23514`；Python 侧 `CHECK_VIOLATION` + field |
| `break_minutes` | 0–120，可空 | 同上 |

### 1.4 超过 32 条时怎么处理

**硬失败 `TOO_MANY_SLOTS`，不截断。**

理由：截断是静默丢用户偏好，用户以为存上了、实际少了几段，比报错糟得多。32 = 7 天 × 4 段 + 4 条每日默认，足够覆盖真实用例。错误里带原始条数（`detail`），便于客户端提示「你设置得太细了，请合并」。

## 2. 版本控制

三个版本号**含义不同，禁止混用**。这是最容易出错的一节。

| 名称 | 含义 | 谁维护 | 递增规则 | 出现位置 |
|---|---|---|---|---|
| `schema_version` | **结构版本**：这段 JSON / 这张表的字段语义 | M1 | 只在字段增删改语义时 +1；当前恒 `1` | 表列 + 每份返回体 |
| `data_version` | **用户数据并发版本**：这一行被改过几次 | 服务端 | 每次成功 upsert +1，从 1 开始；不存在时返回 0 | 表列 + 每份返回体 |
| `expected_version` | **调用方的期望版本**：我基于哪一版在改 | 调用方传入 | 不落库 | 仅写入参数 |

**规则**

1. `schema_version` **不随写入递增**。写 100 次它还是 1。看到它变化，说明是结构变更，此时客户端必须重新适配。
2. `data_version` 只由服务端递增。客户端传什么都不影响它，也不能传。
3. `expected_version` 省略（`null`）= 不校验；给定整数 = CAS，与当前 `data_version` 不等则抛 `VERSION_CONFLICT`（SQLSTATE `40001`），`detail` 里带**当前真实版本**，客户端应重读后再写。
4. 首次写入（该账号还没有行）：`expected_version` 必须为 `null` 或 `0`，传其他值同样报 `VERSION_CONFLICT`（`detail=0`）。
5. 并发：SQL 侧对同一 `user_id` 取事务级咨询锁后再比较版本，因此同账号写入被串行化，CAS 成立。Python 参考实现只模拟单线程语义，**不能拿它当并发正确性证明**。

**典型混用错误**（写在这里是为了让评审能直接指着说）：

- 把 `schema_version` 当 ETag 用 → 永远不冲突，等于没有并发保护。
- 把 `data_version` 写进 JSON 返回值以外的地方（比如当结构版本判断兼容性）→ 结构升级时会误判。
- 客户端自己算 `data_version+1` 传上来 → 服务端忽略传入值，只认自己的计数。

## 3. 写入授权（唯一路径）

### 3.1 原先的问题

原设计给 `authenticated` 授了表的 `insert` / `update`，RLS 只检查 `auth.uid() = user_id`。
后果：客户端可以直接 `insert ... confirmed_at = now()`，**完全绕过 `upsert_preference_profile()` 里的 `confirm=true` 校验**。
「用户确认后才落库」这条红线就只是函数里的一个摆设。

### 3.2 冻结口径

| 对象 | authenticated | anon | 说明 |
|---|---|---|---|
| `preference_profiles` SELECT | ✅ | ❌ | 只能读自己的行（RLS） |
| `preference_profiles` INSERT/UPDATE | ❌ **已收回** | ❌ | 表级写权限一律不授 |
| `upsert_preference_profile(jsonb, integer)` | ✅ EXECUTE | ❌ | **唯一写入路径** |
| `get_preference_profile()` | ✅ EXECUTE | ❌ | 唯一读取路径（带 `status`） |
| `append_behavior_event(jsonb)` | ✅ EXECUTE | ❌ | 事件唯一写入路径 |
| `behavior_events` INSERT | ❌ | ❌ | 只能走函数，避免绕过归属与幂等 |

**为什么只靠 RLS 拦不住**：RLS 管的是「哪些行」，不管「怎么写的」。要强制「必须经过确认流程」，只能不给表级写权限，让写操作只能进函数。
**归属由谁保证**：函数是 `security definer`，以属主身份写表；表属主默认 bypass RLS，所以函数内 `v_user := auth.uid()` 才是唯一归属保证。这也正是禁止客户端直写表的原因——直写时归属只由 RLS 决定，而确认流程无人强制。

### 3.3 对 M2 的影响（必须改）

客户端不能再走 PostgREST 直连写表，**必须改调 RPC**：

```sql
select public.upsert_preference_profile(
  '{"confirm": true, "preferred_slots": [...], "focus_minutes": 25}'::jsonb,
  3            -- expected_version，可省略
);
```

这是我方单方面收紧，属于契约变更，按 §7 流程需要 M2 明确确认。若 M2 认为直写表不可替代，请给出「如何在不给表级写权限的前提下直写」的方案，否则以本节为准。

## 4. BehaviorEvent（存储侧约束）

八种 `event_type` 的**语义归属 M2**，本节只写 M1 存储侧的硬约束：

| 约束 | 内容 |
|---|---|
| 幂等键 | `(user_id, event_id)`，主键。同 `event_id` 重提返回 `inserted:false`，不新增行、不报错 |
| 归属 | `user_id` 不接受入参，恒为 `auth.uid()`；`task_id` 非空时必须属于本人，否则 `TASK_NOT_OWNED` |
| 只追加 | 无 `update` / `delete` 授权。事件是事实记录，不允许改写 |
| `source` | `app` / `workbuddy` / `import` / `test`；`test` 必须能与真实数据区分 |
| 枚举越界 | 由表约束拒绝（`23514`），不是自定义码 |
| 时间 | `occurred_at` 带时区，存储原样，不转本地时间 |

**计时事实（对应任务单第二节第 4 项）**

- 专注时长的**唯一来源**是真实计时记录（`timer_sessions` / `TimerSession`）。
- `task_completed` 事件的 `actual_minutes` 只在客户端有实测计时时填写；**没有实测就留 `null`**。
- **禁止**用 `task_completed` 出现这件事反推专注时长，也禁止用「计划时长」填补 `actual_minutes`。
- 这条不是建议：任务书 §8 红线写明「不能让 LLM 伪造完成记录」，推算时长与伪造同性质。

## 5. ContextSnapshot

字段级映射见 `tools/m1-context/DATA_MAPPING.md`，此处只重申三条冻结口径：

1. **缺失不伪造**：缺数据返回 `null` / `unknown` / `missing` + `blocking.code`，不给默认值。
2. **`status=partial` 时 `free_slots` 只保证「没有课」，不保证「没有任务」**。长周期任务实例由客户端发布，服务端不展开。
3. 课程由 M1 展开（`courses` + `course_schedule_rules` + `semesters` 三者可唯一确定），周次 `week_no = (day - first_week_start_date) / 7 + 1`。

## 6. 三态语义（`null` / `unknown` / `missing`）

| 形态 | 例子 | 消费方式 |
|---|---|---|
| `null` | 单次任务的 `estimated_minutes`（`one_time_reminders` 无时长列） | 不计入 `known_minutes`，计入 `unknown_estimate_count` |
| `unknown` | `estimated_status` | 走「未知分支」，**不得当 0** |
| `missing` | `semester.status`、`freshness.task_occurrences` | 触发 `blocking.code`，不得静默回退成空数据 |

`0 分钟` 与 `未知` 是两个不同事实；`空列表` 与 `这张表不存在` 也是两个不同事实。任何一处把它们合并，都会让下游排出「看似合理但违反现实」的计划。

## 7. 变更流程

1. 字段增删或语义变更 → 改本文件 + 同步 `DATA_MAPPING.md` / `ERROR_CODES.md` + 更新固定样例，**同一次提交**。
2. 通知 M2（消费端）与 M3（服务端验证），并在邮件线程里点名哪一节变了。
3. `schema_version` +1，旧样例保留一份，便于回溯。
4. 不接受「各自维护一份契约」。谁发现两份不一致，以本文件为准，并把差异报给 M1。

## 8. 验证状态（写报告时按这个强度引用）

| 项 | 状态 | 依据 |
|---|---|---|
| 偏好校验与解析规则（weekday null / 覆盖 / 不归一化 / 32 上限 / 版本 CAS） | **PASS（Python 层）** | `python -m unittest test_preference_profile -v` → 35 项通过 |
| 快照算法 | **PASS（Python 层）** | `python -m unittest test_context_snapshot -v` → 25 项通过 |
| 三个 migration 能否在真实库执行 | **BLOCKED** | 表不存在（PGRST205，M3 只读探测）；本机无 psql / 容器，5432 直连超时 |
| RLS 双账号隔离 | **BLOCKED** | 同上，且需两个测试账号 |
| 表级权限收回是否真的生效 | **BLOCKED** | 需在真实库执行后，用 authenticated 角色试直写表并被拒，才算验过 |

**禁止表述**：「偏好存储已上线」「RLS 已验证」「表已建好」。

## 9. 待确认清单

| # | 事项 | 谁确认 | 状态 |
|---|---|---|---|
| 1 | `weekday: null` = 每日默认，显式覆盖不叠加、不归一化 | M2 | ⬜ 待确认 |
| 2 | `schema_version` / `data_version` / `expected_version` 三分，`VERSION_CONFLICT` 走 `40001` | M2、M3 | ⬜ 待确认 |
| 3 | 表级 insert/update 收回，写入只走 RPC | M2 | ⬜ 待确认（会改你的写入路径） |
| 4 | 八种 `event_type` 与 M2 采集点一一对应，`test` 来源可区分 | M2 | ⬜ 待确认 |
| 5 | 专注时长只取 `timer_sessions`，不从 `task_completed` 推算 | M2 | ⬜ 待确认 |
| 6 | 三个 migration 在隔离库或生产库执行（需 M0 定） | M0 | ⬜ 待定 |
