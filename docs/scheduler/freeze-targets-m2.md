# M2 冻结目标清单（供 M0 落契约）

> 定位：**这是给队长的输入，不是已经冻结的东西。**
> 队长发出新的契约 commit 之后，我只做**一次增量复审**：
> 检查「M2 字段 / 硬约束 / Proposal 输出」这三项是否与本文一致，不重新通读全部文档。
>
> 对应指令：暂停扩大 M1 Mock 的调度功能，不依据未冻结字段改动公共 DTO。
> 本文因此**不修改任何公共 DTO**，只登记 M2 需要的精确语义。
>
> 日期：2026-10-31　负责人：B（M2）

## 一、总表

| # | 冻结目标 | M2 侧现状 | 是否已改 DTO | 需 M0 决定的点 |
|---|---|---|---|---|
| 1 | `remaining_minutes_today` | 未取用（`ScheduleTaskDemand` 内暂无此字段） | 否 | 字段归属与缺省语义 |
| 2 | `scheduling_weight` | 未取用（当前只用 `priority` 排序） | 否 | 取值区间与是否参与硬性排序 |
| 3 | 时长优先级 | **已实现并测试通过**，三级齐备 | 否（用现有 `targetDurationSeconds`） | 第三级兜底是否该由服务端快照负责，见下方 |
| 4 | 周期任务单日最多一个 block | **结构上已满足**（一条需求最多一个 block，不拆分） | 否 | 在哪一侧兜底去重 |
| 5 | block 不跨本地日 | **已实现并测试通过**（含 2026-10-31 修复） | 否 | 是否写进契约硬约束供 validate 静态检查 |
| 6 | `reason_code` 枚举 | **已在 M2 内冻结为 4 个值**（见下） | 否 | 取值文案是否与 C 的验收表一致 |
| 7 | `explanations` 统一结构 | M2 用**对象数组** `{task_id, text}`（M1 mock 是字符串数组） | 否 | 二者必须选一个 |

### 状态更新（2026-10-31，对照契约 @2c48579 复审后）

复审过程见 `docs/scheduler/incremental-review-m2.md`，本文正文保留了复审**之前**的措辞以便追溯。

| # | 复审后状态 |
|---|---|
| 1 | **已实现**：`ScheduleTaskDemand.remainingMinutesToday`，三态（0 / 非 0 / null）均有测试 |
| 2 | **保持不接入**：契约自标 `scheduling_weight` 算法 BLOCKED，建议由服务端折算成 `priority` 或 demand 顺序 |
| 7 | **枚举已封闭（M0 2026-10-31 决定）**：`PRESERVED_FIXED_EVENTS` `ESTIMATED_DURATION` `FIXED_BLOCKS_OVERLAP` `NO_AVAILABILITY_WINDOW` `AVAILABILITY_SATURATED` `ALREADY_DONE_TODAY` `SCHEDULED` 七个公共码写进 `kPublicExplanationCodes`；`NO_VALID_DURATION` 已删除；`DISPLACED_BY_FIXED`/`REPAIR_SUMMARY` 登记为 repair 专用，不得进 v1 远程响应 |

> 第 7 条正文里的 `{task_id, text}` 是当时的候选方案，已废弃；实际输出以
> `schedule_contract.dart` 的 `ScheduleNote.toJson()` 与契约 §5.7 为准。

## 二、逐条说明

### 1. `remaining_minutes_today`（recurring，可空）

- **要解决的问题**：知道任务当天目标总量，但不知道还剩多少没做时，
  上午已经背完的单词下午会被再排一次。
- **M2 侧语义**：该值为非空整数时，**它就是本次要排的量**，优先于任务的默认时长；
  为空时按第 3 条逐级回落。
- **不接受的形态**：布尔值、字符串枚举、需要 M2 反查其它工具才能得到的值。
- **缺失后果**：等价劣化为「重复排已完成任务」，是 C 的验收表可直接扣分的行为。

### 2. `scheduling_weight`（recurring，可空）

- **要解决的问题**：目前只有截止时间参与硬性排序，`priority` 只在同截止时兜底，
  于是「连续 5 天没做完所以今天优先」这类解释没有数据支撑。
- **M2 侧语义**：`0.0–1.0` 的数值，仅在两者都不带截止时间、或截止时间相同时参与排序。
  **不得**推翻截止时间优先这一硬规则。
- **缺失后果**：排出来的顺序无法解释，A 的差异文案失去事实依据。

### 3. 时长优先级

已在 `schedule_engine.dart` 落地（函数 `_durationOf`）：

```
周期任务 remaining_minutes_today 非空 → 它就是本次要排的量（标 task_target）
  其中 = 0 表示当天已做完 → 不排程，也不计入 unplanned_tasks
非空且 > 0 的 targetDurationSeconds  → 向上取整到分钟（标 task_target）
否则 requiredMinutes > 0            → 服务端快照估算（标 scheduler_estimate）
兜底                                → max(minimum_block_minutes, 30)（标 scheduler_estimate）
```

- **绝不压缩**：放不下就进 `unplanned_tasks`，不为排满而缩短时长。
- **不写回**：估算值不落任何 Task 持久化字段。
- **测试**：`冻结目标守卫 · 时长优先级`（目标 1800 秒 vs 入参 60 分钟 → 排 30 分钟且标
  `task_target`）；`冻结目标守卫 · 时长兜底为 max(minimum_block_minutes, 30)，且一律算估算`
  （偏好 15 → 兜底 30；偏好 45 → 兜底 45，两者都标 `scheduler_estimate`）。

> **2026-10-31 更正**：最后一行「兜底」此前**只写在文档里，`_durationOf` 实际返回 0**
> （等于静默丢弃该任务）。本轮核 `agent-api-v1.examples.json` 时发现这个落差并补齐。
> 副作用：`NO_VALID_DURATION`（时长非正即跳过）现已成为不可达的防御分支，代码里已注明。

### 4. 周期任务单日最多一个 block

- **当前保证**：一条需求最多产出**一个** `ProposedBlock`，不拆分、不复制；
  同一 `(task_id, 本地日)` 至多一条 `upsert_daily_override`。
- **测试**：`冻结目标守卫 · 周期任务同一本地日最多一个 block`。
- **建议的兜底位置**：由 M0 快照侧保证同一周期任务每天只生成一条需求；
  `validate` 侧静态检查同一 `(item_id, local_date)` 变更数 ≤ 1。
  M2 不自行丢弃重复需求——丢弃会让用户以为任务被排了。

### 5. block 不跨本地日

- **当前保证**：可用窗口先按本地日切分，碎片合并**不跨自然日**，
  因此不可能排出跨零点的时间块。
- **测试**：`确定性与边界 · 排出来的块不跨自然日`，修复记录见算法文档第 8 节。
- **建议写入契约**，这样 `validate` 可以静态检查而不必信任调用方。

### 6. `reason_code` 枚举

M2 已按封闭枚举实现（`UnplannedReason`），取值只有四个：

| code | 含义 |
|---|---|
| `WINDOW_INSUFFICIENT` | 找不到足够长的连续空闲窗口 |
| `PAST_DEADLINE` | 截止已过（精确型过点即算，日期型过天即算） |
| `OVERLAPS_FIXED` | 可用区间被硬约束占满 |
| `NO_AVAILABILITY` | 输入没有给出任何可用窗口 |

- **测试**：`冻结目标守卫 · reason_code 取值必须落在封闭枚举内`，
  断言所有输出值都属于该集合，新增原因必须同步更新枚举。
- **注意**：C 的验收表按此码判定，因此它是**契约级取值**，不是 M2 内部实现细节。

### 7. `explanations` 统一结构

两模块当前不一致，必须二选一：

| 方案 | 结构 | 利 | 弊 |
|---|---|---|---|
| **A（M2 建议）** | 对象数组 `{task_id, text}`，`task_id` 可空 | 能把解释挂到具体任务/固定块上，A 可做行内提示 | 比纯字符串长一点 |
| B（M1 mock 现况） | 字符串数组 | 简单 | 无法定位是哪一条，也无法排序去重 |

- M2 的 `toJson()` 输出里 `explanations` **每个元素只有 `task_id` 与 `text` 两个键**，
  已由测试锁定（`冻结目标守卫 · explanations 元素结构统一`）。
- 契约必须明确元素形状与「是否允许额外字段」；否则 A 的 mock 与我方
  合并时必有一方被 `additionalProperties:false` 拒掉。

## 三、M0 发布新契约后的增量复审清单（只看这五项）

1. 快照 DTO 是否出现第 1、2 项字段；字段名与本文一致则 M2 直接可用，无需改代码结构。
2. 时长优先级是否与第 3 条同序；若契约给出不同的回落顺序，M2 按其调整 `_demandMinutes`。
3. 第 4、5 条是否升格为契约硬约束（M2 侧已是事实约束，升级只需补引用）。
4. 第 6 条的四个取值是否被逐字收录。
5. 第 7 条最终定为方案 A 还是 B：若定为 B，M2 只需在 `toJson()` 处降级，
   **不影响算法**——这是把结构冲突隔离在外层的原因。

除上述五项之外的内容不再重新审阅。
