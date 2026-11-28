# M1 工具映射（WorkBuddy ↔ checkd.agent.v1）

- 契约基准：`c9dda83195a9af4b9ca762d8556fdd0e8d43010a`
- 平台侧名称：MCP server `checkd-m1`（stdio），加载后工具名与契约一致。
- 本地实现：`tools/m1-mock/tool_server.py`

| 契约工具 | 平台/MCP 工具名 | 读/写 | Mock 状态 | 备注 |
|---|---|---|---|---|
| `list_tasks` | `list_tasks` | 只读 | ✅ 实测 | 返回去重 Task、query_version |
| `get_calendar_events` | `get_calendar_events` | 只读 | ✅ 实测 | 外部固定事件不落库 |
| `generate_schedule` | `generate_schedule` | 只读（创建 draft） | ✅ 实测 | Proposal TTL 30 分钟 |
| `validate_schedule` | `validate_schedule` | 校验，零业务写入 | ✅ 实测 | draft → pending_approval |
| `request_approval` | `request_approval` | 建审批，不签 Token | ✅ 实测 | 需 idempotency_key |
| `get_approval_status` | `get_approval_status` | 只读/受控签发 | ✅ 实测 | 首次交付 Token |
| `apply_approved_changes` | `apply_approved_changes` | 写 | ✅ 实测（Mock） | 真实审批仍 BLOCKED |

## 平台侧限制（实测）

1. MCP 首次连接需要在“MCP 服务管理”点一次“信任”，属连接级确认。
2. 写入类工具没有逐次用户确认，也没有把用户身份/确认时间/防重放凭证返回给模型。
3. 模型拿不到宿主内部的 `toolCallId`，只能看到业务 `trace_id`。
4. 远程 HTTPS MCP 未验证（本轮只做 stdio）。

## 复现

```bash
# 本地直接跑 MCP（stdio）
python tools/m1-mock/tool_server.py
# 证据
CHECKD_EXAMPLES=<repo>/docs/contracts/agent-api-v1.examples.json python tools/m1-mock/run_evidence_c53.py
```