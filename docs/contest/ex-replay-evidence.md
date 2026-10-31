# EX-01–EX-20 回放 · C 侧独立证据记录

- **归属**：M3 / Evaluation（同学 C）
- **对象**：M1（A）在 PR #3 head `8a2180209c` 提交的 `docs/contracts/reviews/m1-evidence-m0-2c48579.{md,json}`
- **契约基准**：`2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6` 的 `agent-api-v1.examples.json`（20 条示例）
- **建立日期**：2026-10-31
- **本文件性质**：队长本轮第 4 项要求「为 A 的 EX-01 至 EX-20 回放建立独立证据记录」。记录的是 **C 侧复核结论**，不是转述 A 的 `pass` 标记。
- **不重审**：不评价 A 的用例设计是否充分，不改 M0 契约，不重跑全量审计。

---

## 1. 复核方法

**不采信 `status: pass`**。只从证据文件里读**原始响应**，用 C 自己的断言重判；读不到响应就明确记「不可复核」，不用「A 说通过」代替。

复现：

```bash
python tools/m3-checks/verify_ex_replay.py \
  --evidence path/to/m1-evidence-m0-2c48579.json \
  --examples-ref 2c48579
```

C 侧另在本地跑过一次 A 的脚本（`python tools/m1-mock/run_evidence_m0.py`，Python 3.13 / Windows / MCP stdio），输出与其文档一致：**core 13/13、EX 19 pass / 0 fail / 1 not_executable**。这证明 A 的结论可复现，**不证明**这些结论足以支撑"示例被复现"。

### 判定五档

| 档 | 含义 | 是否算通过 |
|---|---|---|
| `PASS` | 有原始响应，四维（码/状态/数据/写入次数）吻合 | 是 |
| `SHAPE_ONLY` | 只用自有数据跑通了工具，未使用示例的 request，判定仅为"字段存在" | **否**，只能记"结构合法" |
| `UNVERIFIABLE` | 证据里只有 `status/note`，没有响应，无法复核具体值 | **否** |
| `UNBACKED` | 用例名声称了某项（如「零写入」），证据里没有任何对应字段 | **否** |
| `SKIP` | 双方一致认为当前不可执行 | 不计入分母 |

---

## 2. EX-01–EX-20 逐条记录

| ID | 示例 | A 结论 | C 判定 | 依据 |
|---|---|---|---|---|
| EX-01 | `list_tasks_with_recurring_and_one_time` | pass | **SHAPE_ONLY** | 示例 request 是 `2026-11-01~04`、响应 2 条 task；A 的 note 是「4 tasks」→ 用的是自有 fixture（`RANGE=2026-10-29~31`），未回放示例数据 |
| EX-02 | `get_calendar_with_course_and_unexpected_meeting` | pass | **SHAPE_ONLY** | 示例响应 2 条 event；note 为「1 events」→ 同样不是示例数据 |
| EX-03 | `empty_task_list_is_success` | pass | **UNVERIFIABLE** | 只有 `pass`，无响应、无可用 note 值 |
| EX-04 | `empty_calendar_is_success` | pass | **UNVERIFIABLE** | 同上 |
| EX-05 | `unauthorized_request` | pass | PASS（降级） | note `code=AUTH_REQUIRED` 与示例错误码一致；无全字段 |
| EX-06 | `generate_schedule_proposal` | pass | **UNVERIFIABLE** | 「draft + ttl」无法比对具体值 |
| EX-07 | `validate_schedule_pending_approval` | pass | **UNVERIFIABLE** | 「valid」同上 |
| EX-08 | `request_approval_creates_pending_only` | pass | **UNVERIFIABLE** | 「pending only」同上；「不得签发 token」未被取证 |
| EX-09 | `get_approval_status_pending_without_token` | pass | **UNVERIFIABLE** | 「pending no token」同上 |
| EX-10 | `get_approval_status_first_approved_delivery` | pass | **UNVERIFIABLE** | 「approved + token」同上；TTL 是否 ≤300s 未取证 |
| EX-11 | `get_approval_status_after_token_was_issued` | pass | **UNVERIFIABLE** | 「token_issued + null」同上；"不重复泄露"未被取证 |
| EX-12 | `apply_while_external_approval_is_pending` | pass | PASS（降级） | `code=APPROVAL_PENDING` 一致 |
| EX-13 | `apply_approved_changes_success` | pass | **UNVERIFIABLE** | 「readback ok」；`applied_changes` 与库中值未取证 |
| EX-14 | `same_idempotency_key_replays_original_result` | pass | **UNVERIFIABLE** | 「same result」无对照物，无法判定"相同" |
| EX-15 | `already_applied_with_new_idempotency_key` | pass | PASS（降级） | `code=ALREADY_APPLIED` 一致 |
| EX-16 | `proposal_expired_before_approval` | pass | PASS（降级） | `code=PROPOSAL_EXPIRED` 一致 |
| EX-17 | `consumed_token_cannot_authorize_another_apply` | not_executable | **SKIP** | 与 C 侧 P1-1 判断一致：§6.7 判定顺序使 `APPROVAL_CONSUMED` 在该状态不可达 |
| EX-18 | `approval_token_expired_before_apply` | pass | PASS（降级） | `code=APPROVAL_EXPIRED` 一致 |
| EX-19 | `base_version_changed_before_apply` | pass | PASS（降级） | `code=SNAPSHOT_CONFLICT` 一致 |
| EX-20 | `write_may_have_succeeded_but_readback_is_pending` | pass | PASS（降级） | `code=READBACK_PENDING` 一致；写入次数未取证 |

**统计**：`PASS`（降级比对）**7** · `SHAPE_ONLY` **2** · `UNVERIFIABLE` **10** · `SKIP` **1**。
A 自称通过 19 条，**C 可确证 7 条**，差 12 条。

> 差 12 条不代表 A 做错了。原因是**证据粒度**：EX 段只存了 `status + note`，没有响应体，所以"是形状级还是值级"无法区分，只能记不可复核。

---

## 3. core 13 条（同一证据文件，一并复核）

| 用例 | A | C | 依据 |
|---|---|---|---|
| P1 Proposal 不暴露内部 DTO 字段 | pass | PASS | `data` 无 `id/created_at/updated_at/user_id` 等字段 |
| P2 Proposal 必填字段齐全 | pass | PASS | 11 个必填字段齐全，`status=draft` 在枚举内 |
| E1 `explanations` 为对象数组且 `code` 有值 | pass | PASS | 1 项，含 `code` + `message` |
| E2 响应信封符合 examples | pass | **UNVERIFIABLE** | 该条**响应是空对象**，没有任何信封可核 |
| R1-1 Token 过期后 apply → `APPROVAL_EXPIRED` | pass | **UNBACKED** | 错误码对；但"Proposal 仍 `pending_approval`、写入 0"无任何证据字段 |
| R1-2 重新审批生成新 `approval_id` | pass | PASS | `old=appr_0018` → `new=appr_0019`，确实不同 |
| R1-3 旧 Token 永久失效 | pass | PASS | `APPROVAL_EXPIRED` |
| R1-4 新 Token 可成功应用 | pass | PASS | `status=success`、`readback_verified=true` |
| X1-a 首次写入进入 `readback_pending` | pass | PASS | `code=READBACK_PENDING`，`details` 含 `proposal.status=readback_pending` |
| X1-1 新幂等键 → `READBACK_PENDING` | pass | PASS | 同上，`details` 另含 `reuse_same_key_for_readback_only` |
| X1-2 新键仍未写入（零写入保持） | pass | **UNBACKED** | 只验了返回码；`note` 里「no duplicate write」**没有任何字段支撑**——这正是 C 口径 **W4 缺失** |
| ORD-1 已应用 + 新键 → `ALREADY_APPLIED` | pass | PASS | 错误码一致 |
| ORD-2 已应用优先于 Token 过期 | pass | PASS | 错误码一致 |

**统计**：`PASS` **10** · `UNVERIFIABLE` **1** · `UNBACKED` **2**。

---

## 4. 三条给 A 的具体请求（不涉及重做）

1. **EX 段补原始响应**：把每条 EX 的 `response`（或 `structuredContent`）一并写进 JSON。当前只有 `status + note`，20 条里有 10 条连"返回了什么"都无从判断。
2. **EX-01 明确口径**：`ex_list_tasks` 用的是固定 `RANGE`，没有用示例的 `date_range=2026-11-01~04`，所以「4 tasks」与示例的 2 条不同。若定位是"形状级回放"，请在文档里写明；若定位是"示例复现"，需要改成读示例 request。
3. **补写入次数字段**：R1-1、X1-2 的断言里含"零写入"，但证据只有错误码。按 C 口径需要 W4（查库行数/`override_id` 指纹），否则这两条只能记 `UNBACKED`。

E2 那条响应是空对象，可能是脚本录制时漏了；这一条单独补一次即可。

---

## 5. 证据级别与边界

- 本文件所有判定基于 **E1**（进程内 mock + MCP stdio，同一台机器、无真实存储），**不升格为 E2/E3**。
- A 的 EX 回放与 C 的复核**都在 mock 上**，与生产服务无关；`base_version` 真实生成、可信审批、原子写入、生产回读仍 **BLOCKED**。
- 因此本节结论只能写成「mock 上 7 条可确证、2 条形状级、10 条不可复核」，**不得**写成「19/20 通过」「示例回放通过」。
- EX-17 的"不可执行"与 C 侧 P1-1 结论一致，属契约问题（`APPROVAL_CONSUMED` 判定顺序不可达），不计入 A 的实现质量。

---

## 6. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-10-31 | 建立本记录，复核 PR #3 head `8a218020` 的 EX 段与 core 段 | 依队长本轮第 4 项；C 本地复现一次（13/13、19 pass/1 skip），随后用 `verify_ex_replay.py` 独立重判；判 PASS 7 / SHAPE_ONLY 2 / UNVERIFIABLE 10 / SKIP 1 |
