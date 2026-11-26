# CheckD 内置智能体

本功能在原有 Flutter 项目上新增 `lib/features/agent`，入口位于“今天”和“我的”，不增加一级导航。模型只生成结构化提案，原有 Task、Course、Plan、Tag、Review 仓库负责校验与实际写入。未增加三级计划树。

## 使用

1. 打开“和智能体一起安排”，在“目标与资料”设置目标、作息、生活预留和课表确认范围。多个目标共享一份学习预算。
2. 直接查询，或用自然语言新增、修改、归档事项。修改会列出字段、影响日期和警告；确认后才执行。课程单日变化始终预览，只产生单日例外。
3. 上传图片、PDF、Office 或文本资料前，可查看解析结果、截断提示并移除附件。点击“发送”才向模型传输资料。扫描 PDF 在设备上渲染为图片。
4. “临时有事”登记占用，软件确定性检查冲突和共享预算，仅重排未来未完成的受管学习事项；保留事项 ID，放不下的保留为待安排。
5. “反馈进度”保存明确自报资料，不伪造实际计时或完成记录；真实计时、打卡仍使用原按钮。“变更记录”可安全撤销最近20次计划修改，后续手动修改冲突时拒绝覆盖。

默认需要预览确认；可在作息设置中主动开启非课程改动自动应用，包含课程的整批修改仍需要确认。自动应用失败会保留输入和附件。

## 数据与能力边界

- 业务事项和事实继续沿用现有同步队列。智能体档案、平行目标、聊天、操作历史、提示去重标记按账号存储于本机 AppSettings，目前不跨设备同步。
- 20%是初始学习份额，可以在作息设置中修改。占用区间取并集，所有目标共用容量；未知时长和未确认课表不能当作空闲。生活预留是总量，具体吃饭/通勤时段需作为固定占用提供。
- 模型可处理文字和受配置支持的图片；没有新增录音识别或未经验证的音频评分，不将短测换算为官方雅思分数。
- 教务页面由用户自行登录并主动提取表格。不会读取密码、Cookie 或验证码给模型。Web 受浏览器跨域限制，使用独立网页与粘贴/HTML；Canvas、跨域框架或不支持的平台可改用截图/文件。
- 前台按真实北京时间检查提醒，过期不补发。系统提醒通过原 ReminderScheduler 统一重建，依赖平台支持、权限及系统限制。没有独立服务器定时推送或无人值守调用模型的周复盘服务；提醒入口可引导用户发起真实复盘。

## 本机联调：密钥在仓库外

需要 Node.js 22或更新版本和本项目 Flutter SDK。创建仓库外文件，例如用户目录 `.codex/secrets/checkd-agent.env`，只在该文件填写 `DEEPSEEK_API_KEY`，不要放入 Dart define、Flutter assets、聊天、Git 或截图。

```dotenv
DEEPSEEK_API_KEY=在本机文件中填写
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-flash
```

```powershell
node tool/agent/local_server.mjs
node --test tool/agent/core_test.mjs
node tool/agent/live_eval.mjs
flutter test --no-pub tool/agent/live_workflow_test.dart
```

本机服务仅绑定 `127.0.0.1:8766`，启动时生成临时本机令牌，写入仓库外 `.codex/tmp/checkd-agent-runtime.json`。该令牌不是模型密钥。仅允许固定本机预览来源；不可把此开发服务暴露到公网。

本机界面可用临时令牌构建（命令中的值从上述 runtime 文件读取）：

```powershell
$agentRuntime = Get-Content "$env:USERPROFILE/.codex/tmp/checkd-agent-runtime.json" -Raw | ConvertFrom-Json
flutter build web --no-pub "--dart-define=CHECKD_AGENT_DEV_URL=$($agentRuntime.endpoint)" "--dart-define=CHECKD_AGENT_DEV_TOKEN=$($agentRuntime.token)"
node tool/agent/serve_preview.mjs
```

在 `http://127.0.0.1:8767` 用离线体验测试。正式构建不带两个 `CHECKD_AGENT_DEV_*` define，默认调用 Supabase Edge Function。

## 队长部署 Supabase

本次不迁移云平台、不修改现有任务/课程表，新增独立额度表和 Edge Function。腾讯云迁移可复用 `core.mjs` 的标准 Request/Response 处理，但需要替换认证和额度适配。

1. 先审查、应用 `supabase/migrations/202611230001_checkd_agent_quota.sql`。只允许服务角色调用额度 RPC；普通用户不能直接消耗全站额度。默认每用户30次/北京时间日、全站300次/日、用户请求至少间隔3秒。额度在模型调用前原子预留；上游失败也占一次，避免无限重试耗费。
2. 在 Edge Function Secrets 设置 `DEEPSEEK_API_KEY`、`DEEPSEEK_BASE_URL`、`DEEPSEEK_MODEL`、`DEEPSEEK_SUPPORTS_IMAGES` 和正式 Web 来源 `AGENT_ALLOWED_ORIGINS`（逗号分隔完整 origin，不用通配符）。只在队长自己的云端控制台输入真实密钥。模型地址必须是 HTTPS。
3. 保留平台注入的 `SUPABASE_URL`、公开项目 key，以及仅服务端可用的 `SUPABASE_SERVICE_ROLE_KEY` 或新版 `SUPABASE_SECRET_KEYS`。函数先通过 Supabase Auth 验证请求 JWT，再将验证返回的 user ID 交给服务端额度 RPC；请求体中的 owner 信息没有授权作用。
4. 部署 `checkd-agent`。如果项目使用新版 key/JWT，按官方说明选择 `supabase functions deploy checkd-agent --no-verify-jwt`，让函数内 `/auth/v1/user` 完成认证。这个选项不能配合删除函数内认证。旧版网关验证与项目 JWT 兼容时也可保留平台验证。
5. 在测试项目验证：无 JWT 返回401、非法来源403、无密钥503、额度用完429；两个真实账号互相不可读取/修改；普通角色不能执行额度 RPC；正式客户端代码和网络响应中没有模型密钥或服务角色 key。

参考官方说明：[Edge Secrets](https://supabase.com/docs/guides/functions/secrets)、[Edge 认证头](https://supabase.com/docs/guides/functions/auth-headers)、[新 key 迁移](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys)。

## 验证范围

常规回归运行 `flutter test --no-pub`、`flutter build web --no-pub`；真实模型用上面的显式联调命令。全量单测不会偷偷使用付费 API。界面检查覆盖390px手机和1280px桌面。

Web PDF.js固定本地4.6.82，资源和许可证在 `web/vendor/pdfjs-4.6.82`，不依赖CDN，不向PDF服务上传文件。原生 PDF/WebView 与系统通知仍需各平台真机验收；本机缺少 Windows 插件符号链接权限及 Android SDK，不能把 Web 构建成功当作这些平台已经打包或真机验证成功。额度 SQL 与生产 Auth 必须在云端测试项目验证，本次本地测试不声称已部署通过。
