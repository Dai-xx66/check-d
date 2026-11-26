# 缺失状态与 reason code 映射

给 M0 做适配层用。回答两件不同的事，不要混：

- **`status` / `freshness`**：这份数据「新不新、全不全」。永远不抛错，照常返回快照。
- **`blocking[].code` 与抛出的错误码**：某个字段为什么是空的、这次调用为什么被拒。

约定：**缺失不伪造**。缺数据 = `unknown` / `null` / `[]` + 一个可机读的 code，不给默认值冒充真实值。

## 一、时间与入参校验

| code | 触发条件 | Python 侧 | SQL 侧 SQLSTATE | 调用方应做什么 |
|---|---|---|---|---|
| `INVALID_RANGE` | `p_from > p_through`（含 `list_behavior_events` 的同类倒序） | `ValueError` | `22023` | 修正入参，不要重试 |
| `RANGE_TOO_LARGE` | 窗口跨度 > 31 天 | `ValueError` | `22023` | 缩小窗口；31 是硬上限，不提供分页 |
| `INVALID_DAY_WINDOW` | `p_day_start_minute >= p_day_end_minute`，或 `day_end_minute > 1440`，或为负 | `ValueError` | `22023` | 修正入参 |
| `INVALID_ENERGY` | `p_energy_self_report` 不在 `1..5` 且非 `null` | `ValueError` | `22023` | 传 `1..5` 或不传 |

Python 参考实现抛 `ValueError(code)`；SQL 侧 `raise exception using errcode='22023', message=<code>`。两边码字面相同，可直接用字符串匹配。

## 二、身份与归属

| code | 触发条件 | SQLSTATE | 说明 |
|---|---|---|---|
| `AUTH_REQUIRED` | 无 JWT / `auth.uid()` 为空 | `42501` | 匿名身份一律拒绝；**所有**入口（快照、事件追加、事件查询、偏好读写）都有这道闸 |
| `TASK_NOT_OWNED` | `append_behavior_event` 的 `task_id` 不属于 `auth.uid()` | `42501` | 跨账号引用任务；不泄漏该 task 是否存在 |

`42501` 是 PostgreSQL 的 `insufficient_privilege`。调用方按 401/403 处理，不要当成 500。

## 三、行为事件（`behavior_events`）

函数层自定义码（可直接字符串匹配）：

| code | 触发条件 | SQLSTATE |
|---|---|---|
| `INVALID_EVENT` | 入参不是 JSON 对象；或 `event_type` / `source` 缺失 | `22023` |
| `INVALID_EVENT_ID` | `event_id` 缺失或不是合法 uuid | `22023` |
| `INVALID_EVENT_FIELD` | `occurred_at` 无法解析或为空；`task_id` / `planned_minutes` / `actual_minutes` 无法转换类型 | `22023` |

**枚举越界与取值越界不走自定义码，由表约束拒绝**，SQLSTATE `23514`（`check_violation`）。下表约束名按 PostgreSQL 内联 `check` 的默认命名规则（`<表>_<列>_check`）推断——**migration 尚未在真实库执行，实际名字以执行后 `\d+ behavior_events` 为准**；匹配时建议只依赖 `23514` + 列名，不要硬编码约束名。

| 拒绝原因 | 约束名 |
|---|---|
| `event_type` 不在八种枚举内 | `behavior_events_event_type_check` |
| `source` 不在四种内 | `behavior_events_source_check` |
| `planned_minutes < 0` | `behavior_events_planned_minutes_check` |
| `actual_minutes < 0` | `behavior_events_actual_minutes_check` |
| `reason` 超过 500 字符 | `behavior_events_reason_check` |
| `schema_version < 1` | `behavior_events_schema_version_check` |

八种 `event_type`：`plan_accepted` / `plan_rejected` / `plan_modified` / `task_started` / `task_completed` / `task_deferred` / `preference_confirmed` / `manual_note`。
四种 `source`：`app` / `workbuddy` / `import` / `test`。

**这两个错误面必须分开处理**：`22023` 说明调用方拼错了消息体；`23514` 说明值不合法但结构没错。适配层不要笼统写成「事件非法」。

**幂等不是错误码**：同一 `(user_id, event_id)` 重复提交，走 `on conflict do nothing`，返回 `{"event_id": …, "inserted": false, …}` 而不抛错。调用方按成功处理，不要换 ID 重试。

**查询函数 `list_behavior_events` 的两个非报错行为**：

- `p_task_id` 不校验归属；跨账号的 task 只返回空 `events`，**不抛** `TASK_NOT_OWNED`（因为 `where user_id = auth.uid()` 先把它滤掉了）。
- `p_limit` 被静默夹到 `1..2000`，越界不报错。

## 四、偏好存储（`preference_profiles`）

| code | 触发条件 | SQLSTATE |
|---|---|---|
| `INVALID_PROFILE` | 入参不是 JSON 对象 | `22023` |
| `CONFIRMATION_REQUIRED` | 写入未带 `confirm=true` | `22023` |
| `INVALID_PREFERRED_SLOTS` | `preferred_slots` 不是数组 | `22023` |
| `TOO_MANY_SLOTS` | 时段条数 > 32 | `22023` |
| `INVALID_SLOT` | 数组里某一条不是 JSON 对象 | `22023` |
| `INVALID_SLOT_RANGE` | `weekday` 不在 1–7、`start_minute` 不在 0–1439、`end_minute` 不在 1–1440、或 `end_minute <= start_minute`、或字段缺失 | `22023` |
| `INVALID_SOURCE` | `source` 不是 `explicit` / `inferred` | `22023` |

两处**不走自定义码**，如实标出，避免适配层以为全能按 code 分支：

| 情况 | 实际返回 |
|---|---|
| `focus_minutes` 不在 5–480、`break_minutes` 不在 0–120 | 表约束 `23514`（`preference_profiles_focus_minutes_check` / `_break_minutes_check`） |
| `focus_minutes` / `break_minutes` 传了非数字字符串 | PostgreSQL 原始 `22P02`（`invalid_text_representation`），未包自定义码 |

`CONFIRMATION_REQUIRED` 是**产品约束**而非技术校验：偏好只能由用户确认后写入，不能由模型推断直接落库。`inferred` 写入时 `confirmed_at` 恒为 `null`，消费方不得把未确认行当偏好用。

## 五、快照内部的缺失状态（不抛错）

这三种出现在返回 JSON 的 `blocking[]` 里，快照仍然返回，只是 `status` 降级。

| code | 含义 | 对下游的影响 | `status` |
|---|---|---|---|
| `SEMESTER_MISSING` | 没有 `semesters.is_current = true` 且未删除的学期 | 无法定位周次 ⇒ `fixed_events = []`，`free_slots` 退化成每天一整段日窗 `[day_start_minute, day_end_minute)`（默认 480–1380） | `blocked` |
| `TASK_OCCURRENCES_UNAVAILABLE` | `agent_task_occurrence_snapshots` 表不存在（M3 迁移未执行） | 长周期任务实例为空，`free_slots` **只扣课程不扣任务** | `partial` |
| `TASK_OCCURRENCES_MISSING` | 表存在但没有覆盖该窗口的行（客户端尚未发布） | 同上 | `partial` |

**给适配层的硬提醒**：`status = partial` 时 `free_slots` 不等于「这段时间真的全空」。它只保证「没有课」，不保证「没有任务」。缺失硬约束时不得对外宣称可执行。

## 六、字段级「缺失」的三种形态

| 形态 | 例子 | 消费方式 |
|---|---|---|
| `null` | 单次任务的 `estimated_minutes`（`one_time_reminders` 无该列，结构决定恒为 `null`） | 不计入 `workload.known_minutes`，计入 `unknown_estimate_count` |
| `unknown` | `estimated_status` | 需要时长的算法必须走「未知分支」，不能当 0 |
| `missing` | `semester.status`、`freshness.task_occurrences` | 触发对应 `blocking.code`，不得静默回退成空数据 |

三者不可互换：`0 分钟` 与 `未知` 是不同事实，`空列表` 与 `这张表不存在` 也是不同事实。
