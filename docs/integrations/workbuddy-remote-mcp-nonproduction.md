# WorkBuddy 远程 CheckD MCP：非生产联调手册

状态：**服务端骨架可本地运行；WorkBuddy 实机与真实账号授权未完成。** 本文不表示 Connector 已注册、HTTPS 已部署或已读取任何用户数据。

## 当前服务行为

- `POST /mcp` 提供 Streamable HTTP JSON-RPC，保留契约中的 8 个只读/预览工具。
- `GET /healthz` 只返回进程健康状态，不公开配置或密钥。
- `GET /.well-known/oauth-protected-resource` 发布受保护资源元数据，授权服务器指向 `${SUPABASE_URL}/auth/v1`。
- 每个 MCP 请求都通过 Supabase Auth `GET /auth/v1/user` 验证 Bearer，并从该结果取得 CheckD 用户 ID；请求参数里的 `user_id` 被拒绝。
- PostgREST 仅通过当前用户 JWT 发起 `GET`，并仍受现有 RLS 约束；没有 service-role 访问代码，也没有 INSERT/UPDATE/DELETE 工具。
- `get_planning_context` 返回任务、课程、课程规则、计划、工时和来源限制。任务备注不返回。
- 快照标记为 provisional，因为服务端没有设备同步水位，不能证明手机端未同步的本地改动已经到云端。
- 如果有课程规则但 occurrence 没有由 Flutter 规则解析，调度类工具 fail closed 返回 `PLANNING_BLOCKED`。Python 不复制单双周、停课、调课和补课逻辑。
- 计划工具只做计算，不创建持久 Proposal、不审批、不写计划。

## OAuth 评估

Supabase Auth 当前提供 OAuth 2.1 / MCP 认证发现、PKCE、动态注册选项和 Supabase 用户 JWT；它作为 CheckD 身份提供者在协议层适合本方案。Supabase MCP 文档建议 MCP Server 使用 `https://<project-ref>.supabase.co/auth/v1` 作为 authorization server，并使用用户 JWT 执行 RLS 约束访问。WorkBuddy Connector 也支持远程 Streamable HTTP 和标准 MCP OAuth，但其 `server-side` 模式要求与 WorkBuddy 团队接入协调，并要求授权服务器 allowlist WorkBuddy client 名称和回调域名。因此“协议可对接”已由官方文档支持，**当前租户、DCR、回调和 WorkBuddy 实机兼容性仍须实测**。

Supabase OAuth scopes 控制 OIDC 身份信息，不会把数据库权限变成只读。现有 `authenticated` JWT 仍按表 GRANT 与 RLS 工作。本服务通过固定只读工具表面和 PostgREST GET 限制自身行为，但这不等于 JWT 被数据库层限制为只读；生产启用前须评审 OAuth `client_id` 专属的只读 RLS/GRANT，或采用经过安全评审的只读数据层。此手册不授权或执行 Production RLS 修改。

Supabase 返回的 JWT 可能在退出/撤权后继续有效到 `exp`。WorkBuddy 应停止发出撤权连接的请求；但不得宣称服务可以仅靠本 MCP 骨架立即废止所有已签发 access token。真实撤权验收要测 WorkBuddy 断开连接、服务端 Auth 校验结果及旧 JWT 到期边界。

官方依据：

- [WorkBuddy Connector：OAuth、MCP 与 server-side 接入](https://open.workbuddy.cn/en/docs/connector)
- [Supabase MCP Authentication](https://supabase.com/docs/guides/auth/oauth-server/mcp-authentication)
- [Supabase OAuth Token Security & RLS](https://supabase.com/docs/guides/auth/oauth-server/token-security)

## 管理员需要准备的测试环境

1. 创建或指定**非生产** Supabase 项目，准备两名可登录的专用测试用户 A/B，并只放入脱敏测试数据。不要把生产账号用于联调。
2. 在 Supabase Dashboard 打开 `Authentication → OAuth Server`，启用 OAuth 2.1；配置实际 authorization/consent 页面。若采用 DCR，启用 Dynamic Client Registration 并审核客户端/redirect URI。不要把匿名开放注册当成默认安全配置。
3. 管理员确认 Supabase DCR 与 WorkBuddy `server_auth.auth_type="mcp_oauth"` 的 client metadata（尤其 `client_name` 与 redirect URI）兼容。若不兼容，和 WorkBuddy 团队选择预注册 `oauth2_code`，不要在本服务中自写 OAuth Broker。
4. 在 WorkBuddy 开放平台使用 Connector Meta 工具创建非生产 MCP Connector 草稿，选择远程 `streamableHttp`、`auth_mode="server-side"`。服务提供方需要和 WorkBuddy 团队完成 OAuth 接入，并在授权服务按 Connector 文档 allowlist `WorkBuddy Connector`、`CodeBuddy` 及该文档列出的 WorkBuddy/CodeBuddy 回调域名。
5. 提供可公开访问的非生产 HTTPS 主机。Cloudflare 临时 Tunnel 可用于短时联调，但要把生成的 HTTPS URL 配置进服务环境并重启。该地址变化后必须重配 Connector；不要把临时 Tunnel 视作生产托管。
6. 使用本 README 的 Docker/环境变量启动服务。`SUPABASE_URL` 和 publishable key 只能来自非生产项目；不得设置或传入 service-role key。
7. Connector 草稿配置 MCP URL 为 `https://<host>/mcp`，对照服务端 `/.well-known/oauth-protected-resource` 检查 issuer discovery。让测试用户 A 在浏览器中亲自登录、同意授权，不要把账号密码或 JWT 发给 Agent。

## 实机验收步骤与证据

每一步保存 Connector/平台操作截图以及脱敏服务端事件摘要。日志不得保存 `Authorization`、JWT、用户任务正文或邮箱；只记录 request id、工具名、HTTP/MCP 状态、返回计数和不可逆 subject 摘要。

### 账号 A

1. WorkBuddy 打开非生产 Connector 并通过 OAuth 授权 CheckD 测试用户 A。
2. 调用 `tools/list`，确认八个工具名与 `docs/contracts/agent-planning-v0.json` 相同。
3. 调用 `list_tasks`，确认只返回 A 的脱敏测试任务；保留实际工具调用截图/结果和返回任务数。
4. 调用 `get_planning_context`，确认课程和课程规则属于 A，且返回 `provisional=true`、`execution_eligible=false`。
5. 如果课程 occurrence 未解析，调用 `preview_schedule` 应明确返回 `PLANNING_BLOCKED`；这表示安全拒绝，不是规划成功。

### 账号 B、越权和撤权

6. 同一 Connector 授权用户 B，调用相同工具并确认 A 的记录不可见。
7. 以 B 调用中加入 `user_id` 必须得到 `INVALID_INPUT`；用 A 的 task id 在 B 的延期模拟中必须得到统一 `NOT_FOUND`。
8. WorkBuddy 断开 A 的 Connector 授权，A 的后续 WorkBuddy 工具调用应停止。另用旧 A access token 直接对测试服务做撤权/过期验收，区分“Connector 停止发送”与“JWT 服务端立即失效”；确认 B 仍可用。
9. 重启 MCP 服务后再次检查 A/B 各自状态，没有身份回退或共享缓存。

**通过条件：**真实 WorkBuddy Connector 已发布到测试租户；A、B 都实际完成 OAuth；A/B 的 `list_tasks` 与课程结果隔离；撤权和旧 token 行为有真实结果；没有 mock verifier 或 TestJwtAuthority 参与。当前这些步骤尚未执行，因此本项目尚未达到任务的最终验收标准。

## 当前精确阻塞项

- WorkBuddy 测试租户与 Connector 草稿创建/发布权限：需要平台管理员或租户所有者。
- WorkBuddy `server-side OAuth` 接入协调及动态注册/预注册选择：需要 WorkBuddy Connector 团队确认。
- 可公开 HTTPS 非生产主机：当前没有部署，不得把本地 MCP URL 当作 WorkBuddy 可访问 URL。
- Supabase OAuth Server 开启状态、consent 页面、DCR/client allowlist：需非生产 Supabase 管理员配置并验证。
- 测试用户 A/B 和脱敏云端夹具：需非生产项目管理员提供或建立。
- 只读数据库权限：需要安全评审和隔离环境验证；OAuth scopes 本身不限制数据库写权限。
- 课程 occurrence 只读规范化接口和设备同步水位仍缺失；因此涉及课程规则的远程排程预览会拒绝生成。
