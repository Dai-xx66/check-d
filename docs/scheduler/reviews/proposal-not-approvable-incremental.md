# B（M2）增量判断：`PROPOSAL_NOT_APPROVABLE`

> 触发：队长指令第 9 条 —— 该码是 M1 新提议、M0 契约尚未采用；
> 要求「补独立可达测试并交 B/C 做一次增量判断，**不要自行写入最终 Schema**」。
> 对照版本：`upstream/feat/m0-api-contract` @ `2c48579`（全文匹配该码 **0 次**）。
> 日期：2026-10-31　判断人：B（M2）
>
> **本文只是给 M0 / C 的输入，不修改契约任何章节，也不在我方 DTO 里新增该字段或枚举。**
> `ScheduleProposalStatus` 仍是契约 §5.7 的 8 态，我没有加第 9 个状态。

## 一、一句话结论

**建议采纳，但要窄化定义 + 排好顺序**：它应当只补那个真正的空洞 ——
「Proposal 存在且属于当前主体，但当前状态不允许建立审批」，
并且**必须排在 `ALREADY_APPLIED` 与 `PROPOSAL_EXPIRED` 之后**，否则会把这两个已有码的确切语义吞掉。

另外它有两条硬边界，谁采纳谁负责：

1. 它是**错误码**，不是 Proposal 的状态值（不许进 §5.7 的 8 态）；
2. 它**不是权限码**（不许和 `FORBIDDEN` / `AUTH_REQUIRED` 混用），建议 HTTP **409**，
   与 `PROPOSAL_EXPIRED`、`ALREADY_APPLIED` 同级——语义是"资源存在，但当前状态不允许这个动作"。

## 二、它到底补的是哪个洞（现有三个码覆盖不到什么）

把 `request_approval` 的所有入口状态排一遍，就能看出空洞在哪：

| Proposal 状态 | @2c48579 现在的规定 | 现有码能否覆盖 |
|---|---|---|
| `draft`（**没validate 过**） | §6.5 只写「状态必须为 `pending_approval`」，**没有给错误码** | ❌ **这就是洞** |
| `rejected` | §6.6 只把 Proposal 同步到 `rejected`，没规定再走审批时返什么 | ❌ 洞（`APPROVAL_REJECTED` 是审批层的，语义不同） |
| `failed` | 未规定 | ❌ 洞 |
| `applying` / `readback_pending` | 未规定 | ❌ 洞（且和二次写入风险相邻） |
| `expired` | §6.5 明文 `PROPOSAL_EXPIRED` | ✅ 已覆盖 |
| `applied` | §6.5 明文 `ALREADY_APPLIED` | ✅ 已覆盖 |
| 不存在 / 不属于当前主体 | §8 规定 `NOT_FOUND` / `FORBIDDEN` | ✅ 已覆盖 |

**结论**：`PROPOSAL_NOT_APPROVABLE` 的存在价值恰恰是把"§6.5 只写了条件、没给码"这一行补上。
不做这件事的话，`request_approval` 遇到 draft 提案只能泛化成 `INVALID_ARGUMENT`，
而 C 的四项判定里「错误码」一栏就写不出确定的期望值。

## 三、建议的定义草案（供 M0 决定是否收入，我未写入契约）

> `PROPOSAL_NOT_APPROVABLE`（建议 409）：Proposal 存在且属于当前认证主体，
> 但其当前状态不允许建立审批（非 `pending_approval`，且不是 `applied` / `expired`）。
> 零写入，不得创建审批记录，不得返回 `approval_id` 或 `approval_url`。

**`request_approval` 内的建议判定顺序**（在现有 §6.5 基础上补第 4 步）：

1. 不属于当前主体 → `NOT_FOUND` / `FORBIDDEN`（§8）
2. 同作用域幂等键 + 同 Proposal → 返回首次响应快照（§6.5）
3. **已 `applied` → `ALREADY_APPLIED`**（§6.5）
4. **已过期 → `PROPOSAL_EXPIRED`**（§6.5）
5. **其余非 `pending_approval` 状态 → `PROPOSAL_NOT_APPROVABLE`（新增）**
6. 已有未终结审批 → 返回同一个 `approval_id`（§6.5）
7. 同幂等键用于别的 Proposal → `IDEMPOTENCY_CONFLICT`（§6.5）

第 3、4 步必须排在 5 **之前**——否则 `expired` 与 `applied` 的用例会被这个新码抢走，
C 的验收表会出现"期望 PROPOSAL_EXPIRED 实际 NOT_APPROVABLE"的错位。

> 顺带提醒：第 6 步的"未终结"集合**本身还没定义**（见状态机复审文档 R1）。
> 建议跟着这条一起定：`未终结 = {pending, approved, token_issued 且 Token 未过期}`。

## 四、M2 侧能提供的「独立可达测试」输入（不伪造、可执行前提）

**M2 没有服务端实现，因此给不了端到端测试，也不会假装给了。** 我能给的是一条
**100% 确定、不依赖时钟和网络的可达路径**，M1 可以直接拿它写失败用例：

> **M2 纯调度函数的任何输出，`status` 恒为 `draft`。**
> 已有测试锁定：`冻结目标守卫 · 写入次数可推算：每 block 恰一条白名单变更，change_id 唯一，状态恒为 draft`
> （同时断言 `snapshot_ref` / `input_digest` 恒为 null）。

所以在 mock/服务端侧：

| 用例 | 输入 | 四项判定期望 |
|---|---|---|
| **A（负例 · 可达 `PROPOSAL_NOT_APPROVABLE`）** | 拿 M2 的原始输出（未经 `validate_schedule`）直接调 `request_approval` | 错误码 `PROPOSAL_NOT_APPROVABLE`；状态 Proposal 仍 `draft`、审批表无新行；数据不得返回 `approval_id`/`approval_url`；**写入次数 0** |
| **B（对照正例）** | 同一份 Proposal 先 `validate_schedule` 通过 → `pending_approval` → `request_approval` | 错误码无；状态 Proposal `pending_approval`、Approval `pending`；数据返回 `approval_id` + `approval_url`；**写入次数 1（仅审批域）** |

A 与 B 必须成对——只写 A 的话，失败也可能来自"这份 Proposal 本身就是坏的"，
B 用来证明 Proposal 本身没问题、失败只因为状态不对。这才是「独立可达」。

**为什么这条路径比"过期"路径更稳**：过期用例需要操纵时钟或等待，
失败原因可能是"判过期逻辑错了"而不是"不可审批"；而 draft 路径的状态由纯函数保证，
任何抖动都排除在外。

## 五、给 C 的验收口径建议

如果采纳，C 的表里这一行建议是这样填的：

| 触发 | 期望错误码 | 期望 Proposal 状态 | 期望数据 | 期望写入次数 |
|---|---|---|---|---|
| 对未 validate 的 `draft` Proposal 调 `request_approval` | `PROPOSAL_NOT_APPROVABLE`（409） | 不变（`draft`） | 无 `approval_id` / `approval_url` | 0 |
| 对已 applied 的 Proposal 换幂等键 apply | `ALREADY_APPLIED`（409） | `applied` | 含首次 `applied_changes` 摘要 | 0 |
| 对过期 Proposal 调 `request_approval` | `PROPOSAL_EXPIRED`（409） | `expired` | — | 0 |

## 六、我不做的部分（避免越界）

- 不把它写进 §4.1 或其它任何契约章节；
- 不在 `ScheduleProposalStatus` 里加状态、不在 `ScheduleProposal` 里加字段；
- 不代替 M1 写 `tools.candidate.json`，也不把这条算作 M2 的可执行证据；
- 本轮的 M2 测试数**不因本文变化**（仍 28/28，本轮没有新增功能也没有新增测试）。

## 七、待 M0 / C 决策

1. 是否采纳？采纳则按第三节的定义与顺序写进 §4.1 + §6.5。
2. HTTP 409 还是 422？（我建议 409，理由见第一节。）
3. `rejected` / `failed` 状态是否也归这个码，还是各自出码？
4. 「未终结审批」集合是否借这次一并定义（否则第 6 步仍不可判定）。
