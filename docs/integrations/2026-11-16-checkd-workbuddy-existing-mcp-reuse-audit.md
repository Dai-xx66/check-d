# CheckD WorkBuddy 现有 MCP 接入复用审计

日期：2026-11-16

审计 worktree：`/Users/dacy/.codex/worktrees/checkd-planning-delivery`
基线：`codex/checkd-planning-delivery`，`c8ae6c2b4a3c9cb3589c41274134b1dd12332dd2`。审计开始时工作区干净。

## 结论

**复用现有 `checkd-agent-tools`，不要新建第二个 Connector。** 本机 WorkBuddy 配置中的远程 MCP endpoint 在线，且已返回真实工具清单。该服务与 Planning MCP worktree 内的 8 工具候选服务不是同一注册表；现有 endpoint 的部署源码未在当前仓库找到，因此本轮不能安全修改或发布现有服务代码。

## 现有 WorkBuddy 服务的实测

配置读取自 `~/.workbuddy/mcp.json`。本报告不保存 URL query sharecode、header 值或其他凭证。

本轮通过已配置 endpoint 发出只读 JSON-RPC `tools/list`：HTTP 200。服务器实际注册：

1. `list_tasks`
2. `get_calendar_events`
3. `generate_schedule`
4. `validate_schedule`
5. `apply_approved_changes`
6. `request_approval`
7. `get_approval_status`

其中 `apply_approved_changes` 是写操作入口；本轮未调用。没有读取任何任务或课程记录。

Schema 的通用封装字段为 `api_version`、`request_id`、`timezone`、`input`。示例：`list_tasks` 的 `input` 要求 `date_range`，可选 `kinds`、`statuses`、`include_completed`；`get_calendar_events` 的 `input` 为 `date_range`、`external_fixed_events`；`generate_schedule` 还可接收 `preferences`；`apply_approved_changes` 需要 proposal/version/approval/idempotency 字段。被检查的工具 schema 没有 `user_id` 参数。

只对 `tools/list` 做了凭证负向检查：

| 请求凭证 | 结果 | 可确认事项 |
| --- | --- | --- |
| 当前本机配置 | HTTP 200 | endpoint 在线并接受配置中的两项门禁凭证 |
| 去掉 `X-Demo-Token`，保留 sharecode | HTTP 401 | Demo header 是一个必需访问门禁 |
| 保留 header，移除 sharecode | HTTP 403 | URL sharecode 是另一个必需访问门禁 |

这仅确认黑盒行为，不确认服务端对两项凭证的校验代码、生命周期、撤销方式或最终数据主体。实现源码未在本仓库找到。现有配置是一组静态 Demo header，而非 per-user OAuth token；没有证据表明不同 WorkBuddy 用户能被映射到不同 CheckD 用户。因此当前 endpoint **在线状态 PASS，多用户身份与隔离 UNKNOWN/BLOCKED**。

## 三套工具实现对照

| 系统 | 实际位置 | 工具数 | 身份/数据方式 | 当前可复用内容 |
| --- | --- | ---: | --- | --- |
| 已有 WorkBuddy `checkd-agent-tools` | WorkBuddy 托管域名 `checkd-agent-tools.app.workbuddy.host`；本机 `~/.workbuddy/mcp.json` 指向它 | 7 | 静态 Demo header + URL sharecode；服务端映射源码未知 | 优先复用这个入口、现有 schema、现有用户验收习惯；须取得托管源码后改造 |
| Personal Task Agent stdio | 另一工作区 `tools/personal_task_agent/`，不是当前 delivery worktree 的组成部分 | 12 | `run_mcp_authenticated.py` 读取本机 Keychain 会话，注入子进程；`SupabaseTaskRepository.authenticated_user_id()` 调 Auth `/user` 并以普通用户 JWT 访问 RLS | 可复用 `TaskCreationService`、`TaskQueryService`、`TaskUpdateService`、`SupabaseTaskRepository` 的业务语义和校验；不能复用开发者个人 Keychain 作为云端多用户凭据 |
| Planning MCP 候选 | 当前 delivery worktree：`tools/checkd_planning_engine/src/checkd_planning_engine/remote_mcp.py`、`supabase_remote.py`；契约 `docs/contracts/agent-planning-v0.json` | 8 | `SupabaseAccessTokenVerifier` 通过 Auth `/user` 验证 JWT，provider 用同一用户 JWT 做 PostgREST GET；需配置 OAuth `client_id` allowlist | 可复用 request-scoped 身份验证、PostgREST per-user bearer、快照 DTO 与只读工具实现；目前未部署，且有课程 occurrence/sync freshness blocker |

### 身份与存储阻塞

- Personal Task Agent 的 `authenticated_launcher.py` 在 stdio 子进程启动时读取 Keychain access token；这代表本机用户进程，不是 WorkBuddy 用户的远程授权。
- `ConfirmationLedger` 当前本地 SQLite 结构的 `idempotency_key` 是全局唯一，且记录没有用户归属字段。不能直接当作共享远程服务的多用户审批账本；改造时应使用 `(user_id, idempotency_key)` 作用域，并让 confirmation/update ID 与数据主体绑定。
- 当前 Personal Agent 的 12 工具列表含创建、查询、编辑和取消草稿流程。现有远程 7 工具已有 `list_tasks`，且其输入封装与 Personal Agent 的 `list_tasks` 不同；Planning 8 工具也有同名 `list_tasks`。不得把三个 schema 同名工具直接拼接。
- Planning candidate 保留 8 个只读/预览工具；当前 schedule preview 对没有 Flutter occurrence 规范化的数据会 fail closed。不得因接入统一 endpoint 而绕过该限制。
- Supabase OAuth scope 不构成数据库只读授权；真实 JWT 仍受数据库 GRANT/RLS 决定。生产只读访问的 RLS/GRANT 或隔离数据层须先评审。

## 最小改造方案

1. **沿用线上 endpoint 和现有 Connector。** 服务所有者提供 `checkd-agent-tools` 托管服务的源码仓库、部署定义、环境配置方式、负责的审批/回滚人。本轮不尝试向未知服务部署或修改线上配置。
2. **先在既有服务的隔离发布槽接入身份。** 接受 Supabase OAuth 用户 bearer；每个请求服务端校验 JWT、issuer、过期、已 allowlist 的 OAuth client ID，并从认证结果取得 `sub`/用户 ID。拒绝 `user_id` 参数和缺身份请求。OAuth 成功前不使用共享 Demo token 代表多名用户。
3. **保护原有 7 工具契约。** 保持原工具名和 envelope，不改变 `list_tasks`、日历、生成、校验和审批行为；加回归契约测试。先通过同一个既有 MCP endpoint 增量部署，再由 WorkBuddy 用户沿现有入口授权。
4. **复用 Personal Task Agent 业务服务，不复制业务规则。** 通过每请求用户 token 构造 repository/service；将确认账本迁移为具备用户复合隔离的持久存储。保持名称/日期/超时/回读校验和 idempotency 的已测语义。
5. **融合规划能力时明确同名工具。** `list_tasks` 保留线上旧 schema，服务内部把查询与规划上下文按同一 authenticated principal 适配；不注册重复 `list_tasks`。只增补没有现存等价项的只读工具。计划提案可查看、批准/拒绝均留在 WorkBuddy；批准必须服务端校验用户、proposal 所属、TTL、快照版本和明确变更集合。Android 只展示同步后的结果。
6. **分阶段验收并回滚：** 旧 Demo 登录/现有 Connector 先保持可回滚；测试账号 A/B 各自授权；读任务/课程、串用户 ID、审批授权边界和撤权测试通过后，才讨论替换旧 Demo 凭证。不得在本轮生产更新。

## 需要服务所有者/用户完成的最少操作

1. 提供现有 `checkd-agent-tools` 服务端源码仓库或部署入口及代码所有者；不需要再发 sharecode 或 token。
2. 提供非生产 WorkBuddy/Supabase OAuth 测试配置权限，以及两个专用测试账号/脱敏任务和课程。
3. 确认现有 Connector 是否支持原位切换到每用户 OAuth，及其撤权时 WorkBuddy 是否停止发送旧 access token。
4. 由 Supabase 管理员审核 OAuth client 的最小读权限；不能只依赖 `planning:read` scope。
5. **凭证暴露风险：**用户提供的截图中可读到完整 sharecode 与 Demo token。本轮未复制、回显、轮换或修改配置。建议将二者视为可能已泄露；请服务所有者确认这些是否可撤销的测试凭证，并明确授权后再制定轮换窗口，避免直接轮换造成现有 Connector 中断。

## 本轮变更与 Git

本轮只做只读 MCP 请求和代码/文档审计，没有调用任务或计划写入工具，没有修改 `~/.workbuddy/mcp.json`、Production 数据或服务配置，也未修改代码。工作区没有提交或推送新变更；现有分支仍为 `codex/checkd-planning-delivery`，HEAD 为 `c8ae6c2b4a3c9cb3589c41274134b1dd12332dd2`。
