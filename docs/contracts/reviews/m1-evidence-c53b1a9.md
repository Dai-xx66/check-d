# M1 证据 · 契约 c53b1a9

基准：`c53b1a91c17cd9acdee6d3937c093fcf97515ba0`（PR #4）
核心 12/12；EX 20/20；环境 Windows / Python 3.14.3 / MCP stdio

> 与 2c48579 及 26/26 证据分开统计；WorkBuddy 实机另见 `m1-workbuddy-live.md`。

## 核心

| 用例 | 预期 | 实际 | 结论 | 说明 |
|---|---|---|---|---|
| C1 tools/list 与 examples 的 7 工具一致 | ['list_tasks', 'get_calendar_events', 'generate_schedule', 'validate_schedule', 'request_approval', 'get_approval_status', 'apply_approved_changes'] | ['list_tasks', 'get_calendar_events', 'generate_schedule', 'validate_schedule', 'apply_approved_changes', 'request_approval', 'get_approval_status'] | ✅ |  |
| C2 explanations 属七码闭集 | ['ALREADY_DONE_TODAY', 'AVAILABILITY_SATURATED', 'ESTIMATED_DURATION', 'FIXED_BLOCKS_OVERLAP', 'NO_AVAILABILITY_WINDOW', 'PRESERVED_FIXED_EVENTS', 'SCHEDULED'] | ['PRESERVED_FIXED_EVENTS', 'SCHEDULED'] | ✅ |  |
| C3 响应信封字段 | envelope | ['api_version', 'data', 'request_id', 'status', 'trace_id'] | ✅ |  |
| R1-1 Token 过期 → APPROVAL_EXPIRED 且零写入 | APPROVAL_EXPIRED, writes 0 | APPROVAL_EXPIRED, writes=0 | ✅ |  |
| R1-2 旧 Approval 终结后新 approval_id | new id | appr_0018->appr_0019 | ✅ |  |
| R1-3 新 Token 成功应用 | success | success | ✅ |  |
| X1-a 首次写入 → READBACK_PENDING | READBACK_PENDING | READBACK_PENDING | ✅ |  |
| X1-1 新幂等键 → READBACK_PENDING 且零写入 | READBACK_PENDING, writes 0 | READBACK_PENDING, writes=0 | ✅ |  |
| T1 跨 Proposal 错绑 Token → APPROVAL_UNTRUSTED | APPROVAL_UNTRUSTED | APPROVAL_UNTRUSTED | ✅ |  |
| T2 failed+已消费 → APPROVAL_CONSUMED | APPROVAL_CONSUMED | PROPOSAL_INVALID -> APPROVAL_CONSUMED | ✅ |  |
| T3 applying 同键 → IDEMPOTENCY_IN_PROGRESS(retryable) | IDEMPOTENCY_IN_PROGRESS retryable | READBACK_PENDING -> IDEMPOTENCY_IN_PROGRESS retryable=True | ✅ |  |
| ORD-1 已应用 + 新键 → ALREADY_APPLIED | ALREADY_APPLIED | ALREADY_APPLIED | ✅ |  |

## examples 回放

| ID | 名称 | 结果 | 说明 |
|---|---|---|---|
| EX-01 | list_tasks_with_recurring_and_one_time | ✅ pass | keys match=True; mock tasks=4 vs example=2 (fixture differs) |
| EX-02 | get_calendar_with_course_and_unexpected_meeting | ✅ pass | keys=['courses', 'daily_overrides', 'events', 'query_version'] events=1 |
| EX-03 | empty_task_list_is_success | ✅ pass | empty tasks |
| EX-04 | empty_calendar_is_success | ✅ pass | empty calendar |
| EX-05 | unauthorized_request | ✅ pass | code=AUTH_REQUIRED |
| EX-06 | generate_schedule_proposal | ✅ pass | draft |
| EX-07 | validate_schedule_pending_approval | ✅ pass | valid |
| EX-08 | request_approval_creates_pending_only | ✅ pass | pending only |
| EX-09 | get_approval_status_pending_without_token | ✅ pass | pending |
| EX-10 | get_approval_status_first_approved_delivery | ✅ pass | approved+token |
| EX-11 | get_approval_status_after_token_was_issued | ✅ pass | token_issued |
| EX-12 | apply_while_external_approval_is_pending | ✅ pass | code=APPROVAL_PENDING |
| EX-13 | apply_approved_changes_success | ✅ pass | readback ok |
| EX-14 | same_idempotency_key_replays_original_result | ✅ pass | same result |
| EX-15 | already_applied_with_new_idempotency_key | ✅ pass | code=ALREADY_APPLIED |
| EX-16 | proposal_expired_before_approval | ✅ pass | code=PROPOSAL_EXPIRED |
| EX-17 | consumed_token_cannot_authorize_another_apply | ✅ pass | code=APPROVAL_CONSUMED |
| EX-18 | approval_token_expired_before_apply | ✅ pass | code=APPROVAL_EXPIRED |
| EX-19 | base_version_changed_before_apply | ✅ pass | code=SNAPSHOT_CONFLICT |
| EX-20 | write_may_have_succeeded_but_readback_is_pending | ✅ pass | code=READBACK_PENDING |