# B（M2）第二轮增量审查：契约基准补齐为「两份文件」后的核对

> 日期：2026-10-31　审查人：B（M2）
> 触发：队长 @所有人 发布**正式固定 SHA**，并把评审基准从一份文件扩成两份：
>
> - `docs/contracts/agent-api-v1.md`
> - `docs/contracts/agent-api-v1.examples.json` ← **本轮真正的增量**
>
> 固定 SHA：**`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`**
>
> **纪律：不修改 M0 契约本体，不重新进行完整审计，不扩大功能范围。**
> WorkBuddy 真实认证、可信审批、原子写入、生产回读继续 BLOCKED。

## 零、SHA 核对结果：与上一轮一致，上一轮报告继续有效

```
upstream/feat/m0-api-contract HEAD         = 2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6
merge-base --is-ancestor 2c48579... HEAD   = 是（它就是分支 HEAD）
commit 日期                                 = 2026-10-31 04:14:13 +0800
```

队长这次把占位符换成实的了，**与我在上一轮报告里按分支 HEAD 推断出的 SHA 完全一致**。

因此上一份 `incremental-alignment-m2-2c48579.md` 不需要作废，它的四项结论继续有效。
本轮的范围只有一件事：**新增的第二份契约文件 `agent-api-v1.examples.json`（687 行、20 个示例）**，
这是我此前从未核过的对象。同一个 commit 内看不出 diff，所以必须用其它方式发现偏差。

> 顺带修正一处我自己的流程缺陷：上一轮我用 diff 得到「0 行变更」就判定只需定点核对，
> 这在**同一 commit 内**是对的，但会漏掉「评审基准多了一份文件」这类变更。
> 已把 diff 助手扩展为同时覆盖两份文件（见第五节），下一轮不会重犯。

## 一、逐条核对：示例文件里与 M2 相关的部分

示例文件共 20 个示例，其中 5 个落在我的职责边界内（其余属 A/C，我不碰）。

| # | 示例 | 核对内容 | 判定 |
|---|---|---|---|
| 1 | `EX0 list_tasks` 响应 | Task DTO 形状 | ✅ 一致（见下第 2 条） |
| 2 | `EX1 get_calendar_events` 响应 | 日历事件 / courses / daily_overrides | ✅ 一致，且印证固定块必须保留 |
| 3 | `EX5 generate_schedule_proposal` | **Proposal 完整输出形状** | ⚠️ 形状一致，但暴露两个问题（P2、P4） |
| 4 | `EX6 validate_schedule` | violations / validation_status | ✅ 与我职责边界正交，但 `violations: []` 说明「校验失败」的形状仍无示例 |
| 5 | `EX12 apply_approved_changes_success` | `applied_changes` 形状 | ✅ **逐字段与我的 `changes` 一致**（重要，见第 3 条） |

### 1. Task DTO —— 一致，且证实了一处我不该有的假设

示例的 Task 用 **`name`** 而不是 `title`，

```json
{ "task_id": "...", "kind": "one_time", "name": "完成课程报告初稿",
  "execution_mode": "untimed", "duration_target_seconds": null, ... }
```

我上一轮刚从 `unplanned_tasks` 里删掉了契约外的 `title`（当时是照字段名相似推断的），
**示例文件证实了那个推断是对的**——Task 对象确实没有 `title`，只有 `name`。这条不用再纠结。

同时注意 `duration_target_seconds: null`：`untimed` 任务明确可以没有目标时长，
这正是第二级、第三级时长存在的原因（见 P1）。

### 2. `blocks` / `changes` / `unplanned_tasks` / `explanations` —— 形状逐字一致

`EX5` 给出的 Proposal 里，四类嵌套对象的键集合与我的输出**完全相等**：

- `blocks`：`block_id / task_id / task_kind / start_at / end_at / source / persistable_as / duration_source / duration_seconds` → 与我的一致（`has_duration_target` 只是进程内派生用，**从不进 JSON**，已确认）
- `changes`（`schedule_one_time`）：`change_id / type / task_id / planned_date / scheduled_at` → 与我的一致
- `unplanned_tasks`：`task_id / reason_code / remaining_minutes / message` + `reason_code: "WINDOW_INSUFFICIENT"` → 与我的一致，且该码在 §5.7 的封闭枚举内 ✅
- `explanations`：`{code, message, related_task_ids}` 对象数组 → 形状一致 ✅，**但 `code` 的取值不一致（见 P2）**

### 3. 意外收获：`EX12` 给我的一条主张补上了契约侧证据

我此前主张「写入次数 = `changes.length`」只是静态推算。示例里 `apply_approved_changes` 成功响应：

```json
"applied_changes": [ { "change_id": "change_mock_report", "type": "schedule_one_time",
                       "task_id": "...", "planned_date": "2026-11-01", "scheduled_at": "..." } ],
"readback_verified": true
```

`applied_changes` **逐字段复用 proposal 的 change 形状**，且这里是唯一的写入汇总位置。
→ 「写入次数可由 `changes` 条数推算」这条**现在有契约示例佐证，不再只是我的推算**。
（真正的运行时验证仍属服务端职责，M2 不假装做过。）

### 4. `EX5` 的请求侧再次确认我的函数边界是对的

```json
"input": { "date_range": {...}, "external_fixed_events": [...], "preferences": {...} }
```

**没有 `tasks`、没有 `courses`、没有 `base_version`**。这与 §6.3「远程工具请求不接受 LLM 提交的
tasks/courses/calendar_events/daily_overrides/base_version/snapshot_ref」完全吻合，
也印证了我的纯函数只接收已规范化 DTO 的边界是对的。

### 5. `EX19` 再次说明 X1 那条缺口很要紧

```json
{ "code": "READBACK_PENDING", "retryable": true,
  "details": [ { "field": "proposal.status", "reason": "readback_pending" },
               { "field": "input.idempotency_key", "reason": "reuse_same_key_for_readback_only" } ] }
```

示例把「只能用同一幂等键回读」写进了 `details`。而我在上一轮状态机复审里提出的 **X1**
（Proposal 停在 `applying`/`readback_pending` 时**换幂等键**的行为未定义）正对着这条：
示例只覆盖了「同键」，没覆盖「换键」。结论维持：**那是唯一可能二次写入的通道**。

## 二、本轮发现的问题

### P1 · 必修：时长第三级兜底我漏实现了（**我的缺陷，已修**）

契约 §5.6 写死了三级优先级，第三级是 **`max(preferences.minimum_block_minutes, 30)` 分钟**：

> 调度时长来源优先级固定为：`duration_target_seconds`（周期任务使用折算后的
> `remaining_minutes_today`；该字段为 null 时使用完整目标，为 0 时不生成 block）
> → 服务端可信快照估算 → `max(preferences.minimum_block_minutes, 30)` 分钟。

而我的引擎里第三级**写成了返回 0**（等于直接丢弃该任务）——函数注释上明明写着
「任务目标 > 服务端快照估算 > 兜底」，兜底却是空的。这是我在前几轮自称「时长优先级已对齐」
时漏掉的：我只冻结了前两级。

**已修复**：`_durationOf(demand, input)` 第三级返回 `max(minimumBlockMinutes, 30)`，
且 `fromTarget = false`，因此 `duration_source` 恒为 `scheduler_estimate`（符合「只有任务目标
才算 `task_target`」）。新增守卫用例覆盖两个方向：

- `minimum_block_minutes = 15` → 兜底仍取 **30**（⌈floor 值不是偏好值⌉）；
- `minimum_block_minutes = 45` → 兜底取 **45**。

副作用如实报告：原先依赖「时长为 0 就跳过」的 `NO_VALID_DURATION` 分支**现在不可达**，
我把它保留为防御分支并在代码里写明原因；若 M0 决定兜底不该落在纯函数上，它会重新生效。

> **反过来也要说清楚**：如果 M0 的用意是「第三级只应由服务端快照兜底，纯函数不该自己兜」，
> 那我把这一级实现出来就是**代做了服务端的活**。请回一句，我改回来。这条我现在判断不了。

### P2 · 需 M0 决策：`explanations[].code` 出现**三套互不一致的词汇**

这是挂了三轮的旧账，本轮拿到了硬证据：

| 来源 | 取值 | 说明 |
|---|---|---|
| 契约 md §5.7 | 只说「机器可读 `code`」，**没有枚举**（0 个取值） | 没法判定谁对谁错 |
| 示例文件 EX5 | `PRESERVED_FIXED_EVENTS`、`ESTIMATED_DURATION` | **这两个值在 md 全文出现 0 次** |
| M2 实现 | `SCHEDULED` `NO_AVAILABILITY_WINDOW` `AVAILABILITY_SATURATED` `DISPLACED_BY_FIXED` `FIXED_BLOCKS_OVERLAP` `NO_VALID_DURATION` `ALREADY_DONE_TODAY` `REPAIR_SUMMARY` | 我自己定的 |

三套零交集。**我没有擅自把我的码改成示例里的那两个**——示例被声明为 mock 示例，
在没有封闭枚举之前照抄它，只是把「猜」从我的词汇换成别人的词汇，不产生正确性。

请求 M0：**给一份 `explanations[].code` 的封闭枚举**（哪怕只有示例里那两个起步），
我立刻换掉自己的八码；C 也才能穷举验收。这是唯一卡住「四条判定」中「数据」那一条的东西。

### P3 · 需 M0 补示例：`remaining_minutes_today` / `scheduling_weight` 在示例文件里是 0 次

冻结目标的前两条（周期任务当日剩余量、排序权重）在 md 里有定义、在示例里**一个都没有**：

| 关键字 | md | examples.json |
|---|---|---|
| `remaining_minutes_today` | 2 | **0** |
| `scheduling_weight` | 1 | **0** |

后果：这两个字段只可能出现在「服务端可信调度快照」里（`普通 list_tasks 可以省略`），
而示例里 list_tasks 返回的 Task **确实没有它们**——这是自洽的，但也就意味着
**没有任何一个示例能演示「= 0 不排程」或「非空时折算」**。

请求 M0 补两个示例：`remaining_minutes_today = 0`（不生成 block，也不进 unplanned）与
`= 40`（折算后排 40 分钟）。否则 C 拿不到构造用例的依据，我这边虽有单测，但那是我的测试不是契约证据。

### P4 · 需 M0 决策（上轮已有，本轮**追加了实证**）：Proposal 结构与 Schema required 的落差

上一轮我提「调度器输出过不了完整 Proposal 的 Schema 校验」，当时只是从 §5.7 字段表推出的。
现在 `EX5` 给了一份**完整 Proposal 实例**，四个服务端字段全是具体值：

```json
"snapshot_ref": "snapshot_ref_mock_001_not_production",
"base_version": "base_version_mock_001_not_production",
"input_digest": "sha256:mock_input_digest_001_not_production",
"generated_at": "2026-11-01T10:00:00+08:00",
"expires_at":   "2026-11-01T10:30:00+08:00"
```

而契约同时规定这四项**不得由客户端/模型构造**。两边叠起来的结论不变，但现在不是推论而是对照：

> 调度器（含 M2 纯函数）的输出，**结构上永远缺这四个字段**，因此不能被当作一份完整
> Proposal 去做 JSON Schema 校验。

建议在契约里明文二选一：**(a)** Proposal 序列化由服务端完成，调度器输出只是构件；
或 **(b)** 给进程内单列一个不含服务端字段的 DTO。否则 A 跑 Schema 校验时会失败，
且失败原因归不到任何人头上。

## 三、本轮实际改动（都在我自己的地盘）

| 文件 | 改动 | 性质 |
|---|---|---|
| `lib/.../schedule_engine.dart` | 补齐时长第三级兜底 `max(minimum_block_minutes, 30)`；`NO_VALID_DURATION` 分支加注说明为何不可达 | 契约对齐，非新功能 |
| `test/agent_scheduler_test.dart` | 新增 1 个守卫用例（兜底 floor 30 / 取偏好 45，且都标 `scheduler_estimate`） | 冻结守卫 |
| `docs/scheduler/tools/contract-diff-check.sh` | 覆盖第二份契约文件：新增 §7–§10（示例文件变更规模 / tools 清单 / 示例条目清单 / M2 关键字计数） | 流程工具 |

没有新增功能，没有改他人文件，没有改 M0 契约本体。

## 四、证据与边界（不伪造）

- **测试 30/30 通过**（隔离验证工程 `E:\m2-verify`，`dart test`）。历史 18/18 → 22/22 → 26/26 → 28/28 → 29/29 → **30/30** 全部保留。
- **宿主工程 `flutter test` 仍未复跑**（本机缺 Windows 开发人员模式），不替它声称通过。
- **M1 的 26/26 是 Mock 用例数**（A 的 PR #3），与我的 30/30 不是一个东西，汇报时不得合并。
- 没做：不重跑 M1 mock、不生成 `tools.candidate.json`、不开展完整评审、不评审 A/C 负责的示例。

## 五、下一轮防止再漏同一类问题

diff 助手已扩到两份文件，用法不变：

```bash
git fetch upstream
bash docs/scheduler/tools/contract-diff-check.sh <新的固定SHA>
```

已验证：

- `2c48579 → 2c48579`：**全空**（自反正确，不会假报）；
- `503210c → 2c48579`：能检出示例文件 `+61/-404` 行、`request_approval` 与
  `get_approval_status` 两个工具新增、13 个示例条目新增 —— 不是摆设。
- 若某份契约文件被增删，脚本会**明确提示「基准已失效」而不是静默跳过**。
