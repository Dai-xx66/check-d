# M2 explanations 内部代码映射表

> 日期：2026-10-31　负责人：B（M2）
> 契约基准：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`
> 代码基准：`schedule_engine.dart` / `schedule_contract.dart`（feat/m2-scheduler-basic）
> 用途：列出**代码里实际产出的每一个码**、触发条件、是否应该对外暴露、推荐公共 code。
> 本表与代码由守卫用例绑定（见 `冻结目标守卫 · explanations 码必须落在 v1 公共枚举内`），
> 任一侧出现枚举外的码，测试立刻红。

## 一、公共码（7 个，`kPublicExplanationCodes`，允许进入 v1 远程响应）

| 实际 code | 产出位置 | 触发条件 | 是否对外 | 推荐公共 code |
|---|---|---|---|---|
| `SCHEDULED` | generate | 每成功排出一个块，逐块产出（带 `related_task_ids`） | ✅ 对外 | `SCHEDULED`（即公共码本身） |
| `ESTIMATED_DURATION` | generate | 该块 `duration_source == scheduler_estimate`（第二级 `requiredMinutes` 估算或第三级兜底），逐块产出 | ✅ 对外 | `ESTIMATED_DURATION` |
| `ALREADY_DONE_TODAY` | generate | 周期任务 `remaining_minutes_today == 0`（当天已做完：不排、不计未安排） | ✅ 对外 | `ALREADY_DONE_TODAY` |
| `FIXED_BLOCKS_OVERLAP` | generate + repair | 输入里的固定课程/会议互相重叠；**只记录、绝不移动它们来消解** | ✅ 对外 | `FIXED_BLOCKS_OVERLAP` |
| `NO_AVAILABILITY_WINDOW` | generate | `_usableWindows` 为空：输入没有开放任何时间窗口 | ✅ 对外 | `NO_AVAILABILITY_WINDOW` |
| `AVAILABILITY_SATURATED` | generate | 可用窗口全部被硬约束占满（`_freeWindows` 为空） | ✅ 对外 | `AVAILABILITY_SATURATED` |
| `PRESERVED_FIXED_EVENTS` | generate | 输入存在固定课程/会议（`fixedBlocks` 非空）：机器可读地声明「它们被保留」 | ✅ 对外 | `PRESERVED_FIXED_EVENTS` |

## 二、repair 专用码（2 个，`kRepairOnlyExplanationCodes`，**禁止进入 v1 远程响应**）

> M0 2026-10-31 决定：这两个码暂留内部 repair 逻辑，未经批准不得进入 v1 远程响应。
> 服务端序列化 Proposal（方案 A）时应以 `ScheduleProposal.publicExplanations` 为准滤掉它们。

| 实际 code | 产出位置 | 触发条件 | 是否对外 | 推荐公共 code |
|---|---|---|---|---|
| `DISPLACED_BY_FIXED` | repair | 上一版块被新增固定课程/会议撞移，重新找位置 | ❌ 不对外（内部） | 若需对外，建议新增 `RESCHEDULED_BY_FIXED`；**待 M0 批准进公共枚举前不外泄** |
| `REPAIR_SUMMARY` | repair | repair 汇总行：「共移动 N 处」或「无冲突保持原样」 | ❌ 不对外（内部） | 建议不进公共枚举；若必须对外，建议 `REPAIR_APPLIED`（待 M0 决定） |

## 三、已删除的码

| code | 状态 | 说明 |
|---|---|---|
| `NO_VALID_DURATION` | **已整段删除** | M0 决定不进入公共枚举；且第三级兜底补齐后该分支本就不可达，保留会变成幽灵防御 |

## 四、unplanned_tasks 的 `reason_code`（**不属于 explanations**，单列）

契约 §5.7 规定 v1 原因枚举为 4 个，与 M2 实现**逐字一致**（已核对契约原文各出现 1 次）：

| reason_code | 触发条件 | 是否对外 | 对应公共枚举 |
|---|---|---|---|
| `WINDOW_INSUFFICIENT` | 找不到足够长的连续空闲窗口 | ✅ | `WINDOW_INSUFFICIENT`（契约枚举） |
| `PAST_DEADLINE` | 精确截止时间已过（到达即过期） | ✅ | `PAST_DEADLINE`（契约枚举） |
| `OVERLAPS_FIXED` | 可用区间被硬约束占满 | ✅ | `OVERLAPS_FIXED`（契约枚举） |
| `NO_AVAILABILITY` | 输入没有给出任何可用窗口 | ✅ | `NO_AVAILABILITY`（契约枚举） |

守卫用例：`冻结目标守卫 · reason_code 取值必须落在封闭枚举内`。

## 五、核对方法与防漂移

- **列举来源**：直接 `grep "code: '" schedule_engine.dart` 得到全部产出点（10 处，分属 9 个码；
  `FIXED_BLOCKS_OVERLAP` 在 generate 与 repair 各一处），不靠记忆。
- **守卫用例**：generate 的每条解释必须 `isPublic`；repair 只允许出现已登记的两个内部码；
  `publicExplanations` 里不得出现内部码。任一侧漂移立刻红。
- **对外暴露的判定口径**：公共码 = 进入 v1 远程响应；内部码 = 仅进程内 repair 结果，服务端序列化时过滤。
