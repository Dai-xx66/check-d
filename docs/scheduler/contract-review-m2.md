# M2 对 agent-api-v1 契约的评审意见

评审人：B（M2 调度器负责人）  
评审对象：`docs/contracts/agent-api-v1.md`（v1 CANDIDATE，feat/m0-api-contract 分支）  
评审日期：2026-10-29  
对照实现：`lib/features/agent_scheduler/domain/`（Check-D-M2 分支）

总评：契约的 blocks/changes 分离、截止联合类型、白名单变更和  
`snapshot_ref/base_version/input_digest` 由服务端产生的规定，与 M2 纯函数  
边界完全兼容，M2 已按此实现。以下按队长提出的四个问题逐条给出结论。

## 1. 快照 DTO 是否够用

结论：**基本够用，有 2 个缺口需要冻结前确认。**

够用部分：Task（kind/recurrence/deadline 联合类型/duration_target_seconds）、  
Course 规则、calendar_event（含 applied_override_id 和 fixed 标记）、  
daily_override 都能无损映射为 M2 的 `ScheduleTaskDemand` / `ScheduleFixedBlock` /  
`ScheduleDeadline`。

缺口 1 —— **周期任务「当日剩余量」无来源。** M2 排程需要知道一个周期任务  
今天还需排多少分钟（`requiredMinutes`）。契约的 Task DTO 只有  
`duration_target_seconds`（目标总量），没有「当日已完成计时/完成状态」字段。  
快照若不含该量，服务端包装层无法折算剩余需求，M2 只能按全额目标排，会把  
上午已做过的任务下午再排一遍。**建议：快照 DTO 为 recurring 增加  
`remaining_minutes_today`（服务端由计时/完成事实折算，可空；空表示按全额）。**  
这也符合数据最小化——只给一个折算数，不给计时流水。

缺口 2 —— **周期任务排序权重无来源。** M2 的排序键是（截止时间、priority、  
task_id）。契约 Task DTO 没有 priority 类字段，快照里也没有可用的业务排序依据  
（如连续未完成天数）。没有它 M2 只能退化为纯 EDF（按截止排），演示时  
「英语精读已连续 5 天未完成所以排前面」这类解释无数据支撑。**建议：快照为  
recurring 增加 `scheduling_weight`（服务端计算，可空）。**

## 2. 时长估算规则

契约 5.6 允许 `duration_source=scheduler_estimate`，但没冻结估算算法。  
M2 建议 v1 冻结如下最小规则（已在引擎中按此实现）：

1. 优先级：`duration_target_seconds` > `scheduling_estimate`（若快照提供）>  
   兜底常量。
2. 兜底常量取 `max(preferences.minimum_block_minutes, 30)` 分钟；无 preferences  
   时取 30 分钟。
3. 凡非 `task_target` 来源，`duration_source` 必须标 `scheduler_estimate`，  
   且**任何估算值不得写回 Task 持久化字段**（契约已有此禁则，M2 遵守）。
4. **单日单块**：一个周期任务在同一天最多产出一个 block，一个单次事项全  
   提案最多一个 persistable block（契约 5.6 已规定后者，建议把前者也写明，  
   因为 upsert_daily_override 每天只能承载一个分钟区间，物理上也排不下第二个）。
5. **不拆分、不截断**：可用窗口放不下 `requiredMinutes` 时整块进  
   `unplanned_tasks`（WINDOW_INSUFFICIENT），绝不压缩时长凑数。

另请确认：`scheduler_estimate` 的估算输入（历史计时均值等）是否进快照？  
若进，需要哪个字段名；若不进，v1 估算只能走兜底常量，这点要写进文档，  
避免评审以为我们有数据而实际没有。

## 3. 固定事件与单日例外的约束

- `fixed=true`（课程、external_fixed_event）不可移动 ✅，M2 只避让、永不修改。
- **固定-固定重叠**：契约未规定。M2 行为是「不解决、只绕开」——两个固定块  
  本身重叠时照常保留，柔性任务绕开两者的并集。建议在契约写明这是合法输入，  
  防止 validate 把「快照本身有重叠」误判为提案违规。
- **block 不得跨本地日**：`planned_end_minute` 上限 1440 意味着单日例外无法  
  表达跨午夜块。M2 已在引擎内把可用窗口按本地日切分，保证不产生跨天块。  
  建议契约 5.6 加一句「block 的 start_at/end_at 必须落在同一本地日历日」，  
  让 validate 能静态检查。
- `upsert_daily_override` 的 action：**M2 投票支持在 v1 就放开 `skip`**  
  （Open Question 5）。理由：重排场景下「今天确实塞不下」是高频结果，没有  
  skip 就只能留在 unplanned_tasks 里等明天再撞一次；有了 skip，proposal 可以  
  明确表达「今日豁免」，explainability 更好讲。`retarget`（改时长目标）可用  
  scheduler_estimate 在展示层表达，不必进 v1 白名单。
- overrides 对 course 只读不写 ✅，external_fixed_events 只参与本次、不落库 ✅。
- `existing_override_id` 只能来自可信读取 ✅，M2 纯函数不构造该字段，  
  由服务端包装层在快照→DTO 映射时注入。

## 4. `base_version` 和 `input_digest` 需要覆盖哪些数据

M2 的意见（供 M0 设计快照/版本服务参考）：

**`base_version`（可信版本标识）必须覆盖：**

- 范围内全部 Task 的持久化状态（recurrence、deadline、duration_target_seconds、  
  status、planned_date/scheduled_at、available_from）；
- 全部 Course 及其 rules；
- 范围内全部 daily_overrides；
- 上述行的服务端可验证版本凭据（updated_at 或行版本），且必须在**写入事务内**  
  重新比较——仅在读取时比较不够，中间窗口仍可被并发修改击穿。

**`input_digest`（输入摘要）必须覆盖：**

- 规范化后的 Task DTO（M2 实际消费的那一份，不是原始行）；
- 有效 calendar events 的**最终结果**（即 applied override 之后的逐日 occurrence）；
- external_fixed_events 全量；
- preferences 全量；
- date_range 与 timezone（防止同一快照数据在不同范围/时区被误用）。

**关键风险**：`list_tasks` 与 `get_calendar_events` 是两次独立普通读取  
（契约 6.2 已承认不组成一致快照）。因此 digest 绝不能用这两个响应在客户端  
拼接计算，必须基于服务端一次一致性快照读取。否则 validate 重算 digest 时  
两次读取之间任何一次写入都会造成假冲突（SNAPSHOT_CONFLICT 风暴），或者更糟，  
漏掉真实冲突。

**建议算法**：规范化 JSON（键排序、字段顺序固定、时间统一 RFC3339+08:00、  
去除展示性字段如 title/name 的空白差异）后取 SHA-256，十六进制小写。

**有效期建议**：`expires_at` 不宜长。日程快照半衰期很短（用户随时在 App 里  
打卡），建议 30 分钟固定有效、过期走状态机 `expired`，  
重新生成而非续期。

> ⚠️ **2026-10-31 更正（撤回本段的截断建议）**：本段原写「30 分钟或到当日 23:59 取较早者」，
> 该截断建议**已被 M0 否决并撤回**。v1 CANDIDATE 收口后 Proposal TTL 固定为
> `generated_at + 30 分钟`，**不按当日 23:59 截断**。理由：一旦按当日截断，TTL 就成了
> 随当前时刻漂移的变量（23:00 生成只剩 59 分钟，早上生成则远超 30 分钟），
> 「30 分钟」这条冻结规则形同虚设，C 的四项判定也写不出确定的期望值。
> 以契约 §5.7「自 `generated_at` 起固定有效 30 分钟，服务端不得接受客户端指定或延长」为准。
> M2 侧不产出 `generated_at` / `expires_at`，本条对 M2 无实现影响。

## 5. M2 实现侧已遵守的契约条款（备查）

- 纯函数：不读库、不调网、不取系统时钟，时间基准全部来自输入。
- `snapshot_ref/base_version/input_digest` 一律置空，由服务端填，不伪造。
- proposal 恒出 `status=draft`；硬约束失败留在 draft 重新生成，不伪造 validated。
- changes 只产 `schedule_one_time` / `upsert_daily_override` 两种白名单类型。
- 日期型截止整天宽限，不伪造 23:59；精确截止到点即逾期。
- 排不下进 unplanned_tasks 并附机器可读 reason_code，不硬塞。
