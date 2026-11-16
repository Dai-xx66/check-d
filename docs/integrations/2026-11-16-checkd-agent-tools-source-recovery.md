# CheckD 原 MCP 源码找回与统一整合准入审计

日期：2026-11-16
审计工作区：`/Users/dacy/.codex/worktrees/checkd-planning-delivery`
审计分支：`codex/checkd-planning-delivery`

## 结论

找到了 M1 的 `checkd-agent-tools` HTTP/MCP 服务候选源码：本机克隆的 `Tony2215/check-d` 仓库，分支 `demo/competition-11010`，当前本地与对应远端分支 HEAD 为 `64242c2634630640418c7e5870856319869fa4d0`。其 `tools/m1-server/RUNBOOK.md` 明确记录了现有 WorkBuddy 托管 endpoint、HTTP 启动入口和部署构建步骤，因此该仓库是目前最强的源码归属证据。

**尚不能证明线上运行实例精确对应这个 SHA。** M1 手册说明部署目录是构建产物，公网精简 `/health` 不提供 commit；手册提到的 `work/m1/build_deploy.py`、`work/deploy/checkd-tools/MANIFEST.json` 在当前克隆中均不存在。在线 `tools/list` 的七个名称与 M1 工具注册表相符，但名称一致不能证明部署 blob 与当前 HEAD 相同。线上 endpoint 的精确构建 SHA 标为 `UNKNOWN`。

当前源码不能直接承载多用户整合：原 `/mcp` 使用共享静态 Demo 凭证，之后固定为一个服务端 Demo 用户；REAL 路径也使用单一全局 JWT。直接把 Personal Agent 或规划能力接到该身份路径，会使 WorkBuddy 用户共享 CheckD 主体或审批状态。因此本轮没有修改任何线上服务、Connector 或代码运行路径。安全的最小整合必须先在隔离发布槽建立逐请求的可信用户认证及用户级状态存储。

## 找到的服务源码与部署入口

仓库：`https://github.com/Tony2215/check-d`
本地克隆：`/Users/dacy/Documents/Codex/2026-11-10/referenced-chatgpt-conversation-this-is-an/work/check-d`
分支：`demo/competition-11010`
当前克隆 HEAD：`64242c2634630640418c7e5870856319869fa4d0`

关键文件：

- `tools/m1-server/app.py`：HTTP/MCP 传输层、鉴权路由、工具分派。文件中服务名为 `checkd-agent-tools`。
- `tools/m1-mock/tool_server.py`：原七个工具的 schema、注册表和演示业务实现。
- `tools/m1-server/snapshot_tools.py`：四个提案/审批工具的快照接线层。
- `tools/m1-server/real_read.py`：REAL 路径的 Supabase 只读适配。
- `tools/m1-server/real_write.py`：隔离开关后的单任务名称更新实现。
- `tools/m1-server/RUNBOOK.md`：平台沙箱启动、工作目录构建、环境变量和 WorkBuddy 连接步骤。
- `tools/m1-server/README.md`：明确 `tools/m1-server` 是可测试原型，不应单独解读为生产服务。

M1 手册中的入口为 `python work/m1/build_deploy.py`，把 `tools/m1-server` 与 `tools/m1-mock` 组装到部署目录，再由平台沙箱执行 `python3 app.py`。本机克隆未包含该构建脚本和部署产物，因此仍需原部署负责人提供它们及平台部署修订号/镜像摘要。

## 原七个工具的实现位置

`tools/m1-mock/tool_server.py:1291-1299` 注册：

| 工具 | 代码实现 | 当前边界 |
|---|---|---|
| `list_tasks` | `tool_list_tasks` | 默认 mock 路径使用内置演示数据；REAL 路径另有只读实现 |
| `get_calendar_events` | `tool_get_calendar_events` | 默认 mock 路径；REAL 路径另有只读实现 |
| `generate_schedule` | `tool_generate_schedule` | mock 调度器；快照模式仍以演示任务/课程状态作为数据源 |
| `validate_schedule` | `tool_validate_schedule` | mock 提案校验；快照接线另见 `snapshot_tools.py` |
| `apply_approved_changes` | `tool_apply` | 当前 mock/演示状态机；不能等同生产审批事务 |
| `request_approval` | `tool_request_approval` | 创建演示审批记录 |
| `get_approval_status` | `tool_get_approval_status` | 演示轮询及 Token 交付 |

`tools/m1-mock/tool_server.py:1322-1375` 定义七个工具的 JSON Schema 和通用信封。线上工具清单与七个名称一致；现有调用契约应作为兼容 façade 保留，不能直接用另外两份工具表覆盖。

### 任务数据访问与身份

1. 默认在线 `/mcp` 路径由 `tools/m1-server/app.py:827-896` 的 `_call` 分派到 `mock.call_tool(..., DEMO_USER_TOKEN)`。`app.py:171` 中 `DEMO_USER_TOKEN` 是服务级单值；`tool_server.py:317-322` 只把内置演示令牌映射成 `u_alice` 或 `u_bob`。WorkBuddy 的静态访问口令不构成用户身份。
2. `app.py:1347-1379` 验证固定 `X-Demo-Token`/Bearer 口令。通过后并未依据 WorkBuddy 终端用户解析身份。分享码由托管域名/平台层处理；本机服务代码按 URL 路径剥离 query，不能从中证明分享码具备每用户身份绑定能力。
3. 单独的 `/real/mcp` 路径要求静态 `X-Real-Token`，并将服务级 `_current_real_jwt()` 传给 `SupabaseReader`（`app.py:1381-1418, 998-1014`；`real_read.py:192-239`）。REAL 读取只开放 `list_tasks` 和 `get_calendar_events`；Supabase/RLS 能基于这一 JWT 判断其 CheckD 用户，但当前实现是一个服务级 JWT，而不是每个 WorkBuddy 请求各自的用户 JWT。
4. REAL-WRITE 只有隔离开关下的 `update_task_name`（`app.py:977-980, 1056-1090`），不等于原七工具的生产写入支持。

### 审批、幂等与状态存储

- M1 mock 的任务、课程、提案、令牌和幂等索引在 `tool_server.py:100-110` 的进程内 `STATE` 中。
- 审批记录由 `read_approvals`/`write_approvals` 存入 `MOCK_APPROVAL_FILE` JSON 文件（`tool_server.py:210-221`），并在内存建立索引；不等于可扩展的事务型多用户审批账本。
- 快照模式确实将 snapshot/proposal 元数据交给 Postgres `SnapshotStore`，但 `snapshot_tools.py:25-36` 明确说明 approval 仍在 mock 内存及文件中，且 token 链仍是演示流程。审批校验与数据库变更没有统一原子事务。
- 文件型审批状态、内存令牌索引和模糊的部署持久卷行为均不能作为云端多用户授权/幂等记录的可靠基础。

## 可复用实现

### Personal Task Agent（本地 stdio，12 工具）

位置：`/Users/dacy/.codex/worktrees/stage14e-task-schedule-json/打卡app/tools/personal_task_agent/`。

- `src/checkd_task_agent/service.py`：任务创建草稿、显式确认、幂等和回读语义。
- `src/checkd_task_agent/query_service.py`：任务列表、搜索、按日、逾期和详情的业务语义。
- `src/checkd_task_agent/update_service.py`：修改草稿、并发快照保护、确认及回读。
- `src/checkd_task_agent/supabase.py`：以用户级 JWT 调 Auth/PostgREST，遵循 RLS；可抽出 request-scoped repository 工厂。
- `src/checkd_task_agent/mcp_server.py`：12 工具 stdio 注册与 Schema；不适合直接作为远程多用户服务器入口。
- `src/checkd_task_agent/ledger.py`：本机 SQLite 持久确认账本。`idempotency_key` 为全表唯一，schema 没有 `user_id`，不得原样共享给多用户服务。
- `run_mcp_authenticated.py` / `authenticated_launcher.py`：从本机 Keychain 取得一个用户会话，只适用于个人设备进程；不能用负责人的 Keychain 作为云端共享身份。

### Planning MCP（远程只读候选，8 工具）

位置：本工作区 `tools/checkd_planning_engine/src/checkd_planning_engine/remote_mcp.py`、`supabase_remote.py`；契约 `docs/contracts/agent-planning-v0.json`。

- 有 Streamable HTTP 的 initialize、tools/list、tools/call、health 与认证边界原型。
- `IntrospectionTokenVerifier` + `CheckDIdentityBindingResolver` 定义了逐请求验证/绑定接口；后者是 Protocol，尚无 WorkBuddy 真实 introspection 和持久授权绑定实现。
- `SupabaseAccessTokenVerifier` 用 Auth `/user` 确认 CheckD Auth 主体，快照提供器使用该请求同一用户 JWT 做 PostgREST GET。`TestJwtAuthority` 仅用于本地测试，不是真实 OAuth。
- 契约八工具中 `list_tasks` 与线上旧工具同名且参数不同；`preview_schedule`、`check_schedule_feasibility`、`generate_adjustment_draft` 与现有生成/校验流程有功能重叠。
- 当前快照会保留暂定/同步未知等安全标记，不能据此授权生产执行。

## 统一工具注册表建议

保持线上既有七个名称和现有参数 Schema 不变，做兼容外层适配；不再注册第二个 `list_tasks`。内部统一以请求认证上下文构造任务仓库、规划服务和状态仓库。

| 对外工具/候选能力 | 统一注册决策 |
|---|---|
| 七个现有工具 | 七个名称与参数原样保留；`list_tasks` 同时成为查询与规划所用任务读取的唯一入口 |
| Personal Task Agent 的 11 个非重名工具 | 可以逐步作为新增工具迁入：`resolve_deadline`、`prepare_task_creation`、`create_task`、`cancel_task_creation`、`search_tasks`、`get_tasks_by_date`、`list_overdue_tasks`、`get_task_detail`、`prepare_task_update`、`update_task`、`cancel_task_update`。其中写工具须单独授权、绑定当前用户与确认记录，不能因“迁移”自动开放 |
| Planning MCP 的 8 个候选 | 不直接整表拼接。`list_tasks` 复用原工具；`preview_schedule` 映射/兼容原 `generate_schedule`；`check_schedule_feasibility` 映射/兼容原 `validate_schedule`。`get_planning_context`、`get_current_plan`、`generate_adjustment_draft`、`simulate_task_delay`、`list_plan_risks` 是待契约评审的唯一新增候选 |

候选总表需在取得 M1、M0、B、C 的正式 schema 评审后再冻结。旧工具名兼容不意味着旧 schema 可以静默变更；需要契约适配和旧版回归测试。

## 多用户身份与最小改造顺序

1. 沿用同一个 WorkBuddy 专家和当前 Connector，不创建第二个 Connector；先取得 Connector/OAuth 规范及服务所有者可操作的非生产发布槽。
2. 每次 HTTP MCP 请求验证可信 OAuth access token 的 issuer、签名/有效状态、audience、expiry、scope、client/tenant；服务端从已验证 subject 读取授权绑定，禁止 `user_id` 入参。WorkBuddy subject 与 CheckD Auth user ID 必须分开存储。
3. 持久化用户主动授权产生的 `(issuer, subject, tenant, client_id) -> CheckD auth user_id` 绑定、scope、创建/过期/撤销时间。撤权后每次请求都查绑定状态，不能依赖长寿命内存缓存。
4. 以请求级用户 JWT 调用 Supabase Auth/PostgREST，并按 RLS 访问本人数据；不把 service_role 暴露给 MCP。必须验证撤权、过期和 A/B 串用户 ID 的失败行为。
5. 把 Personal Agent ledger、Proposal、Approval、幂等、风险和通知状态迁移为 Postgres 按 `user_id` 复合隔离的记录；对每个 `idempotency_key`、proposal、approval 执行用户归属校验。
6. 保留现有七工具的 façade，内部用兼容适配器映射到复用的 Task/Calendar/Planning 服务。只在非生产环境先开只读工具；写入工具待审批事务和回读验证通过后再启用。
7. 通过 WorkBuddy 同一 Connector 做账号 A/B 的任务、课程、计划隔离及撤权实测，再按可回滚方式迁移现有 Demo 入口。

## 可直接转发给原部署负责人的资料索取清单

请通过仓库/部署系统提供以下**非秘密资料**；无需发送任何 sharecode、Demo token、JWT、密码或 key：

1. 原服务权威仓库 URL、owner、分支、部署时的 commit SHA，以及谁负责审阅/发布/回滚。
2. 实际构建脚本 `work/m1/build_deploy.py` 和本次线上对应的 `MANIFEST.json` 或镜像 digest；说明它是否从当前 Git HEAD 构建。
3. WorkBuddy 沙箱的 deployment/revision ID、创建时间、启动命令模板（变量名保留、值全部删去）及是否启用 snapshot/REAL/REAL-WRITE 模式。
4. 七个线上工具的脱敏 `tools/list` Schema 快照，以及它与 `tool_server.py` 的差异；不要附真实调用数据。
5. 线上服务各状态的后端位置：tasks fixture/真实数据库来源、approval JSON 路径与持久卷行为、Proposal/idempotency/token 的存储和重启恢复语义。
6. 当前分享码的验证方（WorkBuddy platform 或应用）、静态 Demo header 的验证/轮换流程说明；只给机制和负责人，不给凭证值。
7. 现有 WorkBuddy Connector 的 OAuth/server-side auth 可配置能力与撤权行为；提供官方配置说明或租户管理员入口。
8. 非生产测试槽、两个专用 CheckD 测试账号、脱敏任务/课程夹具和可回滚测试窗口的提供方式。

## 验证与安全边界

- `tools/m1-server` 本地单测：339 项通过。只验证仓库代码，不证明当前线上运行的是该 SHA。
- Personal Task Agent：87 项通过（`unittest`；未连 Production）。
- Planning MCP remote/auth adapter：`test_remote_mcp.py` 11 项、`test_supabase_remote.py` 5 项通过（`unittest`；TestJwtAuthority/opener 均为本地测试替身）。
- 本轮只读检查线上 MCP `tools/list`；没有调用任务数据或任何写工具，没有请求任务/课程记录，没有创建/修改 Connector，也没有轮换凭证。
- 本轮在 M1 原仓库运行测试时产生 Python `__pycache__` 未跟踪目录；源码文件没有修改。这些由本轮测试生成的文件不纳入本工作区提交。

## 准入判断

- **源码仓库候选：已找到。** `Tony2215/check-d` / `demo/competition-11010`。
- **线上 endpoint 与仓库的关联：强证据。** M1 RUNBOOK 直接记录了该 endpoint，M1 app 的服务名和七工具注册匹配在线清单。
- **精确线上 commit：UNKNOWN。** 缺少平台 revision 或匹配部署 manifest。
- **可立即安全合并业务代码：否。** 逐请求 WorkBuddy → CheckD 身份绑定、远程多用户账本和真实部署 artifact 均未证实。
- **最小安全下一步：** 获取上方资料清单 1–3、7–8；在隔离发布槽先做 per-request OAuth 身份绑定与 A/B 只读访问验收，再迁入 Personal Task Agent 和规划服务。
