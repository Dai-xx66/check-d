# B（M2）增量审查结果：以 M0 Task 1 固定 SHA 为唯一契约基准

> 日期：2026-10-31　审查人：B（M2）
> 基准：**`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`**（`feat/m0-api-contract`，PR M0-1，
> 文件 `docs/contracts/agent-api-v1.md`，提交时间 2026-10-31 04:14:13 +0800）
> 范围：队长指定四项 —— **调度 DTO / 快照引用 / 时间语义 / Proposal 输出**
>
> **纪律：不修改 M0 契约本体，不重新进行完整审计，不扩大功能范围。**
> WorkBuddy 真实认证、可信审批、原子写入、生产回读继续 BLOCKED。

## 零、先解决 SHA 本身的一个问题

队长的通知里 **"Commit SHA：请填入最新完整 SHA" 是占位符，没有替换**。我核了一遍：

```
upstream/feat/m0-api-contract  HEAD = 2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6
该分支在 2026-10-31 之后没有任何新提交
```

所以我**按字面把占位符填成该分支当前的完整 HEAD**，并以它为唯一基准完成了下面的审查。

> **若队长手中的固定 SHA 不是 `2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`，请回一句，
> 我重跑一次增量（`bash docs/scheduler/tools/contract-diff-check.sh <SHA>`），本结果作废。**

用这个 SHA 跑增量 diff 的结果是 **新增 0 行 / 删除 0 行**（相对我上一轮的对齐基准同源），
因此本次审查的性质是：**以最终 SHA 为基准的四项定点核对**，不是全文通读。

## 一、调度 DTO —— ✅ 对齐，并修掉一处输出偏差

| 契约 | M2 现状 | 判定 |
|---|---|---|
| §5.6 `schedule_block` 九个字段 | 键集合**严格相等**（多一个少一个都会红） | ✅ |
| §5.7 `schedule_one_time`：`change_id/type/task_id/planned_date` + 可选 `scheduled_at` | 严格相等 | ✅ |
| §5.7 `upsert_daily_override`：八个必填 + 可选 `existing_override_id` | 严格相等；`existing_override_id` 恒 null（模型不得猜测） | ✅ |
| §5.7 `unplanned_tasks[]`：`task_id` / `reason_code` / `remaining_minutes` / `message` | **本轮修正**：原来多输出了一个契约外 `title`，已移除 | ✅ 修正 |
| §5.7 `explanations[]`：`code` + `message` + 可选 `related_task_ids` | 键 ⊆ 该集合，且必有 code/message | ✅ |
| §5.2 `remaining_minutes_today` 三态 | 0 / 非 0 / null 三态均有测试 | ✅ |
| §5.6 三条硬约束（单次事项单块、同本地日单块、不跨午夜） | 均有守卫测试 | ✅ |

本轮新增证据：`冻结目标守卫 · DTO 键集合与契约逐字对齐：不多不少，服务端字段除外`
（一次性把上述五个对象的键集合全部钉死，契约以后加字段会立刻红、我这边偷加字段也会立刻红）。

**发现一处需要 M0 决策的问题（不属我修，只报告）**：

> §5.7 把 `generated_at` 与 `expires_at` 列为 `schedule_proposal` 的字段，
> 同时又规定「服务端不得接受客户端指定或延长该 TTL」，而 `snapshot_ref`/`input_digest`
> 也明确「客户端和模型不得构造」。
> 这意味着 **M2 调度器的输出在结构上永远不构成一份能通过 JSON Schema `required`
> 校验的完整 Proposal** —— 它不是缺陷，是职权边界，但契约目前没有明说这句话。
>
> 建议 M0/A 二选一写明：
> **(a)** 「Proposal 的序列化由服务端完成，调度器输出只是服务端 Proposal 的构件」；
> 或 **(b)** 给调度器侧的 Proposal 单列一个不含服务端字段的 DTO（§6.3 允许的进程内 DTO）。
> 不写清楚的话，A 跑 `tools.candidate.json` 的 Schema 校验时，M2 的输出会以一个
> "看起来像 Proposal 但缺字段"的形态失败，而失败原因归不到任何一方。

## 二、快照引用 —— ✅ 对齐

| 项 | 结论 |
|---|---|
| `snapshot_ref` / `input_digest` | M2 **一律留空**，由服务端产生；测试断言为 null，不伪造 |
| `base_version` | M2 只从 `ScheduleInput.baseVersion` 传入并原样带回；文档已注明"进程内传入的值只用于测试，不得当作可信版本" |
| 不读库、不联网 | `模块边界 · 调度模块不得访问数据库或任何应用层代码`（禁 `drift`/`supabase`/`task_repository`/`app_database`） |

**仍挂着**：`input_digest` 覆盖范围**没有排程区间（horizon）与时区**（§5.7 列举了 Task、
日历事件、单日例外、偏好、外部固定事件）。同一快照换 horizon 会产出不同提案却拿到同一
digest，validate 察觉不到。已挂两轮，再次提请。

## 三、时间语义 —— ✅ 对齐

| 语义 | M2 实现 | 证据 |
|---|---|---|
| `date_only` 截止**整天宽限**，绝不合成 23:59 | `latestEndAt` 只是排程上界，不宣称记录为 23:59 | `日期型截止整天宽限，不能被当成 23:59 处理` |
| `exact` 截止**到达即过期**（`now == dueAt` 已逾期） | `isPast` 用 `!now.isBefore(dueAt)` | `截止语义 · ScheduleDeadline 两种形态互斥且语义不同`（含 10-31 修的边界 bug） |
| block `start_at`/`end_at` 同属一个上海本地日 | 窗口按本地日切分，碎片合并不跨日 | `确定性与边界 · 排出来的块不跨自然日` |
| 不取系统时钟，基准全部来自 `ScheduleInput.now` | 纯函数，禁 `DateTime.now()` | 模块边界用例 |
| Proposal TTL 30 分钟 / Token 5 分钟 | **不由 M2 产出**（我不构造 `generated_at`/`expires_at`） | 键集合守卫 + `status 恒 draft` 断言 |

**如实标注一项局限**：M2 内部直接使用 Dart `DateTime`，**不做时区转换**——它假设调用方
（服务端）传入的已经是 Asia/Shanghai 本地时间。处理时区是 M0 的职责，不是 M2 假装支持的东西。

## 四、Proposal 输出 —— ✅ 对齐

| 契约要求 | M2 | 证据 |
|---|---|---|
| `status` 八态（`draft/pending_approval/applying/readback_pending/applied/rejected/expired/failed`） | 枚举与之一致；**纯函数恒出 `draft`**，从不构造终态 | `冻结目标守卫 · ...状态恒为 draft` |
| `blocks` 与 `changes` 分离 | ✅ changes 由 blocks 派生，只出白名单两种 | 契约对齐类用例 |
| `changes` 白名单两种 + `action` 恒 `reschedule` | ✅ 新增任何第三种会红 | `写入次数可推算` 用例 |
| `unplanned_tasks` 四值大写枚举 | ✅ 封闭，新增原因必须改枚举 | `reason_code 取值必须落在封闭枚举内` |
| 不持久化 `skip` | ✅ 排不下只留 `unplanned_tasks`，不写单日例外 | 同上 + 算法文档第 6 节 |

**唯一仍未闭合的旧账**：`explanations[].code` **契约只写"机器可读 code"，没有给枚举**，
M2 现用 8 个值（`FIXED_BLOCKS_OVERLAP`、`NO_AVAILABILITY_WINDOW`、`AVAILABILITY_SATURATED`、
`NO_VALID_DURATION`、`ALREADY_DONE_TODAY`、`SCHEDULED`、`DISPLACED_BY_FIXED`、`REPAIR_SUMMARY`）。
已挂两轮。**C 据此无法穷举验收，也无法判定非法值**，建议与 `reason_code` 一样登记成表。

## 五、本轮实际改动

| 类型 | 内容 |
|---|---|
| 输出形状修正 | `UnplannedTask.toJson()` 移除契约外 `title`（Dart 对象仍保留该字段供进程内使用） |
| 新增测试 1 个 | `DTO 键集合与契约逐字对齐` |

**没碰**：`schedule_engine.dart`、`task_repository`、任何公共 DTO、M0 契约本体。
没有新增功能。

## 六、证据与诚实标注

- **29/29 通过**（隔离验证工程 `E:\m2-verify`，Dart VM + `dart test`）。
- 宿主工程 `flutter test` 因本机缺 Windows 开发人员模式**仍未复跑**，不替它声称通过。
- 历史数字保留：18/18 → 22/22 → 26/26 → 28/28 → **29/29**，没有覆盖也没有合并。
- M1 的 26/26（PR #3 `e7be8c9`）是 Mock 用例数，与我的 29/29 不是一个东西，**不混用**。
- 没有做：重跑 M1 mock、生成 `tools.candidate.json`、重开完整评审。

## 七、需要队长/ M0 回话的三件事

1. **SHA 确认**：固定 SHA 是否就是 `2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`（第一节）。
2. **Proposal 序列化职责**：写明"调度器输出不构成完整 Proposal"（第一节末）。
3. **两个旧账**：`explanations[].code` 枚举；`input_digest` 是否纳入 horizon 与时区。
   （另：状态机侧我提的 R1 死锁与 X1 换幂等键二次写入，属 C/M0 判断范围，未计入本次四项。）
