# M1 工具契约一致性测试证据

对象：`agent-api-v1.md` v1 CANDIDATE（MCP stdio mock 实现，非 WorkBuddy 实机）
结果：**26/26 通过**

## 复现命令

```bash
cd <repo>
python tools/m1-mock/export_schema.py
python tools/m1-mock/run_evidence.py
```

- 运行环境：Windows / Python 3.14.3 / MCP stdio（JSON-RPC 2.0）
- 证据文件：`docs/contracts/reviews/m1-evidence.md`、`m1-evidence.json`
- 代码提交：见文末 Commit 段

## 用例与结果

| 用例 | 预期 | 实际 | 结论 | 说明 |
|---|---|---|---|---|
| A0 tools/list | 7 tools (5 v1 + 2 candidate) | 7 tools | ✅ | ['list_tasks', 'get_calendar_events', 'generate_schedule', 'validate_schedule', 'apply_approved_changes', 'request_approval', 'get_approval_status'] |
| A1 list_tasks 正常读取 | success | success | ✅ | 4 tasks |
| A2 请求体携带 user_id 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A3 非 Asia/Shanghai 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A4 日历包含固定课程与外部会议 | success | success | ✅ | 2 events, 2 fixed |
| A5 generate_schedule：不伪造 deadline 即时、周期任务用目标时长 | no synthesized instant; recurring 3600s/task_target; exact-deadline first | has_2359=False recurring_ok=True first=t_1001 | ✅ | prop_0017 blocks=8 unplanned=0 |
| A6 远程提交 tasks 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A7 validate 通过并进入 pending_approval | success | success | ✅ | validation=valid approval=pending_approval |
| A8 未审批 apply → APPROVAL_REQUIRED | error:APPROVAL_REQUIRED | error:APPROVAL_REQUIRED | ✅ |  |
| A9 request_approval 只建 pending 请求（无 token） | pending + approval_url, no token | pending url=True | ✅ | appr_0018 |
| A10 同一 Proposal 重复 request 幂等 | same approval_id | same=True | ✅ |  |
| A11 外部确认后轮询才签发 token | approved + token | approved token=True | ✅ |  |
| A12 已签发后第三态：approved + token=null | approved + null | approved token=None | ✅ |  |
| A13 审批后原子应用 + 单次/单日例外回读 | readback_verified + both change kinds | verified=True kinds=True | ✅ | 8 changes |
| A14 同幂等键重放返回原结果 | same result_version | same=True | ✅ |  |
| A15 已应用提案换幂等键 → ALREADY_APPLIED | error:ALREADY_APPLIED | error:ALREADY_APPLIED | ✅ |  |
| A16 同幂等键不同请求 → IDEMPOTENCY_CONFLICT | error:IDEMPOTENCY_CONFLICT | error:IDEMPOTENCY_CONFLICT | ✅ |  |
| A17 无效凭据 → AUTH_REQUIRED | error:AUTH_REQUIRED | error:AUTH_REQUIRED | ✅ |  |
| A18 过期提案不得创建审批 → PROPOSAL_EXPIRED | error:PROPOSAL_EXPIRED | error:PROPOSAL_EXPIRED | ✅ |  |
| A19 快照变化 → SNAPSHOT_CONFLICT（validate 重算摘要） | error:SNAPSHOT_CONFLICT | error:SNAPSHOT_CONFLICT | ✅ |  |
| A20 引用不存在事项 → NOT_FOUND（不再 KeyError 崩溃） | error:NOT_FOUND | error:NOT_FOUND | ✅ |  |
| A21 无冲突提案 validate 通过 | success | success | ✅ | validation=valid |
| A22 固定事件冲突 → invalid + draft + FIXED_EVENT_CONFLICT | invalid/draft/FIXED_EVENT_CONFLICT | invalid/draft/['FIXED_EVENT_CONFLICT', 'FIXED_EVENT_CONFLICT', 'FIXED_EVENT_CONFLICT', 'FIXED_EVENT_CONFLICT'] | ✅ |  |
| A23 回读失败 → READBACK_MISMATCH 且标记 readback_pending | error:READBACK_MISMATCH | error:READBACK_MISMATCH | ✅ |  |
| A24 同幂等键重试只回读、不二次写入 | success via re-readback only | verified=True | ✅ | no duplicate write |
| A25 schema 一致、$ref 可解析、各对象层 additionalProperties:false | identical + resolvable refs + closed objects | names=True schemas=True open=0 bad_refs=0 | ✅ |  |

## 边界说明

- A19/A20/A22/A23 的边界状态由**测试专用 flag 文件**构造，不是工具入参；请求 schema 保持闭合。
- `request_approval` / `get_approval_status` 是**候选扩展**，是否写入 v1 待 M0 最终确认，不预设 v1.1。
- WorkBuddy 实机（stdio、env token、确认回调、外部分享）仍为 **BLOCKED**，本证据不构成平台能力证明。
- token 无签名、无 TTL、审批文件无访问控制、确认者身份未验证：保持 BLOCKED。

## Commit

- 本文件在修复提交之后回填；分支 HEAD 以 `git log -1` 为准。