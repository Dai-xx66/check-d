# C（M3 / Evaluation）增量复核 — M0 新基准 `c53b1a9`

- **当前唯一基准**：`c53b1a91c17cd9acdee6d3937c093fcf97515ba0`（`feat/m0-api-contract`，PR `Dai-xx66/check-d#4`，author date `2026-10-31T15:24:10Z`，2 files changed）
- **历史基准**：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`（自本文件起降级为历史证据，不再作为现行契约）
- **审查人**：C（Evaluation / M3）　**日期**：2026-10-31 23:55（北京时间）
- **触发**：M0 邮件《[CheckD][M3] M0 新 SHA 已发布｜状态机与零写入证据增量验收》15:27Z
- **范围**：仅新增/变化条款；不重跑历史全量审计

## 0. 纪律声明

| 项 | 本轮是否做了 |
|---|---|
| 修改 M0 契约本体 | **否**。两份契约文件一字节未动，未提交到 `feat/m0-api-contract` |
| 执行 commit / push / merge | **否**。按 M0 邮件「不执行 commit/push/merge」边界，本文件仅落地本地，等用户确认后走 PR #1 |
| 新增实测证据 | **否**。新基准尚无任何实现/Mock 对应，本轮**零实测**，全部 E0 静态 |
| 解除 BLOCKED | **否**。真实鉴权、可信审批意图、Token 签名与并发锁、原子写入、生产回读仍 BLOCKED |
| 重跑 EX 回放 | **否**。EX 证据对应旧契约 `2c48579`/`8a218020`，编号需重映射，见 §5 |

## 0.1 固定文件指纹（可独立验证）

| 文件 | Git blob | 字节 | SHA-256 |
|---|---|---:|---|
| `docs/contracts/agent-api-v1.md` | `2073f7565a5e5dbcc9739cb6009301c1220479b8` | 46576 | `4330020e55fb9608ed9c7e631cb9451a67ea028a2316e982c2c70edf142e4992` |
| `docs/contracts/agent-api-v1.examples.json` | `f9c916c824fc67b6b22fedc21cf425e1a67e40e2` | 55300 | `335d1444ece8825a8eb52960e8d79016ea4fc9939907f5ed09dccd4e61c8b935` |

对照旧基准：md `42274a2e…`/36798B、examples `cc0832e4…`/23813B
→ md **+9778B（+26.6%）**、examples **+31487B（+132.2%）**、示例 23→45 条。

> **对 M0「只做增量复核」提法的校正**：正文四分之一、示例翻倍，且 §6.7 判定顺序由 3 步重写为 6 步、
> §5.7 新增状态机图与三条收敛路径。这不是补丁级改动，T 矩阵的**可达性列必须整列重判**，
> 不能沿用「只加几条用例」的增量口径。

## 1. 变化面清单（相对 `2c48579`）

| 位置 | 变化 | 对 C 的影响 |
|---|---|---|
| §4.1 | 错误码 20 → **21**（新增 `IDEMPOTENCY_IN_PROGRESS`，409 且 `retryable=true`） | 错误码可判数重算 |
| §4.1 L165 | `READBACK_PENDING` 详情**强制** `proposal_status=readback_pending` | 与 §6.7 L703 冲突，见 B20 |
| §5.2 L218-223 | 两个内部调度 Fixture 固定：`=0` 不生成 block/不入 `unplanned`/只给 `ALREADY_DONE_TODAY`；`=40`+目标 7200 → `duration_seconds=2400`、`task_target` | G1/G2 由「推断」升为**可判**；G3（null→完整目标）可判 |
| §5.7 | Proposal 8 态 + 状态机图 + 三条 `readback_pending` 收敛；`explanations` **7 值闭集**（含 `ALREADY_DONE_TODAY`）；`violations` **7 值闭集**（§5.8） | N1/N5 闭合；G1/G4 可断言 `explanations` |
| §6.4 L521 | `approval_status` 双域 → 改名 `approval_readiness`（`not_requested`/`not_approvable`），只表达「能否进入审批」 | B17 闭合 |
| §6.5 L562 | 一个 Proposal 最多一个有效 Approval；校验态 `pending/approved/token_issued`、终结态 `consumed/rejected/expired`；Token 过期但 Proposal 有效 → 旧 Approval `expired`、可新建 `approval_id`、旧 Token 永久无效 | R1 需重写：新增「用户明确要求」前置 + 旧 Approval 必须已终结 |
| §6.5 L570 | Token 交付不确定 → 保留 `token_issued`，Agent 不得推断丢失、不得撤销/替换/重签，等自然过期 | 支持 M0 第 2 项，删除「主动替换 Token」假设 |
| §6.6 | Approval 6 态迁移图 + 并发 `get_approval_status` 必须原子认领（最多一个请求拿到非空 token） | 新增可判点：并发交付唯一性 |
| §6.7 L658 | 成功 `data` 新增 `recovery_evidence`（`operation=readback_only`、`business_write_count_delta=0`、`second_apply_executed=false`） | W4 有了契约级字段 |
| §6.7 L681-706 | 判定顺序 3 → **6 步**；步骤 4 处理 `applying/readback_pending/applied/rejected/expired/failed`；L703 新键 + 非终态 → `READBACK_PENDING` 零写入 | **B18 契约层闭合**、X1 可判 |
| §6.7 L725 | `APPROVAL_UNTRUSTED` 五类触发条件明文；撤回批准走 `APPROVAL_REJECTED` | P1-2 闭合 |

## 2. 已闭合（C 侧判定，全部 E0 静态）

| 编号 | 原问题 | 闭合证据 |
|---|---|---|
| **B16** | `READBACK_MISMATCH` 后终态未定义 | §6.7「Proposal 转为终态 `failed`，不允许再次写入」+ 示例 25/45 均给 `proposal_status=failed` |
| **B17** | `approval_status` 同名双域 | §6.4 L521 改名 `approval_readiness`；`approval_status` 全文仅作为工具名出现 |
| **B18（P0）** | 非终态 + 新幂等键契约真空 | §6.7 L703 明文「新键但 `applying`/`readback_pending` → 统一 `READBACK_PENDING`、零写入」；步骤 4 先处理收敛语义；示例 21（readback_pending）、31（applying）给出可观察形状 |
| **P1-1** | `APPROVAL_CONSUMED` 不可达 | 步骤 5（同 Proposal 已消费且未 applied → `CONSUMED`）+ 「已消费 Token 但未成功应用」独立路径 + 示例 33（failed+consumed） |
| **P1-2** | `APPROVAL_UNTRUSTED` 零触发条件 | §6.7 L725 五类明文；示例 17（跨 Proposal 绑定不符）、24 |
| **N1/N5** | `ALREADY_DONE_TODAY` 契约 0 次出现 | 进入 §5.7 `explanations` 7 值闭集；§5.2 L222 明文 `=0` 只产生该 explanation |
| **B19（部分）** | `remaining_minutes_today=0` 语义 | L221 明文「不生成 block、不进入 `unplanned_tasks`、不得进入最低时长兜底」；**仍未闭合**：非 0 值是否为上限、`20 < minimum_block_minutes` 的窗口（G5）仍无明文 → G5 维持推断 |

> B18 由 P0 降级为**契约层闭合**的前提：本判定只证明文本已给出唯一解，不证明 A/M1 实现可达。
> 实现侧仍须跑 X1 + 示例 21/31 对应路径，证据等级上限 E1，M1 现无 `c53b1a9` 对应实现。

## 3. 本轮新发现

### B20（P1，契约内部硬冲突，机检可判）

- §4.1 L165：「`READBACK_PENDING` 的错误详情**必须**包含 `proposal_status=readback_pending`」。
- §6.7 L703：「新键但 Proposal 为 `applying` 或 `readback_pending`：统一返回 `READBACK_PENDING`」。
- 示例 31 `new_idempotency_key_while_applying_returns_readback_pending`：`server_fixture.proposal_status="applying"`，错误详情 `proposal_status.reason="applying"`。

→ 同一响应码在合法路径下**不可能**同时满足「必须是 readback_pending」。要么 §4.1 放宽为
`proposal_status ∈ {applying, readback_pending}`，要么 `applying` 分支另给码（不建议：会破坏「零写入」统一语义）。
**验收影响**：断言脚本若按 §4.1 硬校验，示例 31 会被判失败；矩阵不能同时引这两处。

### B21（P2，零写入证据形状不对称）

`readback_pending → applied` 用 `data.recovery_evidence{operation,business_write_count_delta,second_apply_executed}`（示例 44）；
`readback_pending → failed` 把同三字段塞进 `error.details`（示例 45），没有 `recovery_evidence` 对象。
W4 断言必须写两套解析分支；建议 failed 分支也返回 `recovery_evidence`。

### B22（P2，`failed` 终态缺凭据时无码）

§6.7 步骤 4 把 `failed` 列为终态先处理，但只规定「`failed` 且携带**同 Proposal 已消费** Token → `APPROVAL_CONSUMED`」。
`failed` + 未提供 Token / Token 属他 Proposal 时的响应码未定义（`APPROVAL_REQUIRED`? `APPROVAL_UNTRUSTED`? 终态专用码?）。
示例 33 只覆盖「带已消费 Token」这一支。

### B23（P2，步骤 3 与步骤 4 的优先级未声明）

判定顺序把「验证幂等作用域和摘要」放在「检查 Proposal 状态」之前。
对已 `applied` 的 Proposal 用**同键不同摘要**：按步骤 3 → `IDEMPOTENCY_CONFLICT`；按 §6.7 末段「换键也不能再次应用」→ `ALREADY_APPLIED`。
两者都零写入，但响应码不同、都 `retryable=false`，验收会判成两种结果。需一句优先级声明。

## 4. 示例覆盖（45 条 / 21 码）

- 结构：`7` 工具、`4` 内部 Fixture、`45` 远程示例 —— 与 M0 邮件自述一致，**实测相符**。
- 错误码覆盖 **17/21**；无示例：`INVALID_ARGUMENT`、`DEPENDENCY_UNAVAILABLE`、`WRITE_BLOCKED`、`INTERNAL_ERROR`。
  其中 `WRITE_BLOCKED`（无法证明原子性）是 v1 唯一「拒绝写入」的总闸，缺示例会让 M1 的实现只要抛 503 任意码就可能"看起来对"。
- 枚举越界：**0**（错误码 / violation code / explanation code / reason_code 全部落在正文闭集内）。
- 三条 `readback_pending` 收敛路径均有示例：→`applied`(44)、→`failed`(45)、→`readback_pending`(34)；
  零写入断言字段齐全（`business_write_count_delta=0`、`operation=readback_only`）。

## 5. 对验收矩阵的影响（下一轮执行清单）

1. **T 矩阵可达性整列重判**：§6.7 由 3 步变 6 步，T01/T02/T03-a/T03-b/T08/T16/T19–T22 的顺序依赖全部要按新步骤重排。
2. **B18 相关**：T16 从「不可判」→「可判」，`X1` 可直接引用示例 21/31 作为形状基准；仍需实现侧 W4 查库。
3. **R1 重写**：原「Token 过期即重建换 `approval_id`」升级为「旧 Approval 必须终结 + 用户明确要求重审」；后者属可信意图验证 → 标 BLOCKED，只有状态机部分可判。
4. **S1 保留**：仍只认服务端完整 Schema；示例 44/45 的 `recovery_evidence` 归入「必须由服务端返回」，M2 DTO 解析不算证据。
5. **EX 编号重映射**：EX-01..20 对应旧契约示例集，`c53b1a9` 示例由 23 → 45，需按名重挂；已有 7 条 PASS(E1) 不因新契约失效，但不能再声称覆盖新示例。
6. **B20 未定前**：涉及 `READBACK_PENDING` 详情的断言先写「容忍两种状态值」，不要写死 `readback_pending`。

## 6. 仍 BLOCKED（不因新契约解除）

WorkBuddy 工具协议与可信用户确认信号、真实 SSO/OAuth、HTTPS 托管、可信 `base_version` 与事务内比较、
`snapshot_ref` 存储与摘要算法、审批凭据签发者与确认通道、Supabase migration/RLS、原子写入、Drift 收敛、生产回读。
→ 任何 Mock 全绿最高只到 **E1**；本轮全部结论为 **E0**。

## 7. 待 M0 决策（压缩为字段 + 触发条件 + 可观察证据）

| # | 问题 | 触发条件 | 可观察证据 |
|---|---|---|---|
| 1 | B20：`READBACK_PENDING` 详情允许的状态集合 | 新键 + `applying` | 示例 31 的 `error.details[proposal_status]` |
| 2 | B21：failed 分支是否也返回 `recovery_evidence` | `readback_pending` → 权威回读不一致 | 示例 45 顶层 `data/error` 是否出现该对象 |
| 3 | B22：`failed` 终态 + 无有效凭据的码 | Proposal `failed`，Token 缺失/他提案 | 响应 `error.code` |
| 4 | B23：步骤 3 与步骤 4 优先级 | Proposal `applied` + 同键不同摘要 | `IDEMPOTENCY_CONFLICT` vs `ALREADY_APPLIED` |
| 5 | 4 个错误码补示例（优先 `WRITE_BLOCKED`） | — | `examples[].name` 是否出现对应 `error.code` |
