# WorkBuddy 可访问性与真机走查（M1 / A）

- 平台：WorkBuddy 5.9.3（Electron 37.10.3 / Chrome 138），Windows x64
- 账号：演示账号 A（个人版，去敏）
- 结论摘要：**平台侧可接自定义 stdio MCP 并真实调用；分享链接已生成，但“非本人账号打开并触发工具”仍 BLOCKED（无第二账号）。**
- 本文件只记录实测与阻断，不把 demo 层结论写成 PASS。

## 一、分享链接

- 生成路径：任务页右上角 **分享 → 复制链接 / 生成二维码 / 浏览器打开**。
- 分享菜单实测项：分享到微信、分享到企业微信、分享到朋友圈、复制链接、生成二维码、浏览器打开。
- 当前状态：链接已生成；因当前会话无法读取系统剪贴板，未把 URL 文本落库；**未用第二账号打开验证** → `BLOCKED`。
- 复现：任选一个任务 → 分享 → 复制链接，粘贴到未登录/另一账号浏览器；记录是否要求登录、是否能看到工具调用与回答。
- 判定标准（沿用计划）：非本人账号能打开且能触发只读工具，才算通过；仅开发者登录态可打开不算。

## 二、19 项真机走查

| # | 检查项 | 结果 | 证据/说明 |
|---|---|---|---|
| 1 | WorkBuddy 安装并登录演示账号 | ✅ | 5.9.3，账号 A |
| 2 | 新建 Agent/任务并可对话 | ✅ | 任务列表可见 |
| 3 | 分享入口存在 | ✅ | 分享菜单 6 项 |
| 4 | 分享链接生成 | ✅ | 复制链接/二维码/浏览器打开均出现 |
| 5 | 第二账号打开链接 | ⏸️ BLOCKED | 无第二账号，未实测 |
| 6 | 分享范围/权限记录 | ⏸️ BLOCKED | 随上项 |
| 7 | 自定义 MCP（stdio）注册 | ✅ | `%USERPROFILE%\.workbuddy\mcp.json` |
| 8 | 首次连接信任确认 | ✅ | 连接器 → MCP 服务管理 → 信任 |
| 9 | 七工具全部加载 | ✅ | 7/7（list_tasks…get_approval_status） |
| 10 | 真实调用只读工具 | ✅ | `list_tasks` 返回 4 条；request_id=trace 可查 |
| 11 | 工具调用 ID 对模型可见 | ❌ | 平台只给业务 trace_id，内部 `call_*` 仅在本地日志 |
| 12 | 工具返回与契约一致 | ✅ | 信封/字段按 c9dda83；EX 20/20 |
| 13 | “明天有哪些任务”类自然语言触发 | ✅ | 对话触发同一工具 |
| 14 | 超时 | ✅ | 初始化 30s 超时 |
| 15 | 服务不可达 | ✅ | `MCP error -32000: Connection closed` |
| 16 | 401/鉴权失败 | ✅ | `AUTH_REQUIRED`，retryable=false |
| 17 | 空结果 | ✅ | EX-03/EX-04 空列表成功 |
| 18 | 写入工具用户确认信号 | ⏸️ BLOCKED | 无逐次确认，无身份/时间/防重放凭证 |
| 19 | 证据留存（截图/日志） | ✅ | `m1-workbuddy-live.md` 与同目录图片/日志 |

## 三、本地 MCP 配置（可复现）

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

路径：`%USERPROFILE%\.workbuddy\mcp.json` → 连接器 → 自定义连接器 → MCP 服务管理 → 信任 → 新任务对话调用。

## 四、明确 BLOCKED

1. 第二账号 / 异浏览器打开分享链接并触发工具。
2. 远程 HTTPS MCP（本轮只验证 stdio）。
3. 平台可信用户确认（身份、时间、防重放）；写入工具无逐次确认。
4. 模型侧工具调用 ID（平台不透出）。

以上任一项都不能写成“真实审批/真实生产可用”。

## 五、证据索引

- `docs/contracts/reviews/m1-workbuddy-live.md` / `.json`
- `docs/contracts/reviews/mcp-manager.png`、`mcp-7-tools.png`、`mcp-connect-error.png`、`call-result.png`、`401.png`
- `docs/contracts/reviews/daemon-mcp.log.txt`（stdio-connected / timeout / -32000）