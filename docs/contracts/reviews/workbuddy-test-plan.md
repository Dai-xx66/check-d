# WorkBuddy 侧验证步骤（M1，装好客户端后照做）

> 目的：把契约里 5 个 BLOCKED 项变成“有截图、有日志”的结论。
> 环境：Windows + 已安装 WorkBuddy（本机尚未安装，故以下步骤未执行）。

## 0. 准备

1. 确认 Python 绝对路径：`where python`（示例：`C:\Users\DREAMER\AppData\Local\Python\pythoncore-3.14-64\python.exe`）。
2. 确认 mock server 可跑：
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' | python E:\DSHWP\SmallCompetition\work\m1\tool_server.py
   ```
   应返回一行含 `serverInfo` 的 JSON。
3. 复制 `mcp.json.example`，把 `command`/`args` 改成上一步的真实路径。

## 1. 接入 MCP（验证“WorkBuddy 是否支持自定义 stdio MCP”）

1. WorkBuddy 左侧栏 →「专家·技能·连接器」→「连接器」→ 右上「自定义连接器」→「配置 MCP」。
2. 把改好的 `mcpServers` 粘进 `mcp.json`（注意文件名是 `mcp.json`，不是 `.mcp.json`）。
3. 保存 → 在 MCP 服务管理页点「信任」→ 状态灯变绿。
4. 新建对话，展开「正在连接 MCP 服务」，记录“已连接数 / 服务总数”。

**证据**：配置截图、绿色状态截图、连接数截图。

## 2. 工具发现（验证 schema 能否被平台正确加载）

对话里说：「列出你现在可用的 CheckD 工具及其参数」。

**预期**：能列出 5 个工具（`list_tasks`、`get_calendar_events`、`generate_schedule`、`validate_schedule`、`apply_approved_changes`），参数与 `tools.json` 一致。

**证据**：工具列表截图；若参数缺失/错乱，记录具体字段。

## 3. 只读工具调用（验证“真实工具回调”，不是提示词）

依次说：
1. 「列出我 10 月 30 日到 31 日的任务」
2. 「看一下我这两天的课程和日程」
3. 「30 号下午 2 点有个临时会议，加进来再看一次日程」

**预期**：每次出现工具调用卡片/日志，返回真实 mock 数据（3 个任务、1 门课、外部会议）。

**证据**：每次工具调用前后截图 + 返回 JSON；记录**耗时**与**返回体大小**。

## 4. 提案与校验（验证不会假写入）

说：「帮我把实验报告排到 30 号上午，先给我方案，不要直接写」。

**预期**：调用 `generate_schedule` → `validate_schedule`，返回 `pending_approval` 的提案；数据库无变化。

**证据**：提案截图；`validate` 返回的 `validation_status=valid`、`approval_status=pending_approval`。

## 5. 审批缺口（这一步是给队长的关键证据）

说：「直接写入，不用确认」。

**预期**：`apply_approved_changes` 返回 `APPROVAL_REQUIRED`（或 `INVALID_ARGUMENT`，视参数），**不得**返回成功。

**证据**：错误码截图。若 WorkBuddy 自己弹了“确认”按钮但工具仍失败 → 说明平台确认信号不可信，正好支撑 P0-2。

## 6. 超时 / 返回上限 / 并发（验证 §6.2、§6.5）

1. 把 mock 的日期范围改到 31 天（或临时加 300 条事件），看返回是否被平台截断。
2. 连续快速发 3 条“查任务”，观察是否并发/串行、是否超时。
3. 记录：单次工具调用最长等待、报错文案、是否可重试。

**证据**：日志 + 计时截图。

## 7. 分享链接（比赛硬指标）

1. 用这个 MCP 建一个「CheckD 学习规划」专家，配置提示词 + 工具。
2. 点分享，复制链接。
3. 用**另一个账号**（队友手机 / 新注册账号 / 无痕 + 不同网络）打开：
   - 是否要求安装 WorkBuddy？
   - 是否要求登录？
   - 登录后能否看到同一个专家、工具是否仍可用？
4. 记录链接有效期、权限范围。

**证据**：外账号打开成功的截图；若失败，记录失败页面原文。

## 8. 结论回填

把结果填成 5 行，发群里：

| 项 | 结论 | 证据 |
|---|---|---|
| 自定义 stdio MCP | 可用 / 不可用 | 截图 |
| token 透传（env） | 可用 / 不可用 | 日志 |
| 工具超时/返回上限 | 具体数值 | 记录 |
| 分享链接外部可访问 | 是 / 否 / 需登录 | 截图 |
| Workflow 人工确认节点 | 有 / 无 / 未测 | 截图 |