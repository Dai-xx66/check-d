# ContextSnapshot 数据映射

每个快照字段的来源表与列、缺失时的返回值。M0 集成时对着这张表就能判断「这个字段为什么是空」。

约定：**空 ≠ 0，缺 = `unknown`/`null` + `status` 降级**，不用默认值冒充。

## 一、快照顶层

| 快照字段 | 来源 | 缺失时 |
|---|---|---|
| `as_of` | 服务端 `now()` | — |
| `timezone` | 入参 `p_timezone`（默认 Asia/Shanghai） | 仅回显，不参与日期运算 |
| `window.from/through` | 入参 | 跨度 > 31 天 → `RANGE_TOO_LARGE`；倒序 → `INVALID_RANGE` |
| `semester` | `semesters`（`is_current=true` 且 `deleted_at is null`，按 `updated_at desc` 取一条） | 无 → `{"status":"missing"}`，并阻断课程展开 |
| `status` | 派生 | `blocked`（无学期）/ `partial`（有 unknown 或 occurrence 缺失）/ `ok` |
| `blocking[]` | 派生 | 每条 `{code, message}`，机器可读 |

## 二、`fixed_events`（课程实例）

| 字段 | 来源 |
|---|---|
| `date` | 窗口内每一天（`generate_series`） |
| `ref_id` | `courses.id` |
| `title` | `courses.name` |
| `start_minute` / `end_minute` | `course_schedule_rules.starts_at_minute` / `ends_at_minute`（0–1440，本地分钟） |
| `week_no` | `(date - semesters.first_week_start_date) / 7 + 1`（整数除法） |
| `source` | 固定串 `courses+course_schedule_rules` |

筛选条件（全部满足才出现）：

1. `courses.user_id = auth.uid()`、`courses.deleted_at is null`、`courses.status = 'active'`
2. `course_schedule_rules.deleted_at is null`、`course_schedule_rules.weekday = isodow(date)`（1=周一…7=周日）
3. `1 <= week_no <= semesters.total_weeks`
4. `start_week`/`end_week` 若存在则需落在区间内
5. 周次规则：
   - `week_numbers` **非空** → 以清单为准（优先级最高）
   - 否则 `everyWeek` / `oddWeeks`(奇周) / `evenWeeks`(偶周) / `everyNWeeks`(与 `interval_weeks` 配合)
   - 都不匹配 → 不出现

> 为什么课程由 M1 展开而不是读 occurrence：`courses` + `rules` + `semesters` 三者已能唯一确定「某天几点有课」，
> 且这是 M1 模块 03 的职责范围；长周期**任务**的实例仍然只由客户端发布，两者不同类。

## 三、`free_slots`（可用时段）

算法：每天 `[day_start_minute, day_end_minute)` 按分钟打点，减去当天所有课程段，再合并连续分钟为区间，丢弃 `< 5` 分钟的碎片。

| 字段 | 含义 |
|---|---|
| `date` | 本地日期 |
| `start_minute` / `end_minute` | 相对当天 0 点的分钟数（左闭右开） |
| `minutes` | `end_minute - start_minute` |

默认日窗 `480`（08:00）– `1380`（23:00），可由入参调整；`day_end_minute > 1440` 或 `start >= end` → `INVALID_DAY_WINDOW`。

**它只扣课程，不扣任务。** 因为长周期任务实例需客户端发布，M1 不自己造；单次任务的时间占位也没有可靠字段。
`status=partial` 就是这个事实的标记，**不要把它读成「这段时间真的全空」**。

## 四、`tasks`

| 快照字段 | 来源 |
|---|---|
| `task_id` / `name` | `tasks.id` / `tasks.name` |
| `type` | `tasks.type`（`long_term` \| `one_time`） |
| `due_date` / `due_at` / `planned_date` / `available_from` | `one_time_reminders` 同名列（仅单次任务） |
| `completed` | 存在 `task_completions` 行：`task_id` 匹配、`user_id` 匹配、`deleted_at is null`、`is_success = true` |
| `estimated_minutes` | `long_term_tasks.target_duration_seconds / 60`（向上取整） |
| `estimated_status` | 有上面那列 → `known`；否则 `unknown` |

**已知缺口（不是 bug，是表结构决定）**：`one_time_reminders` 没有「预计时长」列，所以单次任务的 `estimated_minutes` 恒为 `null`。
要补这个字段属于数据层变更，需与 M2 对齐后另开迁移。

任务进入窗口的条件：

- `long_term`：全部纳入（长期任务一直在窗口内）
- `one_time`：`due_date` 或 `planned_date` 落在窗口内，或 `due_at` 落在窗口时段内，或提醒行缺失（保留可见，标 unknown）
- 一律排除：`tasks.deleted_at is not null`、`tasks.status <> 'active'`、`type` 不属于上述两种

## 五、`workload`

| 字段 | 来源 |
|---|---|
| `known_minutes` | 未完成任务中 `estimated_minutes` 非空者求和 |
| `unknown_estimate_count` | 未完成但无预计时长的任务数 |
| `open_task_count` | 未完成任务总数（含 unknown） |
| `status` | 无 unknown → `known`；有 → `partial` |

## 六、`freshness`

| 字段 | 取值 | 判定 |
|---|---|---|
| `semester` | `ok` / `missing` | 是否存在 `is_current` 学期 |
| `task_occurrences` | `published` / `missing` | `agent_task_occurrence_snapshots` 是否存在且 `from_date <= window.from` 且 `through_date >= window.through` |
| `completions` | `ok` | 完成记录直接来自表，无额外新鲜度概念 |
| `overall` | 同顶层 `status` | — |

`blocking.code` 现有三种：

- `SEMESTER_MISSING`：无当前学期，课程无法定位周次
- `TASK_OCCURRENCES_UNAVAILABLE`：`agent_task_occurrence_snapshots` 表**不存在**（迁移未执行）——防御分支
- `TASK_OCCURRENCES_MISSING`：表存在，但没有覆盖该窗口的发布记录（客户端尚未发布）

> **两种「没有实例」必须分开，不能都写成「表不存在」**（M3 11-26 提醒，成立）：
>
> | code | 缺的是什么 | 谁来解 |
> |---|---|---|
> | `TASK_OCCURRENCES_UNAVAILABLE` | schema 缺件：表根本不存在 | 执行 M3 的迁移 |
> | `TASK_OCCURRENCES_MISSING` | 数据未就绪：表在、该窗口无发布记录 | 客户端发布 occurrence 快照即可 |
>
> 按 M3 11-26 报告，该表在真实库**已建**（她已在其上完成发布与幂等回读），所以真实库走的是 `MISSING` 而不是 `UNAVAILABLE`。
> 本 PR 的 fixture 样例给的是 `UNAVAILABLE`，因为 fixture 只描述算法分支、不代表真实库状态。
> **执行 migration 后必须以真实库复验这两支的判定**，不能拿 fixture 的 code 当现网事实。

## 七、`BehaviorEvent` 映射

| 事件字段 | 目标列 | 约束 |
|---|---|---|
| `event_id` | `behavior_events.event_id` | 客户端生成 uuid；与 `user_id` 组成主键 |
| `task_id` | `task_id` | 可空；非空时必须属于当前账号，否则 `TASK_NOT_OWNED` |
| `plan_id` | `plan_id` | 可空文本，不透明引用 |
| `event_type` | `event_type` | 八种枚举之一，新增需改约束并通知消费者 |
| `occurred_at` | `occurred_at` | 带时区；存储照原样 |
| `planned_minutes` | `planned_minutes` | 可空，≥0 |
| `actual_minutes` | `actual_minutes` | 可空，≥0；**不得由计时器时长自动推导为「已完成」** |
| `source` | `source` | `app` / `workbuddy` / `import` / `test`；`test` 必须可区分 |
| `reason` | `reason` | 可空，≤500 字符 |
| — | `user_id` | **不接受入参**，一律 `auth.uid()` |

## 七之二、`PreferenceProfile` 映射

存储契约归 M1，画像语义归 M2。本节只写「载荷字段怎么落到列上」。

| 载荷字段 | 目标列 | 约束 |
|---|---|---|
| `preferred_slots` | `preferred_slots` (jsonb) | 数组，≤32 条；每条 `{weekday: 1-7 或 null, start_minute: 0-1439, end_minute: 1-1440}`，`end > start` |
| `preferred_slots[].weekday` | 同列 JSON 内 | **缺省或 `null` = 每日默认**；显式 weekday 覆盖每日默认，两者**不叠加**、**不归一化** |
| `focus_minutes` | `focus_minutes` | 5–480，可空 |
| `break_minutes` | `break_minutes` | 0–120，可空 |
| `source` | `source` | `explicit` / `inferred` |
| `confirm` | **不落库** | 仅写入校验；非严格 `true` → `CONFIRMATION_REQUIRED` |
| `expected_version` | **不落库** | 仅乐观锁比较；冲突 → `VERSION_CONFLICT`（`40001`） |
| — | `confirmed_at` | 仅 `explicit` 由服务端写 `now()`；`inferred` 恒 `null` |
| — | `schema_version` | 恒 `1`（结构版本），不随写入递增 |
| — | `data_version` | 服务端维护，每次成功 upsert +1，首次写入为 1，无行为 0 |
| — | `user_id` | **不接受入参**，一律 `auth.uid()` |

解析某天生效时段：`weekday == d` 的条目存在则只用它们，否则用 `weekday is null` 的条目；都没有 → 空列表（**不等于全天可用**）。分段可能重叠，算可用窗口前先合并。

## 八、与既有表的关系（不改动它们）
```
auth.users
  └─ profiles（时区、显示名）
  └─ semesters ──────────┐          提供 first_week_start_date / total_weeks
  └─ courses ────────────┤
        └─ course_schedule_rules ───┘  → fixed_events / free_slots
  └─ tasks
        ├─ long_term_tasks ───────────→ estimated_minutes（仅长期任务）
        ├─ one_time_reminders ────────→ due_date / due_at / planned_date
        ├─ task_completions ──────────→ completed
        └─ timer_sessions ────────────→ （不参与快照；只作 M2 行为统计原料）
  └─ behavior_events（本 PR 新增）───→ 事件查询
  └─ agent_task_occurrence_snapshots（M3，可能未建）→ freshness.task_occurrences
```

本 PR 对上述既有表**零结构改动**：只新增两张表与五个函数。

## 九、配套文档

- `ERROR_CODES.md`：`blocking.code`、函数抛出的自定义码、表约束拒绝（`23514`）三层的完整对照，含 SQLSTATE 与调用方处置。
- `G2_ACCEPTANCE.md`：G2 四要素结论、最低验收清单逐条状态、复现命令、降级交付声明。
- `samples/context_snapshot_sample.json`：除 `as_of` 外可与 CLI 输出逐字段比对的期望值。
