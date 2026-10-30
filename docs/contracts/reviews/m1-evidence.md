# M1 工具契约一致性测试证据

对象：`agent-api-v1.md` v1 CANDIDATE（MCP stdio mock 实现，非 WorkBuddy 实机）
结果：**15/15 通过**

## 复现命令

```bash
cd <repo>
python tools/m1-mock/run_evidence.py
```

- 运行环境：Windows / Python 3.14.3 / MCP stdio（JSON-RPC 2.0）
- 证据文件：`docs/contracts/reviews/m1-evidence.md`、`m1-evidence.json`
- 代码提交：`6683289891c7772b033deb23148a2c043f37c029`（short `6683289`）

## 用例与结果

| 用例 | 预期 | 实际 | 结论 | 说明 |
|---|---|---|---|---|
| A0 tools/list | 5+1 | 6 tools | ✅ | ['list_tasks', 'get_calendar_events', 'generate_schedule', 'validate_schedule', 'apply_approved_changes', 'request_approval'] |
| A1 list_tasks 正常读取 | success | success | ✅ | 3 tasks |
| A2 请求体携带 user_id 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A3 非 Asia/Shanghai 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A4 日历包含固定课程与外部会议 | success | success | ✅ | 2 events, 2 fixed |
| A5 generate_schedule 生成 draft 提案 | success | success | ✅ | prop_0011 blocks=5 changes=5 unplanned=0 |
| A6 远程提交 tasks 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A7 validate 通过并进入 pending_approval | success | success | ✅ | validation=valid approval=pending_approval |
| A8 无审批凭据不可写入 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A9 扩展工具签发一次性凭据 | success | success | ✅ | approval_0012 |
| A10 审批后原子应用并回读 | success | success | ✅ | readback_verified=True changes=5 |
| A11 同幂等键重放返回原结果 | success | success | ✅ | same_result=True |
| A12 无效凭据被拒 | error:AUTH_REQUIRED | error:AUTH_REQUIRED | ✅ |  |
| A13 同幂等键不同请求被拒 | error:IDEMPOTENCY_CONFLICT | error:IDEMPOTENCY_CONFLICT | ✅ |  |
| A14 固定事件冲突→invalid | invalid + draft + FIXED_EVENT_CONFLICT | invalid / draft / ['FIXED_EVENT_CONFLICT', 'FIXED_EVENT_CONFLICT', 'FIXED_EVENT_CONFLICT'] | ✅ | test seam: 事件在排程后注入 |

## 未覆盖

- WorkBuddy 实机：stdio 接入、env token 透传、工具超时/返回上限、分享链接外部访问，均为 **BLOCKED**。
- 可信审批服务、真实快照版本、原子写入与线上 RLS：mock 中为占位实现。
- T-A8（A14）通过测试注入口 `__test_conflict_event` 在排程后注入冲突事件，仅用于证明 validate 会拒绝，不代表真实数据路径。

## Commit

- 代码与用例提交：`6683289891c7772b033deb23148a2c043f37c029`
- 本文件（回填 SHA）在其后一个提交中更新；分支 HEAD 以 `git log -1` 为准。
- 提交身份为中性署名 `M1 WorkBuddy <m1@checkd.local>`，避免在公开仓库写入个人身份信息。