# CheckD WorkBuddy 远程 MCP 非生产联调准备

状态：**远程 MCP 可运行骨架已实现；实际 WorkBuddy Connector/OAuth 联调仍 BLOCKED**。本说明不表示已有公开服务、测试租户、OAuth 客户端或真实用户授权。

## 平台侧准备

1. 由具备开发者/Connector 发布权限的管理员进入 WorkBuddy 开放平台，使用官方 Connector Meta 工具创建非生产 Connector 草稿。平台入口与权限需由组织管理员提供；没有租户权限时不能由本地代码代替注册或审核。
2. MCP 配置使用远程 HTTPS 地址和 Streamable HTTP。WorkBuddy 文档要求远程地址使用 HTTPS；本地 `127.0.0.1` 测试地址不能作为发布地址。
3. 私有 CheckD 数据需要 OAuth 时，Connector 元数据采用 `auth_mode: "server-side"`，由 WorkBuddy 云端托管授权凭证。官方 Connector 文档列出动态注册 `server_auth.auth_type: "mcp_oauth"` 与预注册 `"oauth2_code"` 两种形式。两者都要求授权服务器 allowlist `WorkBuddy Connector` / `CodeBuddy` 客户端名及 WorkBuddy 回调域名，并要求 HTTPS。
4. 选择动态注册时，服务端至少要提供 OAuth Protected Resource Metadata、Authorization Server Metadata、RFC 7591 客户端注册、PKCE S256 授权及 Token endpoints。选择预注册时，管理员还需先创建 OAuth 客户端并把 client 信息按 WorkBuddy 要求提交配置。具体准入需和 WorkBuddy Connector 团队确认。
5. 准备独立测试域名、TLS 证书、可公开访问的非生产 MCP/OAuth 服务、测试数据库项目、日志脱敏、健康检查与停用开关。不要将 Production URL、密钥或真实用户数据放进测试 Connector。

## CheckD 身份绑定要求

- WorkBuddy 登录身份只证明 WorkBuddy 的 `issuer + subject (+ tenant)`，不等于 CheckD 用户 ID。
- 用户需在 OAuth 授权页面单独登录 CheckD，并明确同意 MCP 权限范围。授权服务把已验证的 CheckD Auth 主体绑定到 WorkBuddy OAuth 授权记录；每次 MCP 请求都校验有效、未撤销的绑定。
- 请求体不得包含可选用户 ID。服务端从验证后的 MCP access token / 授权记录派生 CheckD 主体，再使用该主体的权限访问数据。
- 不得使用个人 Mac Keychain JWT、共享静态用户 JWT 或 service-role 密钥替代用户授权。service-role 仅限受控服务端实现所需操作且不能暴露给 MCP 客户端；当前生产接入尚未建立。
- `TestJwtAuthority` 仅用于本地单元测试。新增 `SupabaseAccessTokenVerifier` 通过 Supabase Auth `/auth/v1/user` 验证每个请求的用户 JWT，并以 Auth 返回的 ID 作为 CheckD 用户；`SupabaseRestSnapshotProvider` 仅使用同一用户 JWT 和 publishable key 发出 owner-filtered PostgREST GET。未使用 WorkBuddy 主体替代 CheckD 用户 ID，也没有 service-role 访问路径。
- Supabase OAuth 2.1 Server 是独立授权服务，不是本 MCP 自行实现的 OAuth Broker。授权服务的 DCR、consent 页面、WorkBuddy `server-side` 的实际兼容性仍需要管理员和 WorkBuddy 团队实测。OAuth 的 `scope` 不是数据库只读权限；MCP 目前只暴露 GET 数据读取和计算工具，但生产仍需专门只读权限方案审核。

## 两账号验收步骤

测试租户、HTTPS 主机和 OAuth 配置完成后，使用两个专用 CheckD 测试账号 A、B：

1. 在同一个 WorkBuddy Connector 中分别完成 CheckD OAuth 授权，确认授权主体在服务端解析成不同 CheckD user ID。
2. 分别调用只读 `get_planning_context`、`list_tasks`、`get_current_plan`、`list_plan_risks`。A 只看到 A 的夹具数据，B 只看到 B 的夹具数据；响应与日志不出现另一账号记录或凭证。
3. 将 A 的 task/proposal 标识放入 B 的调用，检查返回统一 `NOT_FOUND`，并核对没有状态变化。
4. 撤销 A 的 WorkBuddy Connector 授权后，验证 WorkBuddy 停止发送 A 的 token；另外检查旧 JWT 在 Auth 校验及 `exp` 到期前后的行为。不能假设 JWT 撤权即时生效；B 仍应正常读取。
5. 重启 MCP 服务，重复验证绑定与撤权结果，确认服务不回退到个人账号或共享账号。
6. 保存脱敏的请求 ID、HTTP 状态、工具结果摘要和数据库读计数作为验收证据。

## 当前缺项

- WorkBuddy 非生产租户、Connector 创建/审核权限、OAuth server-side 配置权限：需平台管理员提供。
- 公开可达 HTTPS 测试域名及部署环境：需环境所有者提供；本轮没有公开部署。
- Supabase OAuth Server 的开启状态、consent 页面、DCR/客户端 allowlist 与 WorkBuddy server-side 真实兼容性：尚未验证。
- 两个可用的 CheckD 测试账号与脱敏夹具：需测试负责人提供/建立。
- 已提供 Dockerfile 和启动说明；本轮 Docker 拉取基础镜像因 Registry 访问无响应而中止，容器镜像尚未完成构建，也未部署到 HTTPS。8 个只读/预览工具保留。任务/课程读取适配器已实现 Supabase Auth/PostgREST；计划计算遇到尚未解析的课程规则时会返回 `PLANNING_BLOCKED`。个人任务创建/编辑 MCP 尚未与该服务统一认证，Proposal/Approval 写入不对 WorkBuddy 开放。
- 当前读取结果不能证明设备已完全同步，恒标记 provisional。Supabase 用户 JWT 可能直到过期前仍可用，需实际验收 WorkBuddy 撤权行为以及旧 token 的拒绝/到期边界。

## 官方资料

- WorkBuddy [Connector 文档](https://open.workbuddy.cn/docs/connector) 描述 `server-side` OAuth、动态/预注册 OAuth、HTTPS、allowlist 与 Connector 文件结构。
- WorkBuddy [专家文档](https://open.workbuddy.cn/docs/expert) 描述专家中的 MCP Server 配置。
