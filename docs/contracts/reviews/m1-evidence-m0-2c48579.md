# M1 增量证据 · 契约 2c48579

基准：`agent-api-v1.md` + `agent-api-v1.examples.json` @ `2c48579a6f0ab2b9181a9246f893c1c0a8dce7c6`
核心用例：**13/13**；EX 回放：**19/20 通过**（不可执行 1）

> 本文件独立统计，不并入原 26/26 基线（`m1-evidence.md` 保持历史）。

## 复现

```bash
python tools/m1-mock/run_evidence_m0.py
```

- 环境：Windows / Python 3.14.3 / MCP stdio

## 核心用例

| 用例 | 预期 | 实际 | 结论 | 说明 |
|---|---|---|---|---|
| P1 Proposal 不暴露内部 DTO 字段 | no internal fields | leaked=[] | ✅ |  |
| P2 Proposal 必填字段齐全 | all required fields | missing=[] | ✅ |  |
| E1 explanations 为对象数组且 code 有值 | objects with code+message | codes=['PRESERVED_FIXED_EVENTS'] | ✅ | 枚举待 B 提供映射 |
| E2 响应信封符合 examples | api_version/request_id/trace_id/status | ['api_version', 'data', 'request_id', 'status', 'trace_id'] | ✅ |  |
| R1-1 Token 过期后 apply → APPROVAL_EXPIRED | APPROVAL_EXPIRED | APPROVAL_EXPIRED | ✅ |  |
| R1-2 Proposal 仍有效时重新审批生成新 approval_id | new approval_id | old=appr_0018 new=appr_0019 | ✅ |  |
| R1-3 旧 Token 永久失效 | APPROVAL_EXPIRED | APPROVAL_EXPIRED | ✅ |  |
| R1-4 新 Token 可成功应用 | success | None | ✅ |  |
| X1-a 首次写入进入 readback_pending | READBACK_PENDING | READBACK_PENDING | ✅ |  |
| X1-1 readback_pending + 新幂等键 → READBACK_PENDING | READBACK_PENDING | READBACK_PENDING | ✅ |  |
| X1-2 新键仍未写入（零写入保持） | READBACK_PENDING | READBACK_PENDING | ✅ | no duplicate write |
| ORD-1 已应用 + 新键 → ALREADY_APPLIED | ALREADY_APPLIED | ALREADY_APPLIED | ✅ |  |
| ORD-2 已应用优先于 Token 过期 | ALREADY_APPLIED | ALREADY_APPLIED | ✅ |  |

## examples.json 回放（EX-01–EX-20）

| ID | 示例 | 结果 | 说明 |
|---|---|---|---|
| EX-01 | list_tasks_with_recurring_and_one_time | ✅ pass | 4 tasks |
| EX-02 | get_calendar_with_course_and_unexpected_meeting | ✅ pass | 1 events |
| EX-03 | empty_task_list_is_success | ✅ pass | empty tasks |
| EX-04 | empty_calendar_is_success | ✅ pass | empty calendar |
| EX-05 | unauthorized_request | ✅ pass | code=AUTH_REQUIRED |
| EX-06 | generate_schedule_proposal | ✅ pass | draft + ttl |
| EX-07 | validate_schedule_pending_approval | ✅ pass | valid |
| EX-08 | request_approval_creates_pending_only | ✅ pass | pending only |
| EX-09 | get_approval_status_pending_without_token | ✅ pass | pending no token |
| EX-10 | get_approval_status_first_approved_delivery | ✅ pass | approved + token |
| EX-11 | get_approval_status_after_token_was_issued | ✅ pass | token_issued + null |
| EX-12 | apply_while_external_approval_is_pending | ✅ pass | code=APPROVAL_PENDING |
| EX-13 | apply_approved_changes_success | ✅ pass | readback ok |
| EX-14 | same_idempotency_key_replays_original_result | ✅ pass | same result |
| EX-15 | already_applied_with_new_idempotency_key | ✅ pass | code=ALREADY_APPLIED |
| EX-16 | proposal_expired_before_approval | ✅ pass | code=PROPOSAL_EXPIRED |
| EX-17 | consumed_token_cannot_authorize_another_apply | ⏸️ not_executable | 按 §6.5 判定顺序，已 applied 的 Proposal 先返回 ALREADY_APPLIED；APPROVAL_CONSUMED 在该状态不可达，需 M0 明确 |
| EX-18 | approval_token_expired_before_apply | ✅ pass | code=APPROVAL_EXPIRED |
| EX-19 | base_version_changed_before_apply | ✅ pass | code=SNAPSHOT_CONFLICT |
| EX-20 | write_may_have_succeeded_but_readback_is_pending | ✅ pass | code=READBACK_PENDING |

## 边界

- `explanations[].code` 枚举待 B 提供映射；当前只发出已公布的两个值，不做扩展。
- EX 回放按“场景 + 状态/错误码”比对，不比对 mock 生成的 ID 与时间。
- WorkBuddy 实机、真实 Token 签名与撤销、审批服务仍在 BLOCKED。