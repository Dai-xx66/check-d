# C（M3 / Evaluation）增量审查结果 — M0 Task 1 契约固定基准

- **固定基准**：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`
- **分支**：`feat/m0-api-contract`　**PR**：M0-1（`Dai-xx66/check-d#4`）
- **基准文件**：`docs/contracts/agent-api-v1.md`、`docs/contracts/agent-api-v1.examples.json`
- **审查人**：C（Evaluation / M3）　**日期**：2026-10-31
- **范围**：错误码、审批状态、过期语义、回读失败验收用例对齐（C 分工项）

## 0. 纪律声明

| 项 | 本轮是否做了 |
|---|---|
| 修改 M0 契约本体 | **否**。未改动 `docs/contracts/` 任何文件，未提交到 `feat/m0-api-contract` |
| 重新进行完整审计 | **否**。该 SHA 已于同日上午做过一次增量复审（`2026-10-31-m0-final-2c48579-incremental-M3.md`），本轮只做 C 口径的用例对齐 |
| 扩大功能范围 | **否**。仅新增/拆分验收用例，未提出新工具、新字段、新能力 |
| 新增实测证据 | **否**。仓库内 Mock 对应旧契约（`e7be8c9`），对 `2c48579` 无可用实现，本轮**零实测** |
| 解除 BLOCKED | **否**。WorkBuddy 真实认证、可信审批、原子写入、生产回读仍 BLOCKED |

> 结论定位：**以 `2c48579` 为基准，C 侧同意进入冻结前最后一步**；剩余 7 项均为纯文档缺口（B5–B7、B11、B12、B16、B17），不依赖任何 BLOCKED 能力即可关闭。

## 0.1 固定文件指纹（可独立验证）

任何人拿到 `2c48579` 都可以用下列值与 Git blob 比对，确认审的就是这两份文件、且内容未漂移。

| 文件 | Git blob | 字节 | SHA-256 |
|---|---|---:|---|
| `docs/contracts/agent-api-v1.md` | `42274a2e682674158fe2a8a4162997b7b40e8116` | 36798 | `05a87d7a335b618c7ec222531f9d94bbd5f915ec0792355cff31c6d240ab3177` |
| `docs/contracts/agent-api-v1.examples.json` | `cc0832e4c3014ccdbdf2c675895b34d2ed236275` | 23813 | `db6a774687757ec26cad0c4b71b9045e66d53904c67670055bec019df6df34f0` |

校验命令（仓库根目录）：

```bash
git rev-parse 2c48579:docs/contracts/agent-api-v1.md          # 应为 42274a2e…
git show 2c48579:docs/contracts/agent-api-v1.md | sha256sum    # 应为 05a87d7a…
```

## 0.2 两份文件的机检结果（可复算，不是实测）

对 `agent-api-v1.md` 与 `agent-api-v1.examples.json` 做结构化解析，结果如下：

| 检查项 | 结果 |
|---|---|
| 示例 JSON 可解析、`examples` 数组 | 通过（20 条） |
| 请求信封字段 `api_version`/`request_id`/`timezone`/`input` 齐全 | 通过（20/20） |
| 响应信封字段 `api_version`/`request_id`/`trace_id`/`status` 齐全 | 通过（20/20） |
| 错误响应含 `code`/`message`/`retryable` | 通过（8/8） |
| 示例中的 `error.code` 均在 §4.1 表内 | 通过（8 个码，0 越界） |
| `duration_source` / `reason_code` 取值 ⊆ 契约枚举 | 通过（2 值 / 4 值） |
| 示例引用的工具 ⊆ 7 工具 | 通过 |
| §4.1 错误码表条目 / 唯一性 | 20 / 20（无重复） |
| Proposal 状态值 / Approval 状态值 | 8 / 6（与正文枚举一致） |

复算命令（脚本已入库，不依赖任何 Mock 实现，纯静态解析）：

```bash
python tools/m3-checks/check_contract_consistency.py 2c48579
# 期望输出：§4.1 错误码 20/20、Proposal 8 态、Approval 6 态、工具 7、示例 20（错误响应 8）、结构/枚举问题 0
# 退出码 0 = 无越界且结构完整；1 = 有越界或结构缺失
```

**一处疑似越界经复核为误报**：示例 `validate_schedule_pending_approval` 返回 `approval_status="not_requested"`，不在 §6.6 的 6 个审批状态内；但该值由 §6.4 明确定义，并非越界。**由此发现一个真实文档缺陷，见 B17。**

## 1. 错误码对齐（20 个）

判定口径沿用 G1：**只认"能触发"，不认"文档里有"**。

| 判定 | 数量 | 错误码 |
|---|---:|---|
| 可判（有触发条件 + 有对应用例） | **14** | `AUTH_REQUIRED`、`INVALID_ARGUMENT`、`PROPOSAL_INVALID`、`PROPOSAL_EXPIRED`、`SNAPSHOT_CONFLICT`、`APPROVAL_REQUIRED`、`APPROVAL_PENDING`、`APPROVAL_REJECTED`、`APPROVAL_EXPIRED`、`ALREADY_APPLIED`、`IDEMPOTENCY_CONFLICT`、`WRITE_BLOCKED`、`READBACK_PENDING`、`READBACK_MISMATCH` |
| 部分可判 | **2** | `DEPENDENCY_UNAVAILABLE`、`INTERNAL_ERROR`——无触发条件、无示例，只能断言"不得泄露内部细节" |
| 不可判 | **4** | `FORBIDDEN`、`NOT_FOUND`（策略未定，B7）；`APPROVAL_UNTRUSTED`（正文零触发条件，B12）；`APPROVAL_CONSUMED`（消费时点未定义，B11） |

**示例覆盖 8 / 20**，缺 12 个：`FORBIDDEN`、`INVALID_ARGUMENT`、`NOT_FOUND`、`DEPENDENCY_UNAVAILABLE`、`PROPOSAL_INVALID`、`APPROVAL_REQUIRED`、`APPROVAL_REJECTED`、`APPROVAL_UNTRUSTED`、`IDEMPOTENCY_CONFLICT`、`WRITE_BLOCKED`、`READBACK_MISMATCH`、`INTERNAL_ERROR`。

其中 **`READBACK_MISMATCH` 与 `APPROVAL_UNTRUSTED` 建议优先补**：前者是回读失败唯一终局码（T03-a 靠它判定），后者是防篡改唯一断言（T22 完全靠它）。

## 2. 审批状态对齐（6 个值）

| 状态 | 契约语义（§6.6） | 验收用例 | 可判性 |
|---|---|---|---|
| `pending` | 用户尚未决定，不返回 token | T16（创建）、T07（apply 时仍 pending → `APPROVAL_PENDING`） | 可判 |
| `approved` | 外部确认通过，仅首次安全交付返回 token | T16、T19 | 可判 |
| `token_issued` | 已签发未消费，后续轮询 `approval_token=null` | T19（轮询）、T21（并发交付） | T19 可判；T21 部分（原子性未声明，B13） |
| `consumed` | Token 已成功消费 | T18 | **不可判**（B11） |
| `rejected` | 用户拒绝，Proposal 同步 `rejected` | T16 | 可判 |
| `expired` | 审批或 Token 过期；仅 Token 过期时 Proposal 保持 `pending_approval` | T05、T17 | 可判；T17 的重建 `approval_id` 需换新属**推断**（§6.5 幂等仅限"未终结"审批），建议明写一句 |

## 3. 过期语义对齐（三层 TTL）

| 层级 | 契约规定 | 验收用例 | 判定要点 |
|---|---|---|---|
| Proposal 30 分钟 | 自 `generated_at` 起固定 30 分钟，不得由客户端指定或延长 | T06 → `PROPOSAL_EXPIRED`（409） | 过期后 apply 与 `request_approval` 都必须拒绝，且零写入 |
| Token 5 分钟 | 自**签发**起 5 分钟，且 `token_expires_at ≤ proposal.expires_at` | T19(a) → `APPROVAL_EXPIRED`（403） | 是"签发后 5 分钟"，不是"审批创建后 5 分钟"，也不是"当天 23:59 封顶" |
| 仅 Token 过期 | Proposal 仍 `pending_approval`，可重建审批，旧 Token 永久无效 | T19(a) 的状态列 + T17 | 必须与"Proposal 也过期"可区分（错误码不同、状态不同） |

**本轮改写要点**：T19 必须同时断言 `token_expires_at - token_issued_at ≤ 300s` 与 `token_expires_at ≤ proposal.expires_at`。只断言前者会漏掉"Token 越过提案到期"这一违反项。

## 4. 回读失败对齐（本轮主要改动）

上一版把回读失败写成一条 T03，导致两种性质完全不同的情况混在一起。按 §6.7 与 §5.7 状态机，二者结论不同，**已拆为两条**：

| 情况 | 契约依据 | 响应码 | Proposal 状态 | 写入次数 | 可判性 |
|---|---|---|---|---:|---|
| 回读**完成但不一致** | §6.7「任何缺失或不一致返回 `READBACK_MISMATCH`，不得返回成功」 | `READBACK_MISMATCH`（502） | **`[待定]`** | 1（不回滚） | **部分可判**（T03-a）——状态列缺定义，B16 |
| 回读**无法给出结论**（不确定） | §6.7「写入可能已提交但回读失败 → 幂等记录标 `readback_pending`；同键只能重新回读」 | `READBACK_PENDING`（503） | `readback_pending` | 恒 1 | **可判**（T03-b） |

拆分理由：若合并成一条，实现只要"回读不一致就返回 503 + readback_pending"即可蒙过验收——而契约恰恰要求不一致必须报 502 且不得成功。拆开后 T03-b 变成"只能安全回读、不得重写"的净断言（同键重试 N 次，`override_id` 与行数均不变），这类断言在 `e7be8c9` 上已实测通过，是可信基线。

**新增缺口 B16**：`READBACK_MISMATCH` 之后 Proposal 停在哪，契约未写（停留 `applying` / `failed` / `readback_pending` 三选一）。§10 Q5 只列了"`readback_pending` 的恢复流程"，未覆盖本条。建议：**回读结论为"不一致" → `failed`**；`readback_pending` 仅限"结论不确定"。

## 5. 与上一版（同日首轮复审）的差异

| 项 | 首轮复审 | 本轮对齐后 |
|---|---|---|
| 用例编号 | T01–T22 | T01–T22（T03 拆 a/b → **23 个用例项**） |
| 可判性 | 15 可判 / 3 部分 / 4 不可判 | **16 可判 / 4 部分 / 3 不可判** |
| 回读失败覆盖 | 1 条（不可判） | 2 条（1 可判、1 部分可判） |
| 阻塞项 | B1–B15 | B1–B17（新增 B16、B17；B11 补"消费时点"缺失） |
| 契约本体 | 未改 | 未改 |
| 实测 | 无 | 无 |

## 6. 未闭合项（冻结前建议处理，均为文档级）

| 编号 | 内容 | 影响 | 建议 |
|---|---|---|---|
| B5 | `violations[]` 项结构与 `code` 枚举未定义 | T10-a/b、T11 | 定义封闭枚举；当前只有空数组示例 |
| B6 | 幂等"执行中"的响应形态未定义 | T07 | 明确阻塞 / 202 / 409+`in_progress` 三选一 |
| B7 | `FORBIDDEN` / `NOT_FOUND` 策略未定 | T09-b | v1 先统一 `NOT_FOUND` 即可解锁 |
| B11 | `APPROVAL_CONSUMED` 消费时点未定义 → 不可达 | T18、T22 | 明写"进入 `applying` 即消费"，或删码保状态 |
| B12 | `APPROVAL_UNTRUSTED` 正文零触发条件 | T22 | §6.7 五条核验逐条绑错误码（主体、绑定、未过期/未撤销/未消费、快照一致、幂等） |
| B16 | `READBACK_MISMATCH` 后终态未定义 | T03-a | 见 §4 |
| B17 | **`approval_status` 同名双域**：§6.4 的 `validate_schedule.data.approval_status` 只有 `not_requested` / `not_approvable`，与 §6.6 的 6 个审批状态**零交集**；同名不同义，客户端无法用同一套状态机解释 | 全部含 `approval_status` 的响应 | 改名（`approvability` / `approval_hint`），或在 §5 声明"两个独立枚举、不得混用" |

**已闭合（不再讨论）**：`readback_pending` 状态位与同键只回读（T01/T02/T03-b）、apply 阶段 `SNAPSHOT_CONFLICT`、`PROPOSAL_EXPIRED`、`ALREADY_APPLIED`、Token 一次性 5 分钟且不越过提案到期、`skip` 不持久化、`duration_source` 双值枚举、`scheduled_at` 省略/null/跨日三态。

**BLOCKED（不因本轮对齐解除）**：WorkBuddy 真实认证与外部确认回调、可信审批服务与 token 签名/TTL 实证、原子写入与幂等存储、生产回读、`snapshot_ref`/`base_version` 的事务内比较。

## 7. 下一步

1. **M0**：处理 B5、B6、B7、B11、B12、B16、B17（七项纯文档），发布新 commit。
2. **A**：按 `2c48579` 重建 candidate JSON 与 Mock 证据（旧 26/26 对应旧契约，不可复用）。
3. **C**：A 的新 Mock 落地后，按矩阵 §9 跑一次增量验收，回填实测列，输出冻结建议。在此之前不提交任何"已通过"结论。

---

**一句话结论**：C 侧已按 `2c48579` 完成错误码、审批状态、过期、回读失败四类验收对齐，可判用例由 15 增至 16（共 23 项）；**建议在 B5–B7、B11、B12、B16、B17 七项文档缺口关闭后冻结 v1**，七项均不依赖 BLOCKED 能力。
