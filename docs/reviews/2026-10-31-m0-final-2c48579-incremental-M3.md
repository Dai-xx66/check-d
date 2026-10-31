# M0 Agent API v1 最终候选稿增量复审（C / Evaluation）

- **复审对象**：`docs/contracts/agent-api-v1.md` + `agent-api-v1.examples.json`
- **固定版本**：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`（提交 `docs: finalize agent API v1 candidate contract`，作者 dacy，2026-10-31 04:14）
- **对比基线**：`503210c`（上一版 v1 CANDIDATE）
- **复审性质**：**只读、文档级增量复审**。按队长要求"收到新 SHA 后只检查增量，不重新开展完整评审"。
- **实测状态**：**本轮无任何实测**。仓库内现有 Mock 实现对应旧契约 `e7be8c9`，与新契约的 20 个错误码、8 个 Proposal 状态、6 个 Approval 状态均不对齐；在新 Mock 出现前，本文件所有结论都是**文档判定**，不得被引用为"已通过"或"已执行"。

---

## 0. 一页结论

**有条件同意冻结。**

上一轮我提的 10 个阻塞项（B1–B10）中，**7 项闭合、3 项仍开**；我此前实测发现的两个实现级缺陷（F5 `duration_source` 枚举、旧 `scheduled_at` 静默清空）在契约文本层面**都已修正**。

新发现 **2 个 P1**，都属于"错误码写了但路径不通"这一类，而这一类已经连续三轮出现（`ALREADY_APPLIED` → `SNAPSHOT_CONFLICT` → 现在的 `APPROVAL_CONSUMED`），建议在冻结前把**判定顺序与错误码的对应关系逐行列表化**，否则第四个还会出现。

| 类别 | 数量 | 说明 |
|---|---|---|
| 原阻塞项已闭合 | 7 | B1、B2、B3、B4、B8、B10 + 我此前的 P0-6/F5 |
| 原阻塞项仍开 | 3 | B5（`violations[].code` 枚举）、B6（幂等执行中响应）、B7（`FORBIDDEN`/`NOT_FOUND` 策略） |
| 新发现 P1 | 2 | `APPROVAL_CONSUMED` 按正文不可达；`APPROVAL_UNTRUSTED` 零触发条件 |
| 新发现 P2 | 4 | apply 成功响应无 `proposal_status`、`approved→token_issued` 并发交付、`failed` 无判定条件、错误码示例覆盖 8/20 |
| 新发现 P3 | 2 | 31 天上限未绑错误码、`get_approval_status` 的 `consumed` 无示例 |

---

## 1. 状态可达性：原 7 处 `[未定义]` 的处置

上一轮矩阵 §2.1/§2.2 标了 7 处"契约未定义"。逐条复核：

| # | 迁移 | 上一轮判定 | 本轮判定 | 依据 |
|---|---|---|---|---|
| 1 | `pending_approval` → `readback_pending`（写成功但回读失败） | `[未定义]` | **已闭合** | §5.7 status 含 `readback_pending`；§6.7"必须把幂等记录标为 `readback_pending`"；示例 19 给出 `READBACK_PENDING` + `retryable=true` + `details[proposal.status]=readback_pending` |
| 2 | `pending_approval` → `expired`（超 30 分钟） | `[未定义]` | **已闭合** | §5.7 状态机图"30 min → expired"；§6.7 判定顺序"Proposal 过期返回 `PROPOSAL_EXPIRED`" |
| 3 | `applied` → `failed`（回读持续不一致） | `[未定义]` | **部分闭合** | `failed` 已入枚举、状态机图有"safe failure → failed"，但**未定义何为 safe**、无对应错误码（见 P2-3） |
| 4 | `approved` → `token_issued` | `[未定义]` | **已闭合** | §6.6 明确 `status=token_issued`："Token 已签发但尚未成功消费；后续轮询返回 `approval_token=null`" |
| 5 | `token_issued` → `consumed` | `[未定义]` | **已闭合** | §6.6 `status=consumed`"Token 已成功消费" |
| 6 | `pending` → `expired`（审批过期） | `[未定义]` | **已闭合** | §6.6 `status=expired`，并区分"仅 Token 过期（Proposal 仍有效）"与"Proposal 也过期"两种后果 |
| 7 | `expired` → 新 `pending`（重新审批） | `[未定义]` | **部分闭合** | §6.6 写"可以重新创建审批，但旧 Token 永远无效"，**未说明返回新 `approval_id` 还是复用旧记录**。§6.5"已有未终结审批时返回同一个 `approval_id`"——过期审批算不算"已终结"没写。这正是我上一轮的 F1（过期记录被永久复用），契约仍未把它写死 |

**小结**：4 项完全闭合、2 项部分、1 项待补。状态位本身已经够用，缺口集中在**迁移的判定条件**而非状态值。

---

## 2. 错误码可达性：20 个码逐条判定

§4.1 从 14 个扩到 20 个，新增 `APPROVAL_PENDING`、`APPROVAL_REJECTED`、`APPROVAL_UNTRUSTED`、`APPROVAL_CONSUMED`、`IDEMPOTENCY_CONFLICT`、`WRITE_BLOCKED`、`READBACK_PENDING` 等。判定标准沿用 G1：**只认"能触发"，不认"文档里有"**。

| # | 错误码 | 触发条件是否写明 | 示例 | 判定 |
|---|---|---|---|---|
| 1 | `AUTH_REQUIRED` | 是（身份凭证缺失/无效） | 有（示例 4） | 可判 |
| 2 | `FORBIDDEN` | **否**——§8 写"最终策略由安全评审冻结" | 无 | **不可判**（B7） |
| 3 | `INVALID_ARGUMENT` | 是（请求体带 `user_id`、字段/日期/时区无效） | 无 | 可判（示例可补） |
| 4 | `NOT_FOUND` | **否**——与 `FORBIDDEN` 二选一未定 | 无 | **不可判**（B7） |
| 5 | `DEPENDENCY_UNAVAILABLE` | 否（仅表格一行） | 无 | 部分 |
| 6 | `PROPOSAL_INVALID` | 是（结构/类型/未知字段/change 类型；`scheduled_at` 跨日） | 无 | 可判 |
| 7 | `PROPOSAL_EXPIRED` | 是（§6.7 判定顺序 + §6.4） | 有（示例 15） | 可判 |
| 8 | `SNAPSHOT_CONFLICT` | 是（§6.4 validate、§6.7 apply 双阶段；唯一键撞库同码） | 有（示例 18） | 可判 |
| 9 | `APPROVAL_REQUIRED` | 是（§6.7 末段：无审批记录） | 无 | 可判 |
| 10 | `APPROVAL_PENDING` | 是（§6.7 末段：有审批但 pending） | 有（示例 11） | 可判 |
| 11 | `APPROVAL_REJECTED` | 是（§6.7 末段：用户拒绝） | 无 | 可判 |
| 12 | `APPROVAL_EXPIRED` | 是（§6.7：Token 过期） | 有（示例 17） | 可判 |
| 13 | `APPROVAL_UNTRUSTED` | **否**——全表外零引用 | 无 | **不可判**（P1-2） |
| 14 | `APPROVAL_CONSUMED` | **否**——判定顺序使其不可达 | 有（示例 16，但与正文冲突） | **不可判**（P1-1） |
| 15 | `ALREADY_APPLIED` | 是（§6.7 第 2 步） | 有（示例 14） | 可判 |
| 16 | `IDEMPOTENCY_CONFLICT` | 是（§6.5 同键异提案；§6.7 同键异摘要） | 无 | 可判 |
| 17 | `WRITE_BLOCKED` | 是（§6.7：无法证明原子性） | 无 | 可判（依赖 BLOCKED 项） |
| 18 | `READBACK_PENDING` | 部分——§6.7 写"标为 readback_pending"但正文未把**错误码**与状态显式对应 | 有（示例 19） | 可判（示例补齐了对应关系） |
| 19 | `READBACK_MISMATCH` | 是（§6.7：写后回读不一致，不得返回成功） | 无 | 可判 |
| 20 | `INTERNAL_ERROR` | 否（仅表格一行） | 无 | 部分 |

**结论：20 个码中 12 个可判、2 个不可判、2 个部分、4 个仅缺示例。** 20 个示例里 8 个是错误响应，`APPROVAL_REQUIRED`／`APPROVAL_REJECTED`／`READBACK_MISMATCH`／`IDEMPOTENCY_CONFLICT` 这四个验收核心码没有示例，建议补。

---

## 3. 四元组复核：T01–T18 的可判性变化

上一轮：12 条中 3 条完全可判、5 条部分、4 条不可判。本轮按新契约重算（含新增用例）：

| 用例 | 主题 | 上一轮 | 本轮 | 变化原因 |
|---|---|---|---|---|
| T01 | 写成功但回读失败 | 不可判 | **可判** | `READBACK_PENDING` + `proposal_status=readback_pending` |
| T02 | `readback_pending` 恢复 | 不可判 | **可判** | 同键只重读、终局可到 `applied` |
| T03 | 回读持续不一致 → `failed` | 不可判 | 不可判 | `failed` 判定条件未定义（P2-3） |
| T04 | 版本冲突零写入 | 部分 | **可判** | §6.7"以上均为零写入" |
| T04-b | validate 摘要重算 | 部分 | **可判** | §6.4 明确 SHA-256 从一次一致性快照重算 |
| T05 | 审批过期 | 部分 | **可判** | `APPROVAL_EXPIRED` + `status=expired` |
| T06 | 提案过期 | 不可判 | **可判** | `PROPOSAL_EXPIRED` |
| T07 | 并发 apply | 部分 | 部分 | 执行中响应仍未定义（B6） |
| T08 | 重复 apply | 不可判 | **可判** | `ALREADY_APPLIED` 第 2 步 |
| T09-a | 缺 `existing_override_id` 撞唯一键 | 不可判 | **可判** | §5.7"返回 `SNAPSHOT_CONFLICT` 且零写入；不得用另一个 `override_id` 创建重复记录" |
| T09-b | 拿他人 `override_id` | 不可判 | 不可判 | `FORBIDDEN`/`NOT_FOUND` 未定（B7） |
| T09-c | 正确覆盖 + 7 字段回读 | 可判 | **可判** | §6.7 回读字段已写死为 7 项 |
| T10-a/b | `available_from` / `deadline` | 部分 | 部分 | `violations[]` 项结构未定义（B5） |
| T11 | `scheduled_at` 与 `planned_date` 冲突 | 部分 | **可判** | §5.7 明确"必须以 `PROPOSAL_INVALID` 拒绝" |
| T12 | `end_at` 不参与持久化 | 可判 | **可判** | 不变 |
| T12-b | 时长来源优先级 | 部分 | **可判** | 枚举改为 `task_target`/`scheduler_estimate`，三档来源写明 |
| T13 | 请求体带 `user_id` | 可判 | **可判** | §4 明确 `INVALID_ARGUMENT` |
| T14 | 空数据不 404 | 可判 | **可判** | §6.1/§6.2 明确空数组 |
| T15 | `skip` | 不可执行 | **可判（改为负向）** | §5.7"`skip` 不属于 v1 change 白名单" |
| T16 | 审批状态序列 + 重复 request 幂等 | 不可判 | **可判** | §6.6 六态 + §6.5 同 `approval_id` |
| T17 | 过期审批重建 | 不可判 | 部分 | 新/旧 `approval_id` 未定（见 1.#7） |
| T18 | `APPROVAL_CONSUMED` | 不可判 | 不可判 | P1-1 |

**统计：可判 15 → 部分 3（T07、T10、T17）→ 不可判 3（T03、T09-b、T18）。**

---

## 4. 契约正文一致性：三处枚举互查

| 检查项 | 结果 |
|---|---|
| §4.1 错误码表 vs 正文引用 | 20 个码中 3 个在正文零引用（`APPROVAL_UNTRUSTED`、`AUTH_REQUIRED`、`DEPENDENCY_UNAVAILABLE`）。`AUTH_REQUIRED` 有示例可接受；`APPROVAL_UNTRUSTED` 是实质缺陷 |
| §5.7 Proposal 状态 vs 状态机图 | 一致：`draft`/`pending_approval`/`applying`/`readback_pending`/`applied`/`rejected`/`expired`/`failed`，图与枚举 8 个全对应 |
| §6.6 Approval 状态 vs §4.1 错误码 | 6 个 status 均有对应码，唯一例外是 `consumed` 对应的 `APPROVAL_CONSUMED` 不可达（P1-1） |
| `duration_source` 枚举 | 一致：`task_target` / `scheduler_estimate`。**我上一轮指出的 `snapshot_estimate`／`fallback` 用词冲突已消除**，实现与契约现用同一套词 |
| `unplanned_tasks.reason_code` 枚举 | 契约定为 `WINDOW_INSUFFICIENT`/`PAST_DEADLINE`/`OVERLAPS_FIXED`/`NO_AVAILABILITY`。旧 Mock 用的是 `no_free_slot`/`insufficient_window`，**新 Mock 必须改**，否则 A 的既有用例会假通过 |
| `explanations` 形状 | 已定为对象数组（`code`/`message`/`related_task_ids`），不再允许字符串混用。我的开放项闭合 |
| 示例覆盖 | 20 个示例中 `task_target` 零次出现；4 个 `reason_code` 只有 1 个出现；`violations` 只有空数组示例 |

---

## 5. 新发现缺陷

### P1-1 `APPROVAL_CONSUMED` 按正文判定顺序不可达，且示例与正文冲突

§6.7 规定的顺序是：**① 幂等记录（同摘要重放）→ ② 已 applied（换键返回 `ALREADY_APPLIED`）→ ③ TTL / `base_version` / Token**，并在 ③ 里说"Token 已消费且不存在相同幂等记录时返回 `APPROVAL_CONSUMED`"。

三条可能的到达路径全部走不通：

| 路径 | 构造 | 实际返回 | 原因 |
|---|---|---|---|
| A | 同一 Proposal 换幂等键重试 | `ALREADY_APPLIED` | 第 ② 步先命中 |
| B | 用旧 Token 打**另一个** Proposal | 应为 `APPROVAL_UNTRUSTED` | §6.7 要求"凭证绑定完全相同的 `proposal_id`、`base_version` 和变更摘要"；不一致即绑定失败，与 P1-2 冲突 |
| C | Token 已消费但 Proposal 未 `applied` | 不存在 | §6.6 把 `consumed` 定义为"Token 已成功消费"，而成功消费只发生在 apply 成功路径 → 提案必为 `applied` |

**示例 16 走的正是路径 B**：请求体是 `proposal_id: "proposal_mock_other_pending"`、`base_version: "base_version_mock_other"`，却配一个旧 Token，然后返回 `APPROVAL_CONSUMED`。按 §6.7 第 2 条核验，这里应该先报绑定不一致。**示例与正文互相否定。**

修法（二选一，必须写进契约）：
1. **把"消费时点"写死**——若定义"Token 在 apply 开始即标记消费（写入前）"，则路径 C 成立：写入失败后 `status=failed`、Token 已消费，重试即 `APPROVAL_CONSUMED`。同时把 ③ 的检查放到 ② 之前不必要，但要明确"消费"≠"写入成功"。
2. **保留"消费=写入成功后"**，则删除 `APPROVAL_CONSUMED` 错误码（状态 `consumed` 保留用于审计），重复 apply 统一走 `ALREADY_APPLIED`——这与 A 在 `e7be8c9` 的处理一致（A 已删该码）。

我倾向方案 1，因为审计上能区分"Token 被用掉了但没写成"与"提案已应用"。无论选哪个，**示例 16 必须按最终定义重写**。

### P1-2 `APPROVAL_UNTRUSTED` 零触发条件

`APPROVAL_UNTRUSTED` 在全文（除 §4.1 表格行）出现 **0 次**。§6.7 要求核验"凭证绑定完全相同的 `proposal_id`、`base_version` 和变更摘要"，但**没有给这条核验分配错误码**。

后果：篡改 Token 绑定（换 `proposal_id`、改 `base_version`、改 change 摘要）该返回 `APPROVAL_UNTRUSTED`、`APPROVAL_CONSUMED`、`SNAPSHOT_CONFLICT` 还是 `APPROVAL_REQUIRED`，验收时无法判定——而"防篡改"是审批链路唯一真正的安全断言。

修法：把 §6.7 的 5 条核验逐条绑定错误码，形式如：

| 核验 | 失败错误码 |
|---|---|
| 凭证主体 ≠ 当前主体 | `APPROVAL_UNTRUSTED` |
| 凭证绑定的 `proposal_id`／`base_version`／`change_digest` 与提案不符 | `APPROVAL_UNTRUSTED` |
| 凭证已过期 | `APPROVAL_EXPIRED` |
| 凭证已消费 | `APPROVAL_CONSUMED`（或方案 2 下的 `ALREADY_APPLIED`） |

### P2-1 apply 成功响应不含 `proposal_status`，四元组的"状态"一列在成功路径上不可观测

示例 12（apply 成功）的 `data` 只有 `applied_changes`／`readback_verified`／`applied_at`，没有 `proposal_status`。四元组要求"Proposal 状态 = `applied`"，验收时只能二次读取或看 `validate`，**这正是过去几轮"写入成功但状态没变"类缺陷的观测盲区**。

建议：apply 成功响应加 `proposal_status: "applied"`，`READBACK_PENDING` 错误响应的 `details` 里固定带 `proposal.status=readback_pending`（示例 19 已这么做，但属 `details` 非契约字段，应提升为正式字段）。

### P2-2 `approved` → `token_issued` 的并发交付未定义

§6.6 说"仅首次安全交付时返回 `approval_token`"。若两个轮询并发命中 `approved`，是否可能双交付未定义。Token 一次性是安全基线，这里必须声明该迁移**原子**：任一时刻只有一个响应能拿到 Token，其余必须得 `token_issued` + `approval_token=null`。对应用例 T21。

### P2-3 `failed` 无判定条件

状态机图有"safe failure → `failed`"，但：
- 什么算"safe"（写入确证未发生？）没定义；
- 没有任何错误码对应 `failed`；
- 与 `readback_pending` 的边界没写（写入可能发生 → `readback_pending`；确认没发生 → `failed`；那"确认没发生"怎么确认？）

影响 T03 的终局断言。

### P2-4 错误码示例覆盖 8/20

缺示例的 12 个码见 §2。其中 `APPROVAL_REQUIRED`、`APPROVAL_REJECTED`、`READBACK_MISMATCH`、`IDEMPOTENCY_CONFLICT` 属验收核心，建议优先补；这四条同时也是最好的固定回归用例。

---

## 6. 剩余阻塞项（B5 / B6 / B7）

| 编号 | 内容 | 影响用例 | 现状 |
|---|---|---|---|
| B5 | `violations[].code` 枚举与项结构 | T10-a/b、T11 | §6.4 仅"结构化约束错误数组"；示例只有空数组 |
| B6 | 幂等"执行中"响应 | T07 | §6.7"并发请求共享同一执行结果"未定义等待、超时与返回码 |
| B7 | `FORBIDDEN` vs `NOT_FOUND` 策略 | T09-b | §8 明确"由安全评审冻结"，§10 开放问题 5 |

这三项都不依赖 BLOCKED 能力，属纯文档决策。

---

## 7. 仍未验证（不因本轮复审而解除）

- WorkBuddy 实机工具调用、身份透传、外部确认回调（BLOCKED）
- `static_bearer_demo` 的 token 注入与轮换（BLOCKED；且该模式**不能区分共享链接的不同访问者**，演示时必须写明）
- 真实审批服务、确认者身份校验、Token 签名/撤销（BLOCKED）
- 可信 `snapshot_ref`／`base_version` 生成与事务内比较（BLOCKED）
- 原子批量写入、幂等存储并发锁、保留期与崩溃恢复（BLOCKED）
- 生产写后回读路径（BLOCKED）
- `readback_pending` 的恢复流程与终局（契约 §10 开放问题 5 自认未定）
- 幂等记录保留期到期后重放是否二次写入（同上）

---

## 8. 冻结建议

**有条件同意冻结**，条件是按优先级修以下四项（均为文档级、不依赖 BLOCKED）：

1. **P1-1** `APPROVAL_CONSUMED` 消费时点二选一并改写示例 16（否则这是第三个"码在、路不通"）
2. **P1-2** `APPROVAL_UNTRUSTED` 补触发条件，把 §6.7 五条核验逐条绑错误码
3. **B5** `violations[]` 项结构与 code 枚举
4. **B7** `FORBIDDEN`／`NOT_FOUND` 二选一（哪怕先定"v1 统一 `NOT_FOUND`"也能解锁 T09-b）

可延后但建议同批处理：P2-2 并发交付原子性、P2-3 `failed` 判定条件、P2-4 补 4 个核心错误码示例。B6 可留到幂等存储实现时再定，但它会让 T07 一直是"部分可判"。

**不建议**把 `skip`、31 天上限、`explanations` 形状再打开——这三项已经定得足够清楚，重开会拖慢冻结。

---

## 9. 附：本轮复审执行记录

| 步骤（矩阵 §9） | 结果 |
|---|---|
| 1 固定版本 | `2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6` |
| 2 状态可达性 | 原 7 处 `[未定义]`：4 闭合、2 部分、1 待补 |
| 3 错误码可达性 | 20 码：12 可判、2 不可判、2 部分、4 缺示例 |
| 4 四元组复核 | 21 条用例：可判 15、部分 3、不可判 3 |
| 5 正文一致性 | 3 处枚举互查通过；1 处示例与正文冲突（示例 16） |
| 6 归档 | 本轮为文档级复审，无实测，未新增 §7 实测记录 |
| 7 输出 | 本文件 |
