# B（M2）契约对齐记录：v1 CANDIDATE

> 指令来源：队长 2026-10-31「M0 已完成 v1 CANDIDATE 收口，收到固定 commit SHA 后只做一次契约对齐」。
> 对齐对象：`upstream/feat/m0-api-contract` → **`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`**（`docs/contracts/agent-api-v1.md`，PR #4）。
> 日期：2026-10-31　对齐人：B（M2）
>
> **纪律：不修改 M0 契约本体；不扩大业务实现；不宣称 WorkBuddy 或真实审批已经可用；
> 本轮不新增任何功能。**

## 零、状态：这是**预对齐**，不是最终对齐

队长 2026-10-31 @所有人已说明：「M0 已完成 v1 CANDIDATE 最终决策收口（7 工具、
`static_bearer_demo`、30 分钟 Proposal、5 分钟一次性 Token、无持久化 skip、统一状态机及错误码），
**当前修改仍在 M0 本地，待队长本人提交并发布固定 SHA**；PR #2、PR #3 暂不合并。」

所以本文的定位是：

- **收发口决策、锁定措辞、撤回我的过期建议** —— 这些现在就能做，且不依赖 SHA；
- **真正的契约对齐，要在固定 SHA 发布后重做一次**，届时只看增量，流程与判据见
  `docs/scheduler/incremental-checklist-next-sha.md`，配 `docs/scheduler/tools/contract-diff-check.sh` 一条命令出 diff。

我 `git fetch upstream` 后，`upstream/feat/m0-api-contract` 的 HEAD **仍然是 `2c48579`**，
尚未出现固定 SHA。因此本轮对齐以 `2c48579` 为对象——它是我手上唯一能拿到的、
内容与指令 1–8、10 各条完全吻合的提交。

> **收到固定 SHA 时，请发给我，我会按新 SHA 重跑一次增量检查，不会把这次的结论当作已对齐。**

本轮同时记录两个外部事实（不影响我上面的任何结论）：

- A 的 PR #3 HEAD 现在是 **`e7be8c9`**，队长的说法是"已完成 B/C 第一轮修复并有 26/26 Mock 证据，
  但仍需按新 M0 SHA 做最后一次增量对齐"。**我不重跑也不重评 PR #3**（属 M1 侧，队长明确待新 SHA）。
- **两个 26/26 不是一回事**：M1 的 26/26 是 Mock 用例数，M2 的 28/28 是纯函数用例数，
  两者不可比。汇报时不要串成一个数字。

另外：**指令第 9 项的 `PROPOSAL_NOT_APPROVABLE` 在 `2c48579` 里一次都没出现**（全文匹配 0 次），
§4.1 的错误码表仍是 20 个码。所以它当前确实是"M1 提议、M0 未采用"的状态，我按指令
把它单独做增量判断，**不写进 Schema**，详见
`docs/scheduler/reviews/proposal-not-approvable-incremental.md`。

## 一、10 条指令的逐条核对结果

| # | 指令 | 在 @2c48579 的状态 | B 的判定 | M2 侧动作 |
|---|---|---|---|---|
| 1 | 七工具进入 CANDIDATE，不再称"5 v1 + 2 candidate extension" | §6 有 6.1–6.7 共七个工具，**全文无 "candidate extension" 字样**；§10「已决策事项」写明"七个工具"不重开讨论 | ✅ 吻合 | 已在文档确认；我此前在 PR #3 评审里提的"两个审批工具应进 v1 正文"（`reviews/m1-pr3-review-b.md` 第 17 行）已被采纳，**该诉求撤回，不再作为待办** |
| 2 | Proposal TTL 固定 30 分钟，**不按当日 23:59 截断** | §5.7「自 `generated_at` 起固定有效 30 分钟；服务端不得接受客户端指定或延长该 TTL」、§7.1、§10 | ✅ 吻合 | **撤回我自己的旧建议**：`contract-review-m2.md` 原建议"30 分钟或到当日 23:59 取较早者"，已加作废注记。M2 不产出 `generated_at`/`expires_at`，无实现影响 |
| 3 | Token TTL 5 分钟，补 Mock 与过期用例；真实签名/审批服务继续 BLOCKED | §6.6（5 分钟、不得晚于 `proposal.expires_at`）、§7.1 明写"Mock 只能证明协议状态流转，不得描述为生产审批" | ✅ 吻合；Mock 用例属 M1 | **不在 M2 范围**：M2 无服务端、无 Mock。我不代写，也不认领"重跑证据"里的 M1 部分 |
| 4 | Token 签发后的状态改为 `token_issued` | §6.6：`pending → approved(首次交付 Token) → token_issued → consumed`，并有 `rejected`/`expired` | ✅ 吻合 | 我的运转状态描述一直用 `token_issued`，无需改。注意：`approved` 是被**读取**消耗掉的瞬时态（详见/1 缺口 G1） |
| 5 | `explanations` 改为 `{code, message, related_task_ids?}` 对象数组 | §5.7 明文，禁止字符串与对象混用 | ✅ **上一轮已对齐** | `ScheduleNote.toJson()` 已是该形状，`冻结目标守卫 · explanations 元素结构统一` 锁定。**仍欠 M0 一个 `explanations[].code` 枚举**（上轮提的唯一阻塞项，尚未答复） |
| 6 | `reason_code` 用 M0 契约大写枚举 | §5.7 四个值 `WINDOW_INSUFFICIENT` / `PAST_DEADLINE` / `OVERLAPS_FIXED` / `NO_AVAILABILITY` | ✅ **已对齐** | `UnplannedReasonCode` 输出即这四个大写值，`冻结目标守卫 · reason_code 取值必须落在封闭枚举内` 锁定 |
| 7 | 保留 `APPROVAL_CONSUMED`；同一**已应用** Proposal 换键**优先**返回 `ALREADY_APPLIED` | §4.1 两个码都在；§6.7 判定顺序：①幂等记录 → ②**是否已 applied（换键 → ALREADY_APPLIED）** → ③Proposal TTL → ④`base_version` → ⑤Token | ✅ 吻合 | 条款顺序正确，我在复审层面确认「② 必须早于 ⑤」。但仍有上轮提的 **X1**： Proposal 处于 `applying`/`readback_pending`（尚未 applied）时换键未定义 → 那条会漏到二次写入，本指令没覆盖它，建议一并处理 |
| 8 | `READBACK_PENDING` 与 `READBACK_MISMATCH` 分开测 | §4.1 两码分列，前者 503（未知可否写入）、后者 502（已确认不一致，不得返回成功） | ✅ 契约已分开 | 已给 Acceptance 矩阵补 `READBACK_MISMATCH` 一行（原表只有 `readback_pending`） |
| 9 | `PROPOSAL_NOT_APPROVABLE`：M1 提议、M0 未采用；补独立可达测试并交 B/C 增量判断，**不写入最终 Schema** | **全文 0 次**，不在 §4.1 | ⚠️ 按指令处理 | 见专项文档。**未在我方 DTO 增加任何字段或枚举** |
| 10 | 重新生成 `tools.candidate.json` 并重跑证据；旧 26/26 保留历史 | 上游契约分支无该文件；本仓库也不存在（全盘搜索无 `tools*.json`） | ⚠️ 不在我地盘 | 该文件属 M1 产物，**我不代为生成、不代为重跑**。M2 侧自有证据见下 |

## 二、M2 侧的自有证据（本轮状态）

- **28/28 通过**（`E:\m2-verify`，Dart VM + `dart test` 通道），与上轮一致，**本轮没有新增功能，因此也没有新增测试**。
- 宿主工程 `flutter test` 因本机缺 Windows 开发人员模式**仍未复跑**，不做替它声称通过。
- 「旧 26/26 保留为历史结果」——我遵照执行：`docs/scheduler/algorithm-and-license.md` §8 里
  18/18、22/22、26/26 各轮记录原样保留，新增一节记 28/28，不改写历史数字。
- M2 侧不产出 `tools.candidate.json`，也不在其中声明任何工具；七个工具的 JSON Schema 完全是 M0/M1 产物。

## 三、本轮实际改动的文件

| 文件 | 改动 |
|---|---|
| `docs/scheduler/contract-review-m2.md` | 撤回"到当日 23:59 截断"的旧建议并注明作废理由 |
| `docs/scheduler/reviews/proposal-not-approvable-incremental.md` | 新增：第 9 项的 B 侧增量判断 + 独立可达测试输入（不写 Schema） |
| `docs/scheduler/acceptance-matrix-m2.md` | 补 `READBACK_MISMATCH`、`PROPOSAL_NOT_APPROVABLE` 两行；更新七工具措辞一栏 |
| `docs/scheduler/reviews/m1-pr3-review-b.md` | **不改动**（历史留档，其中的"应进 v1 正文"诉求已被采纳，留档即证据） |
| `docs/scheduler/incremental-checklist-next-sha.md` | 新增：固定 SHA 到手后只看的 8 项 + 5 条代码红线 + 3 件"明确不做" |
| `docs/scheduler/tools/contract-diff-check.sh` | 新增：只读 diff 助手，一条命令输出六组增量（已用 `2c48579` 自反验证为空、用 `503210c` 验证能检出 6 个错误码与 3 个工具的增量） |

**未改动**：`lib/features/agent_scheduler/domain/*`、`test/agent_scheduler_test.dart`
（本轮是纯文档对齐，代码一行没动，也没有新增功能）。
`git diff -- lib test` 为空，可以当场核。

## 四、仍然挂着、需要队长或 M0 答复的事

1. **固定 SHA 是不是 `2c48579`**（第一节）。
2. `explanations[].code` 的枚举（上轮提的唯一阻塞项，至今无答复）。
3. 上一轮状态机复审里的两条必修缺口：**R1**（`request_approval` 幂等与 Token 过期重走的死锁）、
   **X1**（`applying`/`readback_pending` 换幂等键可能二次写入）。第 7 条指令只规定了
   "已 applied 的 Proposal"，X1 描述的是"还没走到 applied"的那一段，两者不重叠。
4. `PROPOSAL_NOT_APPROVABLE` 是否采纳（见专项文档，建议**采纳但窄化**）。
