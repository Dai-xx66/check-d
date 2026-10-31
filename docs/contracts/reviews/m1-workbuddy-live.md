# M1 · WorkBuddy 实机能力验证（第二阶段）

- 时间：2026-11-01 01:40–02:10（Asia/Shanghai）
- 平台：WorkBuddy 5.9.3（Electron 37.10.3 / Chrome 138），Windows x64
- 演示账号：A（个人版，已去敏）
- 被测服务：M1 本地 MCP stdio mock（`tools/m1-mock/tool_server.py`，七工具）
- 契约基准：`c53b1a91c17cd9acdee6d3937c093fcf97515ba0`（只读引用，未修改 M0 文件）

## 结论

| 编号 | 能力 | 结果 | 证据 |
|---|---|---|---|
| W1 | 自定义 MCP（stdio）注册与发现 | ✅ 支持 | 7/7 工具加载；`mcp-manager.png`、`mcp-7-tools.png` |
| W2 | 通过对话触发真实工具调用 | ✅ 成功 | 返回 4 条 task、`request_id`/`trace_id`；`call-result.png` |
| W3 | 工具调用 ID 暴露给模型 | ❌ 不暴露 | 模型只拿到业务 `trace_id`；宿主内部 `call_*` 仅出现在本地日志 |
| W4 | 远程 HTTPS MCP | ⏸️ BLOCKED | 本轮只验证 stdio；未部署远程 MCP，不能据此声称支持 |
| W5 | 第二账号 / 分享链接 / 只读调用 | ⏸️ BLOCKED | 无第二账号，未做 |
| W6 | 可信用户确认信号（身份/时间/防重放） | ⏸️ BLOCKED | 只有连接级“信任”开关；写入类工具无逐次确认，也无身份或时间凭证返回 |
| W7 | 连接超时 | ✅ 30s 超时并报错 | `MCP initialize timed out`；`daemon.log` elapsedMs=30028 |
| W8 | 服务不可达 | ✅ 报错 | `MCP error -32000: Connection closed`；`mcp-connect-error.png` |
| W9 | 401/鉴权失败 | ✅ 业务错误可达 | `AUTH_REQUIRED`、`retryable=false`；MCP 层不透出 HTTP 状态码 |

## 复现步骤

1. 在 `%USERPROFILE%\.workbuddy\mcp.json` 写入：

```json
{
  "mcpServers": {
    "checkd-m1": {
      "type": "stdio",
      "command": "python",
      "args": ["<repo>\\tools\\m1-mock\\tool_server.py"],
      "env": {"CHECKD_TOKEN": "<demo token>", "PYTHONIOENCODING": "utf-8"}
    }
  }
}
```

2. WorkBuddy → 专家·技能·连接器 → 连接器 → 自定义连接器 → MCP 服务管理；首次连接点“信任”。
3. 新建任务，输入：调用 `checkd-m1` 的 `list_tasks`，`date_range=2026-10-29..2026-10-31`。

## 关键观测

### W2 成功调用

- 工具：`list_tasks`；返回 `status=success`，`tasks` 4 条，`date_range` 与请求一致。
- 服务端 `request_id=c0c500ff-443c-434d-9420-1395b7c1c40a`，`trace_id=trace_e0de08266854414f`。
- 宿主日志另记内部 `toolCallId=call_2c9192d4d0f245d69764e113`，但模型上下文中不可见。

### W6 确认信号

- 新 MCP 首次连接有一次性“信任”确认（连接级），之后不再询问。
- 写入类工具 `apply_approved_changes` 直接执行，无逐次确认；模型也未收到任何用户身份、确认时间或防重放 nonce。
- 因此不能把平台 UI 当作可信授权信号；真实审批仍 BLOCKED。

### W7/W8/W9 异常

- 初始化挂起 30.0s 后：`MCP initialize timed out for "custom-mcp:checkd-hang"`。
- 进程立即退出：`MCP error -32000: Connection closed`。
- Token 无效：业务体 `AUTH_REQUIRED`，`retryable=false`；MCP 只透出 JSON，无 HTTP 状态码。

## 限制

- 未做远程 HTTPS MCP（无部署）。
- 无第二账号，分享链接/跨账号只读未验证。
- 平台未提供可用于防重放的用户确认凭证；WorkBuddy 终端身份透传仍 BLOCKED。
- 以上只证明平台侧“可以接自定义 MCP、可以真实调用”，不等于真实审批服务可用。

## 证据文件

| 文件 | SHA-256 |
|---|---|
| `work/evidence-wb/mcp-manager.png` | `f7588d73…f8b08a` |
| `work/evidence-wb/mcp-7-tools.png` | `75f0052f…4d0f35` |
| `work/evidence-wb/mcp-connect-error.png` | `720c621a…8301b3` |
| `work/evidence-wb/call-result.png` | `05a6a5cc…5710bc` |
| `work/evidence-wb/401.png` | `0733a23f…a1960aa` |
| `work/evidence-wb/daemon-mcp.log.txt` | 日志摘录（含 elapsedMs/timeoutMs） |

聊天原始回复（去敏后）另存于 `work/evidence-wb/call-success.json`、`401.json`、`write-no-prompt.json`。