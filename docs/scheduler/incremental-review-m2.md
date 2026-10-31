# B（M2）增量复审：v1 CANDIDATE @2c48579

> 复审对象：`docs/contracts/agent-api-v1tration` @ `2c48579`（PR #4）
> 范围：**只看队长给的 7 项**，不重新通读全文。
> 日期：2026-10-31　复审人：B（M2）
>
> 结论先行：**7 项里 6 项无阻塞性偏差，1 项需 M0 补一个枚举**（explanations 的 `code`）。
> 为对齐本次契约，M2 侧改了 5 处输出/类型，**全部有测试覆盖，26/26 通过**。

## 逐项结论

### 1. `remaining_minutes_today` 与 `scheduling_weight` 是否足够映射 M2 DTO

契约 §5.2 已定义：`remaining_minutes_today` 可空非负整数，服务端事实折算，
`0` 时不排、null 时用完整目标；模型不得自行计算或覆盖。

**M2 侧已对齐**（新增内部字段 `ScheduleTaskDemand.remainingMinutesToday`，
属于契约 §6.3 允许的进程内 DTO，不是公共 DTO）：

| 快照值 | M2 行为 | 测试 |
|---|---|---|
| `0` | 不生成 block，**也不进 `unplanned_tasks`**（那不是"排不下"，是"已完成"），另出一条 `ALREADY_DONE_TODAY` 解释 | `remaining_minutes_today 为 0 时不再排程，且不算未安排` ✅ |
| 非 0 | 当日剩余即本次排程量，优先于完整目标，`duration_source=task_target` | `remaining_minutes_today 非空时优先于完整目标` ✅ |
| null | 用完整 `duration_target_seconds` | 同上，`时长优先级` 用例也覆盖 ✅ |

**`scheduling_weight` 我故意没有接入。** 契约自己写明"计算算法尚未实现，保持 BLOCKED"——
取用一个 BLOCKED 的值参与排序，只会让输出不可复现。
建议：由服务端在产出快照时把权重折算成 demand 顺序或 `priority`（M2 已用于同截止兜底），
**M2 不必知道权重本体**。

> **待 M0 确认（小）**：契约希望 M2 直接用 `scheduling_weight`，还是由服务端折算成 priority？
> 我倾向后者——把"BLOCKED 的算法"关在服务端门外。

### 2. 时长优先级及 `duration_source` 是否无歧义

契约 §5.6 的三级顺序、两个标签、以及"估算不得写回"都已写清，**与 M2 完全一致**，无歧义。

唯一需要一句话澄清的：第三级兜底 `max(minimum_block_minutes, 30)`
只在"服务端快照也没给估算"时才触发。M2 目前把调用方传入的 `requiredMinutes`
**定义为服务端快照估算**，因此标 `scheduler_estimate`。
若 M0 认为"估算必须由服务端显式标注"，则需要在输入侧增加一个来源标记；
否则维持现状（把输入的时长视作快照估算），这是最简单且无歧义的解释。

### 3. 单日单 block、不得跨日、固定块重叠规则

契约 §5.6 三条规则与 M2 现状逐条一致：

| 契约 | M2 | 状态 |
|---|---|---|
| 同一单次事项一个提案最多一个可持久化 block | 一条 demand 最多一个 block，不拆分不复制 | ✅ |
| 同一周期任务同一上海本地日最多一个 block | 已由守卫用例锁定 | ✅ |
| block 的 start/end 必须同属一个本地日，不能跨午夜 | 10-31 修复后已保证，窗口按本地日切分且不跨日合并 | ✅ |
| 固定块彼此重叠是合法输入，调度器只绕开不判违规 | `_overlappingFixedBlocks` 只产生解释，从不当作提案违规 | ✅ |
| 大任务由上游先拆成多个独立 Task，v1 不假装支持拆分 | M2 明确不支持拆分（见算法文档第 6 节） | ✅ |

### 4. `unplanned_tasks.reason_code` 与 `explanations` 对象结构

契约已逐字收录四个原因码，与 M2 的 `UnplannedReason` 完全一致 ✅。
本轮发现两处**形状偏差，已改**：

| 契约要求 | M2 改前 | M2 改后 |
|---|---|---|
| `unplanned_tasks[]` 含 `message` | 输出键是 `reason` | 已改 `message`，并保留 `remaining_minutes` ✅ |
| `explanations[]` 为对象数组，每项 `code` + `message` + 可选 `related_task_ids`，不许字符串混用 | 输出 `{task_id, text}` | 已改 `{code, message, related_task_ids?}`，`task_id` 不再直接出现在 JSON 里 ✅ |

配套改动：`ProposedBlock` 的 JSON 去掉了契约 §5.6 之外的 `minutes`、
`moved_from_previous_plan` 两个键（`additionalProperties:false` 时会被拒）；
`ScheduleProposalStatus` 补齐契约的 8 态（原多一个 `validated`、缺 `applying`/`readback_pending`）。

> **需要 M0 补的一个枚举（本轮唯一阻塞项）**：
> M2 目前产出的 `explanations[].code` 取值为
> `FIXED_BLOCKS_OVERLAP`、`NO_AVAILABILITY_WINDOW`、`AVAILABILITY_SATURATED`、
> `NO_VALID_DURATION`、`ALREADY_DONE_TODAY`、`SCHEDULED`、`DISPLACED_BY_FIXED`、
> `REPAIR_SUMMARY`。契约只写了"机器可读 `code`"，**没有给枚举**。
> 这和当初 `reason_code` 的情形一模一样——不登记，C 就没法穷举验收、也没法判定非法值。
> 建议要么把这 8 个写进契约，要么明示"M2 侧的 code 视为开放词汇"。

### 5. 规范化 JSON + SHA-256 的 `input_digest` 输入范围

契约已按我方意见冻结为"一次服务端一致性快照 → 规范化 JSON → SHA-256 小写十六进制"，
并明确禁止用两次普通读取拼接计算 ✅。M2 不构造 digest（输出为 null，不伪造）✅。

> **待 M0 确认（中）**：§5.7 列出的覆盖范围含 Task、有效日历事件、单日例外、偏好、
> 外部固定事件，**但没有排程区间（horizon）与时区**。
> 同一快照下改用不同 horizon 生成的提案，会拿到相同的 digest 却产出不同结果，
> validate 无法察觉。建议把 horizon/timezone 一并纳入摘要范围，
> 或至少规定"digest 相同而 horizon 不同"一律视为冲突重算。

### 6. 七工具 Proposal 状态是否兼容 M2 输出

| 项 | 结论 |
|---|---|
| `blocks` / `changes` 分离 | ✅ 与 M2 一致（`changes` 由 blocks 派生，只出白名单两种） |
| change 白名单两种 type | ✅ 守卫用例已验证，`action` 在 OQ5 定案前恒为 `reschedule` |
| 8 态状态机（含 applying / readback_pending） | ✅ M2 枚举已对齐；纯函数恒出 `draft`，从不伪造终态 |
| `snapshot_ref` / `base_version` / `input_digest` 由服务端产生 | ✅ M2 一律留空 |
| 30 分钟 TTL | ✅ 由服务端控制，M2 不产出 `generated_at`/`expires_at` |

七工具因此对 M2 无额外约束，兼容。

### 7. 不持久化 `skip` 是否符合实现边界

符合 ✅。契约明确 `skip` 不属于 v1 change 白名单，排不下的任务只能留在
`unplanned_tasks`，且"未安排不等于完成或跳过"。M2 现状：

- `changes` 只有 `schedule_one_time` / `upsert_daily_override` 两种 type，
  `action` 恒为 `reschedule`（测试已断言，新增任何 action 会红）；
- **没有任何"跳过"被写进持久化通道**，也不需要为此新增字段。

> **待 M0 确认（小）**：`remaining_minutes_today = 0` 时我不写 unplanned、只出一条
> `ALREADY_DONE_TODAY` 解释。契约说"未安排不等于完成"，而这里**恰恰是完成**，
> 所以我判断它不该出现在 `unplanned_tasks`。若 M0 希望这种情况连解释都不出，改一行即可。

## 本次为对齐而做的 M2 侧改动（全部有测试）

| 改动 | 类型 |
|---|---|
| `explanations` 改为 `{code, message, related_task_ids?}` | 输出形状 |
| `unplanned_tasks.reason` → `message` | 输出形状 |
| `ProposedBlock` 去掉契约外多余键 | 输出形状 |
| 状态枚举对齐 8 态 | 类型对齐 |
| 新增 `remainingMinutesToday` 与 `_durationOf` 三级语义 | 内部实现 |

**测试：26/26 通过**（隔离验证工程，Dart VM 通道；含 8 个冻结目标守卫用例）。

## 复审之外不再重复的工作

按队长要求，除上述 7 项外不再重新审阅契约其它章节，也不重跑 M1 mock。
