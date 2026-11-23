# B（M2）增量复审：Proposal / Approval 状态与写入安全（C 清单 10 项）

> 复审对象：`docs/contracts/agent-api-v1.md` @ `2c48579`（PR #4），条款引用到节号。
> 触发：队长转来的「C 增量复审清单」10 项。
> 日期：2026-10-31　复审人：B（M2）
>
> **纪律：只做条款级静态复审与 M2 侧可执行守卫；不伪造任何我没跑过的执行结果。**
> 判定四值：`已自有证据` / `静态结论` / `未覆盖` / `BLOCKED`。
> 本文不改契约，只指出缺口并给建议措辞。

## 结论摘要（可直接转队长 / C）

1. **10 项中 6 项在条款上已闭合**，落在 M1 实现与 M3 验收口径；**4 项契约有缺口**，其中
   **2 项会造成"错误码不可达或二次写入"**，需要 M0 在合入前补充：

| 级别 | 问题 | 位置 | 后果 |
|---|---|---|---|
| **必修** | Token 过期后重建审批 ≠ request_approval 返回同一 approval_id | §6.5 ↔ §6.6 | 审批死锁，APPROVAL_EXPIRED 之后无路可走 |
| **必修** | `applying`/`readback_pending` 期间换幂等键的行为未定义 | §6.7 判定顺序 | 唯一一条可能二次写入的通道 |
| 建议 | `applying`/`readback_pending` 在状态机图里没有出边到 expired，也没有 readback_pending → applied | §5.7 图 | 「状态」判定项无法终结 |
| 建议 | `>=` 还是 `>` 判定过期、`token_expires_at` 截断算法、时钟源 | §5.7/§6.6 | 边界用例两侧实现不一致 |

2. **C 上一轮发现的我已复核并更正一处**：`ALREADY_APPLIED` 在 M1 mock 中因判定顺序不可达，
   但 @2c48579 §6.7 已**写死**判定顺序（幂等记录 → 是否已 applied → TTL → base_version → Token），
   所以**契约层已可达**，剩下的是 M1 实现缺陷，不再是契约缺口。以 C 的现场结论为准，我这开着对应结论。

3. **M2 本轮新增 2 个可执行守卫（28/28 通过）**，覆盖清单第 8、9 项里 M2 能为服务端消除风险的部分。

---

## 第 1 项：Proposal 与 Approval 状态迁移是否完整

**判定：静态结论 —— 不完整，5 处缺口。**

| 缺口 | 说明 |
|---|---|
| G1 **Approval 无迁移图** | Proposal 有 §5.7 的 8 态图；Approval 只有 §6.6 枚举 `pending/approved/token_issued/consumed/rejected/expired`，没有自己的迁移规则。且 `approved` 是**被读取消耗掉的瞬时态**（首次安全交付 Token 后转 `token_issued`），意味着 `get_approval_status` 带写副作用，与 §6 工具表「只读/受控 Token 签发」的描述一致但容易漏看 |
| G2 **`applying` 无出边到 expired** | §5.7 正文要求「基础数据版本变化即使发生在 30 分钟内也必须返回 SNAPSHOT_CONFLICT」，但图中 `applying` 只有 `readback ok / uncertain / safe failure` 三条出边；applying 期间 Proposal TTL 到点的迁移未定义 |
| G3 **`readback_pending` 无出边** | 图中 `readback_pending` 是叶子；§6.7 说「同一幂等键重试只能重新回读/核验」，回读成功后该迁到 `applied`，图里没有这条边，「状态」判定项会永远悬在不确定态 |
| G4 **`failed` 后能否重试** | 未定义。换幂等键重试同一 Proposal？服务端 forbid 还是允许？ |
| G5 **组合状态表缺** | 例：Proposal=`expired` 且 Approval=`approved`；Proposal=`readback_pending` 且 Approval=`consumed`。没有一个组合合法性对照表 |

**M2 侧影响：无。** `ScheduleProposalStatus` 8 态已与图一致（含 `applying`/`readback_pending`），
纯函数恒出 `draft`。

---

## 第 2 项：PROPOSAL_EXPIRED / APPROVAL_PENDING / APPROVAL_EXPIRED / APPROVAL_CONSUMED / ALREADY_APPLIED 是否可达

**判定：静态结论 —— 4 个在条款上可达，1 个要看 M1 实现顺序。**

| 错误码 | 条款依据 | 判定 |
|---|---|---|
| `PROPOSAL_EXPIRED` | §6.5（已过期 Proposal 不得建审批）、§6.7 判定顺序第 3 步 | **可达**。前提是服务端做**惰性置位**：任何读取路径发现 `now >= expires_at` 即视为 expired，不依赖定时任务。建议 M0 明文写入这条 |
| `APPROVAL_PENDING` | §6.7 末段「已有审批但仍为 pending，返回 APPROVAL_PENDING…写入次数必须为零」 | **可达，且零写入已明文** |
| `APPROVAL_EXPIRED` | §6.7「Token 过期返回 APPROVAL_EXPIRED」 | **可达**，但与第 3 项 R1 冲突，见下 |
| `APPROVAL_CONSUMED` | §6.7「Token 已消费且不存在相同幂等记录时返回」 | **可达**（幂等记录判定在前，顺序正确就不会被 ALREADY_APPLIED 抢先） |
| `ALREADY_APPLIED` | §6.7「再检查 Proposal 是否已经 applied（不同幂等键返回 ALREADY_APPLIED）」 | **契约已可达**；M1 mock 因判定顺序错而不可达，属实现缺陷 |

> **对 C 上一轮结论的更正记录**：我上一轮把 ALREADY_APPLIED 标为「判定顺序导致不可达」，
> 那是针对 M1 mock。@2c48579 §6.7 已经把顺序写成规范，**这一项从契约缺口移出**。

---

## 第 3 项：重复 `request_approval` 的幂等规则

**判定：规则存在但有 1 处死锁（必修）+ 3 处未明写；实现未证实 → 整体 BLOCKED。**

明文已有：§6.5 幂等作用域 `user + request_approval + idempotency_key`；
同一 Proposal 已有未终结审批 → 返回同一 `approval_id`；同一键用于别的 Proposal → `IDEMPOTENCY_CONFLICT`。

**必修 R1（死锁）**：§6.6 说「若仅 5 分钟 Token 过期而 Proposal 仍有效，Proposal 保持
`pending_approval`，**可以重新创建审批**，旧 Token 永远无效」；§6.5 说「已有**未终结审批**时
重复请求**必须返回同一个** `approval_id`」。若 `token_issued` 算未终结，Token 过期后请求审批会拿回
**同一个无 Token 的旧审批**，既不能 apply 也拿不到新 Token —— **审批死锁**。
> 建议修法：M0 明示「未终结集合 = {pending, approved, token_issued **且 Token 未过期**}」；
> Token 已过期时旧审批视为终结，允许返回**新的** `approval_id`。

其余缺口：

| 编号 | 缺口 | 建议 |
|---|---|---|
| R2 | 幂等重放返回什么没写死 | 必须返回首次响应的**完全一致快照**（含同一 `approval_url` 与 `expires_at` 原值），不能借重放顺延签发新的有效期 |
| R3 | 幂等记录保留期未决（OQ5） | 建议 ≥ Proposal TTL + Token TTL，否则重放窗口小于过期窗口，幂等形同虚设 |
| R4 | 并发不同键同时建审批 | 需 `(user, proposal)` 非终结态唯一约束，否则同一 Proposal 会出现两个有效审批 |

---

## 第 4 项：同幂等键重放与换键重复 apply 的判定顺序

**判定：静态结论 —— 顺序已写死且正确，定义闭合。**

§6.7 规定顺序：① 幂等作用域既有记录（同摘要重放 / 不同摘要 `IDEMPOTENCY_CONFLICT`）
→ ② Proposal 是否已 applied（换键 → `ALREADY_APPLIED`）→ ③ Proposal TTL
→ ④ `base_version` → ⑤ Token。且「以上均为零写入」。
摘要里不得写入 Token 本体或前缀 ✅（§6.7），这点我特意核对过。

唯一的洞：见第 7 项 —— **换键时如果 Proposal 停在 `applying`/`readback_pending`，②查不到 applied，会继续往下走到 Token 校验并可能二次写入。**

---

## 第 5 项：Proposal 30 分钟、Token 5 分钟边界

**判定：静态结论 —— 数值规则清楚，边界口径缺 3 条。**

已有：Proposal TTL 生成后固定 30 分钟、服务端不得接受客户端延长（§5.7）；
Token TTL 签发后 5 分钟且 `token_expires_at` 不得晚于 Proposal `expires_at`（§6.6、§7.1）。

| 编号 | 缺口 | 建议口径 |
|---|---|---|
| T1 | `now >= expires_at` 还是 `>` 判过期 | 一律 **`>=`（到达即过期）**。这正是我 10-31 在 M2 里修掉的同款 bug（`isPast` 精确型截止 `now == dueAt` 漏判），两侧用同一口径，边界用例才不会出现 impl 分歧 |
| T2 | Proposal 剩余不足 5 分钟时怎么签 Token | 显式规定 `token_expires_at = min(now + 5min, proposal.expires_at)`；若 `min <= now` 则**拒签**（返回 APPROVAL_REQUIRED 或等价），不签发有效期为 0 的 Token |
| T3 | 时钟源 | 进入 `applying` **之前**完成 TTL 校验；一旦进入写入事务，禁止以 TTL 为由中断，避免「写一半被判过期」。TT 判定应使用服务端单调时钟，不能每次取 `now()` 重算对比不同源 |

---

## 第 6 项：版本冲突是否保证零写入

**判定：条款承诺零写入 ✅，但证据链 BLOCKED。**

- §6.7：apply 前核验「当前快照仍等于 `base_version`」，版本变化返回 `SNAPSHOT_CONFLICT`，「以上均为零写入」。
- §5.7：基础数据版本变化即使发生在 30 分钟内也必须返回 `SNAPSHOT_CONFLICT`。
- daily_override 唯一键冲突也走 `SNAPSHOT_CONFLICT` 且零写入 ✅。

**但 §7.2 明写 `base_version` 当前 BLOCKED**：「名前没有已证实的跨表原子快照版本……不得宣称版本冲突防护完成」，
且 Task 3 在确定服务端事务和版本算法前保持 `WRITE_BLOCKED`。
→ **M3 不能把这一项标成通过**，现在能给的是"条款正确"而不是"行为已证"。

**M2 侧**：不构造 `base_version`/`snapshot_ref`/`input_digest`（测试断言三者中后两为 null），
不参与也不干扰服务端版本判定。

---

## 第 7 项：`readback_pending` 是否只允许回读、禁止重写

**判定：同幂等键路径闭合 ✅；换幂等键路径是**本轮最严重的缺口**。**

已有：§5.7「只能用同一幂等请求继续回读，不能再次写入」；§6.7「同一幂等键重试只能重新回读/核验，不能再次写入」；§4.1 `READBACK_PENDING` 503。

**必修 X1**：换一个新的幂等键、对同一个处于 `applying`/`readback_pending` 的 Proposal 调 apply，
按 §6.7 的判定顺序会走到：① 无幂等记录 → ② 查询是否已 applied → **否**（还没到 applied）
→ ③④⑤ TTL/版本/Token 校验（Token 是一次性的，若尚未标记为 consumed 则可能通过）→ **二次写入**。
> 建议修法：②之前插入一条 —— **Proposal 处于 `applying` 或 `readback_pending` 时，不论幂等键是否相同，
> 一律返回 `READBACK_PENDING`(503) 且零写入。** 这条不补，C 的「写入次数」判定项就有一条假成功。

其余：幂等恢复后须有 `readback_pending → applied` 迁移（第 1 项 G3）；
`readback_pending` 的恢复流程本身在 OQ5 未决。

---

## 第 8 项：单次事项旧 `scheduled_at` 冲突防护

**判定：已自有证据（M2 侧新增可执行守卫）+ 条款清楚。**

§5.7 定义：`scheduled_at` 省略=保留现值 / null=清除现值 / 带偏移 instant=设定；
保留后的值与新 `planned_date` 不同上海本地日 → `PROPOSAL_INVALID`，不得出现
「写入成功但有效计划日期仍来自旧 `scheduled_at`」的假成功。

**M2 侧 eliminates 这条路径**：`_buildChanges` 对 `schedule_one_time` **永远显式给出** `scheduled_at`，
且它取 block 的 `start_at`、`planned_date` 取同一本地日 —— 从不走"保留现值"分支。
新增守卫用例：`冻结目标守卫 · 单次事项必须显式带与 planned_date 同日的 scheduled_at`。

剩余风险归服务端：

- M2 显式写 `scheduled_at` 之后，「写入前现值已被并发改过」只能靠 `base_version`/`input_digest` 察觉（BLOCKED）；
- `planned_date >= available_from` 的校验（§5.7）服务端尚未实现，M2 只在 `earliestStartAt` 侧做了排程避让，
  **不等价于写入时的校验**，请勿把两者当成同一件事。

---

## 第 9 项：daily override 唯一键冲突及完整回读字段

**判定：条款正确 ✅；M2 侧新增可执行守卫；2 处待补。**

已有：`user + item_type + item_id + local_date` 唯一（§5.7）；快照后出现新记录或
`existing_override_id` 不一致 → `SNAPSHOT_CONFLICT` 且零写入，不得用另一个 `override_id` 建重复记录；
§6.7 回读必须核验 `override_id / item_type / item_id / local_date / action / planned_start_minute / planned_end_minute`。

**M2 侧新增守卫**（`冻结目标守卫 · 单日例外变更字段齐全、分钟合法，且同一唯一键在提案内只出现一次`）：

- 七字段齐全（缺一会导致回读必然失败）；
- `item_type` 只能是 `recurring`/`one_time`（**不允许借单日例外改课程**）；
- `action` 恒 `reschedule`；`0 <= start < 1440`，`end > start` 且 `<= 1440`；
- 同一 `(item_type, item_id, local_date)` 在一个提案内唯一（对应服务端唯一键：提案侧先保证不重复，
  服务端的 `SNAPSHOT_CONFLICT` 就只会被**并发**触发而不是被 M2 的重复 changes 触发）；
- **`existing_override_id` 恒为 null**——模型不得猜测，只能由可信读取服务提供（§5.7）。

待补：

| 编号 | 缺口 | 建议 |
|---|---|---|
| D1 | 回读断言里没有「记录数」 | 除七字段比对外，应断言该唯一键下**有效记录数恰为 1**，否则重复行不会被发现 |
| D2 | 回读走哪条路径未定（OQ3：本地 Repository/SyncQueue vs 受控服务端事务） | 双写路径收敛未证之前，回读结果不可作为四判定项的「数据」证据 |
| D3 | change 摘要的规范化形式未定义 | §6.7 要求对白名单 change 生成摘要，`scheduled_at` 省略/null/有值三种形态必须规范化后才能比较 |

---

## 第 10 项：所有用例继续按「错误码 + 状态 + 数据 + 写入次数」验收

见 `acceptance-matrix-m2.md` 的最新表二。M2 能出的仍是其中两项：

| 判定项 | M2 出的依据 |
|---|---|
| 响应码 | 不属 M2（归 M0/M1 服务端） |
| 状态 | M2 proposal 恒 `draft`（纯度 + 测试锁定），服务端不得由模型构造终态 |
| 数据 | blocks/changes/unplanned_tasks/explanations 形状与枚举全部有测试；本轮新增 change 层字段与分钟合法性断言 |
| **写入次数** | **`expect(changes.length) == 期望写入次数`**：每个 block 恰一条白名单 change、change_id 唯一、`(item_type,item_id,local_date)` 与 `(task_id,planned_date)` 在提案内不重复 —— 期望写入次数可从提案直接推算，不必先执行才知道 |

---

## 本轮 M2 侧改动（全部有测试）

| 改动 | 测试名 |
|---|---|
| 新增：单次事项 change 必带同本地日 `scheduled_at` | `冻结目标守卫 · 单次事项必须显式带与 planned_date 同日的 scheduled_at` |
| 新增：单日例外 change 字段齐全 + 分钟合法 + 唯一键唯一 + 不猜 `existing_override_id` | `冻结目标守卫 · 单日例外变更字段齐全、分钟合法，且同一唯一键在提案内只出现一次` |

**测试：28/28 通过**，隔离验证工程 `E:\m2-verify`，Dart VM 通道（`dart test`）。
宿主工程 `flutter test` 仍因本机缺 Windows 开发人员模式**没有复跑**，与 §8 记录保持一致，不作通过陈述。

## 需要 M0 回答的 4 个问题

1. 「未终结审批」的精确定义 —— 修第 3 项 R1 死锁（**必修**）。
2. Proposal 处于 `applying`/`readback_pending` 时换幂等键是否一律零写入（**必修**，第 7 项 X1）。
3. 过期判定用 `>=` 还是 `>`；`token_expires_at` 截断算法与时钟源（第 5 项 T1–T3）。
4. Approval 迁移图与 Proposal×Approval 组合状态表是否补进 §5.7（第 1 项 G1/G5）。
