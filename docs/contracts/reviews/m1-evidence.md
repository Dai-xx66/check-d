# M1 工具契约一致性测试证据

对象：`agent-api-v1.md` v1 CANDIDATE（MCP stdio mock 实现，非 WorkBuddy 实机）
结果：**18/18 通过**

## 复现命令

```bash
cd <repo>
python tools/m1-mock/run_evidence.py
```

- 运行环境：Windows / Python 3.14.3 / MCP stdio（JSON-RPC 2.0）
- 证据文件：`docs/contracts/reviews/m1-evidence.md`、`m1-evidence.json`
- 代码提交：`6683289`（首版）；后续修正提交见文末 Commit 段

## 用例与结果

| 用例 | 预期 | 实际 | 结论 | 说明 |
|---|---|---|---|---|
| A0 tools/list | 7 tools (5 v1 + 2 candidate) | 7 tools | ✅ | ['list_tasks', 'get_calendar_events', 'generate_schedule', 'validate_schedule', 'apply_approved_changes', 'request_approval', 'get_approval_status'] |
| A1 list_tasks 正常读取 | success | success | ✅ | 3 tasks |
| A2 请求体携带 user_id 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A3 非 Asia/Shanghai 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A4 日历包含固定课程与外部会议 | success | success | ✅ | 2 events, 2 fixed |
| A5 generate_schedule 生成 draft 提案 | success | success | ✅ | prop_0011 blocks=5 changes=5 |
| A6 远程提交 tasks 被拒 | error:INVALID_ARGUMENT | error:INVALID_ARGUMENT | ✅ |  |
| A7 validate 通过并进入 pending_approval | success | success | ✅ | validation=valid approval=pending_approval |
| A8 未审批 apply 返回 APPROVAL_REQUIRED | error:APPROVAL_REQUIRED | error:APPROVAL_REQUIRED | ✅ |  |
| A9 request_approval 只创建 pending 请求（不返回 token） | pending + approval_url, no token | pending url=True token=False | ✅ | appr_0012 |
| A10 外部确认后轮询才签发 token | approved + token | approved token=True | ✅ |  |
| A11 审批后原子应用并回读 | success | success | ✅ | readback_verified=True changes=5 |
| A12 同幂等键重放返回原结果 | same result_version | same=True | ✅ |  |
| A13 已消费 token 再用被拒 | error:APPROVAL_CONSUMED | error:APPROVAL_CONSUMED | ✅ |  |
| A14 同幂等键不同请求被拒 | error:IDEMPOTENCY_CONFLICT | error:IDEMPOTENCY_CONFLICT | ✅ |  |
| A15 无效凭据被拒 | error:AUTH_REQUIRED | error:AUTH_REQUIRED | ✅ |  |
| A16 固定事件冲突 → invalid + draft + FIXED_EVENT_CONFLICT | invalid/draft/FIXED_EVENT_CONFLICT | invalid/draft/['FIXED_EVENT_CONFLICT', 'FIXED_EVENT_CONFLICT', 'FIXED_EVENT_CONFLICT'] | ✅ |  |
| A17 tools/list 与 tools.candidate.json 一致且各对象层 additionalProperties:false | identical schemas + no open objects | names_equal=True schemas_equal=True open_objects=0 | ✅ |  |

## 边界说明

- `request_approval` / `get_approval_status` 是**候选扩展**，不是 v1 契约内容；用于证明“工具调用 ≠ 用户确认”。
- 外部确认由测试脚本写 `MOCK_APPROVAL_FILE` 模拟（等价于用户在 approval_url 点确认），token 只在确认后签发、且一次性消费。
- WorkBuddy 实机（stdio、env token、确认回调、外部分享）仍为 **BLOCKED**；mock 不构成平台能力证明。
- A16 通过测试注入口 `__test_conflict_event` 在排程后注入冲突事件，仅证明 validate 会拒绝。

## Commit

- 首版用例代码：`6683289891c7772b033deb23148a2c043f37c029`
- 本次修正（approval 占位、consumed、A17 schema 比对）提交后回填。