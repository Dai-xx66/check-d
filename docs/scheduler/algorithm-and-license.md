# CheckD Agent 调度算法说明与许可证自查

> 负责人：同学 B（M2 智能调度）
> 日期：2026-10-29
> 对应交付：M2-1 `generateSchedule`、M2-2 `repairSchedule`

## 1. 结论先行

本模块采用**自有确定性规则算法**，未引入 Horolog 或任何第三方排程库。

理由：

1. Horolog 的许可证、版本可用性与部署义务尚未核实，引入后会在交付末期带来不可控风险。
2. 智能调度比赛场景看重「为什么这么排」的可解释性。自有规则可以逐条对应到场约束，外
   部求解器难以给出同样直白的解释。
3. 本场景规模很小（一天内十几条柔性任务），不需要重型求解器。

若后续确要引入第三方库，须先把源码版本、许可证全文、部署义务与基线对照结果补写进来，
并向队长提 Issue，不得直接在排程主链路上切换算法。

## 2. 模块边界

- 路径：`lib/features/agent_scheduler/domain/`
- 依赖：仅 Dart 核心库与同目录的 `schedule_contract.dart`
- **不访问**：Drift、Supabase、任何 repository、任何 Flutter  Widget
- **不调用**：`DateTime.now()`。时间基准全部来自 `ScheduleInput.now`，
  否则「相同输入相同输出」这条验收无法成立
- **不写入**：只返回 `ScheduleProposal`，落库完全由 M0 的 `apply_approved_changes` 负责

`test/agent_scheduler_test.dart` 中有一组「模块边界」用例，用源码文本断言上述红线，
任何人引入数据库依赖都会被测试拦下。

## 3. 算法规则

### 3.1 生成排程 `generateSchedule`

按顺序执行：

1. **硬约束重叠检测**：找出相互重叠的课程/会议。只记录说明，**绝不通过移动它们消解冲突**。
2. **可用窗口归一化**：把 `availability` 裁剪到 `[max(horizonStart, now), horizonEnd]`，
   再按本地自然日切分。切分之后每个窗口都属于同一天，
   于是「任务块不得跨日」这条边界在使用窗口时天然成立。
3. **扣减硬约束**：从可用窗口中减去所有课程/会议，得到真正的空闲片段。
4. **需求排序**：截止最紧的先排 → 优先级降序 → `taskId` 升序。
   第三级兜底是为了保证 `List.sort` 不稳定时结果依然确定。
5. **逐个放置**：最早可行优先（earliest-fit），不拆分任务。
   放置时同时满足：不早于 `now`、不早于 `earliestStartAt`、不晚于截止、
   不与已放置的块重叠。
6. **如实上报**：排不进去的任务进入 `unplannedTasks`，带机器可读的 `reason_code`
   与剩余分钟数。**绝不为了「排满」而压缩时长或违反截止。**

### 3.2 最小扰动重排 `repairSchedule`

输入是「新的硬约束」+「上一版提案」：

1. 上一版里**没有被新硬约束撞到**、仍在可用窗口内、且不违反截止的块，原样保留。
2. 只有真正冲突的柔性块进入待重排队列。
3. 上一版未排进去的任务和新加入的任务，都会被重新尝试一次。
4. 重排沿用与生成阶段相同的放置规则，保证行为一致。
5. 输出中 `moved_from_previous_plan` 标记哪些块被动过，供 A 渲染前后差异。

## 4. 与既有时间语义的对齐

模块自带 `ScheduleDeadline`，语义与 `lib/features/tasks/domain/task_models.dart`
中的 `TaskDeadline` / `TaskTimeSemantics` 保持一致：

| 形态 | 判定过期 | 排程含义 |
|---|---|---|
| `dateOnly`（只有日期） | 过了那一天才算逾期 | 当天结束前都算赶上，可排到当天最后一刻 |
| `exact`（带时刻） | 过点即逾期 | 必须在该时刻前结束 |

⚠️ **日期型截止绝不背伪造为一个 23:59 的时刻**。
`latestEndAt` 只是排程意义上的上界，不代表它的截止时刻被记录为 23:59。

## 5. 未排入原因码

| code | 含义 | 触发条件 |
|---|---|---|
| `WINDOW_INSUFFICIENT` | 空闲不足 | 找不到足够长的连续空闲片段 |
| `PAST_DEADLINE` | 已过期 | 截止时间已过 |
| `OVERLAPS_FIXED` | 被占满 | 开放时段被课程/会议完全占满 |
| `NO_AVAILABILITY` | 无窗口 | 输入没有给出任何可用时间窗口 |

## 6. 已知局限（答辩时如实说明，不夸大）

1. **不做拆分**：一条任务必须连续排完，不会自动切成两段。
2. **不做优先级抢占**：已有安排不会被优先级更高的后来者挤掉，
   只有硬约束冲突才会触发重排。
3. **不做个人效率建模**：当前不会根据用户历史计时数据折算预估时长，
   `requiredMinutes` 完全来自输入。
4. **同一时刻只考虑单人单线程**：不处理多件事项需并行的情况。
5. **不处理跨时区**：时区字段仅作标记，内部一律按 `DateTime` 瞬时值比较。
6. **不校验 31 天读取上限**：契约第 5.1 节要求超过 31 天一律拒绝，但具体限额
   须由服务端固定。纯调度函数目前接受任意排程区间，上限 enforcement 落在
   M0 的服务包装层。
7. **`changes` 目前只产出 `reschedule`**：契约 Open Question 5 仍在讨论
   `upsert_daily_override` 是否允许 `skip` / `retarget`。当前按最小权限只输出
   `reschedule`，符合契约第 5.7 节暂定条款。

## 6.1 纯调度函数在契约中的合法位置

契约第 6.3 节明确写到：

> M2 的进程内纯函数仍可直接接收 Task/Course/Event/Override DTO，以便确定性单元
> 测试；这是内部接口，不等于远程工具可以信任这些 DTO。

所以本模块接收内部 DTO 做单元测试是被契约允许的。
但 `snapshot_ref`、`base_version`、`input_digest` 必须由可信服务产生，
纯函数不得自行构造；当前实现将它们置空，提案状态恒为 `draft`。

## 7. 第三方依赖

无。本模块使用的全部为 Dart 语言自带能力。

Horolog 的取舍记录见上文第 1 节；截至本文档日期，未引入、未下载、未移植其任何源码。

## 8. 验证记录

### 2026-10-31 首次实跑：18/18 通过

环境：Windows 11，Flutter 3.47.9（Dart 3.13.7）， stable 通道。

**执行方式（必须如实说明）**：`test/agent_scheduler_test.dart` 的源码被复制到一个
不含任何插件的最小验证工程（仅依赖 `flutter_test` 等价 API），以纯 Dart VM 通道执行。
原因：宿主工程含 `window_manager` 等 Flutter 插件，`flutter test` 需要 Windows
**开发人员模式**（symlink 支持）才能组装插件 registrant，该开关未在本机开启。
两个源文件内容与主仓完全一致，仅 import 前缀不同。

### 2026-10-31 第二轮：22/22 通过（补齐冻结目标守卫）

同一环境。在上一轮基础上新增 4 个「冻结目标守卫」用例，全部通过：

1. 时长优先级：`targetDurationSeconds` 生效时长，`duration_source` 标 `task_target`。
   （此前该字段只影响标签、不参与排时长，属于已修的实现缺口。）
2. 周期任务同一 `(item_id, local_date)` 至多一条 `upsert_daily_override`，
   且 `change_id` 带日期后缀以区分不同天的同一任务。
3. `reason_code` 输出值封闭在 `UnplannedReason` 四个取值内。
4. `explanations` 每个元素恒为 `{task_id, text}` 两个键。

冻结目标清单见 `docs/scheduler/freeze-targets-m2.md`。

结果：**18 个用例全部通过**（含 5 组硬约束、3 组最小扰动重排、4 组契约对齐、1 组模块边界）。
**后续 22/22 详见第 8 节末尾。**

**本次实跑发现并修复的两个真实缺陷：**

1. **精确型截止的过期判定差一分钟**。`isPast` 原为 `now.isAfter(dueAt)`，
   导致 `now == dueAt` 时判为未过期；已改为到达即过期（`!now.isBefore(dueAt)`）。
   语义依据队长 `TaskTimeSemantics` 的「过点即逾期」。
2. **跨零点相邻窗口会被重新合并成跨日窗口**。`_freeWindows` 的碎片合并逻辑
   只判断首尾是否相邻，把「22:00–24:00」与「次日 00:00–02:00」接成一段，
   于是任务块得以跨自然日排布——这正是契约要禁止的形态。
   已改为**合并不跨自然日**：起始日不同则一律不合并。

另修正一处守卫自身的问题：模块边界用例原本扫描含注释的原文，会被本模块
「不调用 DateTime.now()」这行注释自己绊倒；现改为只扫描去掉行注释后的代码。

### 2026-10-31 第四轮：28/28 通过（C 的写入安全清单 → change 层守卫）

同一环境。总结 C 的「 Proposal/Approval 增量复审清单」新增 2 个 change 层守卫：

1. `schedule_one_time` 必须显式携带 `scheduled_at`，且它与 `planned_date` 同属一个本地日。
   契约第 5.7 节里「省略 `scheduled_at` 表示保留现值」一旦保留到旧值跨日，
   就会出现「写入成功但有效计划日期仍来自旧 `scheduled_at`」的假成功；
   M2 从不走这条分支，故以测试把它锁死。
2. `upsert_daily_override` 的七个回读字段齐全、`item_type` 只能是 `recurring`/`one_time`
   （不得借单日例外改课程）、`action` 恒 `reschedule`、`0 <= start < 1440 < end <= 1440`、
   同一 `(item_type, item_id, local_date)` 在提案内唯一，且 `existing_override_id` 恒为 null
   （模型不得猜测，只能由可信读取提供）。

结果：**28/28 通过**。宿主工程 `flutter test` 依旧没有复跑（同 §8 开头的原因），
本机证据只有隔离工程的 Dart VM 通道，不夸大为工程内已验证。

### 2026-10-31 第五轮：29/29 通过（DTO 键集合锁定）

同一环境。以 M0 Task 1 固定 SHA `2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6` 为唯一基准，
做「调度 DTO / 快照引用 / 时间语义 / Proposal 输出」四项定点核对时新增 1 个守卫：

1. 五个输出对象的 **JSON 键集合严格对齐契约**：`schedule_block` 九个键、
   `schedule_one_time` 五个键、`upsert_daily_override` 八个键、
   `unplanned_tasks` 四个键、`explanations ⊆ {code, message, related_task_ids}`。
   顶层字段只允许落在 §5.7 列表内。
   附带修正：`unplanned_tasks` 原来多输出一个契约外的 `title`，已移除
   （Dart 对象仍保留 `title` 供进程内展示，只是不进 JSON）。

结果：**29/29 通过**。宿主 `flutter test` 依旧未复跑（原因同 §8 开头），本机证据只有隔离工程
的 Dart VM 通道。历史数字 18/18、22/22、26/26、28/28 全部保留，不合并、不覆盖。

明确的局限（不假装支持）：M2 内部直接用 Dart `DateTime`、**不做时区转换**，
假设服务端传入的已是 Asia/Shanghai 本地时间；时区处理是上游 M0 的职责。

M1 的 26/26（Mock 用例数）与 M2 的 29/29（纯函数用例数）不是同一个东西，汇报时不合并。

条款级复审结论（不涉及本机执行）见 `docs/scheduler/reviews/incremental-review-m2-state-machine.md`，
本次四项定点核对的结论见 `docs/scheduler/reports/incremental-alignment-m2-2c48579.md`。

### 2026-10-31 第三轮：按 M0 正式决定做增量修订

队长转达 M0 的五项决定后执行（详单见
`docs/scheduler/reports/revision-2026-10-31-m0-decisions.md`）：

- **P1** 保留 `max(minimum_block_minutes, 30)` 兜底；`requiredMinutes` 明确只接受服务端可信
  快照估算、不接受 LLM 的伪可信估算；`remaining_minutes_today = 0` 仍为特殊情况、不进兜底。
- **P2** v1 公共 `explanations[].code` 枚举封闭为 7 个，写进代码
  （`kPublicExplanationCodes`）；`NO_VALID_DURATION` 整段删除；`DISPLACED_BY_FIXED` /
  `REPAIR_SUMMARY` 登记为 repair 专用（`kRepairOnlyExplanationCodes` + `isPublic` +
  `publicExplanations`）。按"不要只改一侧"的要求，同时补上了 M2 原先缺失的
  `PRESERVED_FIXED_EVENTS` 与 `ESTIMATED_DURATION` 产出。
- **P3** 两个服务端内部快照样例落成用例（`= 0` 不排且不进 unplanned、产出
  `ALREADY_DONE_TODAY`；`= 40` 时只排 40 分钟且标 `task_target`）。
- **P4** 选方案 A：**M2 停止自行派生 `proposal_id`**（原先由 baseVersion + 任务 ID 拼出，
  属"自行生成服务端字段"），已整段删除；`base_version` 仅原样带回；
  `snapshot_ref`/`input_digest`/`generated_at`/`expires_at` 一如既往不构造。
- **五·3** 补了可执行证据：只改 `horizonEnd` 输出就不同，故 `input_digest` 必须覆盖 horizon。

结果：**35/35 通过**（隔离工程 `dart test`）。
历史 18/18、22/22、26/26、28/28、29/29、30/30 全部保留。

**宿主工程 `flutter test` 本轮实测（与代码无关）**：卡在原生资产构建，
`sqlite3` 的 hook 要下载 `sqlite3.x64.windows.dll`，本机代理返回 502，
**一行测试都没执行**。此前记录的原因是"插件 symlink / 开发人员模式"，
本轮实测的失败点已变；两者都成立、都不归代码。尝试期间被自动改写的
`GeneratedPluginRegistrant.swift` 与 `windows/flutter/generated_*.{cc,h,cmake}` 已还原。

### 2026-10-31 第二轮：契约基准扩为两份文件后的增量核对（同一 SHA `2c48579`）

队长发布正式固定 SHA（与上轮推断一致），并把评审基准从一份扩成两份，新增
`docs/contracts/agent-api-v1.examples.json`（687 行 / 20 个示例）。这是真正的增量：
同一 commit 内 diff 为 0 行，靠 diff 助手查不出来。核对结论见
`docs/scheduler/reports/incremental-alignment-m2-2c48579-examples.md`。

**发现并修复一个我自己的实现缺陷（P1）**：契约 §5.6 的三级时长优先级里，第三级兜底是
`max(preferences.minimum_block_minutes, 30)` 分钟；而 `_durationOf` 的注释早就写着
「任务目标 > 快照估算 > 兜底」，代码却返回 **0**（等于静默丢弃该任务）——前几轮我自称
「时长优先级已对齐」时只冻结了前两级。**已补齐**并加守卫用例（偏好 15 → 兜底 30；
偏好 45 → 兜底 45；两者 `duration_source` 均为 `scheduler_estimate`）。

结果：**30/30 通过**（隔离工程 `dart test`）。宿主 `flutter test` 仍因缺 Windows
开发人员模式未复跑，不替它声称通过。历史 18/18、22/22、26/26、28/28、29/29 全部保留。

另三项属待决策而非缺陷，已写入报告：**P2** `explanations[].code` 出现三套零交集词汇
（md 无枚举 / 示例两个码在 md 里 0 次 / M2 八个码），在封闭枚举发布前不照抄示例；
**P3** `remaining_minutes_today` 与 `scheduling_weight` 在示例文件中 0 次，缺可演示用例；
**P4** 示例给出了含四个服务端字段的完整 Proposal 实例，把上轮「调度器输出过不了
Schema required」从推论升级为对照实证。

### 2026-10-31 第三轮：按 C 的 M3 增量审计修订（B18/R1/B19/G1/G2/input_digest/DTO/映射表）

- **代码未改实现**：B19/G1/G2 语义本就正确，本轮只**补测试与文档**；
  唯一实现侧动作是新增 3 条守卫用例（B19 三态、时区证据、内部 DTO 递归不含服务端字段）。
- **B18 / R1 举证 M2 无实现可改**（对两个源文件逐一检索 approval/token/idempotency 等 10 个关键字，
  命中全部为状态枚举符号名与注释），并给出供 M1/M0 直接落笔的判定顺序与规则。
- **input_digest**：给出两条可执行证据（horizon 改变输出 / 时区标签不改变输出），digest 由服务端算。
- 交付 `explanations-code-map.md`：9 个实际产出码 + 1 个已删除码 + 4 个 `reason_code`，
  全部标触发条件、是否对外、推荐公共 code。
- 隔离工程 `dart test` **38/38 通过**（35 + 3 新）。
- 宿主 `flutter test` 本轮**未执行**：加载即失败 `flutter_tester WebSocketException`，一行未跑；
  与上轮 sqlite3 原生资产 502 不是同一原因；生成文件已还原。两条通道分开报告。

### 2026-10-31 v1 CANDIDATE 对齐（`2c48579`）：纯文档，代码未动

队长下发「七工具进 CANDIDATE / TTL 固定 30 分钟不按当日截断 / `token_issued` /
`explanations` 对象数组 / `reason_code` 大写枚举 / 错误码优先级」对齐指令后：

- 逐条核对 @2c48579，**10 条里 M2 相关的 5、6 已在此前对齐并有测试，其余属 M0/M1 或纯措辞变更**；
- **撤回我自己先前提的旧建议**：`contract-review-m2.md` 里"TTL 取 30 分钟与当日 23:59 的较早者"
  已被 M0 否决（会让 TTL 随时钟漂移），已加作废注记；
- `PROPOSAL_NOT_APPROVABLE` 在契约里全文 0 次，按指令**只做增量判断、不写 Schema**，
  单独出 `reviews/proposal-not-approvable-incremental.md`；
- 本轮**没有新增功能、没有改动任何源码**，测试仍是 28/28（未新增用例），历史 18/18、22/22、26/26 原样保留。

**尚未验证的部分：** 未能在宿主工程内以 `flutter test` 原样重跑（受上述 symlink 限制）。
待本机开启开发人员模式后补跑，结果一致时可撤销本节的降级说明。
